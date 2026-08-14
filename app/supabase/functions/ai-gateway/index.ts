// Qamar AI gateway.
//
// The app never holds a model key: it calls here with the user's Supabase JWT,
// and this decides whether the question is answerable, gathers the evidence,
// calls the model, and records what happened.
//
// Routes:
//   POST /ai-gateway/chat/reply     { message, lang }
//   POST /ai-gateway/meal/analyze   { inputType, text?, mediaPath? }
//   POST /ai-gateway/plan/generate  { date? }
//
// Secrets (supabase secrets set ...):
//   ANTHROPIC_API_KEY   required
//   VOYAGE_API_KEY      or OPENAI_API_KEY — required for retrieval
//   USDA_API_KEY        optional, improves whole-food figures
//   QAMAR_MODEL         optional, defaults to claude-sonnet-5

import { callModel, chatSystemPrompt, mealAnalysisSystemPrompt, parseJson, planSystemPrompt, type UserContext } from "./model.ts";
import { lookupFoods, retrieve, type FoodFacts, type Passage, type Source } from "./retrieval.ts";
import { classify, refusalText } from "./scope.ts";

const SUPABASE_URL = Deno.env.get("SUPABASE_URL")!;
const SERVICE_KEY = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!;

const CORS = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
};

function json(body: unknown, status = 200): Response {
  return new Response(JSON.stringify(body), {
    status,
    headers: { ...CORS, "Content-Type": "application/json" },
  });
}

// ---- identity -----------------------------------------------------------

/** Verifies the caller's JWT with Supabase and returns their user id. */
async function authenticate(req: Request): Promise<string | null> {
  const auth = req.headers.get("Authorization");
  if (!auth?.startsWith("Bearer ")) return null;
  const res = await fetch(`${SUPABASE_URL}/auth/v1/user`, {
    headers: { Authorization: auth, apikey: SERVICE_KEY },
  });
  if (!res.ok) return null;
  const user = await res.json();
  return user?.id ?? null;
}

async function db(path: string, init: RequestInit = {}): Promise<Response> {
  return await fetch(`${SUPABASE_URL}/rest/v1/${path}`, {
    ...init,
    headers: {
      "Content-Type": "application/json",
      apikey: SERVICE_KEY,
      Authorization: `Bearer ${SERVICE_KEY}`,
      ...(init.headers ?? {}),
    },
  });
}

/**
 * The person's profile and current target. Also enforces eligibility at the
 * gateway: a blocked user must not be able to reach the model by calling the
 * API directly, whatever the app shows.
 */
async function loadContext(userId: string, lang: string): Promise<{ ctx: UserContext; blocked: boolean }> {
  const res = await db(`profiles?user_id=eq.${userId}&select=*`);
  const rows = res.ok ? await res.json() : [];
  const p = rows[0];

  let targetKcal: number | null = null;
  const tRes = await db(`targets?user_id=eq.${userId}&select=kcal&order=valid_from.desc&limit=1`);
  if (tRes.ok) {
    const tRows = await tRes.json();
    targetKcal = tRows[0]?.kcal ?? null;
  }

  let age: number | null = null;
  if (p?.birth_date) {
    const b = new Date(p.birth_date);
    const now = new Date();
    age = now.getFullYear() - b.getFullYear();
    const before = now.getMonth() < b.getMonth() || (now.getMonth() === b.getMonth() && now.getDate() < b.getDate());
    if (before) age--;
  }

  const blocked =
    p?.eligibility_status === "blocked_minor" ||
    p?.eligibility_status === "blocked_safety" ||
    (age != null && age < 18);

  return {
    blocked,
    ctx: {
      name: p?.name ?? null,
      age,
      gender: p?.gender ?? null,
      heightCm: p?.height_cm ?? null,
      weightKg: p?.weight_kg ?? null,
      goal: p?.goal ?? null,
      activityFactor: p?.activity_factor ?? null,
      exclusions: p?.food_exclusions ?? [],
      targetKcal,
      lang,
    },
  };
}

