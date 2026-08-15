// The verifier.
//
// packet.ts records what an answer claimed. This is the half that checks it.
//
// The one decision that shapes everything here: the verifier is arithmetic, not
// a second model. A model asked to check a model's sums is the weakest form of
// verification available — it costs another call, it agrees far too readily,
// and when it disagrees you have two opinions and no fact. Every check below
// recomputes a number from figures already in the packet and compares. That is
// why verifier_results has a `recomputed` column and why `model` on those rows
// is null: nothing here is anyone's opinion.
//
// It follows that the verifier can only check what is actually checkable, and
// the honest scope is narrower than it first looks:
//
//   plan            fully checkable. Every portion carries a kcal figure, the
//                   meals must total near the target, and the dish names are
//                   structured, so a withheld food appearing in one is
//                   unambiguous.
//   meal_analysis   arithmetic only. Macros must reconcile with kcal. No
//                   restriction check: the user is reporting what they ate, and
//                   flagging their own food back at them is not a safety
//                   feature.
//   chat            advisory only. Prose that names a restricted food may be
//                   recommending it or may be declining it, and nothing here
//                   can tell those apart, so it is recorded and never acted on.
//   body_scan       not verifiable. Re-reading the image needs another vision
//                   call, which is the model-checks-model trap. The
//                   plausibility filter in the route is the whole check, and
//                   claiming more would be a false audit record.

import type { Restriction } from "./safety.ts";
import { violatesConstraint } from "./safety.ts";

export type Verdict = "PASS" | "REVISE" | "ESCALATE";

/**
 * What a failure is allowed to do.
 *
 * `advisory` is recorded and changes nothing — it exists so a finding the
 * verifier cannot act on safely is still visible to whoever reads the log.
 * `revise` earns one bounded re-ask. `escalate` means the answer does not go
 * out.
 */
export type Severity = "advisory" | "revise" | "escalate";

export interface Failure {
  claim: string;
  failure_type: string;
  detail: string;
  severity: Severity;
}

export interface Verification {
  verdict: Verdict;
  failures: Failure[];
  recomputed: Record<string, unknown>;
}

/** One line of a meal analysis, in the shape the prompt asks for. */
export interface MealItem {
  ar?: string;
  en?: string;
  portionAr?: string;
  portionEn?: string;
  confidence?: string;
  kcal?: number;
  proteinG?: number;
  carbsG?: number;
  fatG?: number;
}

export interface Portion {
  ar?: string;
  en?: string;
  amount_ar?: string;
  amount_en?: string;
  kcal?: number;
}

export interface Meal {
  slot?: string;
  name_ar?: string;
  name_en?: string;
  note_ar?: string;
  note_en?: string;
  portions?: Portion[];
  alt?: { name_ar?: string; name_en?: string; portions?: Portion[] };
}

// ---- tolerances ---------------------------------------------------------
//
// Every one of these is deliberately looser than the instruction the model was
// given. A verifier calibrated to the exact threshold spends its revisions on
// rounding, and a correction round that changes 4% to 3% has bought nothing and
// cost a full model call.

/** Macros against kcal. Generous: fibre, rounding and cooking losses all move this. */
const ATWATER_TOLERANCE = 0.2;
const ATWATER_FLOOR_KCAL = 25;

/** The plan prompt asks for 5%. */
const TARGET_TOLERANCE = 0.05;
const TARGET_FLOOR_KCAL = 60;

/** The prompt asks an alternative to land within 10% of the meal it replaces. */
const ALT_TOLERANCE = 0.1;
const ALT_FLOOR_KCAL = 50;

/** Above this, one item on one plate is not a portion, it is a typo. */
const ABSURD_ITEM_KCAL = 3000;

const num = (v: unknown): number | null =>
  typeof v === "number" && Number.isFinite(v) ? v : null;

const round = (n: number, dp = 1): number => {
  const f = 10 ** dp;
  return Math.round(n * f) / f;
};

/** The worst severity present decides the verdict. */
function verdictOf(failures: Failure[]): Verdict {
  if (failures.some((f) => f.severity === "escalate")) return "ESCALATE";
  if (failures.some((f) => f.severity === "revise")) return "REVISE";
  return "PASS";
}

// ---- meal analysis ------------------------------------------------------

/**
 * Checks that each item's macros reconcile with its kcal at 4/4/9.
 *
 * This is the check worth having on a meal log: the number that reaches the
 * daily total is the kcal, and an item whose macros say something different is
 * one of the two numbers being wrong, which is exactly the case nobody notices
 * by reading the answer.
 */
