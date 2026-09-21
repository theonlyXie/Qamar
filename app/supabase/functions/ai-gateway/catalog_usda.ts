// Brings the whole of USDA FoodData Central into the food graph.
//
// The difference from ingest_usda.ts, which stays: that script takes the 131
// foods the Egyptian seed authored and finds a USDA match for each, so the
// authored graph gets laboratory numbers. This one goes the other way and
// imports USDA's own catalogue as new foods, so a phrase the seed never
// anticipated — "quinoa", "tilapia fillet, baked", "pumpkin seeds" — resolves
// locally instead of costing an external call and arriving as an estimate.
//
//   deno run --allow-net --allow-env \
//     supabase/functions/ai-gateway/catalog_usda.ts \
//     [--datasets=foundation,sr_legacy,survey] [--limit=N] [--batch=N] [--dry-run]
//
// Needs USDA_API_KEY, SUPABASE_URL and SUPABASE_SERVICE_ROLE_KEY.
//
// On scale and why Branded is not the default. Foundation, SR Legacy and
// Survey together are about 15,000 foods: every generic raw and cooked item
// USDA has laboratory or survey values for, which is most of what an Egyptian
// home-cooked plate is made of, and it fits inside one api.data.gov hourly
// quota. Branded is roughly two million rows of American supermarket packaging,
// which at twenty foods per detail call is a hundred thousand requests and a
// hundred hours. Packaged goods are Open Food Facts' job — see catalog_off.ts,
// which carries Egyptian products USDA has never heard of. --datasets=branded
// works if you want it, but pair it with --limit and know what you are asking.

import {
  assertStorageAllowed,
  type CatalogFood,
  catalogSlug,
  foodGroupFrom,
  isDone,
  loadDoneState,
  NUTRIENT_SET_VERSION,
  requireEnv,
  screenNutrients,
  USDA_NUTRIENT_MAP,
  USDA_PREFERRED_IDS,
  writeBatch,
} from "./catalog.ts";

const SOURCE_ID = "usda_fdc";

/**
 * Per-dataset trust, expressed as the two numbers the resolver ranks on.
 *
 * Every rank sits below the 50 the authored Egyptian seed carries, and that is
 * the point rather than a detail: when a user types عيش and both an authored
 * loaf and an imported wheat bread score the same, the authored row has to win.
 * Foundation is current lab analysis, SR Legacy is the older lab archive,
 * Survey is what FNDDS models from consumption data rather than measures.
 */
const DATASETS: Record<string, { apiName: string; rank: number; confidence: number }> = {
  foundation: { apiName: "Foundation", rank: 45, confidence: 0.9 },
  sr_legacy: { apiName: "SR Legacy", rank: 40, confidence: 0.85 },
  survey: { apiName: "Survey (FNDDS)", rank: 35, confidence: 0.75 },
  branded: { apiName: "Branded", rank: 25, confidence: 0.6 },
};

const args = Deno.args;
const flag = (name: string): string | undefined =>
  args.find((a) => a.startsWith(`--${name}=`))?.split("=").slice(1).join("=");

const DRY_RUN = args.includes("--dry-run");
const LIMIT = Number(flag("limit") ?? 0);
const BATCH = Math.max(1, Number(flag("batch") ?? 100));
const WANTED = (flag("datasets") ?? "foundation,sr_legacy,survey")
  .split(",")
  .map((d) => d.trim())
  .filter(Boolean);

for (const d of WANTED) {
  if (!(d in DATASETS)) {
    console.error(`unknown dataset '${d}'; pick from ${Object.keys(DATASETS).join(", ")}`);
    Deno.exit(1);
  }
}

// ---------------------------------------------------------------------
// The API
// ---------------------------------------------------------------------

interface AbridgedFood {
  fdcId: number;
  description: string;
  dataType?: string;
}

