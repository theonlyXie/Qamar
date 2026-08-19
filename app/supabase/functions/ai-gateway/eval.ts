// The eval runner for cases the database cannot execute.
//
// qamar_run_eval (0026) runs everything that lives in SQL — food resolution and
// the RMR arithmetic — against live data with no key required. The rest of the
// frozen set exercises pure TypeScript: the scope guard's refusal boundary and
// the verifier's arithmetic. Those cannot run inside Postgres, so they run here
// and write into the same eval_runs / eval_results tables, which is what keeps
// the suite one thing with one pass rate rather than two half-measures nobody
// compares.
//
// Run:
//   SUPABASE_URL=... SUPABASE_SERVICE_ROLE_KEY=... \
//     deno run --allow-net --allow-env eval.ts "label"
//
// It needs the service role key because eval_cases, eval_runs and eval_results
// are staff tables with RLS on and no policy. Nothing here calls a model, so
// there is no Anthropic key and no cost: the point of these families is that
// they are deterministic.

import { classify } from "./scope.ts";
import { blocks, verifyMeal, verifyPlan, type Meal, type MealItem } from "./verify.ts";
import type { Restriction } from "./safety.ts";

export interface EvalCase {
  id?: string;
  slug: string;
  family: string;
  input: Record<string, unknown>;
  expected: Record<string, unknown>;
}

export interface CaseOutcome {
  passed: boolean;
  actual: Record<string, unknown>;
  detail: string | null;
}

// ---- the cases ----------------------------------------------------------

/**
 * Evaluates one case. Pure, so the dispatch itself is testable without a
 * database — see eval_test.ts, which runs the real seeded cases through it.
 */
export function runCase(c: EvalCase): CaseOutcome {
  const kind = c.input.kind as string;
  try {
    switch (kind) {
      case "scope":
        return scopeCase(c);
      case "verify_meal":
        return verifyMealCase(c);
      case "verify_plan":
        return verifyPlanCase(c);
      default:
        return { passed: false, actual: {}, detail: `no Deno runner for kind ${kind}` };
    }
  } catch (e) {
    // A case that throws is a failure, not a crashed run. One broken
    // expectation must not hide the state of every case after it.
    return { passed: false, actual: {}, detail: `error: ${e instanceof Error ? e.message : e}` };
  }
}

function scopeCase(c: EvalCase): CaseOutcome {
  const verdict = classify(c.input.question as string);
  const actual: Record<string, unknown> = !verdict.allowed
    ? { refused: true, reason: verdict.reason }
    // A greeting is allowed and has no domain. Reported as its own thing
    // rather than folded into nutrition, so an eval case can tell the
    // difference between "answered as a food question" and "said hello back".
    : "greeting" in verdict
    ? { refused: false, domain: "greeting" }
    : { refused: false, domain: verdict.domain };

  if (actual.refused !== c.expected.refused) {
    return {
      passed: false,
      actual,
      detail: c.expected.refused
        ? `expected a refusal for ${c.expected.reason}, it was allowed`
        : `expected an answer, it refused for ${actual.reason}`,
    };
  }
  if (c.expected.reason !== undefined && actual.reason !== c.expected.reason) {
    return {
      passed: false,
      actual,
      detail: `refused for the wrong reason: expected ${c.expected.reason}, got ${actual.reason}`,
    };
  }
  if (c.expected.domain !== undefined && actual.domain !== c.expected.domain) {
    return {
      passed: false,
      actual,
      detail: `answered in the wrong domain: expected ${c.expected.domain}, got ${actual.domain}`,
    };
  }
  return { passed: true, actual, detail: null };
}

function verifyMealCase(c: EvalCase): CaseOutcome {
  const v = verifyMeal(c.input.items as MealItem[]);
  return compareVerification(c, {
    verdict: v.verdict,
    failure_types: v.failures.map((f) => f.failure_type),
    blocks: blocks(v).length > 0,
    recomputed: v.recomputed,
  });
}

/**
 * Builds a day of eating from a list of per-meal kcal figures, so a case can
 * say `"meals": [500, 800, 700]` instead of carrying a full plan.
 *
 * `poison_meal` and `poison_name` rename one meal to something a restriction
 * should catch — the allergen case is about the constraint check firing, not
 * about the shape of the plan around it.
 */
