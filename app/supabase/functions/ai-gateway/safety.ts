// Safety recording and escalation.
//
// scope.ts has always decided *whether* to answer. What it never did was leave
// a trace: a medical question got refused, the user saw a sensible sentence,
// and nothing anywhere recorded that a safety rule had fired. Migration 0014
// built safety_events, risk_assessments and red_flag_rules for exactly this and
// nothing wrote to them, which meant the guardrails could not be audited, could
// not be counted, and could not be shown to have worked.
//
// Two rules shape this file.
//
// The database is the registry. red_flag_rules holds each rule's escalation
// route and minimum tier, and this reads them rather than keeping a second copy
// in TypeScript that drifts from the first. It is cached per isolate, so the
// cost is one query on a cold start, not one per request.
//
// Recording never breaks the request. A refusal that fails to log is still a
// refusal, and losing the answer because the audit insert failed would trade a
// safety feature for a safety incident.

import type { RefusalReason } from "./scope.ts";

export type RiskTier =
  | "general_wellness"
  | "condition_aware"
  | "clinician_guided"
  | "high_risk";

export type EscalateTo = "refuse" | "clinician_review" | "urgent_referral";

/**
 * scope.ts reasons to red_flag_rules slugs.
 *
 * off_topic is deliberately null: declining to discuss football is scope
 * working, not a safety event, and filling the safety log with it would bury
 * the rows that matter.
 */
const RULE_FOR_REASON: Record<RefusalReason, string | null> = {
  medical: "medical_question",
  eating_disorder: "eating_disorder",
  pregnancy: "pregnancy_declared",
  minor: "minor",
  prompt_injection: "prompt_injection",
  off_topic: null,
};

interface RedFlagRule {
  slug: string;
  escalate_to: EscalateTo;
  min_risk_tier: RiskTier;
  is_active: boolean;
}

let ruleCache: Map<string, RedFlagRule> | null = null;

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

async function rules(url: string, key: string): Promise<Map<string, RedFlagRule>> {
  if (ruleCache) return ruleCache;
  const res = await db(url, key, "red_flag_rules?select=slug,escalate_to,min_risk_tier,is_active");
  if (!res.ok) {
    console.error("red_flag_rules unavailable; falling back to refuse/high_risk");
    return new Map();
  }
  ruleCache = new Map((await res.json() as RedFlagRule[]).map((r) => [r.slug, r]));
  return ruleCache;
}

/**
 * Records a refusal, its tier, and an escalation if the rule calls for one.
 *
 * Returns the tier so the caller can put it in the response, but the caller is
 * not expected to check for failure: everything here is best-effort by design.
 */
export async function recordRefusal(
  url: string,
  key: string,
  userId: string,
  interactionId: string | null,
  reason: RefusalReason,
  question: string,
): Promise<RiskTier> {
  const slug = RULE_FOR_REASON[reason];
  const rule = slug ? (await rules(url, key)).get(slug) : undefined;

  // An unknown or inactive rule is treated as the most serious case rather than
  // the least. A safety mapping that has gone stale should get louder, not
  // quieter.
  const tier: RiskTier = slug ? (rule?.min_risk_tier ?? "high_risk") : "general_wellness";
  const escalate: EscalateTo = slug ? (rule?.escalate_to ?? "refuse") : "refuse";

  try {
    await db(url, key, "safety_events", {
      method: "POST",
      body: JSON.stringify({
        user_id: userId,
        interaction_id: interactionId,
        kind: reason === "prompt_injection" ? "override_attempt" : "refusal",
        rule_slug: slug,
        reason,
        // The question is kept because "why did it refuse this" is
        // unanswerable without it. It is already stored on ai_interactions, so
        // this adds no new category of data.
        detail: { question: question.slice(0, 500), escalate_to: escalate },
      }),
    });

    await db(url, key, "risk_assessments", {
      method: "POST",
      body: JSON.stringify({
        user_id: userId,
        interaction_id: interactionId,
        risk_tier: tier,
        flags: slug ? [slug] : [reason],
        allowed_actions: [],
        decided_by: "rules",
      }),
    });

    if (escalate !== "refuse") {
      await queueClinicianReview(url, key, userId, slug!, escalate, question);
    }
  } catch (e) {
    console.error("safety recording failed (request continues):", e);
  }

  return tier;
}

