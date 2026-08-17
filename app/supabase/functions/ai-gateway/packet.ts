// Evidence packets and what each stage cost.
//
// ai_interactions records a question, an answer and a bag of sources. That is
// enough to show someone what happened and not enough to show *why* — which
// facts about the person were in play, which portion the graph assumed, which
// rules applied and which were ruled out, what the answer asserted that a
// verifier would have to re-check. Migration 0015 built evidence_packets,
// verifier_results and ai_stage_costs for exactly that, and nothing wrote to
// them, so every past answer was unreconstructable and every token was
// unmeasured.
//
// Three rules shape this file, and they are the same three that shape safety.ts.
//
// Recording never breaks the request. A packet that fails to write must not
// cost the user their answer.
//
// Nothing is invented to fill a field. An empty applicable_rules array means no
// rule was curated, not that the filter rejected everything; a null cost means
// the model was unpriced, not that the call was free. Fields that would have to
// be guessed are left out, because a packet that quietly guesses is worse than
// no packet — it is a false audit trail.
//
// The database owns policy. Prices live in model_prices and population
// filtering lives in qamar_rule_selection, both from 0022, so neither drifts
// against a constant compiled into the gateway.

import type { Usage, UserContext } from "./model.ts";
import type { Resolution } from "./graph.ts";

export type Kind = "chat" | "meal_analysis" | "plan" | "body_scan";

/**
 * The stages 0015 budgets.
 *
 * The gateway is one model call per request, not the twelve-worker pipeline the
 * architecture describes, so the mapping is deliberately conservative:
 * reasoning-and-composing calls are filed under `reasoner` (they produce the
 * decision, and `composer` is defined as adding no new facts), transcription
 * calls under `extractor`. Retrieval and food resolution are recorded even
 * though no model runs in them, because their cost is external calls and
 * latency, and a budget that only counts tokens misses both.
 */
export type Stage =
  | "extractor"
  | "router"
  | "risk_triage"
  | "food_resolver"
  | "retrieval"
  | "requirement"
  | "reasoner"
  | "optimizer"
  | "verifier"
  | "composer"
  | "adaptation"
  | "other";

async function db(
  url: string,
  key: string,
  path: string,
  init: RequestInit = {},
): Promise<Response> {
  return await fetch(`${url}/rest/v1/${path}`, {
    ...init,
    headers: {
      "Content-Type": "application/json",
      apikey: key,
      Authorization: `Bearer ${key}`,
      ...(init.headers ?? {}),
    },
  });
}

// ---- timing -------------------------------------------------------------

/** Runs something and reports how long it took, so a stage can be costed. */
export async function timed<T>(fn: () => Promise<T>): Promise<[T, number]> {
  const started = performance.now();
  const value = await fn();
  return [value, Math.round(performance.now() - started)];
}

// ---- the packet ---------------------------------------------------------

export interface PacketInput {
  userId: string;
  interactionId: string | null;
  kind: Kind;
  userFacts?: unknown[];
  foodFacts?: unknown[];
  calculatedTargets?: unknown[];
  applicableRules?: unknown[];
  excludedRules?: unknown[];
  candidateDecision?: unknown;
  safetyFlags?: string[];
  uncertainty?: Record<string, unknown>;
  claimsToVerify?: unknown[];
}

/**
 * Writes the packet and returns its task_id, or null if it could not be
 * written. Callers pass the null straight through to the cost rows: an
 * unlinked cost row is worth more than a lost one.
 */