function planFrom(input: Record<string, unknown>): Meal[] {
  const kcals = input.meals as number[];
  const slots = ["breakfast", "lunch", "dinner"];
  const poisonAt = input.poison_meal as number | undefined;
  const poisonName = input.poison_name as string | undefined;

  return kcals.map((kcal, i) => ({
    slot: slots[i] ?? `meal ${i + 1}`,
    name_en: i === poisonAt && poisonName ? poisonName : (slots[i] ?? `meal ${i + 1}`),
    portions: [{ en: "portion", ar: "حصة", kcal }],
  }));
}

function verifyPlanCase(c: EvalCase): CaseOutcome {
  const v = verifyPlan(
    planFrom(c.input),
    (c.input.target_kcal as number) ?? null,
    (c.input.restrictions as Restriction[]) ?? [],
  );
  return compareVerification(c, {
    verdict: v.verdict,
    failure_types: v.failures.map((f) => f.failure_type),
    blocks: blocks(v).length > 0,
    recomputed: v.recomputed,
  });
}

function compareVerification(c: EvalCase, actual: Record<string, unknown>): CaseOutcome {
  const types = actual.failure_types as string[];

  if (actual.verdict !== c.expected.verdict) {
    return {
      passed: false,
      actual,
      detail: `expected ${c.expected.verdict}, got ${actual.verdict}` +
        (types.length ? ` (${types.join(", ")})` : " with no findings"),
    };
  }
  if (c.expected.failure_type !== undefined && !types.includes(c.expected.failure_type as string)) {
    return {
      passed: false,
      actual,
      detail: `right verdict, wrong finding: expected ${c.expected.failure_type}, got ` +
        (types.length ? types.join(", ") : "none"),
    };
  }
  // Whether the answer is withheld is a separate question from the verdict, and
  // the allergen case is the one that turns on it.
  if (c.expected.blocks !== undefined && actual.blocks !== c.expected.blocks) {
    return {
      passed: false,
      actual,
      detail: c.expected.blocks
        ? "expected this to withhold the answer, it did not"
        : "expected the answer to still be returned, it was withheld",
    };
  }
  return { passed: true, actual, detail: null };
}

// ---- the run ------------------------------------------------------------

async function db(url: string, key: string, path: string, init: RequestInit = {}) {
  const res = await fetch(`${url}/rest/v1/${path}`, {
    ...init,
    headers: {
      "Content-Type": "application/json",
      apikey: key,
      Authorization: `Bearer ${key}`,
      ...(init.headers ?? {}),
    },
  });
  if (!res.ok) throw new Error(`${path}: ${res.status} ${await res.text()}`);
  return res;
}

async function main() {
  const url = Deno.env.get("SUPABASE_URL");
  const key = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY");
  if (!url || !key) {
    console.error("SUPABASE_URL and SUPABASE_SERVICE_ROLE_KEY are required");
    Deno.exit(2);
  }
  const label = Deno.args[0] ?? `deno eval ${new Date().toISOString().slice(0, 16)}`;

  const cases = await (await db(
    url,
    key,
    "eval_cases?input->>runner=eq.deno&select=id,slug,family,input,expected&order=family,slug",
  )).json() as EvalCase[];

  if (cases.length === 0) {
    console.error("no Deno-runnable cases found — has 0026 been applied?");
    Deno.exit(1);
  }

  const run = (await (await db(url, key, "eval_runs", {
    method: "POST",
    headers: { Prefer: "return=representation" },
    body: JSON.stringify({
      label,
      trigger: "manual",
      notes: "Deno-runnable families only: scope guard and verifier. No model calls.",
    }),
  })).json())[0];

  const results = [];
  let passed = 0;
  for (const c of cases) {
    const started = performance.now();
    const outcome = runCase(c);
    results.push({
      run_id: run.id,
      case_id: c.id,
      passed: outcome.passed,
      actual: outcome.actual,
      failure_detail: outcome.detail,
      latency_ms: Math.round(performance.now() - started),
    });
    if (outcome.passed) passed++;
    else console.error(`FAIL  ${c.family}/${c.slug}: ${outcome.detail}`);
  }

  await db(url, key, "eval_results", { method: "POST", body: JSON.stringify(results) });
  await db(url, key, `eval_runs?id=eq.${run.id}`, {
    method: "PATCH",
    body: JSON.stringify({
      finished_at: new Date().toISOString(),
      passed,
      failed: cases.length - passed,
    }),
  });

  console.log(`${passed}/${cases.length} passed  (run ${run.id})`);
  // A non-zero exit so this can gate a deploy without anyone reading the output.
  Deno.exit(passed === cases.length ? 0 : 1);
}

if (import.meta.main) await main();