interface FullFood {
  fdcId: number;
  description: string;
  dataType?: string;
  foodCategory?: { description?: string } | string;
  wweiaFoodCategory?: { wweiaFoodCategoryDescription?: string };
  foodNutrients?: {
    nutrient?: { id?: number; name?: string; unitName?: string };
    amount?: number;
  }[];
  foodPortions?: {
    amount?: number;
    gramWeight?: number;
    modifier?: string;
    portionDescription?: string;
    measureUnit?: { name?: string };
  }[];
}

/**
 * Stops the run rather than hammering a closed door.
 *
 * api.data.gov answers 429 for the rest of the hour once the quota is gone, so
 * retrying is just a slower way to fail. Exiting is safe because progress lives
 * in the database, not in this process: re-running resumes at the first food
 * without nutrients at the current set version.
 */
function bailOnRateLimit(res: Response): void {
  if (res.status === 429) {
    console.error(
      "\nrate limited by USDA (api.data.gov allows 1,000 requests an hour per key).",
    );
    console.error("Everything written so far is committed. Re-run to resume.");
    Deno.exit(2);
  }
}

async function usda(path: string, init?: RequestInit): Promise<Response> {
  const key = Deno.env.get("USDA_API_KEY")!;
  const sep = path.includes("?") ? "&" : "?";
  const res = await fetch(`https://api.nal.usda.gov/fdc/v1/${path}${sep}api_key=${key}`, init);
  bailOnRateLimit(res);
  return res;
}

/** Enumerates one dataset, 200 ids at a time. Cheap: this is the whole index. */
async function* enumerate(apiName: string): AsyncGenerator<AbridgedFood> {
  for (let page = 1;; page++) {
    const res = await usda(
      `foods/list?dataType=${encodeURIComponent(apiName)}&pageSize=200&pageNumber=${page}`,
    );
    if (!res.ok) {
      console.error(`  ! listing ${apiName} page ${page}: ${res.status}`);
      return;
    }
    const rows = (await res.json()) as AbridgedFood[];
    if (rows.length === 0) return;
    for (const r of rows) yield r;
    if (rows.length < 200) return;
  }
}

/**
 * Full records for up to twenty ids.
 *
 * The abridged listing above carries nutrients already, but keyed by USDA's
 * legacy nutrient *number* rather than its id. USDA_NUTRIENT_MAP is keyed by
 * id and has been in service since ingest_usda.ts; maintaining a parallel
 * number map from memory is exactly the kind of transcription that puts folate
 * in the vitamin A column. So the listing is used only to enumerate, and the
 * numbers come from the full record — which also carries portions, which the
 * abridged one does not.
 */
async function detail(ids: number[]): Promise<FullFood[]> {
  const res = await usda("foods", {
    method: "POST",
    headers: { "Content-Type": "application/json" },
    body: JSON.stringify({ fdcIds: ids, format: "full" }),
  });
  if (!res.ok) {
    console.error(`  ! detail for ${ids.length} ids: ${res.status} ${await res.text()}`);
    return [];
  }
  return (await res.json()) as FullFood[];
}

// ---------------------------------------------------------------------
// Mapping
// ---------------------------------------------------------------------

/**
 * USDA writes "Broccoli, raw" and a person writes "raw broccoli". Inverting at
 * the first comma gives the phrase people actually type, which is what the
 * resolver matches against.
 *
 * The head term on its own — "Broccoli" — is deliberately not an alias. Several
 * hundred USDA rows begin "Cheese," and every one of them would claim the bare
 * word at identical priority and identical score, so a user typing جبنة would
 * get whichever the tie-break happened to reach. A generic alias on a specific
 * food is worse than no alias: it turns a clean miss, which the graph reports
 * honestly and falls back on, into a confident wrong answer.
 */
export function inverted(description: string): string | null {
  const at = description.indexOf(",");
  if (at <= 0) return null;
  const head = description.slice(0, at).trim();
  const tail = description.slice(at + 1).replace(/,/g, " ").replace(/\s+/g, " ").trim();
  if (!head || !tail || tail.length > 40) return null;
  return `${tail} ${head}`.toLowerCase();
}

