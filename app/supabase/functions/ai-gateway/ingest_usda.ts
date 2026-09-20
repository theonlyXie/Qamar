// Fills nutrient values on the food graph from USDA FoodData Central.
//
// The seed migration deliberately writes no nutrient numbers: names, aliases,
// portions and recipes are authored, but every per-100g figure has to trace to
// a laboratory analysis. This is the script that fetches them.
//
//   deno run --allow-net --allow-env \
//     supabase/functions/ai-gateway/ingest_usda.ts [--limit N] [--dry-run]
//
// Needs USDA_API_KEY (free, api.data.gov), SUPABASE_URL and
// SUPABASE_SERVICE_ROLE_KEY. DEMO_KEY is shared across the whole internet and
// is usually already rate-limited, so it is not a fallback worth having.
//
// Matching is deliberately conservative. A wrong food is worse than a missing
// one, because a missing one shows as an estimate the user can correct while a
// wrong one shows as a confident number that is wrong. Anything below the
// score floor is left alone and reported for a human to map by hand.

const USDA_KEY = Deno.env.get("USDA_API_KEY");
const SUPABASE_URL = Deno.env.get("SUPABASE_URL");
const SERVICE_KEY = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY");

if (!USDA_KEY || !SUPABASE_URL || !SERVICE_KEY) {
  console.error("need USDA_API_KEY, SUPABASE_URL and SUPABASE_SERVICE_ROLE_KEY");
  Deno.exit(1);
}

const args = new Set(Deno.args);
const DRY_RUN = args.has("--dry-run");
const LIMIT = Number(Deno.args.find((a) => a.startsWith("--limit="))?.split("=")[1] ?? 0);

// USDA nutrient IDs to Qamar nutrient codes. Anything not listed is ignored
// rather than guessed at.
const NUTRIENT_MAP: Record<number, string> = {
  1008: "energy_kcal",
  1003: "protein_g",
  1005: "carbs_g",
  1004: "fat_g",
  1079: "fiber_g",
  2000: "sugars_g",
  1258: "sat_fat_g",
  1093: "sodium_mg",
  1092: "potassium_mg",
  1087: "calcium_mg",
  1089: "iron_mg",
  1095: "zinc_mg",
  1114: "vitamin_d_ug",
  1178: "vitamin_b12_ug",
  1177: "folate_ug",
  1190: "folate_ug", // Folate, DFE — see PREFERRED_IDS
  1162: "vitamin_c_mg",
  1106: "vitamin_a_ug",
  1100: "iodine_ug",
  1051: "water_g",
  // Added with the DRI seed in 0031. A target with no food values behind it is
  // a number the app can display and never act on, so the importer has to reach
  // these before the gap report means anything.
  1090: "magnesium_mg",
  1103: "selenium_ug",
  1109: "vitamin_e_mg", // alpha-tocopherol, which is what the DRI is set on
  1165: "thiamin_mg",
  1166: "riboflavin_mg",
  1167: "niacin_mg",
  1175: "vitamin_b6_mg",
};

/**
 * When two USDA fields map to one Qamar code, the one listed here wins
 * regardless of which arrives first in the response.
 *
 * Folate is the case that matters. USDA reports both "Folate, total" (1177, in
 * µg of folate) and "Folate, DFE" (1190, in dietary folate equivalents), and
 * the DRI is set in DFE. Fortified flour — Egyptian baladi bread included —
 * carries folic acid, which is absorbed roughly 1.7 times better than the
 * natural form, so the two numbers diverge exactly where bread is the staple.
 * Taking whichever came last in the array would have made the folate column
 * silently mean different things for different foods.
 */
const PREFERRED_IDS = new Set([1190]);

