// The food resolver: Qamar's graph first, external APIs only on a miss.
//
// This is the source router. Before it, every logged food went to USDA and Open
// Food Facts on every request, which is slow, costs calls, and cannot resolve
// عيش بلدي at all because no international database carries it. Now the local
// graph answers first, and an external lookup is what happens when it cannot.
//
// The other half of the job is honesty. A resolution carries how it was made —
// exact alias, fuzzy match, derived from a recipe, or fetched from outside —
// and whether the portion was named by the user or assumed. The caller uses
// that to ask instead of asserting, which is the rule that stops an uncertain
// match from reaching the user as a confident number.

import { lookupFood, type FoodFacts } from "./retrieval.ts";

/** Above this, a fuzzy match is treated as settled. */
const CONFIDENT = 0.75;
/** Below this, the graph is treated as having missed entirely. */
const PLAUSIBLE = 0.35;

export interface GraphCandidate {
  qamarFoodId: string;
  slug: string;
  nameEn: string;
  nameAr: string | null;
  nameEg: string | null;
  isRecipe: boolean;
  matchScore: number;
  matchedAlias: string;
  matchKind: "exact" | "fuzzy";
  hasNutrients: boolean;
}

export interface ResolvedPortion {
  labelEn: string;
  labelAr: string | null;
  grams: number;
  basis: string;
  confidence: number | null;
  /** True when the user named this portion, false when we picked the default. */
  matchedInPhrase: boolean;
}

export type Origin = "graph" | "graph_derived" | "external" | "unresolved";

export interface Resolution {
  phrase: string;
  food: GraphCandidate | null;
  alternatives: GraphCandidate[];
  portion: ResolvedPortion | null;
  /** Per 100 g. Null when nothing could supply it — never zero. */
  facts: FoodFacts | null;
  origin: Origin;
  needsConfirmation: boolean;
  /** Why confirmation is being asked for, in a form the UI can show. */
  uncertainty: string[];
}

async function rpc<T>(
  supabaseUrl: string,
  serviceKey: string,
  fn: string,
  body: Record<string, unknown>,
): Promise<T[]> {
  const res = await fetch(`${supabaseUrl}/rest/v1/rpc/${fn}`, {
    method: "POST",
    headers: {
      "Content-Type": "application/json",
      apikey: serviceKey,
      Authorization: `Bearer ${serviceKey}`,
    },
    body: JSON.stringify(body),
  });
  if (!res.ok) {
    console.error(`rpc ${fn} failed: ${res.status} ${await res.text()}`);
    return [];
  }
  return (await res.json()) as T[];
}

interface RawCandidate {
  qamar_food_id: string;
  slug: string;
  name_en: string;
  name_ar: string | null;
  name_eg: string | null;
  is_recipe: boolean;
  match_score: number;
  matched_alias: string;
  match_kind: "exact" | "fuzzy";
  has_nutrients: boolean;
}

interface RawNutrient {
  nutrient_code: string;
  amount: number;
  unit: string;
  source_id: string;
  confidence: number | null;
  derived: boolean;
}

const toCandidate = (r: RawCandidate): GraphCandidate => ({
  qamarFoodId: r.qamar_food_id,
  slug: r.slug,
  nameEn: r.name_en,
  nameAr: r.name_ar,
  nameEg: r.name_eg,
  isRecipe: r.is_recipe,
  matchScore: r.match_score,
  matchedAlias: r.matched_alias,
  matchKind: r.match_kind,
  hasNutrients: r.has_nutrients,
});

/**
 * Per-100g macros for a resolved food.
 *
 * Returns null rather than zeros when the graph holds no values. A dish whose
 * ingredients have not been ingested yet is a miss, and a miss has to fall
 * through to an external lookup — reporting it as 0 kcal would be a confident
 * lie in the one place this product cannot afford one.
 */
async function graphFacts(
  supabaseUrl: string,
  serviceKey: string,
  food: GraphCandidate,
): Promise<{ facts: FoodFacts; derived: boolean } | null> {
  const rows = await rpc<RawNutrient>(supabaseUrl, serviceKey, "qamar_nutrients_per_100g", {
    p_food_id: food.qamarFoodId,
  });
  if (rows.length === 0) return null;

  const by = new Map(rows.map((r) => [r.nutrient_code, r]));
  const kcal = by.get("energy_kcal");
  if (!kcal) return null;

  const num = (code: string) => Math.round(by.get(code)?.amount ?? 0);
  const derived = rows.some((r) => r.derived);

  return {
    derived,
    facts: {
      name: food.nameEn,
      per100g: {
        kcal: Math.round(kcal.amount),
        protein: num("protein_g"),
        carbs: num("carbs_g"),
        fat: num("fat_g"),
      },
      source: derived ? "Qamar recipe (derived)" : `Qamar graph (${kcal.source_id})`,
      url: null,
    },
  };
}