async function record(
  userId: string,
  kind: "chat" | "meal_analysis" | "plan",
  fields: { inScope: boolean; refusal?: string; question?: string; answer?: string; sources?: Source[]; model?: string },
): Promise<void> {
  try {
    await db("ai_interactions", {
      method: "POST",
      body: JSON.stringify({
        user_id: userId,
        kind,
        in_scope: fields.inScope,
        refusal_reason: fields.refusal ?? null,
        question: fields.question ?? null,
        answer: fields.answer ?? null,
        sources: fields.sources ?? [],
        model: fields.model ?? null,
      }),
    });
  } catch {
    // Audit is important but never worth failing the user's request over.
  }
}

const asSources = (p: Passage[], f: FoodFacts[] = []): Source[] => [
  ...p.map(({ source, title, url }) => ({ source, title, url })),
  ...f.map((x) => ({ source: x.source, title: x.name, url: x.url })),
];

/** Candidate food names to look up, from free text. Crude on purpose. */
function foodTerms(text: string): string[] {
  return text
    .split(/[,\n+·•]| and | و /gi)
    .map((s) => s.replace(/[0-9٠-٩]+\s*(g|جم|kg|كجم|ml|مل)?/gi, "").trim())
    .filter((s) => s.length > 2 && s.length < 40)
    .slice(0, 8);
}

// ---- routes -------------------------------------------------------------

async function chatReply(userId: string, body: { message?: string; lang?: string }): Promise<Response> {
  const message = (body.message ?? "").trim();
  const lang = body.lang === "ar" ? "ar" : "en";

  const verdict = classify(message);
  if (!verdict.allowed) {
    await record(userId, "chat", { inScope: false, refusal: verdict.reason, question: message });
    return json({ reply: refusalText(verdict.reason, lang), refused: true, reason: verdict.reason });
  }

  const { ctx, blocked } = await loadContext(userId, lang);
  if (blocked) {
    await record(userId, "chat", { inScope: false, refusal: "minor", question: message });
    return json({ reply: refusalText("minor", lang), refused: true, reason: "minor" });
  }

  const passages = await retrieve(SUPABASE_URL, SERVICE_KEY, message, verdict.domain);
  if (passages.length === 0) {
    // No grounding, no answer. This is the rule that stops the assistant
    // becoming a general chatbot the moment retrieval is empty.
    const reply = lang === "ar"
      ? "معنديش مصدر موثوق يجاوب على ده دلوقتي، ومش هألّف. جرّب تسأل بطريقة تانية أو عن حاجة أقرب للأكل والتمرين."
      : "I do not have a grounded source for that right now, and I will not make one up. Try asking differently, or about something closer to food and training.";
    await record(userId, "chat", { inScope: true, refusal: "no_grounding", question: message, answer: reply });
    return json({ reply, refused: true, reason: "no_grounding" });
  }

  const foods = await lookupFoods(foodTerms(message));
  const { text, model } = await callModel({
    system: chatSystemPrompt(ctx, passages, foods),
    user: message,
    maxTokens: 600,
  });

  await record(userId, "chat", {
    inScope: true,
    question: message,
    answer: text,
    sources: asSources(passages, foods),
    model,
  });
  return json({ reply: text, sources: asSources(passages, foods), refused: false });
}

async function analyzeMeal(
  userId: string,
  body: { inputType?: string; text?: string; mediaPath?: string; lang?: string },
): Promise<Response> {
  const lang = body.lang === "ar" ? "ar" : "en";
  const described = (body.text ?? "").trim();

  const { ctx, blocked } = await loadContext(userId, lang);
  if (blocked) return json({ error: "not eligible" }, 403);

  if (!described) {
    // Photo and voice need transcription/vision before this can be grounded.
    // Returning empty is honest; the app keeps its confirm-before-write step.
    return json({ items: [], note: "no text to analyse" });
  }

  const foods = await lookupFoods(foodTerms(described));
  const { text, model } = await callModel({
    system: mealAnalysisSystemPrompt(ctx, foods),
    user: described,
    maxTokens: 900,
    prefill: "{",
  });

  const parsed = parseJson<{ items: unknown[] }>(text);
  if (!parsed?.items) return json({ error: "could not analyse" }, 502);

  await record(userId, "meal_analysis", {
    inScope: true,
    question: described,
    answer: JSON.stringify(parsed.items).slice(0, 2000),
    sources: asSources([], foods),
    model,
  });
  return json({ items: parsed.items, sources: asSources([], foods) });
}