/**
 * Which set of nutrients this importer knows how to fetch.
 *
 * Bump this whenever NUTRIENT_MAP gains a code. It is stored on every row it
 * writes, and it is how the run below decides a food is done.
 *
 * Skipping "foods that already have nutrients" was right exactly once. The
 * moment the map grew, every food loaded by the old map — all of them — looked
 * finished while missing the seven nutrients that had just been added, and no
 * amount of re-running would have fixed it. Same shape as the bug in the
 * knowledge-base ingest: a skip rule that was true when written and quietly
 * false after the thing it skipped for changed.
 *
 * The write is an upsert on (food, nutrient, basis), so re-fetching a food
 * updates its rows rather than duplicating them.
 */
const NUTRIENT_SET_VERSION = "fdc-2026-08";

/** Below this, we do not claim a match. */
const SCORE_FLOOR = 0.45;

interface Food {
  qamar_food_id: string;
  slug: string;
  name_en: string;
  food_state: string;
  is_recipe: boolean;
}

async function db(path: string, init: RequestInit = {}): Promise<Response> {
  return await fetch(`${SUPABASE_URL}/rest/v1/${path}`, {
    ...init,
    headers: {
      "Content-Type": "application/json",
      apikey: SERVICE_KEY!,
      Authorization: `Bearer ${SERVICE_KEY}`,
      ...(init.headers ?? {}),
    },
  });
}

/**
 * Refuses to run if the registry does not permit storing USDA results.
 *
 * This looks redundant — USDA is public domain and always will be — but the
 * point is that every ingestion path asks the same question of the same table.
 * The first time a script skips the check is the first time an unlicensed
 * source ends up cached in the graph.
 */
async function assertStorageAllowed(sourceId: string): Promise<void> {
  const res = await db(
    `source_registry?source_id=eq.${sourceId}&select=status,storage_rights,license_class`,
  );
  const rows = await res.json();
  const s = rows[0];
  if (!s) throw new Error(`source ${sourceId} is not in the registry; add it before ingesting`);
  if (s.status !== "active") throw new Error(`source ${sourceId} is '${s.status}', not active`);
  if (!["indefinite", "time_limited_cache"].includes(s.storage_rights)) {
    throw new Error(
      `source ${sourceId} has storage_rights '${s.storage_rights}'; results may not be persisted`,
    );
  }
  console.log(`registry: ${sourceId} ok (${s.license_class}, ${s.storage_rights})`);
}

/** Crude token overlap. Good enough to reject a bad match, which is its job. */
function score(query: string, candidate: string): number {
  const norm = (s: string) =>
    s.toLowerCase().replace(/[^a-z0-9 ]/g, " ").split(/\s+/).filter((w) => w.length > 2);
  const a = new Set(norm(query));
  const b = new Set(norm(candidate));
  if (a.size === 0 || b.size === 0) return 0;
  let hits = 0;
  for (const w of a) if (b.has(w)) hits++;
  return hits / a.size;
}

interface UsdaHit {
  fdcId: number;
  description: string;
  nutrients: Record<string, number>;
}

/**
 * Maps one USDA nutrient list onto Qamar codes.
 *
 * The search endpoint and the by-id endpoint spell the same list differently
 * (`nutrientId`/`value` versus `nutrient.id`/`amount`), so the two accessors
 * are passed in and the PREFERRED_IDS rule lives in one place.
 */
function pickNutrients(
  list: unknown[],
  idOf: (n: unknown) => number | undefined,
  valueOf: (n: unknown) => unknown,
): Record<string, number> | null {
  const nutrients: Record<string, number> = {};
  const fromPreferred = new Set<string>();
  for (const n of list) {
    const id = idOf(n);
    const code = id === undefined ? undefined : NUTRIENT_MAP[id];
    const value = valueOf(n);
    if (!code || typeof value !== "number") continue;
    if (fromPreferred.has(code)) continue; // a preferred field already won
    nutrients[code] = value;
    if (id !== undefined && PREFERRED_IDS.has(id)) fromPreferred.add(code);
  }
  // Absent, not zero. Water, salt and brewed tea legitimately report 0 kcal,
  // and 0034 made them recipe ingredients; a falsy check here used to throw
  // them away as "no energy value".
  if (nutrients.energy_kcal === undefined) return null;
  return nutrients;
}