export async function writePacket(
  url: string,
  key: string,
  p: PacketInput,
): Promise<string | null> {
  try {
    const res = await db(url, key, "evidence_packets", {
      method: "POST",
      headers: { Prefer: "return=representation" },
      body: JSON.stringify({
        user_id: p.userId,
        interaction_id: p.interactionId,
        kind: p.kind,
        user_facts_used: p.userFacts ?? [],
        food_facts: p.foodFacts ?? [],
        calculated_targets: p.calculatedTargets ?? [],
        applicable_rules: p.applicableRules ?? [],
        excluded_rules: p.excludedRules ?? [],
        candidate_decision: p.candidateDecision ?? null,
        safety_flags: p.safetyFlags ?? [],
        uncertainty: p.uncertainty ?? {},
        claims_to_verify: p.claimsToVerify ?? [],
      }),
    });
    if (!res.ok) {
      console.error("evidence packet write failed:", res.status, await res.text());
      return null;
    }
    const rows = await res.json();
    return rows?.[0]?.task_id ?? null;
  } catch (e) {
    console.error("evidence packet write failed (request continues):", e);
    return null;
  }
}

/**
 * Records one verification pass against its packet.
 *
 * `model` is left null on purpose: the verifier is arithmetic, so there is no
 * model behind the verdict and naming one would misrepresent where it came
 * from. `revision_number` is the pass — 0 for the first check, 1 for the check
 * after the one allowed correction — and the unique constraint from 0015 is
 * what actually enforces the cap.
 *
 * A packet that failed to write means no task_id, and verifier_results.task_id
 * is NOT NULL, so there is nothing to attach the result to. That is logged
 * rather than swallowed: a verification that happened and was not recorded is
 * exactly the thing this table exists to make impossible.
 */
export async function recordVerification(
  url: string,
  key: string,
  taskId: string | null,
  v: { verdict: string; failures: unknown[]; recomputed: Record<string, unknown> },
  revision: number,
): Promise<void> {
  if (!taskId) {
    console.error("verification not recorded: no packet to attach it to", v.verdict);
    return;
  }
  try {
    const res = await db(url, key, "verifier_results", {
      method: "POST",
      body: JSON.stringify({
        task_id: taskId,
        verdict: v.verdict,
        failures: v.failures,
        recomputed: v.recomputed,
        revision_number: revision,
        model: null,
      }),
    });
    if (!res.ok) console.error("verifier result write failed:", res.status, await res.text());
  } catch (e) {
    console.error("verifier result write failed (request continues):", e);
  }
}

// ---- cost ---------------------------------------------------------------

export interface StageCost {
  stage: Stage;
  model?: string | null;
  usage?: Usage | null;
  /** Calls to anything outside Supabase and the model: USDA, OFF, embeddings. */
  externalCalls?: number;
  latencyMs?: number | null;
}

/**
 * Writes the stage costs for one request in a single insert.
 *
 * cost_usd is left off on purpose. A trigger from 0022 prices the row from
 * model_prices using the row's own timestamp, so a price correction is one
 * UPDATE and a redeployed gateway is not required to get costs right.
 */
export async function recordStages(
  url: string,
  key: string,
  ref: { taskId: string | null; interactionId: string | null; userId: string },
  stages: StageCost[],
): Promise<void> {
  if (stages.length === 0) return;
  try {
    const rows = stages.map((s) => ({
      task_id: ref.taskId,
      interaction_id: ref.interactionId,
      user_id: ref.userId,
      stage: s.stage,
      model: s.model ?? null,
      // Null, not zero, when the response carried no usage block. Zero would
      // read as a free call and quietly deflate every total built on it.
      input_tokens: s.usage?.inputTokens ?? null,
      output_tokens: s.usage?.outputTokens ?? null,
      cached_input_tokens: s.usage?.cachedInputTokens ?? null,
      external_api_calls: s.externalCalls ?? 0,
      latency_ms: s.latencyMs ?? null,
    }));
    const res = await db(url, key, "ai_stage_costs", {
      method: "POST",
      body: JSON.stringify(rows),
    });
    if (!res.ok) console.error("stage cost write failed:", res.status, await res.text());
  } catch (e) {
    console.error("stage cost write failed (request continues):", e);
  }
}

// ---- packet contents ----------------------------------------------------

interface RawFact {
  field: string;
  value_text: string | null;
  value_num: number | null;
  value_json: unknown;
  unit: string | null;
  source: string;
  confidence: number | null;
  measured_at: string | null;
  recorded_at: string;
}