interface PlanShape {
  meals: unknown[];
  rationale_ar?: string;
  rationale_en?: string;
}

async function generatePlan(userId: string, body: { date?: string; lang?: string }): Promise<Response> {
  const lang = body.lang === "ar" ? "ar" : "en";
  const day = body.date ?? new Date().toISOString().slice(0, 10);

  const { ctx, blocked } = await loadContext(userId, lang);
  if (blocked) return json({ error: "not eligible" }, 403);
  if (!ctx.targetKcal) return json({ error: "no target yet — finish onboarding first" }, 409);

  const brief =
    `daily meal plan for ${ctx.targetKcal} kcal, goal ${ctx.goal ?? "maintain"}, ` +
    `Egyptian home cooking, avoiding ${ctx.exclusions?.join(", ") || "nothing"}`;

  const passages = await retrieve(SUPABASE_URL, SERVICE_KEY, brief, "nutrition", 8);
  if (passages.length === 0) return json({ error: "no grounded guidance available" }, 503);

  // Look the staples up so the model has real per-100g figures to divide.
  const staples = [
    "foul medames", "baladi bread", "white rice cooked", "chicken breast grilled",
    "greek yogurt", "oats", "banana", "olive oil", "tomato", "cucumber", "eggs", "tuna",
  ];
  const foods = await lookupFoods(staples);

  const { text, model } = await callModel({
    system: planSystemPrompt(ctx, passages, foods),
    user: brief,
    maxTokens: 2000,
    prefill: "{",
  });

  const parsed = parseJson<PlanShape>(text);
  if (!parsed?.meals?.length) return json({ error: "could not generate a plan" }, 502);

  const sources = asSources(passages, foods);
  const saved = await db("meal_plans?on_conflict=user_id,plan_date", {
    method: "POST",
    headers: { Prefer: "resolution=merge-duplicates,return=representation" },
    body: JSON.stringify({
      user_id: userId,
      plan_date: day,
      meals: parsed.meals,
      target_kcal: ctx.targetKcal,
      rationale_ar: parsed.rationale_ar ?? null,
      rationale_en: parsed.rationale_en ?? null,
      sources,
      model,
    }),
  });
  if (!saved.ok) return json({ error: `could not save plan: ${await saved.text()}` }, 500);

  await record(userId, "plan", { inScope: true, question: brief, answer: JSON.stringify(parsed.meals).slice(0, 2000), sources, model });
  return json({ plan: parsed, date: day, sources });
}

// ---- entry --------------------------------------------------------------

Deno.serve(async (req) => {
  if (req.method === "OPTIONS") return new Response("ok", { headers: CORS });
  if (req.method !== "POST") return json({ error: "POST only" }, 405);

  const userId = await authenticate(req);
  if (!userId) return json({ error: "unauthorized" }, 401);

  let body: Record<string, string> = {};
  try {
    body = await req.json();
  } catch {
    return json({ error: "invalid JSON" }, 400);
  }

  const route = new URL(req.url).pathname.replace(/^\/ai-gateway/, "").replace(/\/$/, "");
  try {
    switch (route) {
      case "/chat/reply":
        return await chatReply(userId, body);
      case "/meal/analyze":
        return await analyzeMeal(userId, body);
      case "/plan/generate":
        return await generatePlan(userId, body);
      default:
        return json({ error: `unknown route ${route}` }, 404);
    }
  } catch (e) {
    console.error("ai-gateway", route, e);
    return json({ error: "gateway error" }, 500);
  }
});