async function searchUsda(query: string): Promise<UsdaHit | null> {
  const url =
    `https://api.nal.usda.gov/fdc/v1/foods/search?api_key=${USDA_KEY}` +
    `&query=${encodeURIComponent(query)}&pageSize=5&dataType=SR%20Legacy,Foundation`;

  const res = await fetch(url);
  if (res.status === 429) {
    console.error("rate limited by USDA; stopping so the run can be resumed cleanly");
    Deno.exit(2);
  }
  if (!res.ok) return null;

  const json = await res.json();
  const foods = json.foods ?? [];
  if (foods.length === 0) return null;

  let best = null as null | { fdcId: number; description: string; s: number; raw: unknown };
  for (const f of foods) {
    const s = score(query, f.description ?? "");
    if (!best || s > best.s) best = { fdcId: f.fdcId, description: f.description, s, raw: f };
  }
  if (!best || best.s < SCORE_FLOOR) {
    console.log(`  no confident match (best ${best?.s.toFixed(2)} "${best?.description}")`);
    return null;
  }

  const nutrients = pickNutrients(
    // deno-lint-ignore no-explicit-any
    (best.raw as any).foodNutrients ?? [],
    // deno-lint-ignore no-explicit-any
    (n) => (n as any).nutrientId,
    // deno-lint-ignore no-explicit-any
    (n) => (n as any).value,
  );
  if (!nutrients) {
    console.log(`  match has no energy value, skipping: "${best.description}"`);
    return null;
  }
  return { fdcId: best.fdcId, description: best.description, nutrients };
}

/**
 * Fetches one USDA food by its fdcId, for the foods a person has mapped by
 * hand.
 *
 * The search cannot find عيش بلدي or جبنة قريش under any English name, and the
 * unmatched report at the end of every run has been asking for a way to act on
 * "map them to the closest generic food deliberately". The way is a
 * food_source_links row: source 'usda_fdc', external_type 'fdc_id', written by
 * the person who made the judgement. This importer then takes that id as
 * given and skips the search, so a deliberate choice is never second-guessed
 * by a token-overlap score — and the provenance of the choice is the row.
 */
async function fetchUsdaById(fdcId: number): Promise<UsdaHit | null> {
  const url = `https://api.nal.usda.gov/fdc/v1/food/${fdcId}?api_key=${USDA_KEY}`;
  const res = await fetch(url);
  if (res.status === 429) {
    console.error("rate limited by USDA; stopping so the run can be resumed cleanly");
    Deno.exit(2);
  }
  if (!res.ok) {
    console.log(`  hand-mapped fdc_id ${fdcId} returned ${res.status}`);
    return null;
  }
  const json = await res.json();
  const nutrients = pickNutrients(
    json.foodNutrients ?? [],
    // deno-lint-ignore no-explicit-any
    (n) => (n as any).nutrient?.id,
    // deno-lint-ignore no-explicit-any
    (n) => (n as any).amount,
  );
  if (!nutrients) {
    console.log(`  hand-mapped fdc_id ${fdcId} has no energy value: "${json.description}"`);
    return null;
  }
  return { fdcId, description: json.description ?? String(fdcId), nutrients };
}

