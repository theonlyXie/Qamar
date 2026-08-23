// Qamar AI gateway.
//
// The app never holds a model key: it calls here with the user's Supabase JWT,
// and this decides whether the question is answerable, gathers the evidence,
// calls the model, and records what happened.
//
// Routes:
//   POST /ai-gateway/chat/reply     { message, lang, date?, current_plan?, swapped_slots? }
//   POST /ai-gateway/meal/analyze   { inputType, text?, imageBase64?, imageMediaType? }
//     text/voice: food graph only — no model, no daily AI use
//     photo: takeAiUse + vision model (Qamar+ on the client)
//   POST /ai-gateway/plan/generate  { date?, lang?, force?, instruction? }
//   POST /ai-gateway/scan/barcode   { barcode, lang, date?, grams? }
//     camera feature — Qamar+ on the client; spends a daily AI use
//   POST /ai-gateway/scan/label     { imageBase64, imageMediaType, lang, barcode?, name?, grams? }
//     camera feature — reads the nutrition table off a packet
//   POST /ai-gateway/scan/read      { imageBase64, imageMediaType, lang }
//   POST /ai-gateway/quota          {}
//
// Secrets (supabase secrets set ...):
//   ANTHROPIC_API_KEY   required
//   VOYAGE_API_KEY      or OPENAI_API_KEY — required for retrieval
//   USDA_API_KEY        free from api.data.gov — without it the ingredient
//                       lookups fall back to a shared demo key that is rate
//                       limited to the point of uselessness, and the model is
//                       left estimating figures it should be reading
//   QAMAR_MODEL         optional, defaults to claude-sonnet-5

import {
  bodyScanSystemPrompt,
  callModel,
  chatSystemPrompt,
  labelScanSystemPrompt,
  scanPlacementSystemPrompt,
  mealAnalysisSystemPrompt,
  mealPhotoSystemPrompt,
  parseJson,
  planSystemPrompt,
  type ImageInput,
  type Turn,
  type UserContext,
} from "./model.ts";
import { retrieve, type FoodFacts, type Passage, type Source } from "./retrieval.ts";
import {
  asFoodFacts,
  eatenPortion,
  lookupBarcode,
  scaleTo,
  type ScannedProduct,
} from "./barcode.ts";
import {
  labelProblemText,
  normaliseLabel,
  type LabelReading,
} from "./label.ts";
import {
  identifyItems,
  itemsFromResolutions,
  renderResolutions,
  resolveFoods,
  toPacketFacts,
  type Resolution,
} from "./graph.ts";
import { classify, refusalText } from "./scope.ts";
import {
  loadHardConstraints,
  recordAllowed,
  recordHardBlock,
  recordRefusal,
  violatesConstraint,
} from "./safety.ts";
import {
  externalCallsIn,
  loadUserFacts,
  nutrientGaps,
  numericClaims,
  recordStages,
  recordVerification,
  resolutionUncertainty,
  ruleSelection,
  targetsFrom,
  timed,
  writePacket,
  type Kind,
  type PacketInput,
  type StageCost,
  type TargetRow,
} from "./packet.ts";
import {
  blocks,
  finalVerdict,
  isImprovement,
  isRevisable,
  revisionInstruction,
  verifyChat,
  verifyMeal,
  verifyPlan,
  type Meal,
  type MealItem,
  type Verification,
} from "./verify.ts";
import {
  foodTermsFromMeals,
  mergePlanUpdate,
  type PlanUpdate,
} from "./plan_edit.ts";
import { asQuota, quotaExceededMessage, quotaPayload, type Quota } from "./quota.ts";

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

async function rpcJson(name: string, args: Record<string, unknown>): Promise<unknown> {
  const res = await db(`rpc/${name}`, { method: "POST", body: JSON.stringify(args) });
  if (!res.ok) throw new Error(`${name} failed: ${res.status} ${await res.text()}`);
  return await res.json();
}

/** Spends one of today's five (or extra) uses. Body scan never calls this. */
async function consumeAi(userId: string): Promise<Quota> {
  const q = asQuota(await rpcJson("qamar_ai_try_consume", { p_user_id: userId }));
  if (!q) throw new Error("quota consume returned nothing usable");
  return q;
}

async function refundAi(userId: string): Promise<void> {
  try {
    await rpcJson("qamar_ai_refund_consume", { p_user_id: userId });
  } catch (e) {
    console.error("ai-gateway refund", e);
  }
}

async function quotaStatus(userId: string): Promise<Quota> {
  const q = asQuota(await rpcJson("qamar_ai_quota_snapshot", { p_user_id: userId }));
  if (!q) throw new Error("quota snapshot returned nothing usable");
  return q;
}

function quotaDenied(lang: "ar" | "en", q: Quota): Response {
  const message = quotaExceededMessage(lang);
  return json({
    error: message,
    reply: message,
    refused: true,
    reason: "quota",
    quota: quotaPayload(q),
  }, 429);
}