/** Resolves one phrase. Graph first, external only when the graph cannot answer. */
export async function resolveOne(
  supabaseUrl: string,
  serviceKey: string,
  phrase: string,
): Promise<Resolution> {
  const uncertainty: string[] = [];
  const raw = await rpc<RawCandidate>(supabaseUrl, serviceKey, "qamar_resolve_food", {
    p_phrase: phrase,
    p_limit: 3,
  });

  const candidates = raw.map(toCandidate);
  const top = candidates[0] ?? null;
  const usable = top && top.matchScore >= PLAUSIBLE ? top : null;

  let portion: ResolvedPortion | null = null;
  let facts: FoodFacts | null = null;
  let origin: Origin = "unresolved";

  if (usable) {
    if (usable.matchKind === "fuzzy" && usable.matchScore < CONFIDENT) {
      uncertainty.push(
        `matched "${usable.matchedAlias}" at ${usable.matchScore.toFixed(2)}, not an exact name`,
      );
    }
    // A second candidate scoring nearly as well is a genuine ambiguity, not a
    // ranking detail — the user is the one who knows which they ate.
    const runnerUp = candidates[1];
    if (runnerUp && usable.matchScore - runnerUp.matchScore < 0.1) {
      uncertainty.push(`could also be ${runnerUp.nameEn}`);
    }

    const portions = await rpc<{
      label_en: string;
      label_ar: string | null;
      grams: number;
      basis: string;
      confidence: number | null;
      matched_in_phrase: boolean;
    }>(supabaseUrl, serviceKey, "qamar_resolve_portion", {
      p_food_id: usable.qamarFoodId,
      p_phrase: phrase,
    });

    if (portions[0]) {
      const p = portions[0];
      portion = {
        labelEn: p.label_en,
        labelAr: p.label_ar,
        grams: Number(p.grams),
        basis: p.basis,
        confidence: p.confidence,
        matchedInPhrase: p.matched_in_phrase,
      };
      if (!portion.matchedInPhrase) uncertainty.push(`portion assumed: ${portion.labelEn}`);
      if (portion.basis === "estimated") uncertainty.push("portion weight is an estimate");
    }

    const got = await graphFacts(supabaseUrl, serviceKey, usable);
    if (got) {
      facts = got.facts;
      origin = got.derived ? "graph_derived" : "graph";
    }
  }

  // The graph knew the food but not its numbers, or did not know it at all.
  if (!facts) {
    const external = await lookupFood(phrase);
    if (external) {
      facts = external;
      origin = "external";
      uncertainty.push(`nutrition from ${external.source}, not the Qamar graph`);
    }
  }

  return {
    phrase,
    food: usable,
    alternatives: candidates.slice(1),
    portion,
    facts,
    origin,
    needsConfirmation: uncertainty.length > 0 || origin === "unresolved",
    uncertainty,
  };
}

/** Resolves several phrases at once. */
export async function resolveFoods(
  supabaseUrl: string,
  serviceKey: string,
  phrases: string[],
): Promise<Resolution[]> {
  return await Promise.all(
    phrases.slice(0, 12).map((p) => resolveOne(supabaseUrl, serviceKey, p)),
  );
}

/**
 * What the model is shown.
 *
 * Deliberately includes the gram weight of the named portion, so the model is
 * reading an arithmetic input rather than guessing how much a رغيف weighs — and
 * marks anything uncertain, so it cannot present a fuzzy match as settled.
 */
export function renderResolutions(items: Resolution[]): string {
  const usable = items.filter((r) => r.facts);
  if (usable.length === 0) return "(no food data resolved)";

  return usable
    .map((r) => {
      const f = r.facts!;
      const portion = r.portion ? ` · ${r.portion.labelEn} = ${r.portion.grams} g` : "";
      const flag = r.needsConfirmation ? " [UNCERTAIN: " + r.uncertainty.join("; ") + "]" : "";
      return `${f.name}${portion}: per 100 g — ${f.per100g.kcal} kcal, P ${f.per100g.protein} g, ` +
        `C ${f.per100g.carbs} g, F ${f.per100g.fat} g (${f.source})${flag}`;
    })
    .join("\n");
}

/** The food_facts entry of the evidence packet, per the architecture paper. */
export function toPacketFacts(items: Resolution[]): unknown[] {
  return items
    .filter((r) => r.food || r.facts)
    .map((r) => ({
      phrase: r.phrase,
      qamar_food_id: r.food?.qamarFoodId ?? null,
      slug: r.food?.slug ?? null,
      quantity_g: r.portion?.grams ?? null,
      origin: r.origin,
      match_score: r.food?.matchScore ?? null,
      nutrients: r.facts?.per100g ?? null,
      source: r.facts?.source ?? null,
      needs_confirmation: r.needsConfirmation,
      uncertainty: r.uncertainty,
    }));
}