async function main() {
  await assertStorageAllowed("usda_fdc");

  // Never recipes: a dish is computed from its ingredients, not looked up,
  // because no food table contains koshary.
  const res = await db(
    "foods?is_recipe=eq.false&select=qamar_food_id,slug,name_en,food_state&order=slug",
  );
  const all: Food[] = await res.json();

  // Done means "loaded by this version of the map", not "has some nutrients".
  const haveRes = await db(
    `food_nutrients?select=qamar_food_id&nutrient_definition_version=eq.${NUTRIENT_SET_VERSION}`,
  );
  const have = new Set((await haveRes.json()).map((r: { qamar_food_id: string }) => r.qamar_food_id));

  let todo = all.filter((f) => !have.has(f.qamar_food_id));
  if (LIMIT > 0) todo = todo.slice(0, LIMIT);

  // Hand-mapped ids, written by a person into food_source_links. A food that
  // has one is fetched by id and never searched.
  const linksRes = await db(
    "food_source_links?source_id=eq.usda_fdc&external_type=eq.fdc_id&select=qamar_food_id,external_id",
  );
  const handMapped = new Map<string, number>(
    ((await linksRes.json()) as { qamar_food_id: string; external_id: string }[])
      .map((r) => [r.qamar_food_id, Number(r.external_id)] as [string, number])
      .filter(([, id]) => Number.isFinite(id)),
  );

  console.log(
    `${todo.length} of ${all.length} foods to resolve ` +
      `(${have.size} already at nutrient set ${NUTRIENT_SET_VERSION}, ` +
      `${handMapped.size} hand-mapped)\n`,
  );

  let matched = 0;
  const unmatched: string[] = [];

  for (const food of todo) {
    // The state matters: boiled rice and raw rice are different rows in USDA
    // and wildly different per 100 g.
    const query = food.food_state === "unspecified"
      ? food.name_en
      : `${food.name_en} ${food.food_state}`;
    const mappedId = handMapped.get(food.qamar_food_id);
    console.log(mappedId ? `${food.slug}: hand-mapped fdc_id ${mappedId}` : `${food.slug}: "${query}"`);

    const hit = mappedId ? await fetchUsdaById(mappedId) : await searchUsda(query);
    if (!hit) {
      unmatched.push(food.slug);
      continue;
    }
    console.log(`  -> ${hit.fdcId} "${hit.description}" (${Object.keys(hit.nutrients).length} nutrients)`);
    matched++;

    if (DRY_RUN) continue;

    const rows = Object.entries(hit.nutrients).map(([code, amount]) => ({
      qamar_food_id: food.qamar_food_id,
      nutrient_code: code,
      amount,
      per_basis: "per_100g",
      source_id: "usda_fdc",
      nutrient_definition_version: NUTRIENT_SET_VERSION,
      confidence: 0.9,
    }));

    const ins = await db("food_nutrients?on_conflict=qamar_food_id,nutrient_code,per_basis", {
      method: "POST",
      headers: { Prefer: "resolution=merge-duplicates" },
      body: JSON.stringify(rows),
    });
    if (!ins.ok) console.error(`  ! nutrients: ${await ins.text()}`);

    const link = await db("food_source_links?on_conflict=qamar_food_id,source_id,external_id", {
      method: "POST",
      headers: { Prefer: "resolution=merge-duplicates" },
      body: JSON.stringify({
        qamar_food_id: food.qamar_food_id,
        source_id: "usda_fdc",
        external_id: String(hit.fdcId),
        external_type: "fdc_id",
        url: `https://fdc.nal.usda.gov/food-details/${hit.fdcId}`,
        field_provenance: Object.fromEntries(
          Object.keys(hit.nutrients).map((c) => [c, "usda_fdc"]),
        ),
      }),
    });
    if (!link.ok) console.error(`  ! link: ${await link.text()}`);

    // Courtesy pacing. The published limit is generous but this runs once.
    await new Promise((r) => setTimeout(r, 250));
  }

  console.log(`\nmatched ${matched}, unmatched ${unmatched.length}`);
  if (unmatched.length) {
    console.log("\nneeding a hand-mapped fdc_id (or a national table entry):");
    for (const s of unmatched) console.log(`  ${s}`);
    console.log(
      "\nThese are mostly Egyptian items USDA does not carry. Map them to the " +
        "closest generic food deliberately — insert a food_source_links row " +
        "(source_id 'usda_fdc', external_type 'fdc_id') and re-run — or take " +
        "them from the Egypt food composition tables. Do not let the model " +
        "estimate them. `select * from dish_nutrient_readiness where not " +
        "computable` lists which dishes each gap is holding back.",
    );
  }
  if (DRY_RUN) console.log("\n(dry run: nothing written)");
}

await main();
