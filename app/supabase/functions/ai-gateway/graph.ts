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
import type { MealItem } from "./verify.ts";

/** Above this, a fuzzy match is treated as settled. */
const CONFIDENT = 0.75;
/** Below this, the graph is treated as having missed entirely. */
const PLAUSIBLE = 0.35;
/**
 * Below this fraction of the typed words accounted for, a match is refused
 * however well it scores.
 *
 * Trigram similarity rewards an alias that matches part of a phrase, so the
 * graph used to answer برجر لحم with raw beef at 0.38, فراخ بروستد with a plain
 * chicken breast, and — the one nobody had noticed — رز ابيض مسلوق with eggs.
 * None of those failed; they returned a different food at roughly half the
 * calories. Coverage is what tells them apart: every correct match in the
 * catalogue covers 1.0 of the phrase, and every one of those wrong ones covers
 * 0.5 or less.
 */
const COVERAGE_FLOOR = 0.6;

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
  /** Fraction of the typed words this alias accounts for. */
  phraseCoverage: number;
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
  phrase_coverage: number;
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
  phraseCoverage: Number(r.phrase_coverage ?? 1),
});

/** Whether the graph is entitled to claim this match. */
/**
 * Whether the graph is entitled to claim this match.
 *
 * The coverage floor applies to ingredients and not to dishes, and that is not
 * a fudge to make a test pass — it is the difference the failures themselves
 * showed. Every wrong answer returned a raw ingredient while ignoring the word
 * that named a cooked thing: برجر لحم gave beef, فراخ بروستد gave a chicken
 * breast, رز ابيض مسلوق gave eggs. The one legitimate partial match, شاورما
 * فراخ, returned the right dish and merely did not know which protein.
 *
 * Answering a dish with a generic version of that dish is incomplete.
 * Answering it with one of its raw ingredients is wrong. A partial dish match
 * is therefore allowed through and marked for confirmation; a partial
 * ingredient match is refused.
 */
function isUsable(c: GraphCandidate | null): c is GraphCandidate {
  if (!c || c.matchScore < PLAUSIBLE) return false;
  return c.phraseCoverage >= COVERAGE_FLOOR || c.isRecipe;
}

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
  const usable = isUsable(top) ? top : null;

  // Refused for coverage rather than for score: the graph knows a food by that
  // name and the phrase said more than the name did. Worth saying out loud,
  // because it is the difference between "I have never heard of this" and "I
  // ignored half of what you typed".
  if (top && !usable && top.matchScore >= PLAUSIBLE) {
    uncertainty.push(
      `"${top.matchedAlias}" only accounts for part of "${phrase}", so it was not used`,
    );
  }
  // Let through as a dish, but not silently: the generic version of a dish is
  // not the variant that was asked for, and the confirmation screen is where
  // that gets settled.
  if (usable && usable.phraseCoverage < COVERAGE_FLOOR) {
    uncertainty.push(
      `matched the dish "${usable.matchedAlias}" but not everything in "${phrase}"`,
    );
  }

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

/** What an item needs to carry for anything past calories to be computable. */
export interface FoodIdentity {
  /** The food this item was matched to, as foods.qamar_food_id. */
  qamarFoodId: string | null;
  /** The eaten weight. Null when no portion could be established. */
  grams: number | null;
  /** True when the user named the portion; false when Qamar assumed one. */
  portionMatched: boolean;
  /** Match score, so a caller can decline to trust a weak identification. */
  matchScore: number | null;
  slug: string | null;
}

/**
 * Identifies each analysed item against the food graph.
 *
 * This exists because of a gap that made the whole micronutrient layer inert.
 * meal_logs.items has held a name and four macros since 0001 — the model's
 * reading of the plate — and none of it points at a row in `foods`. So the
 * moment anything wanted to ask a question calories cannot answer ("has she
 * been short on iron this week"), there was nothing to join on. Attaching the
 * food id and the gram weight at analysis time is what turns a log from a
 * calorie diary into a diet history.
 *
 * The identification is per item and on the item's own name, not on the phrase
 * list the prompt was built from: the model splits "koshary and salad" into two
 * items, and each of them has to be identified as itself.
 *
 * Weak matches are returned as nulls rather than as guesses. A wrong food id is
 * worse than a missing one — it produces a confident number about an entirely
 * different meal — and every consumer of this already treats a null as "cannot
 * say" and reports its coverage.
 */