/**
 * The cooking state, read off the description.
 *
 * It matters more than it looks: boiled rice and raw rice are different rows in
 * USDA and wildly different per 100 g, and food_state is what stops the graph
 * from treating them as the same food.
 */
export function stateOf(description: string): string {
  const d = description.toLowerCase();
  if (/\braw\b/.test(d)) return "raw";
  if (/\bboiled\b/.test(d)) return "boiled";
  if (/\bfried\b/.test(d)) return "fried";
  if (/\bgrilled\b|\bbroiled\b/.test(d)) return "grilled";
  if (/\bbaked\b|\broasted\b/.test(d)) return "baked";
  if (/\bsteamed\b/.test(d)) return "steamed";
  if (/\bdried\b|\bdehydrated\b/.test(d)) return "dried";
  if (/\bcanned\b/.test(d)) return "canned";
  if (/\bcooked\b/.test(d)) return "cooked";
  return "unspecified";
}

function portionLabel(p: NonNullable<FullFood["foodPortions"]>[number]): string | null {
  if (p.portionDescription && p.portionDescription.toLowerCase() !== "quantity not specified") {
    return p.portionDescription;
  }
  const unit = p.measureUnit?.name;
  if (!unit || unit === "undetermined") return p.modifier ?? null;
  const amount = p.amount ?? 1;
  return p.modifier ? `${amount} ${unit}, ${p.modifier}` : `${amount} ${unit}`;
}

export function toCatalogFood(
  food: FullFood,
  dataset: { rank: number; confidence: number },
): CatalogFood | null {
  const description = (food.description ?? "").trim();
  if (!description) return null;

  // Nutrients. A preferred id wins its code outright: see USDA_PREFERRED_IDS.
  const raw: Record<string, number> = {};
  const fromPreferred = new Set<string>();
  for (const n of food.foodNutrients ?? []) {
    const id = n.nutrient?.id;
    if (id === undefined) continue;
    const code = USDA_NUTRIENT_MAP[id];
    if (!code || typeof n.amount !== "number") continue;
    if (fromPreferred.has(code)) continue;
    raw[code] = n.amount;
    if (USDA_PREFERRED_IDS.has(id)) fromPreferred.add(code);
  }

  const screened = screenNutrients(raw);
  if (!screened.usable) return null;

  const category = typeof food.foodCategory === "string"
    ? food.foodCategory
    : food.foodCategory?.description ??
      food.wweiaFoodCategory?.wweiaFoodCategoryDescription ?? null;

  const aliases: CatalogFood["aliases"] = [{
    alias: description,
    lang: "en",
    priority: 70,
  }];
  const flipped = inverted(description);
  if (flipped && flipped !== description.toLowerCase()) {
    aliases.push({ alias: flipped, lang: "en", priority: 65 });
  }

  const portions: CatalogFood["portions"] = [];
  for (const p of food.foodPortions ?? []) {
    const label = portionLabel(p);
    if (!label || !p.gramWeight) continue;
    portions.push({ labelEn: label, grams: p.gramWeight, basis: "measured" });
  }

  return {
    externalId: String(food.fdcId),
    externalType: "fdc_id",
    url: `https://fdc.nal.usda.gov/food-details/${food.fdcId}`,
    slug: catalogSlug("fdc", String(food.fdcId), description),
    nameEn: description,
    countryRegion: "US",
    foodState: stateOf(description),
    foodGroup: foodGroupFrom(category),
    // USDA describes composition, not diet suitability. NULL means nobody has
    // established it, which the schema is explicit is not the same as "no".
    isVegan: null,
    isVegetarian: null,
    containsGluten: null,
    allergens: [],
    sourceRank: dataset.rank,
    confidence: dataset.confidence,
    aliases,
    portions,
    nutrients: screened.kept,
  };
}