async function takeAiUse(userId: string, lang: "ar" | "en"): Promise<Quota | Response> {
  try {
    const q = await consumeAi(userId);
    if (!q.allowed) return quotaDenied(lang, q);
    return q;
  } catch (e) {
    console.error("ai-gateway consume", e);
    return json({ error: "quota unavailable" }, 503);
  }
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
async function loadContext(
  userId: string,
  lang: string,
): Promise<{ ctx: UserContext; blocked: boolean; lifeStage: string; target: TargetRow | null }> {
  const res = await db(`profiles?user_id=eq.${userId}&select=*`);
  const rows = res.ok ? await res.json() : [];
  const p = rows[0];

  // The whole row, not just the kcal: since 0025 it carries the equation that
  // produced it and the inputs that equation ran on, which is what the evidence
  // packet cites.
  let target: TargetRow | null = null;
  const tRes = await db(
    `targets?user_id=eq.${userId}&select=kcal,protein_g,carbs_g,fat_g,formula_version,inputs` +
      `&order=valid_from.desc&limit=1`,
  );
  if (tRes.ok) target = (await tRes.json())[0] ?? null;
  const targetKcal = target?.kcal ?? null;

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
    target,
    // Pregnancy and lactation are recorded since 0007 but nothing read the
    // column, so the refusal was still a keyword match on the question. A user
    // who declared it at onboarding and then asked plainly got an answer from
    // equations that are not valid for them.
    lifeStage: p?.life_stage ?? "none",
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
  kind: "chat" | "meal_analysis" | "plan" | "body_scan",
  fields: { inScope: boolean; refusal?: string; question?: string; answer?: string; sources?: Source[]; model?: string },
): Promise<string | null> {
  // Returns the row id so a safety event can point at the interaction that
  // caused it. Null on failure, which callers pass through: an unlinked safety
  // event is worth more than no safety event.
  try {
    const res = await db("ai_interactions", {
      method: "POST",
      headers: { Prefer: "return=representation" },
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
    if (!res.ok) return null;
    const rows = await res.json();
    return rows?.[0]?.id ?? null;
  } catch {
    // Audit is important but never worth failing the user's request over.
    return null;
  }
}

const asSources = (p: Passage[], f: FoodFacts[] = []): Source[] => [
  ...p.map(({ source, title, url }) => ({ source, title, url })),
  ...f.map((x) => ({ source: x.source, title: x.name, url: x.url })),
];

/** Sources from a resolution set, so a graph-resolved food still cites itself. */
const resolvedSources = (p: Passage[], r: Resolution[]): Source[] =>
  asSources(p, r.map((x) => x.facts).filter((x): x is FoodFacts => x !== null));

/**
 * Writes the evidence packet and the per-stage costs for one request.
 *
 * Packet first, because the cost rows point at it — but a failed packet write
 * returns null rather than throwing, and the costs are written anyway against
 * the interaction. Losing the reasoning trail is bad; losing the token counts
 * as well, when they are the part that cannot be reconstructed afterwards,
 * would be worse.
 *
 * Awaited rather than fired and forgotten. It adds two inserts to a request
 * that already spent seconds in the model, and an audit trail that races the
 * response is one that goes missing exactly when the request is interesting.
 */
async function trace(
  userId: string,
  interactionId: string | null,
  kind: Kind,
  packet: Omit<PacketInput, "userId" | "interactionId" | "kind">,
  stages: StageCost[],
  /** One entry per verification pass, in order: index 0 is the first check. */
  verifications: Verification[] = [],
): Promise<string | null> {
  const taskId = await writePacket(SUPABASE_URL, SERVICE_KEY, {
    userId,
    interactionId,
    kind,
    ...packet,
  });
  await recordStages(SUPABASE_URL, SERVICE_KEY, { taskId, interactionId, userId }, stages);
  for (let i = 0; i < verifications.length; i++) {
    await recordVerification(SUPABASE_URL, SERVICE_KEY, taskId, verifications[i], i);
  }
  return taskId;
}

/** The verification, in the shape the app can act on. */
function verificationSummary(v: Verification) {
  return {
    verdict: v.verdict,
    // The plain question the client actually asks. An ESCALATE that reached the
    // user is an answer worth showing with its correction attached, not one
    // worth presenting as checked.
    verified: v.verdict === "PASS",
    recomputed: v.recomputed,
    findings: v.failures.map((f) => ({ type: f.failure_type, detail: f.detail })),
  };
}

/** Candidate food names to look up, from free text. Crude on purpose. */
function foodTerms(text: string): string[] {
  return text
    .split(/[,\n+·•]| and | و /gi)
    .map((s) => s.replace(/[0-9٠-٩]+\s*(g|جم|kg|كجم|ml|مل)?/gi, "").trim())
    .filter((s) => s.length > 2 && s.length < 40)
    .slice(0, 8);
}

/**
 * What Qamar says back to a hello.
 *
 * Written rather than generated: a greeting should be instant and free, and
 * spending a model call plus one of five daily uses on "hi" would be the
 * wrong trade in both directions. It ends with an invitation, so the next
 * message is the one worth answering properly.
 */
function greetingText(lang: string): string {
  return lang === "ar"
    ? "أهلاً! أنا قمر. أنا هنا للأكل والتمرين — قولي أكلت إيه النهاردة، أو اسألني عن أي وجبة."
    : "Hello. I am Qamar. I am here for food and training — tell me what you ate today, or ask me about any meal.";
}

/**
 * What the day has already had.
 *
 * Deterministic on purpose. The model is told the answer rather than asked to
 * work it out: subtraction is the one thing in this flow that must be right
 * every time, and it is also the one thing a language model has no business
 * doing.
 */
async function todaySoFar(userId: string, day: string): Promise<number> {
  const next = new Date(`${day}T00:00:00Z`);
  next.setUTCDate(next.getUTCDate() + 1);
  const to = next.toISOString().slice(0, 10);
  const res = await db(
    `meal_logs?user_id=eq.${userId}&logged_at=gte.${day}&logged_at=lt.${to}&select=kcal`,
  );
  if (!res.ok) return 0;
  const rows = await res.json() as { kcal: number }[];
  return rows.reduce((n, r) => n + (Number(r.kcal) || 0), 0);
}

/** How many earlier exchanges Qamar is allowed to remember. */
const HISTORY_TURNS = 6;

/**
 * How far back a conversation reaches before it is a different conversation.
 *
 * Someone who opens the app at breakfast and again at dinner is starting
 * again, not continuing; carrying the morning into the evening would make
 * Qamar answer questions nobody had just asked.
 */
const HISTORY_WINDOW_MINUTES = 120;

/**
 * The last few turns of this person's conversation, oldest first.
 *
 * Read from the database rather than accepted from the request. The client
 * could send anything, and "what did this user say a minute ago" is not a
 * thing a client should get to assert — it decides what Qamar treats as
 * already established.
 *
 * Both kinds are included because both appear in the same conversation on
 * screen: `chat` is asking Qamar something, `meal_analysis` is typing a meal
 * into the same box. Splitting them is what produced the original bug —
 * somebody typed "kasam", then "and I got", and the second message was judged
 * with no knowledge of the first because the first was filed under a different
 * kind.
 */
async function loadRecentTurns(userId: string): Promise<Turn[]> {
  const since = new Date(Date.now() - HISTORY_WINDOW_MINUTES * 60_000).toISOString();
  try {
    const res = await db(
      `ai_interactions?user_id=eq.${userId}` +
        `&kind=in.(chat,meal_analysis)` +
        `&created_at=gte.${since}` +
        `&select=kind,question,answer,in_scope,refusal_reason,created_at` +
        `&order=created_at.desc&limit=${HISTORY_TURNS}`,
    );
    if (!res.ok) return [];
    const rows = await res.json() as {
      kind: string;
      question: string | null;
      answer: string | null;
      in_scope: boolean;
      refusal_reason: string | null;
    }[];

    const turns: Turn[] = [];
    for (const r of rows.reverse()) {
      const q = (r.question ?? "").trim();
      if (!q) continue;
      turns.push({ user: q, assistant: assistantSideOf(r) });
    }
    return turns;
  } catch {
    // Memory is an improvement, not a precondition. A conversation with no
    // history is the behaviour this app had until now.
    return [];
  }
}

/**
 * What Qamar said back, or an honest note about what happened when it said
 * nothing.
 *
 * A refusal stored no sentence, and a meal reading stored a JSON array of
 * items. Replaying either verbatim would be worse than useless: an empty
 * content block is rejected outright, and `[]` invites the model to interpret
 * punctuation as an answer. The note says what took place instead, which is
 * the part that carries meaning into the next turn.
 */
function assistantSideOf(
  r: { kind: string; answer: string | null; in_scope: boolean; refusal_reason: string | null },
): string {
  const a = (r.answer ?? "").trim();
  if (r.refusal_reason) return `[declined: ${r.refusal_reason}]`;
  if (r.kind === "meal_analysis") {
    return a === "" || a === "[]"
      ? "[could not read that meal]"
      : "[read the meal and offered the items to confirm]";
  }
  if (!a || a.startsWith("[") || a.startsWith("{")) return "[no reply recorded]";
  return a;
}

/**
 * Writes a scanned product into the graph so the next person who scans it
 * pays nothing and gets its micronutrients.
 *
 * Marked unreviewed and ranked below the curated catalogue, like every other
 * imported food. The barcode goes in food_source_links, which is what makes
 * the second scan a local hit.
 */
async function rememberProduct(p: ScannedProduct): Promise<string | null> {
  try {
    const slug = `barcode_${p.barcode}`;
    const name = p.brand ? `${p.brand} ${p.name}` : p.name;
    const created = await db("foods?on_conflict=slug", {
      method: "POST",
      headers: { Prefer: "resolution=merge-duplicates,return=representation" },
      body: JSON.stringify({
        slug,
        name_en: name,
        food_state: "unspecified",
        is_recipe: false,
        source_rank: 10,
        confidence: 0.75,
        human_reviewed: false,
      }),
    });
    const foodId = (await created.json())[0]?.qamar_food_id as string | undefined;
    if (!foodId) return null;

    // The barcode itself is an alias, so typing the digits finds it too.
    await db("food_aliases?on_conflict=qamar_food_id,alias,lang", {
      method: "POST",
      headers: { Prefer: "resolution=merge-duplicates" },
      body: JSON.stringify([
        { qamar_food_id: foodId, alias: name.toLowerCase(), lang: "en", priority: 10 },
        { qamar_food_id: foodId, alias: p.barcode, lang: "en", priority: 10 },
      ]),
    });

    const rows = Object.entries(p.per100g).map(([code, amount]) => ({
      qamar_food_id: foodId,
      nutrient_code: code,
      amount,
      per_basis: "per_100g",
      source_id: p.source === "usda_branded" ? "usda_fdc" : "open_food_facts",
      nutrient_definition_version: "barcode-2026-08",
      confidence: 0.8,
    }));
    if (rows.length) {
      await db("food_nutrients?on_conflict=qamar_food_id,nutrient_code,per_basis", {
        method: "POST",
        headers: { Prefer: "resolution=merge-duplicates" },
        body: JSON.stringify(rows),
      });
    }

    await db("food_source_links?on_conflict=qamar_food_id,source_id,external_id", {
      method: "POST",
      headers: { Prefer: "resolution=merge-duplicates" },
      body: JSON.stringify({
        qamar_food_id: foodId,
        source_id: p.source === "usda_branded" ? "usda_fdc" : "open_food_facts",
        external_id: p.barcode,
        external_type: "barcode",
        url: p.sourceUrl,
      }),
    });
    return foodId;
  } catch (e) {
    // A caching failure must never cost the user their scan.
    console.error("ai-gateway rememberProduct", e);
    return null;
  }
}

function asString(v: unknown): string | undefined {
  return typeof v === "string" ? v : undefined;
}

function truthy(v: unknown): boolean {
  return v === true || v === "true";
}

interface SavedPlan {
  meals: Meal[];
  rationale_ar?: string | null;
  rationale_en?: string | null;
  sources?: unknown;
  model?: string | null;
}

/** The menu already written for this person today, or null if none. */
async function loadSavedPlan(userId: string, day: string): Promise<SavedPlan | null> {
  const res = await db(
    `meal_plans?user_id=eq.${userId}&plan_date=eq.${day}&select=meals,rationale_ar,rationale_en,sources,model`,
  );
  if (!res.ok) return null;
  const rows = await res.json();
  const row = Array.isArray(rows) ? rows[0] : null;
  if (!row || !Array.isArray(row.meals) || row.meals.length === 0) return null;
  return row as SavedPlan;
}

async function saveMealPlan(
  userId: string,
  day: string,
  meals: Meal[],
  targetKcal: number,
  rationaleAr: string | null,
  rationaleEn: string | null,
  sources: unknown,
  model: string | null,
): Promise<Response> {
  return await db("meal_plans?on_conflict=user_id,plan_date", {
    method: "POST",
    headers: { Prefer: "resolution=merge-duplicates,return=representation" },
    body: JSON.stringify({
      user_id: userId,
      plan_date: day,
      meals,
      target_kcal: targetKcal,
      rationale_ar: rationaleAr,
      rationale_en: rationaleEn,
      sources,
      model,
    }),
  });
}

function mealsFromBody(plan: unknown): Meal[] | null {
  if (!plan || typeof plan !== "object") return null;
  const meals = (plan as { meals?: unknown }).meals;
  if (!Array.isArray(meals) || meals.length === 0) return null;
  return meals as Meal[];
}

// ---- routes -------------------------------------------------------------

async function chatReply(userId: string, body: Record<string, unknown>): Promise<Response> {
  const message = (asString(body.message) ?? "").trim();
  const lang = asString(body.lang) === "ar" ? "ar" : "en";
  const day = (asString(body.date) ?? new Date().toISOString().slice(0, 10));

  let verdict = classify(message);

  // Someone said hello. Answer, and spend nothing doing it: no retrieval, no
  // model, no daily use. The first real conversation this app ever had opened
  // with "ازيك" and was told Qamar only covers food and training.
  if (verdict.allowed && "greeting" in verdict) {
    await record(userId, "chat", { inScope: true, question: message, model: "greeting" });
    return json({ reply: greetingText(lang), greeting: true });
  }

  // off_topic is now a hint, not a verdict.
  //
  // A keyword allowlist cannot hold a conversation. It refused "ازيك", it
  // refused "أنا تعبان النهاردة", and it refused someone saying they had eaten
  // koshary — because a list of thirty words is not a nutritionist's sense of
  // what belongs in their consulting room. The safety refusals below stay
  // deterministic and stay in front of the model, because those must never be
  // a matter of judgement. Deciding whether a message is about food is exactly
  // the kind of thing judgement is for, so it goes to the model, which then
  // answers or declines in one warm sentence.
  //
  // An off-topic message still costs nothing: if the model says it was out of
  // scope, the daily use is refunded below.
  const topicUncertain = !verdict.allowed && verdict.reason === "off_topic";
  if (topicUncertain) verdict = { allowed: true, domain: "nutrition" };

  if (!verdict.allowed) {
    const id = await record(userId, "chat", {
      inScope: false,
      refusal: verdict.reason,
      question: message,
    });
    await recordRefusal(SUPABASE_URL, SERVICE_KEY, userId, id, verdict.reason, message);
    return json({ reply: refusalText(verdict.reason, lang), refused: true, reason: verdict.reason });
  }

  const { ctx, blocked, lifeStage, target } = await loadContext(userId, lang);
  if (blocked) {
    const id = await record(userId, "chat", { inScope: false, refusal: "minor", question: message });
    await recordRefusal(SUPABASE_URL, SERVICE_KEY, userId, id, "minor", message);
    return json({ reply: refusalText("minor", lang), refused: true, reason: "minor" });
  }

  const saved = await loadSavedPlan(userId, day);
  const currentMeals = saved?.meals ?? mealsFromBody(body.current_plan);
  const swapped = Array.isArray(body.swapped_slots)
    ? (body.swapped_slots as unknown[]).filter((s): s is string => typeof s === "string")
    : [];
  const menuJson = currentMeals
    ? JSON.stringify({ date: day, meals: currentMeals, swapped_slots: swapped })
    : "";

  const [passages, retrievalMs] = await timed(() =>
    retrieve(SUPABASE_URL, SERVICE_KEY, message, verdict.domain)
  );
  // Empty retrieval used to end the conversation here. It should not: a
  // corpus of ten documents cannot cover everything a person says, and
  // "عدّل العشا" — change my dinner — was refused for want of a citation when
  // it is an instruction about their own plan, not a claim needing a source.
  //
  // Grounding now constrains what may be *asserted*, which the prompt states
  // and the verifier enforces on the numbers. It no longer decides whether
  // Qamar is allowed to speak.

  const lookup = [...foodTerms(message), ...foodTermsFromMeals(currentMeals)].slice(0, 16);
  const [resolved, resolveMs] = await timed(() =>
    resolveFoods(SUPABASE_URL, SERVICE_KEY, lookup)
  );
  // What was already said. Loaded before the use is taken so a fragment like
  // "and I got" is judged as the continuation it is, not as a sentence about
  // nothing.
  const history = await loadRecentTurns(userId);

  const taken = await takeAiUse(userId, lang);
  if (taken instanceof Response) return taken;
  const quota = taken;

  let called: Awaited<ReturnType<typeof callModel>>;
  try {
    called = await callModel({
      system: chatSystemPrompt(ctx, passages, renderResolutions(resolved), menuJson),
      user: message,
      maxTokens: 1600,
      prefill: "{",
      history,
    });
  } catch (e) {
    await refundAi(userId);
    throw e;
  }
  const { text, model, usage, latencyMs } = called;

  const parsed = parseJson<{
    reply?: string;
    in_scope?: boolean;
    action?: string;
    plan_update?: PlanUpdate | null;
  }>(text);

  // The model judged this out of scope. Record it as the refusal it is, and
  // give the daily use back — someone who asked Qamar about football should
  // not lose one of five nutrition questions for it. The reply is the model's
  // own sentence, so the decline is in their language and in character rather
  // than a canned line about keywords.
  if (parsed?.in_scope === false) {
    await refundAi(userId);
    const declined = (parsed.reply ?? "").trim() || refusalText("off_topic", lang);
    const id = await record(userId, "chat", {
      inScope: false,
      refusal: "off_topic",
      question: message,
      answer: declined,
      model,
    });
    await recordRefusal(SUPABASE_URL, SERVICE_KEY, userId, id, "off_topic", message);
    return json({ reply: declined, refused: true, reason: "off_topic" });
  }

  let reply: string;
  if (parsed && typeof parsed.reply === "string" && parsed.reply.trim()) {
    reply = parsed.reply.trim();
  } else if (!parsed && text.trim() && !text.trim().startsWith("{")) {
    reply = text.trim();
  } else {
    reply = lang === "ar"
      ? "فاهمة. قولي تاني وأنا أظبط اليوم."
      : "I heard you. Say that again and I will adjust the day.";
  }
  let action = (parsed?.action ?? "").trim() || undefined;
  let planUpdate = parsed?.plan_update ?? null;
  let plan: { meals: Meal[]; rationale_ar?: string | null; rationale_en?: string | null } | undefined;
  const verifications: Verification[] = [];

  // The only thing checkable in prose is whether it named something the person
  // cannot have — and even that is advisory, because a reply that mentions
  // sesame in order to refuse it looks identical to one suggesting it.
  const [constraints, verifyMs] = await timed(() =>
    loadHardConstraints(SUPABASE_URL, SERVICE_KEY, userId)
  );
  verifications.push(verifyChat(reply, constraints));

  const merged = planUpdate ? mergePlanUpdate(currentMeals, planUpdate) : null;
  if (merged?.kind === "rebuild") {
    planUpdate = {
      kind: "rebuild",
      instruction: merged.instruction || message,
    };
    if (!action) action = lang === "ar" ? "شوفي الخطة" : "See the plan";
  } else if (merged && (merged.kind === "replace_slot" || merged.kind === "replace_day")) {
    const planCheck = verifyPlan(merged.meals, ctx.targetKcal ?? null, constraints);
    verifications.push(planCheck);
    if (blocks(planCheck).length > 0) {
      // A restricted food does not land on the menu. The spoken reply still
      // goes out — they asked a question — but Plan/Today do not change.
      planUpdate = null;
    } else if (ctx.targetKcal) {
      const savedPlan = await saveMealPlan(
        userId,
        day,
        merged.meals,
        ctx.targetKcal,
        saved?.rationale_ar ?? null,
        saved?.rationale_en ?? (merged.instruction ?? null),
        resolvedSources(passages, resolved),
        model,
      );
      if (savedPlan.ok) {
        plan = {
          meals: merged.meals,
          rationale_ar: saved?.rationale_ar,
          rationale_en: saved?.rationale_en ?? merged.instruction,
        };
        planUpdate = { kind: merged.kind };
        if (!action) action = lang === "ar" ? "شوفي الخطة" : "See the plan";
      } else {
        planUpdate = null;
      }
    } else {
      planUpdate = null;
    }
  } else {
    planUpdate = null;
  }

  const sources = resolvedSources(passages, resolved);
  const id = await record(userId, "chat", {
    inScope: true,
    question: message,
    answer: reply,
    sources,
    model,
  });
  const flags: string[] = lifeStage === "none" ? [] : [`life_stage:${lifeStage}`];
  if (plan) flags.push("plan_updated");
  if (merged?.kind === "rebuild") flags.push("plan_rebuild");
  // Allowed requests are recorded too. A safety log that only holds refusals
  // cannot answer what proportion of traffic was high-risk, which is the
  // question an audit actually asks.
  await recordAllowed(
    SUPABASE_URL,
    SERVICE_KEY,
    userId,
    id,
    lifeStage === "none" ? "general_wellness" : "condition_aware",
    flags,
    plan ? ["answer_grounded", "update_plan"] : ["answer_grounded"],
  );

  const [facts, rules] = await Promise.all([
    loadUserFacts(SUPABASE_URL, SERVICE_KEY, userId, ctx),
    ruleSelection(SUPABASE_URL, SERVICE_KEY, { age: ctx.age ?? null, sex: ctx.gender ?? null, lifeStage }),
  ]);
  await trace(userId, id, "chat", {
    userFacts: facts,
    foodFacts: toPacketFacts(resolved),
    calculatedTargets: targetsFrom(ctx, target),
    applicableRules: rules.applicable,
    excludedRules: rules.excluded,
    candidateDecision: {
      reply: reply.slice(0, 2000),
      domain: verdict.domain,
      sources,
      plan_update: planUpdate,
    },
    safetyFlags: flags,
    uncertainty: {
      foods: resolutionUncertainty(resolved),
      passages_retrieved: passages.length,
    },
    claimsToVerify: numericClaims(reply),
  }, [
    { stage: "retrieval", externalCalls: 1, latencyMs: retrievalMs },
    { stage: "food_resolver", externalCalls: externalCallsIn(resolved), latencyMs: resolveMs },
    { stage: "reasoner", model, usage, latencyMs },
    { stage: "verifier", latencyMs: verifyMs },
  ], verifications);
  return json({
    reply,
    action,
    plan_update: planUpdate,
    ...(plan ? { plan, date: day } : {}),
    sources,
    refused: false,
    quota: quotaPayload(quota),
  });
}

/**
 * The photo the app sent, if it sent one.
 *
 * A meal photo arrives inline as base64 rather than as a storage path: the
 * picture is only needed for the length of this one call, so uploading it,
 * reading it back and then having to delete it buys nothing.
 *
 * Anthropic accepts images up to 5 MB after base64 encoding. The app already
 * downscales before sending; this is the backstop, and it refuses clearly
 * instead of letting the model call fail with something unreadable.
 */
const MAX_IMAGE_B64 = 5 * 1024 * 1024;
const ALLOWED_MEDIA = ["image/jpeg", "image/png", "image/webp", "image/gif"];

function readImage(body: { imageBase64?: string; imageMediaType?: string }): ImageInput | string | null {
  const data = (body.imageBase64 ?? "").trim();
  if (!data) return null;
  if (data.length > MAX_IMAGE_B64) return "image too large";
  const mediaType = (body.imageMediaType ?? "image/jpeg").toLowerCase();
  if (!ALLOWED_MEDIA.includes(mediaType)) return `unsupported image type ${mediaType}`;
  return { data, mediaType };
}

/**
 * A meal analysis restated as claims that can be checked without the model.
 *
 * Both checks named here are arithmetic: the macros must reconcile with the
 * kcal at 4/4/9, and the kcal must reconcile with the per-100g figures at the
 * portion claimed. Nothing here runs those checks — verifier_results is still
 * empty — but the claims have to be recorded in a checkable form before
 * anything can, and writing them down is what turns "the model said 520 kcal"
 * into something later provable or disprovable.
 */
function mealClaims(items: MealItem[]): unknown[] {
  return items.slice(0, 20).map((i) => ({
    claim: `${i?.en ?? i?.ar ?? "item"} at ${i?.portionEn ?? i?.portionAr ?? "unstated portion"}`,
    kcal: i?.kcal ?? null,
    macros: { protein_g: i?.proteinG ?? null, carbs_g: i?.carbsG ?? null, fat_g: i?.fatG ?? null },
    model_confidence: i?.confidence ?? null,
    check: "atwater_4_4_9_and_portion_arithmetic",
  }));
}

function graphMealNote(lang: "ar" | "en", items: MealItem[]): string {
  if (items.length === 0) {
    return lang === "ar"
      ? "مقدرتش ألاقي الأكل ده في قاعدة البيانات. جرّب اسم أوضح. تصوير الطبق لـ Qamar+."
      : "I could not match that to a food we know. Try a clearer name. Photographing a plate is Qamar+.";
  }
  return lang === "ar"
    ? "الأرقام من قاعدة الأكل، مش من الموديل. ظبّط الكميات قبل ما تأكد."
    : "These numbers come from the food database, not the model. Adjust the amounts before you confirm.";
}

/**
 * Prices a typed or spoken meal from the food graph only.
 *
 * This is the free-tier path. The daily AI counter, Voyage retrieval, and the
 * model stay off: a miss is an empty list, not a reason to call Claude.
 */
async function analyzeMealFromGraph(
  userId: string,
  lang: "ar" | "en",
  described: string,
  ctx: UserContext,
  lifeStage: string,
  target: TargetRow | null,
): Promise<Response> {
  const [resolved, resolveMs] = await timed(() =>
    resolveFoods(SUPABASE_URL, SERVICE_KEY, foodTerms(described))
  );
  const items = itemsFromResolutions(resolved);
  const sources = resolvedSources([], resolved);
  const verification = verifyMeal(items);

  let quota: Quota;
  try {
    quota = await quotaStatus(userId);
  } catch {
    quota = { allowed: true, used: 0, limit: 5, extra: 0, remaining: 5 };
  }

  const id = await record(userId, "meal_analysis", {
    inScope: true,
    question: described,
    answer: JSON.stringify(items).slice(0, 2000),
    sources,
    model: "graph",
  });
  const flags = lifeStage === "none" ? [] : [`life_stage:${lifeStage}`];
  await recordAllowed(
    SUPABASE_URL,
    SERVICE_KEY,
    userId,
    id,
    "general_wellness",
    flags,
    ["analyse_meal_graph"],
  );

  const [facts, rules] = await Promise.all([
    loadUserFacts(SUPABASE_URL, SERVICE_KEY, userId, ctx),
    ruleSelection(SUPABASE_URL, SERVICE_KEY, { age: ctx.age ?? null, sex: ctx.gender ?? null, lifeStage }),
  ]);
  await trace(userId, id, "meal_analysis", {
    userFacts: facts,
    foodFacts: toPacketFacts(resolved),
    calculatedTargets: targetsFrom(ctx, target),
    applicableRules: rules.applicable,
    excludedRules: rules.excluded,
    candidateDecision: { items, input: "text", priced_by: "graph" },
    safetyFlags: flags,
    uncertainty: {
      foods: resolutionUncertainty(resolved),
      passages_retrieved: 0,
      low_confidence_items: items
        .filter((i) => i?.confidence !== "high")
        .map((i) => i?.en ?? i?.ar ?? "unnamed"),
    },
    claimsToVerify: mealClaims(items),
  }, [{ stage: "food_resolver", externalCalls: externalCallsIn(resolved), latencyMs: resolveMs }], [verification]);

  return json({
    items,
    note: graphMealNote(lang, items),
    quota: quotaPayload(quota),
    sources,
    resolutions: toPacketFacts(resolved),
    verification: verificationSummary(verification),
  });
}

async function analyzeMeal(
  userId: string,
  body: { inputType?: string; text?: string; imageBase64?: string; imageMediaType?: string; lang?: string },
): Promise<Response> {
  const lang = body.lang === "ar" ? "ar" : "en";
  const described = (body.text ?? "").trim();

  const { ctx, blocked, lifeStage, target } = await loadContext(userId, lang);
  if (blocked) {
    const id = await record(userId, "meal_analysis", {
      inScope: false,
      refusal: "minor",
      question: described || "[photo]",
    });
    await recordRefusal(SUPABASE_URL, SERVICE_KEY, userId, id, "minor", described || "[photo]");
    return json({ error: "not eligible" }, 403);
  }

  const image = readImage(body);
  if (typeof image === "string") return json({ error: image }, 413);

  if (!described && !image) return json({ items: [], note: "nothing to analyse" });

  // Typed and spoken logs are the food graph: aliases, portions, per-100 g
  // numbers. No embeddings, no model, no daily AI use. A photo is the one
  // meal path that still needs vision, and that is what the five-a-day cap
  // is for.
  if (!image) {
    return await analyzeMealFromGraph(userId, lang, described, ctx, lifeStage, target);
  }

  // Free text names foods we can resolve; a photo does not, so resolution is
  // driven by whatever the user typed alongside it, if anything. The graph
  // answers first and knows what a رغيف weighs; an external lookup is the
  // fallback for what it does not carry.
  const [resolved, resolveMs] = await timed(() =>
    resolveFoods(SUPABASE_URL, SERVICE_KEY, foodTerms(described))
  );

  // Meal analysis needs the knowledge base as much as chat does: no food
  // database contains a cooked national dish, so the only way to price a plate
  // of koshary is to retrieve what it is made of and look up the ingredients.
  // A bare photo has no text to retrieve on, so it falls back to a standing
  // query that pulls the dish and household-portion documents.
  const [passages, retrievalMs] = await timed(() =>
    retrieve(
      SUPABASE_URL,
      SERVICE_KEY,
      described || "Egyptian dish ingredients and typical household portion sizes",
      "nutrition",
      6,
    )
  );

  // A photo with no caption still needs something in the user turn — the
  // instruction is what the picture is being asked about.
  const ask = image
    ? described || (lang === "ar" ? "الوجبة دي فيها إيه وكام سعرة؟" : "What is in this meal, and how many calories?")
    : described;

  const foodBlock = renderResolutions(resolved);
  const taken = await takeAiUse(userId, lang);
  if (taken instanceof Response) return taken;
  const quota = taken;

  let called: Awaited<ReturnType<typeof callModel>>;
  try {
    called = await callModel({
      system: image
        ? mealPhotoSystemPrompt(ctx, passages, foodBlock)
        : mealAnalysisSystemPrompt(ctx, passages, foodBlock),
      user: ask,
      maxTokens: 900,
      prefill: "{",
      image: image ?? undefined,
    });
  } catch (e) {
    await refundAi(userId);
    throw e;
  }
  const { text, model, usage, latencyMs } = called;

  const stages: StageCost[] = [
    { stage: "food_resolver", externalCalls: externalCallsIn(resolved), latencyMs: resolveMs },
    { stage: "retrieval", externalCalls: 1, latencyMs: retrievalMs },
    // Transcribing a plate into items is extraction, not reasoning, whatever
    // the size of the model doing it.
    { stage: "extractor", model, usage, latencyMs },
  ];

  const parsed = parseJson<{ items: MealItem[]; note_ar?: string; note_en?: string }>(text);
  if (!parsed?.items) {
    // A call that produced nothing usable still cost what it cost, and a run of
    // these is the signal that the prompt or the model has drifted. Recording
    // only successes is how that stays invisible until someone reads the bill.
    await trace(userId, null, "meal_analysis", {
      candidateDecision: { parse_failed: true, raw: text.slice(0, 1000) },
      uncertainty: { parse: "model did not return the requested JSON" },
    }, stages);
    await refundAi(userId);
    return json({ error: "could not analyse" }, 502);
  }

  // Check the arithmetic, and spend the one allowed correction if it fails.
  // The revision deliberately drops the photo and uses the text prompt: the
  // task has changed from "read this plate" to "fix these numbers in this
  // JSON", which needs no image and costs a fraction of the input tokens.
  let items = parsed.items;
  let verification = verifyMeal(items);
  const verifications: Verification[] = [verification];

  if (isRevisable(verification)) {
    const [retry, retryMs] = await timed(() =>
      callModel({
        system: mealAnalysisSystemPrompt(ctx, passages, foodBlock),
        user: revisionInstruction(verification, { items }),
        maxTokens: 900,
        prefill: "{",
      })
    );
    stages.push({ stage: "extractor", model: retry.model, usage: retry.usage, latencyMs: retryMs });
    const again = parseJson<{ items: MealItem[] }>(retry.text);
    const after = again?.items?.length ? finalVerdict(verifyMeal(again.items)) : null;
    if (after) verifications.push(after);
    if (after && isImprovement(verification, after)) {
      items = again!.items;
      verification = after;
    } else {
      // The correction did not land. The cap is spent either way, so the
      // original answer stands and the verdict says it was not fixed.
      verification = finalVerdict(verification);
    }
  }

  // Identify each final item against the graph, and hand the ids back with the
  // items so that whatever the app writes to meal_logs can be joined to
  // food_nutrients later. Done after the verifier rather than before, because a
  // revision can replace the item list and identifying the discarded one would
  // attach ids to a meal nobody ate.
  const [identities, identifyMs] = await timed(() =>
    identifyItems(SUPABASE_URL, SERVICE_KEY, items)
  );
  stages.push({
    stage: "food_resolver",
    externalCalls: identities.length * 2,
    latencyMs: identifyMs,
  });

  const itemsWithIdentity = items.map((item, i) => ({
    ...item,
    // Snake case on purpose: these two keys travel through the app into
    // meal_logs.items, and qamar_nutrient_intake reads them by these names.
    qamar_food_id: identities[i]?.qamarFoodId ?? null,
    grams: identities[i]?.grams ?? null,
    food_slug: identities[i]?.slug ?? null,
    portion_matched: identities[i]?.portionMatched ?? false,
  }));

  const sources = resolvedSources(passages, resolved);
  const id = await record(userId, "meal_analysis", {
    inScope: true,
    question: image ? `[photo] ${ask}` : ask,
    answer: JSON.stringify(items).slice(0, 2000),
    sources,
    model,
  });
  const flags = lifeStage === "none" ? [] : [`life_stage:${lifeStage}`];
  // Describing what someone ate is general wellness whatever their life stage —
  // it is prescription that pregnancy takes out of scope, not observation.
  await recordAllowed(
    SUPABASE_URL,
    SERVICE_KEY,
    userId,
    id,
    "general_wellness",
    flags,
    ["analyse_meal"],
  );

  const [facts, rules] = await Promise.all([
    loadUserFacts(SUPABASE_URL, SERVICE_KEY, userId, ctx),
    ruleSelection(SUPABASE_URL, SERVICE_KEY, { age: ctx.age ?? null, sex: ctx.gender ?? null, lifeStage }),
  ]);
  await trace(userId, id, "meal_analysis", {
    userFacts: facts,
    foodFacts: toPacketFacts(resolved),
    calculatedTargets: targetsFrom(ctx, target),
    applicableRules: rules.applicable,
    excludedRules: rules.excluded,
    candidateDecision: { items: itemsWithIdentity, input: image ? "photo" : "text" },
    safetyFlags: flags,
    uncertainty: {
      foods: resolutionUncertainty(resolved),
      passages_retrieved: passages.length,
      // An item with no food id contributes to the calorie total and to nothing
      // else. Recording which ones is how a thin micronutrient history later
      // gets explained rather than guessed at.
      unidentified_items: itemsWithIdentity
        .filter((i) => !i.qamar_food_id || !i.grams)
        .map((i) => i.ar ?? i.en ?? "unnamed"),
      // Every item the model itself marked uncertain. This is what the
      // confirmation screen is for, and what the verifier recomputes first.
      low_confidence_items: items
        .filter((i) => i?.confidence !== "high")
        .map((i) => i?.en ?? i?.ar ?? "unnamed"),
    },
    claimsToVerify: mealClaims(items),
  }, stages, verifications);

  let shown = quota;
  if (items.length === 0) {
    await refundAi(userId);
    try {
      shown = await quotaStatus(userId);
    } catch {
      shown = { ...quota, used: Math.max(quota.used - 1, 0), remaining: quota.remaining + 1, allowed: true };
    }
  }

  return json({
    // These carry qamar_food_id and grams. The app must persist them onto
    // meal_logs.items unchanged; dropping them costs nothing today and silently
    // costs every micronutrient answer from then on.
    items: itemsWithIdentity,
    // How much of this meal the log will actually be able to speak for. The
    // confirmation screen should say so when it is not all of it.
    identified: identities.filter((x) => x.qamarFoodId && x.grams).length,
    note: (lang === "ar" ? parsed.note_ar : parsed.note_en) ?? null,
    quota: quotaPayload(shown),
    sources,
    // What the graph made of each phrase: the canonical food, the portion it
    // assumed, and every reason it is unsure. The confirmation screen needs
    // this to ask a specific question rather than a vague one.
    resolutions: toPacketFacts(resolved),
    // Whether the numbers reconcile. An item whose macros do not match its kcal
    // is one of the two figures being wrong, and the app should not present
    // that as settled.
    verification: verificationSummary(verification),
  });
}

interface BodyScanShape {
  heightCm?: number | null;
  weightKg?: number | null;
  bodyFatPct?: number | null;
  age?: number | null;
  note?: string | null;
}

/**
 * Reads a body-composition report.
 *
 * Anything outside a plausible human range is dropped rather than trusted: a
 * misread "1.74" as 174 kg has to fail closed, because these numbers set the
 * person's calorie target and nobody re-checks them afterwards.
 */
function plausible(v: unknown, min: number, max: number, decimals = 0): number | null {
  if (typeof v !== "number" || !Number.isFinite(v)) return null;
  const factor = 10 ** decimals;
  const n = Math.round(v * factor) / factor;
  return n >= min && n <= max ? n : null;
}

/**
 * A scanned barcode, placed into the day.
 *
 * The flow the product asks for: point the camera at a packet of crisps and
 * have it counted and the rest of the day adjusted, without typing anything.
 *
 * Order matters here. The graph is asked first so a packet somebody has
 * already scanned costs nothing. The arithmetic — pack weight, the item's
 * kcal, what is left of the target — is all done here, deterministically, and
 * handed to the model as fact. The model is left with the judgement: does this
 * still work, and if not, what on the menu should move.
 */
async function scanBarcode(
  userId: string,
  body: { barcode?: string; lang?: string; date?: string; grams?: number },
): Promise<Response> {
  const lang = asString(body.lang) === "ar" ? "ar" : "en";
  const day = asString(body.date) ?? new Date().toISOString().slice(0, 10);
  const code = (asString(body.barcode) ?? "").replace(/\D/g, "");
  if (!code) return json({ error: "no barcode" }, 400);

  const { ctx, blocked, target } = await loadContext(userId, lang);
  if (blocked) {
    const id = await record(userId, "meal_analysis", {
      inScope: false,
      refusal: "minor",
      question: `[barcode] ${code}`,
    });
    await recordRefusal(SUPABASE_URL, SERVICE_KEY, userId, id, "minor", `[barcode] ${code}`);
    return json({ error: "not eligible" }, 403);
  }

  const [product, lookupMs] = await timed(() => lookupBarcode(code));
  if (!product) {
    // A local Egyptian brand nobody has catalogued. Saying so and offering the
    // label scan is the honest answer; inventing a plausible packet is not.
    await record(userId, "meal_analysis", {
      inScope: true,
      question: `[barcode] ${code}`,
      answer: "",
      model: "barcode",
    });
    return json({
      found: false,
      barcode: code,
      reply: lang === "ar"
        ? "المنتج ده مش في أي قاعدة بيانات لسه. صوّرلي جدول القيم الغذائية اللي ورا العلبة وأنا أقراه."
        : "That product is not in any database yet. Photograph the nutrition table on the back and I will read it.",
    }, 200);
  }

  await rememberProduct(product);

  // What was eaten, and what it came to.
  const asked = typeof body.grams === "number" && body.grams > 0 && body.grams <= 3000
    ? { grams: body.grams, label: `${body.grams} g`, assumed: false }
    : eatenPortion(product);
  const totals = scaleTo(product.per100g, asked.grams);
  const kcal = Math.round(totals.energy_kcal ?? 0);

  const eaten = await todaySoFar(userId, day);
  const targetKcal = ctx.targetKcal ?? null;
  const remaining = targetKcal == null ? null : targetKcal - eaten;

  const saved = await loadSavedPlan(userId, day);
  const currentMeals = saved?.meals ?? null;
  const menuJson = currentMeals ? JSON.stringify({ date: day, meals: currentMeals }) : "";

  const name = product.brand ? `${product.brand} ${product.name}` : product.name;
  const itemLine =
    `${name} — ${asked.label}${asked.assumed ? " (portion assumed, ask them)" : ""}: ` +
    `${kcal} kcal, P ${Math.round(totals.protein_g ?? 0)} g, ` +
    `C ${Math.round(totals.carbs_g ?? 0)} g, F ${Math.round(totals.fat_g ?? 0)} g`;

  const taken = await takeAiUse(userId, lang);
  if (taken instanceof Response) return taken;
  const quota = taken;

  let called: Awaited<ReturnType<typeof callModel>>;
  try {
    called = await callModel({
      system: scanPlacementSystemPrompt(
        ctx,
        { targetKcal, eatenKcal: eaten, remainingKcal: remaining, menuJson },
        itemLine,
        renderFoodLine(product),
      ),
      user: name,
      maxTokens: 900,
      prefill: "{",
    });
  } catch (e) {
    await refundAi(userId);
    throw e;
  }
  const { text, model, usage, latencyMs } = called;

  const parsed = parseJson<{ reply?: string; fits?: boolean; plan_update?: PlanUpdate | null }>(text);
  const reply = (parsed?.reply ?? "").trim() ||
    (lang === "ar" ? `${name}: ${kcal} سعرة.` : `${name}: ${kcal} kcal.`);

  // Apply whatever the model decided the menu should do, through the same
  // merge the chat route uses — one place where a plan is edited, not two.
  //
  // And through the same verification. A scan that rewrites dinner is a plan
  // change like any other, so it goes past the allergy check before it is
  // saved: the shortest path to putting sesame on somebody's menu would be a
  // route that edits the plan without the guard the other route has.
  let plan: { meals: Meal[] } | undefined;
  let rebuildNeeded: string | undefined;
  const verifications: Verification[] = [];
  if (parsed?.plan_update && currentMeals) {
    const merged = mergePlanUpdate(currentMeals, parsed.plan_update);
    if (merged?.kind === "rebuild") {
      // The day needs re-planning rather than patching. Say so; do not invent
      // the new meals here.
      rebuildNeeded = merged.instruction || name;
    } else if (merged && (merged.kind === "replace_slot" || merged.kind === "replace_day")) {
      const constraints = await loadHardConstraints(SUPABASE_URL, SERVICE_KEY, userId);
      const planCheck = verifyPlan(merged.meals, targetKcal, constraints);
      verifications.push(planCheck);
      if (blocks(planCheck).length > 0) {
        await recordHardBlock(
          SUPABASE_URL, SERVICE_KEY, userId, null, "restricted_food_in_generated_plan",
          { failures: blocks(planCheck), stage: "scan_plan_update" },
        );
      } else {
        await saveMealPlan(
          userId, day, merged.meals, targetKcal ?? 0,
          saved?.rationale_ar ?? null, saved?.rationale_en ?? null,
          saved?.sources ?? null, model,
        );
        plan = { meals: merged.meals };
      }
    }
  }

  const id = await record(userId, "meal_analysis", {
    inScope: true,
    question: `[barcode] ${code} ${name}`,
    answer: reply,
    model,
  });
  await recordAllowed(
    SUPABASE_URL, SERVICE_KEY, userId, id, "general_wellness", [], ["scan_barcode"],
  );

  const stages: StageCost[] = [
    { stage: "food_resolver", externalCalls: 1, latencyMs: lookupMs },
    { stage: "reasoner", model, usage, latencyMs },
  ];
  await trace(userId, id, "meal_analysis", {
    calculatedTargets: targetsFrom(ctx, target),
    candidateDecision: {
      barcode: code,
      product: name,
      grams: asked.grams,
      portion_assumed: asked.assumed,
      totals,
      eaten_before: eaten,
      remaining_before: remaining,
      fits: parsed?.fits ?? null,
      plan_changed: plan != null,
    },
    uncertainty: {
      portion_assumed: asked.assumed,
      source: product.source,
    },
    claimsToVerify: [{
      claim: "item kcal scaled from the product table",
      grams: asked.grams,
      kcal,
      check: "per_100g_times_weight",
    }],
  }, stages, verifications);

  return json({
    found: true,
    barcode: code,
    name,
    brand: product.brand,
    grams: asked.grams,
    portionLabel: asked.label,
    portionAssumed: asked.assumed,
    per100g: product.per100g,
    totals,
    kcal,
    // The app writes the log; these are the keys meal_logs.items needs so the
    // scan counts towards micronutrients like anything else.
    item: {
      name,
      qamar_food_id: null,
      grams: asked.grams,
      kcal,
      protein_g: Math.round(totals.protein_g ?? 0),
      carbs_g: Math.round(totals.carbs_g ?? 0),
      fat_g: Math.round(totals.fat_g ?? 0),
    },
    targetKcal,
    eatenKcal: eaten,
    remainingKcal: remaining == null ? null : remaining - kcal,
    fits: parsed?.fits ?? null,
    reply,
    plan,
    rebuildNeeded,
    source: product.source,
    sourceUrl: product.sourceUrl,
    quota: quotaPayload(quota),
  });
}

/** One line of food data for the placement prompt. */
function renderFoodLine(p: ScannedProduct): string {
  const f = asFoodFacts(p);
  return `${f.name}: per 100 g — ${f.per100g.kcal} kcal, P ${f.per100g.protein} g, ` +
    `C ${f.per100g.carbs} g, F ${f.per100g.fat} g (${f.source})`;
}

/**
 * The nutrition table on the back of a packet.
 *
 * This is the answer to the barcode route's own dead end: a local Egyptian
 * brand that no database has ever catalogued still has its figures printed on
 * it, and a photograph of that panel is better data than anything a model
 * could infer from the product's name.
 *
 * The model transcribes; label.ts decides whether the transcription can be
 * trusted and converts it to per 100 g. Everything after that is the barcode
 * route's path exactly — the same placement prompt, the same plan merge, the
 * same allergy check — because "how much of my day did this take" does not
 * depend on whether the product arrived by barcode or by camera.
 */
async function scanLabel(
  userId: string,
  body: {
    imageBase64?: string;
    imageMediaType?: string;
    lang?: string;
    date?: string;
    barcode?: string;
    name?: string;
    grams?: number;
  },
): Promise<Response> {
  const lang = asString(body.lang) === "ar" ? "ar" : "en";
  const day = asString(body.date) ?? new Date().toISOString().slice(0, 10);
  const barcode = (asString(body.barcode) ?? "").replace(/\D/g, "");

  const image = readImage(body);
  if (typeof image === "string") return json({ error: image }, 413);
  if (!image) return json({ error: "no image" }, 400);

  const { ctx, blocked, target } = await loadContext(userId, lang);
  if (blocked) {
    const id = await record(userId, "meal_analysis", {
      inScope: false,
      refusal: "minor",
      question: "[label]",
    });
    await recordRefusal(SUPABASE_URL, SERVICE_KEY, userId, id, "minor", "[label]");
    return json({ error: "not eligible" }, 403);
  }

  const taken = await takeAiUse(userId, lang);
  if (taken instanceof Response) return taken;
  const quota = taken;

  let read: Awaited<ReturnType<typeof callModel>>;
  try {
    read = await callModel({
      system: labelScanSystemPrompt(lang),
      user: lang === "ar" ? "اقرا الجدول ده." : "Read this panel.",
      maxTokens: 700,
      prefill: "{",
      image,
    });
  } catch (e) {
    await refundAi(userId);
    throw e;
  }

  const parsed = parseJson<LabelReading & { productName?: string | null }>(read.text);
  if (!parsed) {
    await refundAi(userId);
    await trace(userId, null, "meal_analysis", {
      candidateDecision: { parse_failed: true, raw: read.text.slice(0, 500) },
      uncertainty: { parse: "model did not return the requested JSON" },
    }, [{ stage: "extractor", model: read.model, usage: read.usage, latencyMs: read.latencyMs }]);
    return json({ error: "could not read the panel" }, 502);
  }

  const normalised = normaliseLabel(parsed);
  if (!normalised.ok) {
    // A panel that cannot be trusted is worth less than nothing, so the use is
    // given back and the person is told what to do differently.
    await refundAi(userId);
    const id = await record(userId, "meal_analysis", {
      inScope: true,
      question: "[label]",
      answer: normalised.problem,
      model: read.model,
    });
    await trace(userId, id, "meal_analysis", {
      candidateDecision: { label_rejected: normalised.problem, reading: parsed },
      uncertainty: { label: normalised.problem, note: parsed.note ?? null },
    }, [{ stage: "extractor", model: read.model, usage: read.usage, latencyMs: read.latencyMs }]);
    return json({
      found: false,
      problem: normalised.problem,
      reply: labelProblemText(normalised.problem, lang),
      quota: quotaPayload(quota),
    });
  }

  const label = normalised.value;
  const name = (asString(body.name) ?? parsed.productName ?? "").trim() ||
    (lang === "ar" ? "المنتج" : "the product");

  // A panel photographed after a barcode miss is the missing catalogue entry.
  // Saving it means nobody has to photograph that packet again.
  const product: ScannedProduct = {
    barcode: barcode || `label_${Date.now()}`,
    name,
    brand: null,
    per100g: label.per100g,
    packGrams: null,
    servingGrams: label.servingGrams,
    packLabel: null,
    source: "open_food_facts",
    sourceUrl: null,
  };
  if (barcode) await rememberProduct({ ...product, barcode });

  const asked = typeof body.grams === "number" && body.grams > 0 && body.grams <= 3000
    ? { grams: body.grams, label: `${body.grams} g`, assumed: false }
    : eatenPortion(product);
  const totals = scaleTo(label.per100g, asked.grams);
  const kcal = Math.round(totals.energy_kcal ?? 0);

  const eaten = await todaySoFar(userId, day);
  const targetKcal = ctx.targetKcal ?? null;
  const remaining = targetKcal == null ? null : targetKcal - eaten;

  const saved = await loadSavedPlan(userId, day);
  const currentMeals = saved?.meals ?? null;
  const menuJson = currentMeals ? JSON.stringify({ date: day, meals: currentMeals }) : "";

  const itemLine =
    `${name} — ${asked.label}${asked.assumed ? " (portion assumed, ask them)" : ""}: ` +
    `${kcal} kcal, P ${Math.round(totals.protein_g ?? 0)} g, ` +
    `C ${Math.round(totals.carbs_g ?? 0)} g, F ${Math.round(totals.fat_g ?? 0)} g` +
    (label.basis === "per_serving" ? " (panel was per serving; converted)" : "") +
    (label.energyFromKj ? " (energy converted from kJ)" : "");

  let placed: Awaited<ReturnType<typeof callModel>>;
  try {
    placed = await callModel({
      system: scanPlacementSystemPrompt(
        ctx,
        { targetKcal, eatenKcal: eaten, remainingKcal: remaining, menuJson },
        itemLine,
        `${name}: per 100 g — ${Math.round(label.per100g.energy_kcal ?? 0)} kcal (read off the packet)`,
      ),
      user: name,
      maxTokens: 900,
      prefill: "{",
    });
  } catch (e) {
    // The reading itself succeeded; the placement is the part that failed, and
    // the person should still get their numbers.
    console.error("ai-gateway label placement", e);
    placed = { text: "", model: read.model, usage: null, latencyMs: 0 };
  }

  const decision = parseJson<{ reply?: string; fits?: boolean; plan_update?: PlanUpdate | null }>(
    placed.text,
  );
  const reply = (decision?.reply ?? "").trim() ||
    (lang === "ar" ? `${name}: ${kcal} سعرة.` : `${name}: ${kcal} kcal.`);

  const verifications: Verification[] = [];
  let plan: { meals: Meal[] } | undefined;
  let rebuildNeeded: string | undefined;
  if (decision?.plan_update && currentMeals) {
    const merged = mergePlanUpdate(currentMeals, decision.plan_update);
    if (merged?.kind === "rebuild") {
      rebuildNeeded = merged.instruction || name;
    } else if (merged && (merged.kind === "replace_slot" || merged.kind === "replace_day")) {
      const constraints = await loadHardConstraints(SUPABASE_URL, SERVICE_KEY, userId);
      const planCheck = verifyPlan(merged.meals, targetKcal, constraints);
      verifications.push(planCheck);
      if (blocks(planCheck).length > 0) {
        await recordHardBlock(
          SUPABASE_URL, SERVICE_KEY, userId, null, "restricted_food_in_generated_plan",
          { failures: blocks(planCheck), stage: "label_plan_update" },
        );
      } else {
        await saveMealPlan(
          userId, day, merged.meals, targetKcal ?? 0,
          saved?.rationale_ar ?? null, saved?.rationale_en ?? null,
          saved?.sources ?? null, placed.model,
        );
        plan = { meals: merged.meals };
      }
    }
  }

  const id = await record(userId, "meal_analysis", {
    inScope: true,
    question: `[label] ${name}`,
    answer: reply,
    model: read.model,
  });
  await recordAllowed(
    SUPABASE_URL, SERVICE_KEY, userId, id, "general_wellness", [], ["scan_label"],
  );

  await trace(userId, id, "meal_analysis", {
    calculatedTargets: targetsFrom(ctx, target),
    candidateDecision: {
      source: "label",
      barcode: barcode || null,
      product: name,
      basis: label.basis,
      serving_grams: label.servingGrams,
      grams: asked.grams,
      totals,
      eaten_before: eaten,
      fits: decision?.fits ?? null,
      plan_changed: plan != null,
    },
    uncertainty: {
      portion_assumed: asked.assumed,
      energy_from_kj: label.energyFromKj,
      converted_from_serving: label.basis === "per_serving",
      note: parsed.note ?? null,
    },
    claimsToVerify: [{
      claim: "per-100g figures transcribed from the printed panel",
      basis: label.basis,
      kcal_per_100g: label.per100g.energy_kcal,
      check: "label_transcription",
    }],
  }, [
    { stage: "extractor", model: read.model, usage: read.usage, latencyMs: read.latencyMs },
    { stage: "reasoner", model: placed.model, usage: placed.usage, latencyMs: placed.latencyMs },
  ], verifications);

  return json({
    found: true,
    name,
    barcode: barcode || null,
    basis: label.basis,
    servingGrams: label.servingGrams,
    energyFromKj: label.energyFromKj,
    per100g: label.per100g,
    grams: asked.grams,
    portionLabel: asked.label,
    portionAssumed: asked.assumed,
    totals,
    kcal,
    item: {
      name,
      qamar_food_id: null,
      grams: asked.grams,
      kcal,
      protein_g: Math.round(totals.protein_g ?? 0),
      carbs_g: Math.round(totals.carbs_g ?? 0),
      fat_g: Math.round(totals.fat_g ?? 0),
    },
    targetKcal,
    eatenKcal: eaten,
    remainingKcal: remaining == null ? null : remaining - kcal,
    fits: decision?.fits ?? null,
    reply,
    plan,
    rebuildNeeded,
    note: parsed.note ?? null,
    quota: quotaPayload(quota),
  });
}

async function readBodyScan(
  userId: string,
  body: { imageBase64?: string; imageMediaType?: string; lang?: string },
): Promise<Response> {
  const lang = body.lang === "ar" ? "ar" : "en";
  const image = readImage(body);
  if (typeof image === "string") return json({ error: image }, 413);
  if (!image) return json({ error: "no image supplied" }, 400);

  const { text, model, usage, latencyMs } = await callModel({
    system: bodyScanSystemPrompt(lang),
    user: lang === "ar" ? "اقرا الأرقام اللي في التقرير ده." : "Read the figures on this report.",
    maxTokens: 400,
    prefill: "{",
    image,
  });
  const stages: StageCost[] = [{ stage: "extractor", model, usage, latencyMs }];

  const parsed = parseJson<BodyScanShape>(text);
  if (!parsed) {
    await trace(userId, null, "body_scan", {
      candidateDecision: { parse_failed: true, raw: text.slice(0, 1000) },
      uncertainty: { parse: "model did not return the requested JSON" },
    }, stages);
    return json({ error: "could not read the report" }, 502);
  }

  // Weight and body fat keep one decimal: the profile columns are numeric, and
  // a smoothed weight trend cannot see a change smaller than the rounding it
  // was stored with. Height and age are whole numbers on the page anyway.
  const result = {
    heightCm: plausible(parsed.heightCm, 120, 230),
    weightKg: plausible(parsed.weightKg, 30, 300, 1),
    bodyFatPct: plausible(parsed.bodyFatPct, 3, 70, 1),
    age: plausible(parsed.age, 13, 100),
    note: typeof parsed.note === "string" ? parsed.note : null,
  };

  const id = await record(userId, "body_scan", {
    inScope: true,
    question: "[body scan]",
    answer: JSON.stringify(result),
    model,
  });

  // What the model claimed before the plausibility filter, alongside what
  // survived it. A field the model read and this rejected is the single most
  // useful thing in the trace — it is either a misread digit caught, or a
  // range set too tight, and the two are indistinguishable without both halves.
  const dropped = (["heightCm", "weightKg", "bodyFatPct", "age"] as const)
    .filter((k) => parsed[k] != null && result[k] == null);
  await trace(userId, id, "body_scan", {
    candidateDecision: { read: result, raw: parsed },
    claimsToVerify: (["heightCm", "weightKg", "bodyFatPct", "age"] as const)
      .filter((k) => result[k] != null)
      .map((k) => ({ claim: k, value: result[k], check: "transcription_against_image" })),
    uncertainty: {
      not_legible: (["heightCm", "weightKg", "bodyFatPct", "age"] as const)
        .filter((k) => parsed[k] == null),
      rejected_as_implausible: dropped,
    },
    safetyFlags: dropped.length ? ["body_scan_value_rejected"] : [],
  }, stages);
  return json(result);
}

interface PlanShape {
  meals: Meal[];
  rationale_ar?: string;
  rationale_en?: string;
}

async function generatePlan(userId: string, body: Record<string, unknown>): Promise<Response> {
  const lang = asString(body.lang) === "ar" ? "ar" : "en";
  const day = asString(body.date) ?? new Date().toISOString().slice(0, 10);
  const force = truthy(body.force);
  const instruction = (asString(body.instruction) ?? "").trim();

  const { ctx, blocked, lifeStage, target } = await loadContext(userId, lang);
  if (blocked) {
    const id = await record(userId, "plan", { inScope: false, refusal: "minor", question: "[plan]" });
    await recordRefusal(SUPABASE_URL, SERVICE_KEY, userId, id, "minor", "[plan]");
    return json({ error: "not eligible" }, 403);
  }

  // Pregnancy and lactation are out of consumer-wellness scope, and the
  // pregnancy module in clinical_modules is not approved. Prescribing a day of
  // eating is exactly the act that is out of scope — which is why this gate is
  // here and not on chat or meal analysis, where the user is asking about food
  // rather than being told what to eat.
  if (lifeStage !== "none") {
    const id = await record(userId, "plan", {
      inScope: false,
      refusal: "pregnancy",
      question: `[plan] life_stage=${lifeStage}`,
    });
    await recordRefusal(
      SUPABASE_URL, SERVICE_KEY, userId, id, "pregnancy", `[plan] life_stage=${lifeStage}`,
    );
    return json({ error: refusalText("pregnancy", lang), refused: true, reason: "life_stage" }, 409);
  }

  if (!ctx.targetKcal) return json({ error: "no target yet — finish onboarding first" }, 409);

  // Stored rather than regenerated so talking to Qamar can edit today's menu
  // without the next visit to Plan silently replacing it. force and a
  // nutritionist instruction are the two ways a new day of eating is written.
  if (!force && !instruction) {
    const existing = await loadSavedPlan(userId, day);
    if (existing) {
      let quota: Record<string, number> | undefined;
      try {
        quota = quotaPayload(await quotaStatus(userId));
      } catch {
        // A saved day still belongs on the screen even if the counter is down.
      }
      return json({
        plan: {
          meals: existing.meals,
          rationale_ar: existing.rationale_ar,
          rationale_en: existing.rationale_en,
        },
        date: day,
        reused: true,
        sources: existing.sources ?? [],
        ...(quota ? { quota } : {}),
      });
    }
  }

  const brief =
    `daily meal plan for ${ctx.targetKcal} kcal, goal ${ctx.goal ?? "maintain"}, ` +
    `Egyptian home cooking, avoiding ${ctx.exclusions?.join(", ") || "nothing"}`;
  const user = instruction
    ? `${brief}\n\nNutritionist adjustment — rewrite today's meals for this, keeping exclusions and the calorie target:\n${instruction}`
    : brief;

  const [passages, retrievalMs] = await timed(() =>
    retrieve(SUPABASE_URL, SERVICE_KEY, instruction ? `${brief} ${instruction}` : brief, "nutrition", 8)
  );
  if (passages.length === 0) return json({ error: "no grounded guidance available" }, 503);

  // Look the staples up so the model has real per-100g figures to divide.
  // Resolved through the graph, so the plan is built on Egyptian foods with
  // known household portions rather than whatever an international database
  // returns for "bread".
  const staples = [
    "فول", "عيش بلدي", "رز", "فراخ", "زبادي", "شوفان",
    "موز", "زيت زيتون", "طماطم", "خيار", "بيض", "تونة", "جبنة قريش", "عدس أصفر",
  ];
  const [resolvedAll, resolveMs] = await timed(() =>
    resolveFoods(SUPABASE_URL, SERVICE_KEY, staples)
  );

  // Hard constraints are applied before the model sees the food list, not
  // checked afterwards. An allergen the model never receives cannot end up in
  // the plan, whereas one it receives and is merely asked to avoid depends on
  // it obeying an instruction.
  const constraints = await loadHardConstraints(SUPABASE_URL, SERVICE_KEY, userId);
  const excludedFoods: { food: string; restriction: string }[] = [];
  const resolved: Resolution[] = [];
  for (const r of resolvedAll) {
    const hit = r.facts
      ? violatesConstraint(constraints, {
        name: [r.facts.name, r.food?.nameAr, r.food?.nameEg, r.phrase].filter(Boolean).join(" "),
      })
      : null;
    if (hit) {
      await recordHardBlock(SUPABASE_URL, SERVICE_KEY, userId, null, "restricted_food_excluded", {
        food: r.food?.slug ?? r.phrase,
        restriction: hit.label,
        kind: hit.kind,
        severity: hit.severity,
        stage: "plan_staples",
      });
      excludedFoods.push({ food: r.food?.slug ?? r.phrase, restriction: hit.label });
      continue;
    }
    resolved.push(r);
  }

  // What the last week of their own logging says they are short on. A plan
  // built on a calorie number alone is an allocation; this is the part that
  // makes it advice. Empty is a normal answer — nothing logged, or nothing
  // short — and the prompt says explicitly not to speculate when it is.
  //
  // Read before the daily use is taken, deliberately. It is a database call
  // that costs nothing, and charging someone a use for a plan that then fails
  // to generate is the wrong order.
  const [gaps, gapsMs] = await timed(() => nutrientGaps(SUPABASE_URL, SERVICE_KEY, userId, 7));

  const taken = await takeAiUse(userId, lang);
  if (taken instanceof Response) return taken;
  const quota = taken;

  let called: Awaited<ReturnType<typeof callModel>>;
  try {
    called = await callModel({
      system: planSystemPrompt(ctx, passages, renderResolutions(resolved), gaps),
      user,
      maxTokens: 2000,
      prefill: "{",
    });
  } catch (e) {
    await refundAi(userId);
    throw e;
  }
  const { text, model, usage, latencyMs } = called;
  const stages: StageCost[] = [
    { stage: "retrieval", externalCalls: 1, latencyMs: retrievalMs },
    { stage: "food_resolver", externalCalls: externalCallsIn(resolvedAll), latencyMs: resolveMs },
    { stage: "requirement", externalCalls: 1, latencyMs: gapsMs },
    { stage: "reasoner", model, usage, latencyMs },
  ];

  const parsed = parseJson<PlanShape>(text);
  if (!parsed?.meals?.length) {
    await trace(userId, null, "plan", {
      candidateDecision: { parse_failed: true, raw: text.slice(0, 1000) },
      uncertainty: { parse: "model did not return the requested JSON" },
    }, stages);
    await refundAi(userId);
    return json({ error: "could not generate a plan" }, 502);
  }

  // Verification happens before the plan is saved or shown. The constraint
  // check here is not the same as the filtering above: that removed restricted
  // foods from the list the model was *shown*, and nothing stopped it naming
  // one that was never on the list. This is the difference between asking it
  // not to and checking that it did not.
  let meals = parsed.meals;
  let verification = verifyPlan(meals, ctx.targetKcal, constraints);
  const verifications: Verification[] = [verification];

  if (isRevisable(verification)) {
    const [retry, retryMs] = await timed(() =>
      callModel({
        system: planSystemPrompt(ctx, passages, renderResolutions(resolved), gaps),
        user: revisionInstruction(verification, { meals }),
        maxTokens: 2000,
        prefill: "{",
      })
    );
    stages.push({ stage: "reasoner", model: retry.model, usage: retry.usage, latencyMs: retryMs });
    const again = parseJson<PlanShape>(retry.text);
    const after = again?.meals?.length
      ? finalVerdict(verifyPlan(again.meals, ctx.targetKcal, constraints))
      : null;
    if (after) verifications.push(after);
    if (after && isImprovement(verification, after)) {
      meals = again!.meals;
      verification = after;
    } else {
      verification = finalVerdict(verification);
    }
  }

  const flags = constraints.length ? [`hard_constraints:${constraints.length}`] : [];
  const blocking = blocks(verification);
  const sources = resolvedSources(passages, resolved);

  if (blocking.length > 0) {
    // A plan naming something the person is allergic to is not a draft to
    // improve. It is not saved, not returned, and not re-asked for: the model
    // has already been told and has already ignored it once, so another round
    // of the same model is not a control. The user gets a plain refusal and a
    // human gets a row to look at.
    await recordHardBlock(SUPABASE_URL, SERVICE_KEY, userId, null, "restricted_food_in_generated_plan", {
      failures: blocking,
      restrictions: constraints.map((c) => c.label),
      stage: "plan_verification",
    });
    await trace(userId, null, "plan", {
      userFacts: await loadUserFacts(SUPABASE_URL, SERVICE_KEY, userId, ctx),
      foodFacts: toPacketFacts(resolved),
      calculatedTargets: targetsFrom(ctx, target),
      candidateDecision: { meals, plan_date: day, rejected: true },
      safetyFlags: [...flags, "restricted_food_in_output"],
      uncertainty: { staples_withheld: excludedFoods },
    }, stages, verifications);
    await refundAi(userId);
    return json({
      error: lang === "ar"
        ? "الخطة اللي اتولدت فيها حاجة مش مفروض تاكلها، فمنفعش أعرضهالك. جرّب تاني من فضلك."
        : "The generated plan included something you have told me you cannot eat, so I am not showing it. Please try again.",
      refused: true,
      reason: "failed_safety_verification",
    }, 409);
  }

  const saved = await saveMealPlan(
    userId,
    day,
    meals,
    ctx.targetKcal,
    parsed.rationale_ar ?? null,
    parsed.rationale_en ?? null,
    sources,
    model,
  );
  if (!saved.ok) {
    await refundAi(userId);
    return json({ error: `could not save plan: ${await saved.text()}` }, 500);
  }

  const planId = await record(userId, "plan", {
    inScope: true,
    question: user,
    answer: JSON.stringify(meals).slice(0, 2000),
    sources,
    model,
  });
  await recordAllowed(
    SUPABASE_URL,
    SERVICE_KEY,
    userId,
    planId,
    "general_wellness",
    flags,
    ["generate_plan"],
  );

  const [facts, rules] = await Promise.all([
    loadUserFacts(SUPABASE_URL, SERVICE_KEY, userId, ctx),
    ruleSelection(SUPABASE_URL, SERVICE_KEY, { age: ctx.age ?? null, sex: ctx.gender ?? null, lifeStage }),
  ]);
  await trace(userId, planId, "plan", {
    userFacts: facts,
    foodFacts: toPacketFacts(resolved),
    calculatedTargets: targetsFrom(ctx, target),
    applicableRules: rules.applicable,
    excludedRules: rules.excluded,
    // The shortfalls this plan was asked to close, and how much of the week's
    // logging they were computed from. Without the coverage figure a reviewer
    // cannot tell a real iron gap from three days of unidentified meals.
    candidateDecision: {
      meals,
      plan_date: day,
      addressed_gaps: gaps.map((g) => ({
        nutrient: g.nameEn,
        pct_of_target: g.pctOfTarget,
        kind: g.kind,
        log_coverage_pct: g.coveragePct,
      })),
    },
    safetyFlags: excludedFoods.length ? [...flags, "restricted_food_excluded"] : flags,
    uncertainty: {
      foods: resolutionUncertainty(resolved),
      passages_retrieved: passages.length,
      // Staples dropped before the model saw them. Without this the plan looks
      // like it simply never thought of eggs, rather than like it was stopped
      // from suggesting them.
      staples_withheld: excludedFoods,
    },
    // The plan's own arithmetic: the prompt requires the three meals to land
    // within 5% of the target, and that is checkable from the meals alone.
    claimsToVerify: [{
      claim: "meals total within 5% of the daily target",
      target_kcal: ctx.targetKcal,
      check: "sum_portion_kcal_against_target",
    }],
  }, stages, verifications);

  // An energy sum that is still off after its one correction is returned, not
  // withheld — refusing a whole day of food over a 9% miss would be worse for
  // the person than showing it. What must not happen is presenting it as
  // checked, so the recomputed total travels with it and `verified` is false.
  return json({
    plan: { ...parsed, meals },
    date: day,
    sources,
    verification: verificationSummary(verification),
    quota: quotaPayload(quota),
  });
}

// ---- entry --------------------------------------------------------------

Deno.serve(async (req) => {
  if (req.method === "OPTIONS") return new Response("ok", { headers: CORS });
  if (req.method !== "POST") return json({ error: "POST only" }, 405);

  const userId = await authenticate(req);
  if (!userId) return json({ error: "unauthorized" }, 401);

  let body: Record<string, unknown> = {};
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
        return await analyzeMeal(userId, body as {
          inputType?: string;
          text?: string;
          imageBase64?: string;
          imageMediaType?: string;
          lang?: string;
        });
      case "/plan/generate":
        return await generatePlan(userId, body);
      case "/scan/barcode":
        return await scanBarcode(userId, body as {
          barcode?: string;
          lang?: string;
          date?: string;
          grams?: number;
        });
      case "/scan/label":
        return await scanLabel(userId, body as {
          imageBase64?: string;
          imageMediaType?: string;
          lang?: string;
          date?: string;
          barcode?: string;
          name?: string;
          grams?: number;
        });
      case "/scan/read":
        return await readBodyScan(userId, body as {
          imageBase64?: string;
          imageMediaType?: string;
          lang?: string;
        });
      case "/quota":
        return json(quotaPayload(await quotaStatus(userId)));
      default:
        return json({ error: `unknown route ${route}` }, 404);
    }
  } catch (e) {
    console.error("ai-gateway", route, e);
    return json({ error: "gateway error" }, 500);
  }
});