export function verifyMeal(items: MealItem[]): Verification {
  const failures: Failure[] = [];
  const recomputed: Record<string, unknown>[] = [];

  for (const item of items) {
    const name = item?.en ?? item?.ar ?? "unnamed item";
    const kcal = num(item?.kcal);
    const p = num(item?.proteinG);
    const c = num(item?.carbsG);
    const f = num(item?.fatG);

    if (kcal === null) {
      failures.push({
        claim: name,
        failure_type: "missing_kcal",
        detail: "item has no kcal figure, so it cannot reach a daily total",
        severity: "revise",
      });
      continue;
    }

    if (kcal < 0 || kcal > ABSURD_ITEM_KCAL) {
      failures.push({
        claim: name,
        failure_type: "implausible_kcal",
        detail: `${kcal} kcal for a single item is outside any plausible portion`,
        severity: "revise",
      });
    }

    if (p === null || c === null || f === null) {
      failures.push({
        claim: name,
        failure_type: "missing_macros",
        detail: "one or more macros absent, so the kcal figure cannot be checked",
        severity: "advisory",
      });
      continue;
    }

    const fromMacros = 4 * p + 4 * c + 9 * f;
    const drift = Math.abs(fromMacros - kcal);
    const allowed = Math.max(ATWATER_FLOOR_KCAL, kcal * ATWATER_TOLERANCE);
    recomputed.push({
      item: name,
      stated_kcal: kcal,
      kcal_from_macros: round(fromMacros),
      drift_kcal: round(drift),
      allowed_kcal: round(allowed),
    });

    if (drift > allowed) {
      failures.push({
        claim: `${name} at ${kcal} kcal`,
        failure_type: "atwater_mismatch",
        detail:
          `macros give ${round(fromMacros)} kcal (P ${p} C ${c} F ${f} at 4/4/9), ` +
          `stated ${kcal} kcal, off by ${round(drift)}`,
        severity: "revise",
      });
    }
  }

  return { verdict: verdictOf(failures), failures, recomputed: { items: recomputed } };
}

// ---- plan ---------------------------------------------------------------

function sumPortions(portions: Portion[] | undefined): { total: number; missing: number } {
  let total = 0;
  let missing = 0;
  for (const p of portions ?? []) {
    const k = num(p?.kcal);
    if (k === null) missing++;
    else total += k;
  }
  return { total, missing };
}

/**
 * Checks a generated day of eating against the target it was built for, and
 * against the person's hard constraints.
 *
 * The constraint check is the important one and it is not redundant with the
 * filtering the route already does. That filter removes restricted foods from
 * the list the model is *shown*; nothing stops the model naming a food that was
 * never on the list. Catching that here is the difference between "we asked it
 * not to" and "we checked".
 */
export function verifyPlan(
  meals: Meal[],
  targetKcal: number | null,
  restrictions: Restriction[],
): Verification {
  const failures: Failure[] = [];
  const mealTotals: Record<string, number> = {};
  let total = 0;

  meals.forEach((meal, i) => {
    const slot = meal?.slot ?? meal?.name_en ?? `meal ${i + 1}`;
    const { total: mealKcal, missing } = sumPortions(meal?.portions);
    mealTotals[slot] = round(mealKcal);
    total += mealKcal;

    if (missing > 0) {
      failures.push({
        claim: slot,
        failure_type: "missing_portion_kcal",
        detail: `${missing} portion(s) carry no kcal, so this meal cannot be totalled`,
        severity: "revise",
      });
    }

    // The alternative is what the user taps when they do not have the
    // ingredients. One that is nowhere near the same energy quietly changes
    // their day, which is worth recording but is not worth a revision round of
    // its own.
    if (meal?.alt) {
      const alt = sumPortions(meal.alt.portions).total;
      const allowed = Math.max(ALT_FLOOR_KCAL, mealKcal * ALT_TOLERANCE);
      if (mealKcal > 0 && Math.abs(alt - mealKcal) > allowed) {
        failures.push({
          claim: `${slot} alternative`,
          failure_type: "alt_kcal_mismatch",
          detail: `alternative is ${round(alt)} kcal against a ${round(mealKcal)} kcal meal`,
          severity: "advisory",
        });
      }
    }

    // Every name and note the user will read, checked against what they cannot
    // have. Matching is deliberately generous — a false positive costs one
    // regenerated plan, a false negative is the failure this exists to prevent.
    const text = [
      meal?.name_en, meal?.name_ar, meal?.note_en, meal?.note_ar,
      ...(meal?.portions ?? []).flatMap((p) => [p?.en, p?.ar]),
      meal?.alt?.name_en, meal?.alt?.name_ar,
      ...(meal?.alt?.portions ?? []).flatMap((p) => [p?.en, p?.ar]),
    ].filter((s): s is string => typeof s === "string" && s.length > 0);

    const hit = violatesConstraint(restrictions, { name: text.join(" ") });
    if (hit) {
      failures.push({
        claim: slot,
        failure_type: "restricted_food_present",
        detail: `names "${hit.label}", recorded as ${hit.kind}${hit.severity ? ` (${hit.severity})` : ""}`,
        // Never revised, never returned. A plan containing something the person
        // is allergic to is not a draft to improve, and re-asking the same model
        // for a safer version is not a control.
        severity: "escalate",
      });
    }
  });

  const recomputed: Record<string, unknown> = {
    meal_totals: mealTotals,
    total_kcal: round(total),
    target_kcal: targetKcal,
  };

  if (targetKcal != null && targetKcal > 0) {
    const delta = total - targetKcal;
    const allowed = Math.max(TARGET_FLOOR_KCAL, targetKcal * TARGET_TOLERANCE);
    recomputed.delta_kcal = round(delta);
    recomputed.delta_pct = round((delta / targetKcal) * 100, 2);
    recomputed.allowed_kcal = round(allowed);

    if (Math.abs(delta) > allowed) {
      failures.push({
        claim: "meals total within 5% of the daily target",
        failure_type: "target_mismatch",
        detail:
          `meals total ${round(total)} kcal against a ${targetKcal} kcal target, ` +
          `off by ${round(delta)} (${round((delta / targetKcal) * 100, 2)}%)`,
        severity: "revise",
      });
    }
  }

  return { verdict: verdictOf(failures), failures, recomputed };
}

