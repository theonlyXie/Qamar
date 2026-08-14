// The model call, and the instructions that keep it inside the job.
//
// The scope guard in scope.ts decides *whether* to call; this decides *how*.
// The rule that matters most: the assistant answers from the retrieved
// passages and the looked-up food data, and says so when it cannot. A
// confident invented number is worse than an admitted gap in a product people
// use to decide what to eat.

import type { FoodFacts, Passage } from "./retrieval.ts";

const ANTHROPIC_VERSION = "2023-06-01";
const DEFAULT_MODEL = "claude-sonnet-5";

export interface ModelResult {
  text: string;
  model: string;
}

interface CallOptions {
  system: string;
  user: string;
  maxTokens?: number;
  /** Forces JSON-only output for the structured endpoints. */
  prefill?: string;
}

export async function callModel({ system, user, maxTokens = 1024, prefill }: CallOptions): Promise<ModelResult> {
  const key = Deno.env.get("ANTHROPIC_API_KEY");
  if (!key) throw new Error("ANTHROPIC_API_KEY is not configured");
  const model = Deno.env.get("QAMAR_MODEL") ?? DEFAULT_MODEL;

  const messages: { role: string; content: string }[] = [{ role: "user", content: user }];
  // Putting the opening brace in the assistant's mouth is the cheapest way to
  // stop a model wrapping JSON in prose.
  if (prefill) messages.push({ role: "assistant", content: prefill });

  const res = await fetch("https://api.anthropic.com/v1/messages", {
    method: "POST",
    headers: {
      "Content-Type": "application/json",
      "x-api-key": key,
      "anthropic-version": ANTHROPIC_VERSION,
    },
    body: JSON.stringify({ model, max_tokens: maxTokens, system, messages }),
  });

  if (!res.ok) {
    throw new Error(`model call failed: ${res.status} ${await res.text()}`);
  }
  const json = await res.json();
  const text = (json.content ?? []).map((b: { text?: string }) => b.text ?? "").join("");
  return { text: prefill ? prefill + text : text, model };
}

// ---- prompts ------------------------------------------------------------

/** Facts about the person, so advice is about them and not about nobody. */
export interface UserContext {
  name?: string | null;
  age?: number | null;
  gender?: string | null;
  heightCm?: number | null;
  weightKg?: number | null;
  goal?: string | null;
  activityFactor?: number | null;
  exclusions?: string[];
  targetKcal?: number | null;
  lang: string;
}

function describeUser(u: UserContext): string {
  const bits = [
    u.age != null ? `age ${u.age}` : null,
    u.gender ? u.gender : null,
    u.heightCm ? `${u.heightCm} cm` : null,
    u.weightKg ? `${u.weightKg} kg` : null,
    u.goal ? `goal: ${u.goal}` : null,
    u.activityFactor ? `activity factor ${u.activityFactor}` : null,
    u.targetKcal ? `daily target ${u.targetKcal} kcal` : null,
    u.exclusions?.length ? `must never be suggested: ${u.exclusions.join(", ")}` : null,
  ].filter(Boolean);
  return bits.length ? bits.join(" · ") : "no profile details yet";
}

function renderPassages(passages: Passage[]): string {
  if (passages.length === 0) return "(no guidance retrieved)";
  return passages
    .map((p, i) => `[${i + 1}] ${p.source} — ${p.title}\n${p.content.trim()}`)
    .join("\n\n");
}

function renderFoods(foods: FoodFacts[]): string {
  if (foods.length === 0) return "(no food database matches)";
  return foods
    .map((f) => `${f.name}: per 100 g — ${f.per100g.kcal} kcal, P ${f.per100g.protein} g, C ${f.per100g.carbs} g, F ${f.per100g.fat} g (${f.source})`)
    .join("\n");
}

const COMMON_RULES = `
You are Qamar, a nutrition and training assistant for adults in Egypt.

Hard rules, in order of priority:
1. You are not a doctor. Never diagnose, never discuss medication, never
   contradict a clinician. If a question turns medical, say so and stop.
2. Answer only from the RETRIEVED GUIDANCE and FOOD DATA supplied below. If
   they do not cover the question, say plainly that you do not have a grounded
   answer rather than filling the gap from memory. An admitted gap is
   acceptable; an invented number is not.
3. Never invent calorie or macro figures. Use the supplied food data. Where a
   figure is your own estimate, label it as an estimate.
4. Respect the user's exclusions absolutely — an allergy is not a preference.
5. Never encourage restriction below a safe intake, never frame food as moral,
   never comment on appearance. If the user sounds distressed about eating,
   stop and suggest real support.
6. Keep it short and concrete. Egyptian home food, Egyptian portions, prices in
   EGP if money comes up. Speak Egyptian Arabic when the user's language is
   'ar', otherwise plain English.
`.trim();

export function chatSystemPrompt(u: UserContext, passages: Passage[], foods: FoodFacts[]): string {
  return `${COMMON_RULES}

THE PERSON: ${describeUser(u)}
REPLY LANGUAGE: ${u.lang === "ar" ? "Egyptian Arabic" : "English"}

RETRIEVED GUIDANCE:
${renderPassages(passages)}

FOOD DATA:
${renderFoods(foods)}

Answer in at most four sentences. Cite the guidance you used as [1], [2] where
it carries real weight — not on every sentence.`;
}

export function planSystemPrompt(u: UserContext, passages: Passage[], foods: FoodFacts[]): string {
  return `${COMMON_RULES}

THE PERSON: ${describeUser(u)}

RETRIEVED GUIDANCE:
${renderPassages(passages)}

FOOD DATA (use these figures; do not invent others):
${renderFoods(foods)}

Write one day of eating: breakfast, lunch and dinner. Requirements:
- The three meals must total within 5% of the daily target.
- Every meal lists its portions with a real amount (grams, loaves, spoons) and
  the kcal for that portion, computed from the FOOD DATA per-100g figures.
- Ordinary Egyptian home cooking. Nothing the person excluded.
- Every name and note in both Egyptian Arabic and English.

Return ONLY JSON of this exact shape, no prose:
{
  "meals": [
    {
      "slot": "breakfast|lunch|dinner",
      "name_ar": "", "name_en": "",
      "note_ar": "", "note_en": "",
      "portions": [
        {"ar": "", "en": "", "amount_ar": "", "amount_en": "", "kcal": 0}
      ]
    }
  ],
  "rationale_ar": "one sentence on why this suits them",
  "rationale_en": "one sentence on why this suits them"
}`;
}

export function mealAnalysisSystemPrompt(u: UserContext, foods: FoodFacts[]): string {
  return `${COMMON_RULES}

THE PERSON: ${describeUser(u)}

FOOD DATA (use these figures where they match; otherwise mark confidence low):
${renderFoods(foods)}

The user has described or photographed a meal. Break it into items with
portions and nutrition. Confidence is "high" only when the item matched the
food data; otherwise "low".

Return ONLY JSON, no prose:
{
  "items": [
    {"ar": "", "en": "", "portionAr": "", "portionEn": "",
     "confidence": "high|low", "kcal": 0, "proteinG": 0, "carbsG": 0, "fatG": 0}
  ]
}`;
}

/** Pulls the JSON object out of a model reply, tolerating stray wrapping. */
export function parseJson<T>(text: string): T | null {
  const start = text.indexOf("{");
  const end = text.lastIndexOf("}");
  if (start === -1 || end <= start) return null;
  try {
    return JSON.parse(text.slice(start, end + 1)) as T;
  } catch {
    return null;
  }
}