/**
 * The facts about the person that this answer stands on.
 *
 * profile_facts is the provenance table and is read first, because it carries
 * when a number was measured and how much to trust it. Nothing writes to it on
 * signup yet — only the 0013 backfill populated it — so anything the profile
 * has and the fact table does not is emitted with source `profiles_projection`
 * and a null measured_at. That is the truth: the value is known, its
 * provenance is not, and a packet claiming otherwise would be the exact
 * failure this table exists to prevent.
 */
export async function loadUserFacts(
  url: string,
  key: string,
  userId: string,
  ctx: UserContext,
): Promise<unknown[]> {
  const facts: Record<string, unknown>[] = [];
  const seen = new Set<string>();

  try {
    const res = await db(
      url,
      key,
      `profile_facts?user_id=eq.${userId}&superseded_by=is.null` +
        `&select=field,value_text,value_num,value_json,unit,source,confidence,measured_at,recorded_at`,
    );
    if (res.ok) {
      for (const r of (await res.json()) as RawFact[]) {
        seen.add(r.field);
        facts.push({
          field: r.field,
          value: r.value_num ?? r.value_text ?? r.value_json,
          unit: r.unit,
          source: r.source,
          confidence: r.confidence,
          measured_at: r.measured_at,
          recorded_at: r.recorded_at,
        });
      }
    }
  } catch (e) {
    console.error("profile_facts read failed (packet continues):", e);
  }

  const projected: [string, unknown, string | null][] = [
    ["height_cm", ctx.heightCm, "cm"],
    ["weight_kg", ctx.weightKg, "kg"],
    ["goal", ctx.goal, null],
    ["gender", ctx.gender, null],
    ["activity_factor", ctx.activityFactor, null],
  ];
  for (const [field, value, unit] of projected) {
    if (value == null || seen.has(field)) continue;
    facts.push({
      field,
      value,
      unit,
      source: "profiles_projection",
      confidence: null,
      measured_at: null,
    });
  }

  // Age is never stored; it is computed from birth_date at request time, and
  // saying so is cheaper than someone later wondering which birthday it used.
  if (ctx.age != null) {
    facts.push({
      field: "age_years",
      value: ctx.age,
      unit: "years",
      source: "derived",
      confidence: null,
      measured_at: null,
    });
  }

  return facts;
}

/** A row of the targets table, as the packet needs to cite it. */
export interface TargetRow {
  kcal: number;
  protein_g: number | null;
  carbs_g: number | null;
  fat_g: number | null;
  formula_version: string | null;
  inputs: Record<string, unknown> | null;
}

/**
 * The targets this answer was built against, and what produced them.
 *
 * equation_version was null on every packet until 0025, because until then
 * `targets.formula_version` was the string 'calc v2.0' naming a formula whose
 * coefficients existed nowhere, and citing it would have been worse than citing
 * nothing. Rows written by qamar_set_target now name the equation and carry the
 * inputs it ran on, so the citation is real — and a row from before the engine
 * still says so rather than borrowing the new provenance.
 */
export function targetsFrom(ctx: UserContext, target: TargetRow | null): unknown[] {
  if (!target && ctx.targetKcal == null) return [];
  if (!target) {
    return [{
      metric: "energy_kcal",
      value: ctx.targetKcal,
      unit: "kcal/day",
      equation_version: null,
      source: "targets table, provenance unknown",
    }];
  }

  const derived = target.formula_version !== null &&
    target.formula_version !== "calc v2.0";
  const cite = (metric: string, value: number | null, unit: string) =>
    value == null ? null : {
      metric,
      value,
      unit,
      equation_version: derived ? target.formula_version : null,
      source: derived ? "qamar_set_target" : "targets table, predates the requirement engine",
      // Only on the energy row: it is the one the equation actually computed,
      // and repeating the whole input set on all four would suggest four
      // separate derivations.
      ...(metric === "energy_kcal" && derived ? { inputs: target.inputs } : {}),
    };

  return [
    cite("energy_kcal", target.kcal, "kcal/day"),
    cite("protein_g", target.protein_g, "g/day"),
    cite("carbs_g", target.carbs_g, "g/day"),
    cite("fat_g", target.fat_g, "g/day"),
  ].filter((x) => x !== null);
}

