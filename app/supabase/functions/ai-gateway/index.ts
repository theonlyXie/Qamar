// Qamar AI gateway.
//
// The app never holds a model key: it calls here with the user's Supabase JWT,
// and this decides whether the question is answerable, gathers the evidence,
// calls the model, and records what happened.
//
// Routes:
//   POST /ai-gateway/chat/reply     { message, lang, date?, current_plan?, swapped_slots?, imageBase64?, imageMediaType? }
//   POST /ai-gateway/meal/analyze   { inputType, text?, imageBase64?, imageMediaType? }
//     text/voice: food graph only — no model, never counted
//     photo: the photo bucket (3/day on Lite, more with Su) + vision model
//   POST /ai-gateway/plan/generate  { date?, lang?, force?, instruction? }
//   POST /ai-gateway/plan/nightly   {}   X-Qamar-Cron header, not a user JWT — the 22:00 job
//     the plan bucket — a small cap for everyone
//   POST /ai-gateway/scan/read      { imageBase64, imageMediaType, lang }
//     the photo bucket + vision model
//   POST /ai-gateway/quota          {}  → every bucket
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
  mealAnalysisSystemPrompt,
  mealPhotoSystemPrompt,
  parseJson,
  planSystemPrompt,
  type ImageInput,
  type UserContext,
} from "./model.ts";
import { retrieve, type FoodFacts, type Passage, type Source } from "./retrieval.ts";
import {
  identifyItems,
  itemsFromResolutions,
  renderResolutions,
  resolveFoods,
  toPacketFacts,
  type Resolution,
} from "./graph.ts";
import { graphMealNote, modelMealNote } from "./notes.ts";
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
import { asQuota, quotaExceededMessage, quotaPayload, type Bucket, type Quota } from "./quota.ts";
import {
  cairoDatePlus,
  cairoNow,
  chunks,
  dueMembers,
  isNightlyWindow,
  type NightlyReport,
  nightSentence,
  planKcal,
  RETURN_DAYS,
  returningAudience,
  returnSentence,
  RUN_BUDGET_MS,
} from "./nightly.ts";

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

/** Spends one of today's uses in the named bucket. Typed and spoken logs never call this. */
async function consumeAi(userId: string, bucket: Bucket): Promise<Quota> {
  const q = asQuota(await rpcJson("qamar_ai_try_consume", { p_user_id: userId, p_bucket: bucket }), bucket);
  if (!q) throw new Error("quota consume returned nothing usable");
  return q;
}

async function refundAi(userId: string, bucket: Bucket): Promise<void> {
  try {
    await rpcJson("qamar_ai_refund_consume", { p_user_id: userId, p_bucket: bucket });
  } catch (e) {
    console.error("ai-gateway refund", e);
  }
}

/**
 * Every bucket at once, as the database reports it: the flat fields are the
 * chat bucket for anything reading the old shape, and `photo`, `chat`, `plan`
 * carry each bucket in full. Passed to the app untouched.
 */
async function quotaSnapshot(userId: string): Promise<Record<string, unknown>> {
  const raw = await rpcJson("qamar_ai_quota_snapshot", { p_user_id: userId });
  if (!raw || typeof raw !== "object") throw new Error("quota snapshot returned nothing usable");
  return raw as Record<string, unknown>;
}

/** One bucket out of the snapshot, for a response that spent nothing. */
async function quotaStatus(userId: string, bucket: Bucket): Promise<Quota> {
  const snap = await quotaSnapshot(userId);
  const q = asQuota(snap[bucket], bucket);
  if (!q) throw new Error("quota snapshot returned nothing usable");
  return q;
}

function quotaDenied(lang: "ar" | "en", q: Quota): Response {
  const message = quotaExceededMessage(lang, q.bucket, q.plus === true);
  return json({
    error: message,
    reply: message,
    refused: true,
    reason: "quota",
    quota: quotaPayload(q),
  }, 429);
}