export async function identifyItems(
  supabaseUrl: string,
  serviceKey: string,
  items: { ar?: string; en?: string; portionAr?: string; portionEn?: string }[],
): Promise<FoodIdentity[]> {
  return await Promise.all(items.slice(0, 20).map(async (item) => {
    const none: FoodIdentity = {
      qamarFoodId: null,
      grams: null,
      portionMatched: false,
      matchScore: null,
      slug: null,
    };

    // Arabic first: the graph's aliases are Egyptian Arabic, and the English
    // name the model produces is a translation of its own making.
    const name = (item.ar ?? item.en ?? "").trim();
    if (!name) return none;

    // The portion goes into the phrase because that is how the resolver finds a
    // named household measure — "رغيف" only becomes 90 g if the word is there.
    const phrase = [name, item.portionAr ?? item.portionEn ?? ""].join(" ").trim();

    const raw = await rpc<RawCandidate>(supabaseUrl, serviceKey, "qamar_resolve_food", {
      p_phrase: name,
      p_limit: 1,
    });
    const top = raw[0] ? toCandidate(raw[0]) : null;
    // Same bar as resolveOne. An id attached on a half-matched name is worse
    // than no id: it files the meal under the wrong food permanently.
    if (!isUsable(top)) return none;

    const portions = await rpc<{
      grams: number;
      matched_in_phrase: boolean;
    }>(supabaseUrl, serviceKey, "qamar_resolve_portion", {
      p_food_id: top.qamarFoodId,
      p_phrase: phrase,
    });

    return {
      qamarFoodId: top.qamarFoodId,
      grams: portions[0] ? Number(portions[0].grams) : null,
      portionMatched: portions[0]?.matched_in_phrase ?? false,
      matchScore: top.matchScore,
      slug: top.slug,
    };
  }));
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
      phrase_coverage: r.food?.phraseCoverage ?? null,
      nutrients: r.facts?.per100g ?? null,
      source: r.facts?.source ?? null,
      needs_confirmation: r.needsConfirmation,
      uncertainty: r.uncertainty,
    }));
}

/** A meal item that knows which food it is, in the keys meal_logs stores. */
export type IdentifiedMealItem = MealItem & {
  qamar_food_id: string | null;
  grams: number | null;
  food_slug: string | null;
  portion_matched: boolean;
};

/**
 * Turns graph resolutions into the meal-item shape the app confirms.
 *
 * Typed and spoken logs use this instead of the model: the numbers are the
 * per-100 g facts scaled by the resolved portion, so a رغيف is arithmetic
 * rather than a guess. Phrases the graph could not price are dropped — an
 * empty list is the honest answer, not a reason to spend a model call.
 *
 * The food id and the gram weight travel with the item. On this path they cost
 * nothing to know — the resolution being converted is already holding both —
 * and without them a meal logged by typing would price correctly and then be
 * invisible to every micronutrient question, which is the failure the photo
 * path was just fixed for.
 */
export function itemsFromResolutions(items: Resolution[]): IdentifiedMealItem[] {
  return items.flatMap((r) => {
    const facts = r.facts;
    if (!facts) return [];
    const grams = r.portion && r.portion.grams > 0 ? r.portion.grams : 100;
    const scale = grams / 100;
    const high =
      !r.needsConfirmation && (r.origin === "graph" || r.origin === "graph_derived");
    const portionEn = r.portion?.labelEn ?? `${grams} g`;
    const portionAr = r.portion?.labelAr ?? portionEn;
    return [{
      ar: r.food?.nameEg ?? r.food?.nameAr ?? r.phrase,
      en: r.food?.nameEn ?? facts.name,
      portionAr,
      portionEn,
      confidence: high ? "high" : "low",
      kcal: Math.round(facts.per100g.kcal * scale),
      proteinG: Math.round(facts.per100g.protein * scale),
      carbsG: Math.round(facts.per100g.carbs * scale),
      fatG: Math.round(facts.per100g.fat * scale),
      // Null when the graph did not identify the food, even though an external
      // lookup priced it. A price is not an identity.
      qamar_food_id: r.food?.qamarFoodId ?? null,
      grams: r.portion?.grams ?? null,
      food_slug: r.food?.slug ?? null,
      portion_matched: r.portion?.matchedInPhrase ?? false,
    }];
  });
}