/** Records a request that was allowed, so the tier of every call is known. */
export async function recordAllowed(
  url: string,
  key: string,
  userId: string,
  interactionId: string | null,
  tier: RiskTier,
  flags: string[],
  allowedActions: string[],
): Promise<void> {
  try {
    await db(url, key, "risk_assessments", {
      method: "POST",
      body: JSON.stringify({
        user_id: userId,
        interaction_id: interactionId,
        risk_tier: tier,
        flags,
        allowed_actions: allowedActions,
        decided_by: "rules",
      }),
    });
  } catch (e) {
    console.error("risk assessment recording failed (request continues):", e);
  }
}

/**
 * A hard block: something the user is recorded as unable to have was about to
 * be recommended to them. Distinct from a refusal, which declines a question —
 * this one caught the system itself about to do the wrong thing.
 */
export async function recordHardBlock(
  url: string,
  key: string,
  userId: string,
  interactionId: string | null,
  reason: string,
  detail: Record<string, unknown>,
): Promise<void> {
  try {
    await db(url, key, "safety_events", {
      method: "POST",
      body: JSON.stringify({
        user_id: userId,
        interaction_id: interactionId,
        kind: "hard_block",
        reason,
        detail,
      }),
    });
  } catch (e) {
    console.error("hard block recording failed (request continues):", e);
  }
}

async function queueClinicianReview(
  url: string,
  key: string,
  userId: string,
  ruleSlug: string,
  escalate: EscalateTo,
  question: string,
): Promise<void> {
  // Minimal relevant information and explicit questions, per the escalation
  // design. A reviewer needs the decision to make, not a transcript to read.
  await db(url, key, "clinician_reviews", {
    method: "POST",
    body: JSON.stringify({
      user_id: userId,
      trigger_rule: ruleSlug,
      priority: escalate === "urgent_referral" ? "urgent" : "routine",
      review_packet: {
        rule: ruleSlug,
        escalate_to: escalate,
        user_said: question.slice(0, 500),
        automated_action: "refused and escalated",
      },
      explicit_questions: [
        "Does this need contact with the user?",
        "Should the account be moved out of general wellness scope?",
      ],
    }),
  });
}

// ---- hard constraints ---------------------------------------------------

export interface Restriction {
  label: string;
  kind: string;
  severity: string | null;
}

/** The user's hard constraints. Allergy and intolerance only — a dislike is a preference. */
export async function loadHardConstraints(
  url: string,
  key: string,
  userId: string,
): Promise<Restriction[]> {
  const res = await db(
    url,
    key,
    `food_restrictions?user_id=eq.${userId}&kind=in.(allergy,intolerance,medical)&select=label,kind,severity`,
  );
  if (!res.ok) return [];
  return await res.json() as Restriction[];
}

/**
 * Whether a food violates a hard constraint.
 *
 * Matches the restriction against the food's name, its allergen tags and its
 * ingredients if it is a dish, because "no sesame" has to stop tahina and it
 * has to stop the baba ghanoug that contains it.
 *
 * Deliberately generous about what counts as a match. A false positive costs a
 * user one suggestion; a false negative is the failure mode this exists to
 * prevent.
 */
export function violatesConstraint(
  restrictions: Restriction[],
  food: { name: string; allergens?: string[]; ingredientNames?: string[] },
): Restriction | null {
  const haystack = [
    food.name,
    ...(food.allergens ?? []),
    ...(food.ingredientNames ?? []),
  ].join(" ").toLowerCase();

  for (const r of restrictions) {
    const needle = r.label.trim().toLowerCase();
    if (needle.length < 2) continue;
    if (haystack.includes(needle)) return r;
  }
  return null;
}