interface RawRule {
  rule_id: string;
  applies: boolean;
  compact_recommendation: string;
  recommendation_type: string;
  source_id: string;
  source_version: string;
  source_locator: unknown;
  reason_not_applicable: string | null;
}

/**
 * Which curated rules were in population for this person, and which were not.
 *
 * Both halves come back from one call because the excluded half is the one
 * nobody would otherwise record, and it is the only thing that can answer "why
 * did this user never see a rule that obviously applied to them".
 */
export async function ruleSelection(
  url: string,
  key: string,
  who: { age: number | null; sex: string | null; lifeStage: string },
): Promise<{ applicable: unknown[]; excluded: unknown[] }> {
  try {
    const res = await db(url, key, "rpc/qamar_rule_selection", {
      method: "POST",
      body: JSON.stringify({
        p_age_years: who.age,
        p_sex: who.sex,
        // The rules table says 'adult' where the profile says 'none'; they are
        // different vocabularies for different questions.
        p_life_stage: who.lifeStage === "none" ? "adult" : who.lifeStage,
      }),
    });
    if (!res.ok) return { applicable: [], excluded: [] };
    const rows = (await res.json()) as RawRule[];
    return {
      applicable: rows.filter((r) => r.applies).map((r) => ({
        rule_id: r.rule_id,
        compact_recommendation: r.compact_recommendation,
        recommendation_type: r.recommendation_type,
        source_id: r.source_id,
        source_version: r.source_version,
        source_locator: r.source_locator,
      })),
      excluded: rows.filter((r) => !r.applies).map((r) => ({
        rule_id: r.rule_id,
        reason_not_applicable: r.reason_not_applicable ?? "failed the population filter",
      })),
    };
  } catch (e) {
    console.error("rule selection failed (packet continues):", e);
    return { applicable: [], excluded: [] };
  }
}

/** Everything the resolver was unsure about, keyed by the phrase it came from. */
export function resolutionUncertainty(items: Resolution[]): Record<string, string[]> {
  const out: Record<string, string[]> = {};
  for (const r of items) {
    if (r.uncertainty.length > 0) out[r.phrase] = r.uncertainty;
    else if (r.origin === "unresolved") out[r.phrase] = ["no food matched"];
  }
  return out;
}

/**
 * External lookups the resolver made.
 *
 * A phrase the graph could not price falls through to USDA and Open Food Facts,
 * so both `external` (the fallback answered) and `unresolved` (it was tried and
 * did not) count as a call made. This is the number the food_resolver budget of
 * six external calls is compared against.
 */
export function externalCallsIn(items: Resolution[]): number {
  return items.filter((r) => r.origin === "external" || r.origin === "unresolved").length;
}

/**
 * The numbers an answer asserted, as claims a verifier would re-check.
 *
 * Free text is not structured output, and pretending to extract meaning from it
 * would be its own invention. What is extractable without guessing is every
 * quantity the reply stated — and a wrong quantity is precisely the failure
 * mode worth catching in a product people use to decide what to eat.
 */
export function numericClaims(text: string): unknown[] {
  const claims: unknown[] = [];
  const seen = new Set<string>();
  for (const m of asciiDigits(text).matchAll(QUANTITY)) {
    const unit = (m[2] ?? m[3]).toLowerCase();
    const claim = `${m[1]} ${unit}`;
    if (seen.has(claim)) continue;
    seen.add(claim);
    claims.push({
      claim,
      value: Number(m[1].replace(",", ".")),
      unit,
      check: "arithmetic_against_food_facts",
    });
    if (claims.length >= 20) break;
  }
  return claims;
}

/**
 * A number followed by a unit, in either language.
 *
 * Longest alternatives first, because the alternation is ordered and a bare
 * `g` placed early would swallow the start of `grams`. The Latin branch ends
 * in a letter boundary so "500 great" is not read as 500 grams; the Arabic
 * branch deliberately has none, since Arabic attaches prefixes and suffixes
 * freely and a boundary there would reject more real matches than false ones.
 */