// ---------------------------------------------------------------------
// Run
// ---------------------------------------------------------------------

async function main() {
  requireEnv(
    DRY_RUN
      ? ["USDA_API_KEY"]
      : ["USDA_API_KEY", "SUPABASE_URL", "SUPABASE_SERVICE_ROLE_KEY"],
  );
  if (!DRY_RUN) await assertStorageAllowed(SOURCE_ID);

  const state = DRY_RUN
    ? { linked: new Map<string, string>(), versioned: new Set<string>() }
    : await loadDoneState(SOURCE_ID, NUTRIENT_SET_VERSION);
  if (!DRY_RUN) {
    console.log(
      `${state.linked.size} foods already linked to ${SOURCE_ID}, ` +
        `${state.versioned.size} carrying nutrients at ${NUTRIENT_SET_VERSION}\n`,
    );
  }

  let seen = 0, skipped = 0, created = 0, refreshed = 0, unusable = 0, nutrients = 0;

  for (const key of WANTED) {
    const dataset = DATASETS[key];
    console.log(`--- ${dataset.apiName} ---`);

    let pending: number[] = [];
    let buffer: CatalogFood[] = [];

    const flushDetail = async () => {
      if (pending.length === 0) return;
      const fulls = await detail(pending);
      pending = [];
      for (const f of fulls) {
        const mapped = toCatalogFood(f, dataset);
        if (!mapped) {
          unusable++;
          continue;
        }
        buffer.push(mapped);
      }
    };

    const flushWrite = async () => {
      if (buffer.length === 0) return;
      if (!DRY_RUN) {
        const r = await writeBatch(SOURCE_ID, NUTRIENT_SET_VERSION, buffer, state);
        created += r.created;
        refreshed += r.refreshed;
        nutrients += r.nutrientRows;
      } else {
        created += buffer.length;
      }
      console.log(
        `  ${dataset.apiName}: ${created} new, ${refreshed} refreshed, ` +
          `${skipped} already done, ${unusable} unusable`,
      );
      buffer = [];
    };

    for await (const row of enumerate(dataset.apiName)) {
      if (LIMIT > 0 && seen >= LIMIT) break;
      seen++;
      if (isDone(state, String(row.fdcId))) {
        skipped++;
        continue;
      }
      pending.push(row.fdcId);
      // Twenty is the documented ceiling for a /foods request.
      if (pending.length === 20) await flushDetail();
      if (buffer.length >= BATCH) await flushWrite();
    }
    await flushDetail();
    await flushWrite();
    if (LIMIT > 0 && seen >= LIMIT) break;
  }

  console.log(
    `\nsaw ${seen}, created ${created}, refreshed ${refreshed}, ` +
      `already done ${skipped}, unusable ${unusable}, nutrient rows ${nutrients}`,
  );
  if (unusable) {
    console.log(
      `${unusable} records had no energy value or failed the plausibility screen ` +
        `and were left out. A missing food shows as an estimate the user can ` +
        `correct; a wrong one shows as a number they will not question.`,
    );
  }
  if (DRY_RUN) console.log("\n(dry run: nothing written)");
}

// Only when run, never when imported: catalog_test.ts imports the mapping
// functions above, and a bare top-level call would make every test run try to
// page a live API.
//
// The catch is not decoration. This runs unattended on a schedule, and a DNS
// failure or a refused registry check should say so in one line an operator
// can act on, not bury it under a stack trace in a collapsed Actions log.
// Exit 1 for a real failure; the importers use 2 for "stopped cleanly, run
// again", which is a different thing.
if (import.meta.main) {
  try {
    await main();
  } catch (err) {
    console.error(`\n${err instanceof Error ? err.message : err}`);
    console.error("Nothing further was written. Anything already committed stays; re-run to resume.");
    Deno.exit(1);
  }
}