// ---- chat ---------------------------------------------------------------

/**
 * The only thing checkable in prose.
 *
 * Recorded, never acted on. "You told me you are allergic to sesame, so skip
 * the tahina" and "have some tahina" both contain the word, and no string test
 * separates them. Suppressing the first would be worse than surfacing the
 * second, so this produces an advisory finding and the reply goes out
 * unchanged. What it buys is a row in the log: if these cluster, the prompt
 * needs work, and without this nobody would ever find that out.
 */
export function verifyChat(reply: string, restrictions: Restriction[]): Verification {
  const failures: Failure[] = [];
  const hit = violatesConstraint(restrictions, { name: reply });
  if (hit) {
    failures.push({
      claim: "reply names a restricted food",
      failure_type: "restricted_food_mentioned",
      detail: `mentions "${hit.label}" (${hit.kind}); may be declining it rather than suggesting it`,
      severity: "advisory",
    });
  }
  return {
    verdict: verdictOf(failures),
    failures,
    // Said plainly so a PASS on a chat row is not mistaken for arithmetic that
    // was checked and held.
    recomputed: {
      numeric_claims_recomputed: false,
      reason: "prose does not attach its numbers to a resolved food",
    },
  };
}

// ---- revision -----------------------------------------------------------

/** Whether anything here is worth one more model call. */
export function isRevisable(v: Verification): boolean {
  return v.verdict === "REVISE" && revisableCount(v) > 0;
}

/** How many findings the one allowed correction is meant to address. */
export function revisableCount(v: Verification): number {
  return v.failures.filter((f) => f.severity === "revise").length;
}

/**
 * Whether a second attempt is actually better than the first.
 *
 * A revision is not accepted for having happened. A model asked to fix three
 * numbers can return four wrong ones, and taking the newer answer on faith
 * would make the verifier a way of degrading answers rather than improving
 * them.
 */
export function isImprovement(before: Verification, after: Verification): boolean {
  if (blocks(after).length > 0) return false;
  return revisableCount(after) < revisableCount(before);
}

/**
 * What the model is told on the second attempt.
 *
 * Only the failures, only the ones worth acting on, and its own previous answer
 * to correct. The original question is deliberately not restated: the system
 * prompt still holds the task, and repeating it invites a rewrite of the whole
 * answer when what is wanted is a fixed number.
 */
export function revisionInstruction(v: Verification, previous?: unknown): string {
  const lines = v.failures
    .filter((f) => f.severity === "revise")
    .map((f) => `- ${f.claim}: ${f.detail}`)
    .join("\n");
  const prior = previous === undefined
    ? ""
    : `\nYour previous answer:\n${JSON.stringify(previous)}\n`;
  return `Your previous answer failed these arithmetic checks:

${lines}
${prior}
Return the corrected JSON in the same shape. Fix the figures rather than
replacing the answer, and do not explain the correction.`;
}

/**
 * The verdict after the allowed revision has been spent.
 *
 * The cap is the point. A disagreement that survives one bounded correction is
 * escalated rather than argued about, because the alternative is an unbounded
 * loop of a model correcting itself with no new information entering.
 */
export function finalVerdict(after: Verification): Verification {
  if (after.verdict === "REVISE") {
    return {
      ...after,
      verdict: "ESCALATE",
      failures: after.failures.map((f) =>
        f.severity === "revise"
          ? { ...f, detail: `${f.detail} — still failing after one revision` }
          : f
      ),
    };
  }
  return after;
}

/** Failures the user must never be shown an answer despite. */
export function blocks(v: Verification): Failure[] {
  return v.failures.filter((f) => f.severity === "escalate");
}
