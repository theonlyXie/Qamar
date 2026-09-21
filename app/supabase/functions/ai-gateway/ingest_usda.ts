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

import {
  NUTRIENT_SET_VERSION,
  USDA_NUTRIENT_MAP as NUTRIENT_MAP,
  USDA_PREFERRED_IDS as PREFERRED_IDS,
} from "./catalog.ts";

// The nutrient set, the folate preference and the version marker moved to
// catalog.ts when the whole-catalogue importers arrived, and are imported here
// rather than kept in step by hand. Two scripts writing different sets of
// nutrients under the same nutrient_definition_version would make the version
// string a lie, and the "is this food done" check that rests on it would start
// skipping foods missing half their values — the same shape as the bug the
// version marker was introduced to fix. Adding a code means adding it in one
// place and bumping the version there; both importers pick it up.

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

async function searchUsda(query: string): Promise<{ fdcId: number; description: string; nutrients: Record<string, number> } | null> {
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

  const nutrients: Record<string, number> = {};
  const fromPreferred = new Set<string>();
  // deno-lint-ignore no-explicit-any
  for (const n of ((best.raw as any).foodNutrients ?? [])) {
    const code = NUTRIENT_MAP[n.nutrientId];
    if (!code || typeof n.value !== "number") continue;
    if (fromPreferred.has(code)) continue; // a preferred field already won
    nutrients[code] = n.value;
    if (PREFERRED_IDS.has(n.nutrientId)) fromPreferred.add(code);
  }
  if (!nutrients.energy_kcal) {
    console.log(`  match has no energy value, skipping: "${best.description}"`);
    return null;
  }
  return { fdcId: best.fdcId, description: best.description, nutrients };
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

  console.log(
    `${todo.length} of ${all.length} foods to resolve ` +
      `(${have.size} already at nutrient set ${NUTRIENT_SET_VERSION})\n`,
  );

  let matched = 0;
  const unmatched: string[] = [];

  for (const food of todo) {
    // The state matters: boiled rice and raw rice are different rows in USDA
    // and wildly different per 100 g.
    const query = food.food_state === "unspecified"
      ? food.name_en
      : `${food.name_en} ${food.food_state}`;
    console.log(`${food.slug}: "${query}"`);

    const hit = await searchUsda(query);
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
        "closest generic food deliberately, or take them from the Egypt food " +
        "composition tables — do not let the model estimate them.",
    );
  }
  if (DRY_RUN) console.log("\n(dry run: nothing written)");
}

await main();