async function takeAiUse(userId: string, lang: "ar" | "en", bucket: Bucket): Promise<Quota | Response> {
  try {
    const q = await consumeAi(userId, bucket);
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
      // Ramadan mode (0050): the plan becomes iftar and suhoor.
      fasting: p?.fasting_mode ?? "none",
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

/** Whether this account is on Qamar+ right now, by the rule the database uses. */
async function isPlusMember(userId: string): Promise<boolean> {
  const res = await db("rpc/qamar_is_plus", { method: "POST", body: JSON.stringify({ p_user_id: userId }) });
  if (!res.ok) return false;
  return (await res.json()) === true;
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

/** The question a menu photo asks when the person typed nothing with it. */
function menuQuestion(lang: "ar" | "en"): string {
  return lang === "ar" ? "أطلب إيه من هنا؟" : "What should I order from this menu?";
}

async function chatReply(userId: string, body: Record<string, unknown>): Promise<Response> {
  const lang = asString(body.lang) === "ar" ? "ar" : "en";
  const day = (asString(body.date) ?? new Date().toISOString().slice(0, 10));

  // A photo in the conversation — a restaurant menu, a label, a plate on the
  // table — rides the same route as a question. It is metered as a photo,
  // because that is what costs the model call, and the words with it may be
  // empty: the question is implied.
  const image = readImage(body as { imageBase64?: string; imageMediaType?: string });
  if (typeof image === "string") return json({ error: image }, 400);
  const typed = (asString(body.message) ?? "").trim();
  const message = typed || (image ? menuQuestion(lang) : "");
  const bucket: Bucket = image ? "photo" : "chat";

  // The safety gate reads the words either way. Only the "not about food"
  // outcome is overridden by a photo, since "what do I order here" carries no
  // food term and the picture is the food.
  let verdict = classify(message);
  if (!verdict.allowed && verdict.reason === "off_topic" && image) {
    verdict = { allowed: true, domain: "nutrition" };
  }
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

  const domain = verdict.domain;
  const [passages, retrievalMs] = await timed(() =>
    retrieve(
      SUPABASE_URL,
      SERVICE_KEY,
      image ? `${message} — choosing from a restaurant menu, eating out, portion size` : message,
      domain,
    )
  );
  if (passages.length === 0 && !image) {
    // No grounding, no answer. This is the rule that stops the assistant
    // becoming a general chatbot the moment retrieval is empty.
    const reply = lang === "ar"
      ? "معنديش مصدر موثوق يجاوب على ده دلوقتي، ومش هألّف. جرّب تسأل بطريقة تانية أو عن حاجة أقرب للأكل والتمرين."
      : "I do not have a grounded source for that right now, and I will not make one up. Try asking differently, or about something closer to food and training.";
    await record(userId, "chat", { inScope: true, refusal: "no_grounding", question: message, answer: reply });
    return json({ reply, refused: true, reason: "no_grounding" });
  }

  const lookup = [...foodTerms(message), ...foodTermsFromMeals(currentMeals)].slice(0, 16);
  const [resolved, resolveMs] = await timed(() =>
    resolveFoods(SUPABASE_URL, SERVICE_KEY, lookup)
  );
  // The fourth question of the day is the paywall; a photo spends a photo.
  const taken = await takeAiUse(userId, lang, bucket);
  if (taken instanceof Response) return taken;
  const quota = taken;

  let called: Awaited<ReturnType<typeof callModel>>;
  try {
    called = await callModel({
      system: chatSystemPrompt(ctx, passages, renderResolutions(resolved), menuJson, { photo: image !== null }),
      user: message,
      maxTokens: 1600,
      prefill: "{",
      ...(image ? { image } : {}),
    });
  } catch (e) {
    await refundAi(userId, bucket);
    throw e;
  }
  const { text, model, usage, latencyMs } = called;

  const parsed = parseJson<{ reply?: string; action?: string; plan_update?: PlanUpdate | null }>(text);
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
  // The audit row notes that a photo was attached; the photo itself is never
  // stored.
  const id = await record(userId, "chat", {
    inScope: true,
    question: image ? `[photo] ${message}` : message,
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
      domain,
      input: image ? "photo" : "text",
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

  // Nothing was spent; report the photo bucket so the app can show what a
  // photo would cost next.
  let quota: Quota;
  // Whether today's photos are known: a note offers a photo only when they
  // are, and some are left (notes.ts).
  let quotaKnown = true;
  try {
    quota = await quotaStatus(userId, "photo");
  } catch {
    quotaKnown = false;
    quota = { bucket: "photo", allowed: true, used: 0, limit: 3, extra: 0, remaining: 3 };
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
    note: graphMealNote(lang, items, quotaKnown && quota.remaining > 0),
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
  // A photo is the photo bucket: three a day on Lite, more with Su, and never
  // a paywall on its own.
  const taken = await takeAiUse(userId, lang, "photo");
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
    await refundAi(userId, "photo");
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
    await refundAi(userId, "photo");
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

  // An empty item list is a real answer the model was paid for — a photo too
  // dark to read, or not food. It used to be refunded, which made "send a
  // black image" a free, unbounded vision call. The use stands; only a
  // parse failure above, which is our fault, is refunded.
  const shown = quota;

  return json({
    // These carry qamar_food_id and grams. The app must persist them onto
    // meal_logs.items unchanged; dropping them costs nothing today and silently
    // costs every micronutrient answer from then on.
    items: itemsWithIdentity,
    // How much of this meal the log will actually be able to speak for. The
    // confirmation screen should say so when it is not all of it.
    identified: identities.filter((x) => x.qamarFoodId && x.grams).length,
    // Never about the score: a note that talks points is dropped (notes.ts).
    note: modelMealNote(lang === "ar" ? parsed.note_ar : parsed.note_en),
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

async function readBodyScan(
  userId: string,
  body: { imageBase64?: string; imageMediaType?: string; lang?: string },
): Promise<Response> {
  const lang = body.lang === "ar" ? "ar" : "en";
  const image = readImage(body);
  if (typeof image === "string") return json({ error: image }, 413);
  if (!image) return json({ error: "no image supplied" }, 400);

  // Same gates as every other model route. This one used to have neither: any
  // anonymous sign-up could loop vision calls through it at no cost to them
  // and full cost to us, and a blocked profile could reach the model here when
  // it could not anywhere else. A body scan is one use of the day, like a
  // meal photo — it is the same call to the same model.
  const { blocked } = await loadContext(userId, lang);
  if (blocked) {
    const id = await record(userId, "body_scan", { inScope: false, refusal: "minor", question: "[body scan]" });
    await recordRefusal(SUPABASE_URL, SERVICE_KEY, userId, id, "minor", "[body scan]");
    return json({ error: "not eligible" }, 403);
  }
  const taken = await takeAiUse(userId, lang, "photo");
  if (taken instanceof Response) return taken;
  const quota = taken;

  let called: Awaited<ReturnType<typeof callModel>>;
  try {
    called = await callModel({
      system: bodyScanSystemPrompt(lang),
      user: lang === "ar" ? "اقرا الأرقام اللي في التقرير ده." : "Read the figures on this report.",
      maxTokens: 400,
      prefill: "{",
      image,
    });
  } catch (e) {
    await refundAi(userId, "photo");
    throw e;
  }
  const { text, model, usage, latencyMs } = called;
  const stages: StageCost[] = [{ stage: "extractor", model, usage, latencyMs }];

  const parsed = parseJson<BodyScanShape>(text);
  if (!parsed) {
    await trace(userId, null, "body_scan", {
      candidateDecision: { parse_failed: true, raw: text.slice(0, 1000) },
      uncertainty: { parse: "model did not return the requested JSON" },
    }, stages);
    // Unusable output is our failure, not a use of theirs.
    await refundAi(userId, "photo");
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
  return json({ ...result, quota: quotaPayload(quota) });
}

interface PlanShape {
  meals: Meal[];
  rationale_ar?: string;
  rationale_en?: string;
}

/**
 * Writes (or returns) the day's plan. [opts.metered] is false only for the
 * night job: tomorrow's plan is what Qamar+ is paid for, not a use of the
 * member's own daily plan bucket.
 */
async function generatePlan(
  userId: string,
  body: Record<string, unknown>,
  opts: { metered?: boolean } = {},
): Promise<Response> {
  const meter = opts.metered !== false;
  const lang = asString(body.lang) === "ar" ? "ar" : "en";
  const day = asString(body.date) ?? new Date().toISOString().slice(0, 10);
  const force = truthy(body.force);
  const instruction = (asString(body.instruction) ?? "").trim();

  // Paywall four: tomorrow. The night job (unmetered) writes it for everyone
  // who was active today; a member opens it; the free tier reads the night
  // sentence and finds the plan behind it locked. Today and the past stay
  // free — those plans were built on request.
  if (meter && day > cairoNow(new Date()).date && !(await isPlusMember(userId))) {
    return json({
      error: lang === "ar"
        ? "بكرة موجود لما تكمل — خطة بكرة من قمر+."
        : "Tomorrow is there when you continue — tomorrow’s plan is Qamar+.",
      locked: true,
      reason: "tomorrow_locked",
    }, 403);
  }

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
      let quota: Record<string, unknown> | undefined;
      try {
        quota = quotaPayload(await quotaStatus(userId, "plan"));
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

  const taken = meter ? await takeAiUse(userId, lang, "plan") : null;
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
    if (meter) await refundAi(userId, "plan");
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
    if (meter) await refundAi(userId, "plan");
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
    if (meter) await refundAi(userId, "plan");
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
    if (meter) await refundAi(userId, "plan");
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
    ...(quota ? { quota: quotaPayload(quota) } : {}),
  });
}


// ---- the night job --------------------------------------------------------

/**
 * Tomorrow's plan and the night sentence. Fired by pg_cron (see
 * 0044_nightly_plan_cron.sql) with a shared secret rather than a user JWT;
 * accepted only in the 22:00–23:59 Cairo window unless [force] is set for a
 * manual run.
 *
 * The audience is every Qamar+ member, then every free-tier account that
 * logged today: the blueprint's night step generates tomorrow from today's
 * log for everyone and writes one sentence for the morning — a member opens
 * the plan behind it, the free tier finds it locked (paywall four). Members
 * come first so a long night never costs a paying member their morning.
 * Sequential on purpose: one model call per person, stopping at the
 * wall-clock budget and reporting how many are left for the next slot.
 */
async function nightlyPlans(now: Date, force: boolean): Promise<NightlyReport> {
  const date = cairoDatePlus(now, 1);
  const today = cairoNow(now).date;
  const report: NightlyReport = {
    date, ran: false, plus: 0, lite: 0, written: 0, noted: 0, returning: 0, skipped: 0, failed: 0, remaining: 0, failures: [],
  };
  if (!force && !isNightlyWindow(now)) {
    report.reason = "outside the 22:00 Cairo window";
    return report;
  }
  report.ran = true;

  const nowIso = now.toISOString();
  const membersRes = await db(
    `entitlements?status=eq.active&or=(period_end.is.null,period_end.gte.${encodeURIComponent(nowIso)})` +
      `&select=user_id&order=updated_at.asc&limit=1000`,
  );
  if (!membersRes.ok) throw new Error(`entitlements: ${membersRes.status} ${await membersRes.text()}`);
  const members = (await membersRes.json() as Array<{ user_id: string }>).map((r) => r.user_id);

  const activeRes = await db("rpc/qamar_active_today", { method: "POST", body: "{}" });
  const active = activeRes.ok ? (await activeRes.json() as string[]) : [];
  const plusSet = new Set(members);
  const lite = active.filter((id) => !plusSet.has(id));
  report.plus = members.length;
  report.lite = lite.length;
  // Anyone who logged this week but not today wakes to a line too, with no
  // plan behind it: no model call, so members keep the run's budget.
  report.returning = await writeReturningNotes(date, members, active);
  const audience = [...members, ...lite];
  if (audience.length === 0) return report;

  const planned: string[] = [];
  const noted = new Set<string>();
  for (const group of chunks(audience)) {
    const plannedRes = await db(`meal_plans?plan_date=eq.${date}&user_id=in.(${group.join(",")})&select=user_id`);
    if (plannedRes.ok) {
      for (const r of await plannedRes.json() as Array<{ user_id: string }>) planned.push(r.user_id);
    }
    const notedRes = await db(`night_notes?day=eq.${date}&user_id=in.(${group.join(",")})&select=user_id`);
    if (notedRes.ok) {
      for (const r of await notedRes.json() as Array<{ user_id: string }>) noted.add(r.user_id);
    }
  }
  report.skipped = planned.length;

  // A plan already there (a member who asked for tomorrow, an earlier slot
  // that stopped before the sentence) still owes the morning its line.
  for (const userId of planned) {
    if (noted.has(userId)) continue;
    const saved = await loadSavedPlan(userId, date);
    if (saved && await writeNightNote(userId, date, today, saved.meals)) report.noted++;
  }

  const due = dueMembers(audience, planned);
  const started = Date.now();
  for (let i = 0; i < due.length; i++) {
    if (Date.now() - started > RUN_BUDGET_MS) {
      report.remaining = due.length - i;
      break;
    }
    const userId = due[i];
    try {
      const res = await generatePlan(userId, { date, lang: "ar" }, { metered: false });
      if (res.ok) {
        report.written++;
        const meals = mealsFromBody((await res.json())?.plan);
        if (meals && await writeNightNote(userId, date, today, meals)) report.noted++;
      } else {
        // 403/409 are the gateway's own refusals (blocked, life stage, no
        // target yet): not failures of the job, but the member gets no plan
        // and the report says why.
        report.failed++;
        let error: string | undefined;
        try {
          const j = await res.json();
          error = typeof j?.error === "string" ? j.error.slice(0, 200) : undefined;
        } catch { /* body was not JSON */ }
        report.failures.push({ user: userId, status: res.status, error });
      }
    } catch (e) {
      report.failed++;
      report.failures.push({ user: userId, status: 500, error: e instanceof Error ? e.message.slice(0, 200) : "error" });
    }
  }
  return report;
}

/**
 * The returning lines (0062): one batched write, no plan and no model call.
 * A note already written for [date] is never overwritten; plan_kcal 0 tells
 * the phone there is no plan behind the sentence. Returns how many were
 * written.
 */
async function writeReturningNotes(date: string, members: string[], active: string[]): Promise<number> {
  const res = await db("rpc/qamar_returning", { method: "POST", body: JSON.stringify({ p_days: RETURN_DAYS }) });
  if (!res.ok) {
    console.error("ai-gateway returning audience", res.status, await res.text());
    return 0;
  }
  const returning = await res.json() as Array<{ user_id: string; meal_name: string }>;
  if (returning.length === 0) return 0;
  const noted: string[] = [];
  for (const group of chunks(returning.map((r) => r.user_id))) {
    const notedRes = await db(`night_notes?day=eq.${date}&user_id=in.(${group.join(",")})&select=user_id`);
    if (notedRes.ok) for (const r of await notedRes.json() as Array<{ user_id: string }>) noted.push(r.user_id);
  }
  const due = returningAudience(returning, members, active, noted);
  if (due.length === 0) return 0;
  const rows = due.map((r) => {
    const s = returnSentence(r.meal_name);
    return { user_id: r.user_id, day: date, sentence_ar: s.ar, sentence_en: s.en, plan_kcal: 0, today_kcal: 0 };
  });
  const write = await db("night_notes?on_conflict=user_id,day", {
    method: "POST",
    headers: { Prefer: "resolution=ignore-duplicates" },
    body: JSON.stringify(rows),
  });
  if (!write.ok) {
    console.error("ai-gateway returning notes", write.status, await write.text());
    return 0;
  }
  return rows.length;
}

/**
 * Tomorrow against today, in one sentence, for the morning (night_notes,
 * migration 0048). Today's calories come from the database in Cairo time so
 * the comparison is the day the person lived, not the UTC one.
 */
async function writeNightNote(userId: string, day: string, today: string, meals: Meal[]): Promise<boolean> {
  const kcalRes = await db("rpc/qamar_day_kcal", {
    method: "POST",
    body: JSON.stringify({ p_user_id: userId, p_day: today }),
  });
  const todayKcal = kcalRes.ok ? Number(await kcalRes.json()) || 0 : 0;
  const plan = planKcal(meals);
  const s = nightSentence({ planKcal: plan, todayKcal, meals: meals.length });
  const res = await db("night_notes?on_conflict=user_id,day", {
    method: "POST",
    headers: { Prefer: "resolution=merge-duplicates" },
    body: JSON.stringify({
      user_id: userId,
      day,
      sentence_ar: s.ar,
      sentence_en: s.en,
      plan_kcal: plan,
      today_kcal: todayKcal,
    }),
  });
  if (!res.ok) console.error("ai-gateway night note", userId, res.status, await res.text());
  return res.ok;
}

/** True when the request carries the job's shared secret. Constant-time compare. */
function cronAuthorized(req: Request): boolean | "unset" {
  const expected = Deno.env.get("QAMAR_CRON_SECRET");
  if (!expected) return "unset";
  const given = req.headers.get("X-Qamar-Cron") ?? "";
  if (given.length !== expected.length) return false;
  let diff = 0;
  for (let i = 0; i < expected.length; i++) diff |= given.charCodeAt(i) ^ expected.charCodeAt(i);
  return diff === 0;
}

// ---- entry --------------------------------------------------------------

Deno.serve(async (req) => {
  if (req.method === "OPTIONS") return new Response("ok", { headers: CORS });
  if (req.method !== "POST") return json({ error: "POST only" }, 405);

  const route = new URL(req.url).pathname.replace(/^\/ai-gateway/, "").replace(/\/$/, "");

  // The night job is the scheduler, not a person: a shared secret instead of
  // a JWT, checked before anything else and never reachable with a user token.
  if (route === "/plan/nightly") {
    const ok = cronAuthorized(req);
    if (ok === "unset") return json({ error: "QAMAR_CRON_SECRET is not set" }, 503);
    if (!ok) return json({ error: "unauthorized" }, 401);
    let force = false;
    try {
      const b = await req.json();
      force = truthy(b?.force);
    } catch { /* empty body */ }
    try {
      return json(await nightlyPlans(new Date(), force));
    } catch (e) {
      console.error("ai-gateway nightly", e);
      return json({ error: "nightly error" }, 500);
    }
  }

  const userId = await authenticate(req);
  if (!userId) return json({ error: "unauthorized" }, 401);

  let body: Record<string, unknown> = {};
  try {
    body = await req.json();
  } catch {
    return json({ error: "invalid JSON" }, 400);
  }

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
      case "/scan/read":
        return await readBodyScan(userId, body as {
          imageBase64?: string;
          imageMediaType?: string;
          lang?: string;
        });
      case "/quota":
        return json(await quotaSnapshot(userId));
      default:
        return json({ error: `unknown route ${route}` }, 404);
    }
  } catch (e) {
    console.error("ai-gateway", route, e);
    return json({ error: "gateway error" }, 500);
  }
});