const QUANTITY =
  /(\d+(?:[.,]\d+)?)\s*(?:(kilocalories?|calories?|kcal|kilograms?|grams?|kg|g|ml|%)(?![a-z])|(سعرات|سعرة|سعر حراري|كيلوجرام|كيلو|كجم|جرامات|جرام|جم|مل))/gi;

/**
 * Arabic-Indic digits to ASCII.
 *
 * An Arabic reply may well say "٥٠٠ سعرة", and without this every claim in the
 * app's primary language goes unrecorded — the one place a silent gap would be
 * least visible and matter most.
 */
function asciiDigits(s: string): string {
  return s.replace(/[٠-٩۰-۹]/g, (d) => {
    const c = d.codePointAt(0)!;
    return String(c >= 0x06f0 ? c - 0x06f0 : c - 0x0660);
  });
}

// ---- nutrient shortfalls ------------------------------------------------

interface RawGap {
  nutrient_code: string;
  name_ar: string;
  name_en: string;
  unit: string;
  kind: string;
  target: number;
  mean_daily: number;
  pct_of_target: number | null;
  status: string;
  coverage_pct: number;
  nutrient_coverage_pct: number;
  items_total: number;
  items_resolved: number;
}

/**
 * What this person has actually been short on, from their own logged meals.
 *
 * Only rows the database is willing to stand behind are returned. A status of
 * "unknown" means no logged item resolved to a known food, and it is dropped
 * here rather than passed along as a zero — the whole point of that column is
 * that an unmeasured intake and an intake of nothing are different claims, and
 * a prompt is exactly the place where that distinction gets lost.
 *
 * Sodium is dropped too, for the opposite reason: it has an AI, so it appears
 * as a shortfall whenever someone eats less than 1500 mg, and telling an
 * Egyptian household to eat more salt is the last advice this app should give.
 *
 * Returns [] on any failure. A plan without shortfall data is a worse plan; a
 * plan that fails to generate because a report was unavailable is no plan.
 */
export async function nutrientGaps(
  url: string,
  key: string,
  userId: string,
  days = 7,
): Promise<
  {
    nameEn: string;
    nameAr: string;
    unit: string;
    target: number;
    meanDaily: number;
    pctOfTarget: number;
    kind: string;
    coveragePct: number;
    /** How much of what they ate carried a value for this nutrient at all. */
    nutrientCoveragePct: number;
  }[]
> {
  try {
    const res = await db(url, key, "rpc/qamar_nutrient_gaps", {
      method: "POST",
      body: JSON.stringify({ p_user_id: userId, p_days: days }),
    });
    if (!res.ok) return [];
    const rows = (await res.json()) as RawGap[];
    return rows
      .filter((r) =>
        (r.status === "short" || r.status === "low") &&
        r.nutrient_code !== "sodium_mg" &&
        r.pct_of_target != null &&
        // A shortfall computed from under half the plate is not a finding worth
        // planning against. The database already refuses to call an unmeasured
        // nutrient short; this is the weaker version of the same judgement, and
        // it is the gateway's to make because it is the one writing advice.
        r.nutrient_coverage_pct >= 50
      )
      // Worst first, and capped: a prompt listing fifteen shortfalls is asking
      // the model to fix none of them.
      .sort((a, b) => (a.pct_of_target ?? 0) - (b.pct_of_target ?? 0))
      .slice(0, 5)
      .map((r) => ({
        nameEn: r.name_en,
        nameAr: r.name_ar,
        unit: r.unit,
        target: Number(r.target),
        meanDaily: Number(r.mean_daily),
        pctOfTarget: Number(r.pct_of_target),
        kind: r.kind,
        coveragePct: Number(r.coverage_pct),
        nutrientCoveragePct: Number(r.nutrient_coverage_pct),
      }));
  } catch (e) {
    console.error("nutrientGaps", e);
    return [];
  }
}
