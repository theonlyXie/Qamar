// Brings packaged products into the food graph from Open Food Facts.
//
// USDA is the laboratory backbone for generic foods and has never heard of
// Juhayna milk, Domty cheese or a Molto croissant. Those are what people
// actually log off a barcode in Cairo, and Open Food Facts is the only cleared
// source that carries them.
//
//   deno run --allow-net --allow-env --allow-read \
//     supabase/functions/ai-gateway/catalog_off.ts \
//     [--countries=egypt] [--limit=N] [--batch=N] [--jsonl=PATH] [--dry-run]
//
// Needs SUPABASE_URL and SUPABASE_SERVICE_ROLE_KEY. No API key: the service is
// open, and in exchange it asks for an identifying User-Agent and a modest
// request rate, both of which are honoured below.
//
// Two ways in, for two sizes of job:
//
//   --countries=egypt (default) pages the search API. Right for the Egyptian
//   market, a few thousand products, tens of minutes at the rate the service
//   asks for. --countries=world works but the search API stops paging at ten
//   thousand results, so it is a sample and not the catalogue.
//
//   --jsonl=PATH streams the full ODbL export
//   (https://static.openfoodfacts.org/data/openfoodfacts-products.jsonl.gz,
//   several million products). This is the honest answer to "all of it": one
//   download, no rate limit, no pagination ceiling. It reads the file as a
//   stream, so it does not need the memory the file size suggests.
//
// On licensing. The registry has this source at open_share_alike: the database
// is ODbL, which puts share-alike obligations on a *derived database* if one is
// ever published. Nothing here publishes anything — it fills a private graph —
// and the per-row provenance written alongside each value is what makes the
// obligation traceable if that changes. The registry row is the switch: set
// open_food_facts to 'blocked' and this script refuses to run, by design.

import {
  assertStorageAllowed,
  type CatalogFood,
  catalogSlug,
  foodGroupFrom,
  isDone,
  loadDoneState,
  OFF_NUTRIENT_SET_VERSION,
  requireEnv,
  screenNutrients,
  writeBatch,
} from "./catalog.ts";

const SOURCE_ID = "open_food_facts";
const UA = "Qamar/0.6 (https://dr-qamar.com; contact: support@dr-qamar.com)";

/**
 * Below the 50 the authored Egyptian seed carries and below every USDA
 * dataset, because this is crowd-sourced label transcription rather than
 * laboratory analysis. It is the right source for a barcode and the wrong one
 * for a tie-break against a measured food.
 */
const SOURCE_RANK = 20;
const CONFIDENCE = 0.5;

const args = Deno.args;
const flag = (name: string): string | undefined =>
  args.find((a) => a.startsWith(`--${name}=`))?.split("=").slice(1).join("=");

const DRY_RUN = args.includes("--dry-run");
const LIMIT = Number(flag("limit") ?? 0);
const BATCH = Math.max(1, Number(flag("batch") ?? 100));
const COUNTRIES = (flag("countries") ?? "egypt").toLowerCase();
const JSONL = flag("jsonl");

// ---------------------------------------------------------------------
// Mapping
// ---------------------------------------------------------------------

export interface OffProduct {
  code?: string;
  product_name?: string;
  product_name_en?: string;
  product_name_ar?: string;
  brands?: string;
  quantity?: string;
  serving_size?: string;
  serving_quantity?: number | string;
  product_quantity?: number | string;
  categories_tags?: string[];
  allergens_tags?: string[];
  traces_tags?: string[];
  labels_tags?: string[];
  countries_tags?: string[];
  ingredients_analysis_tags?: string[];
  nutriments?: Record<string, number | string>;
}

/**
 * Open Food Facts nutriment keys to Qamar codes, with the factor that converts
 * the one to the other.
 *
 * The factor is the whole point of this table. Every `_100g` field except
 * energy is stored in **grams**, minerals and vitamins included, so calcium
 * arrives as 0.12 and has to become 120 mg. Reading those fields at face value
 * produces a graph where every micronutrient is a thousand or a million times
 * too small — numbers small enough that nothing looks broken and the
 * micronutrient gap report quietly tells every user they are deficient in
 * everything.
 */
const OFF_NUTRIENTS: Record<string, { code: string; factor: number }> = {
  "energy-kcal_100g": { code: "energy_kcal", factor: 1 },
  "proteins_100g": { code: "protein_g", factor: 1 },
  "carbohydrates_100g": { code: "carbs_g", factor: 1 },
  "fat_100g": { code: "fat_g", factor: 1 },
  "fiber_100g": { code: "fiber_g", factor: 1 },
  "sugars_100g": { code: "sugars_g", factor: 1 },
  "saturated-fat_100g": { code: "sat_fat_g", factor: 1 },
  "water_100g": { code: "water_g", factor: 1 },
  "sodium_100g": { code: "sodium_mg", factor: 1000 },
  "potassium_100g": { code: "potassium_mg", factor: 1000 },
  "calcium_100g": { code: "calcium_mg", factor: 1000 },
  "iron_100g": { code: "iron_mg", factor: 1000 },
  "zinc_100g": { code: "zinc_mg", factor: 1000 },
  "magnesium_100g": { code: "magnesium_mg", factor: 1000 },
  "vitamin-c_100g": { code: "vitamin_c_mg", factor: 1000 },
  "vitamin-e_100g": { code: "vitamin_e_mg", factor: 1000 },
  "vitamin-b1_100g": { code: "thiamin_mg", factor: 1000 },
  "vitamin-b2_100g": { code: "riboflavin_mg", factor: 1000 },
  "vitamin-pp_100g": { code: "niacin_mg", factor: 1000 },
  "vitamin-b6_100g": { code: "vitamin_b6_mg", factor: 1000 },
  "vitamin-a_100g": { code: "vitamin_a_ug", factor: 1_000_000 },
  "vitamin-d_100g": { code: "vitamin_d_ug", factor: 1_000_000 },
  "vitamin-b12_100g": { code: "vitamin_b12_ug", factor: 1_000_000 },
  "folates_100g": { code: "folate_ug", factor: 1_000_000 },
  "iodine_100g": { code: "iodine_ug", factor: 1_000_000 },
  "selenium_100g": { code: "selenium_ug", factor: 1_000_000 },
};

/** OFF allergen tags to the vocabulary the Egyptian seed already uses. */
const ALLERGEN_TAGS: Record<string, string> = {
  "en:gluten": "gluten",
  "en:milk": "dairy",
  "en:eggs": "egg",
  "en:fish": "fish",
  "en:peanuts": "peanut",
  "en:nuts": "nuts",
  "en:sesame-seeds": "sesame",
  "en:soybeans": "soy",
  "en:crustaceans": "shellfish",
  "en:molluscs": "shellfish",
  "en:mustard": "mustard",
  "en:celery": "celery",
  "en:lupin": "lupin",
  "en:sulphur-dioxide-and-sulphites": "sulphites",
};

function num(v: unknown): number | undefined {
  if (typeof v === "number") return Number.isFinite(v) ? v : undefined;
  if (typeof v === "string" && v.trim() !== "") {
    const n = Number(v);
    return Number.isFinite(n) ? n : undefined;
  }
  return undefined;
}

export function offNutrients(nutriments: Record<string, number | string>): Record<string, number> {
  const out: Record<string, number> = {};
  for (const [key, { code, factor }] of Object.entries(OFF_NUTRIENTS)) {
    const v = num(nutriments[key]);
    if (v === undefined) continue;
    out[code] = v * factor;
  }

  // Labels in Egypt and the EU carry salt far more often than sodium, and
  // 2.5 g of salt is 1 g of sodium. Only a fallback: a reported sodium wins.
  if (out.sodium_mg === undefined) {
    const salt = num(nutriments["salt_100g"]);
    if (salt !== undefined) out.sodium_mg = (salt / 2.5) * 1000;
  }

  // Same shape for energy: a kilojoule figure is better than nothing, and
  // 4.184 kJ is one kcal. Anything that arrives already in kcal is left alone.
  if (out.energy_kcal === undefined) {
    const kj = num(nutriments["energy-kj_100g"]) ?? num(nutriments["energy_100g"]);
    if (kj !== undefined) out.energy_kcal = kj / 4.184;
  }

  return out;
}

/**
 * Three-state, and the third state is the point.
 *
 * Open Food Facts says vegan, non-vegan, or that it could not tell from the
 * ingredient list. The schema is explicit that NULL means unestablished and
 * never "no", so an unknown must not collapse to false — a vegetarian user
 * filtering on is_vegetarian = false would have every uncertain product hidden
 * from them as if it contained meat.
 */
export function dietFlag(tags: string[] | undefined, kind: "vegan" | "vegetarian"): boolean | null {
  if (!tags) return null;
  if (tags.includes(`en:${kind}`)) return true;
  if (tags.includes(`en:non-${kind}`)) return false;
  return null;
}

export function toCatalogFood(p: OffProduct): CatalogFood | null {
  const code = (p.code ?? "").trim();
  if (!code || !/^[0-9]{6,20}$/.test(code)) return null;

  const nameEn = (p.product_name_en || p.product_name || "").trim();
  const nameAr = (p.product_name_ar || "").trim() || null;
  if (!nameEn && !nameAr) return null;

  const screened = screenNutrients(offNutrients(p.nutriments ?? {}));
  if (!screened.usable) return null;

  const brand = (p.brands ?? "").split(",")[0].trim() || null;
  const display = nameEn || nameAr!;

  const aliases: CatalogFood["aliases"] = [];
  if (nameEn) aliases.push({ alias: nameEn, lang: "en", priority: 70 });
  if (nameEn && brand) aliases.push({ alias: `${brand} ${nameEn}`, lang: "en", priority: 65 });
  if (nameAr) aliases.push({ alias: nameAr, lang: "ar", priority: 70 });

  const allergens = [
    ...new Set(
      (p.allergens_tags ?? [])
        .map((t) => ALLERGEN_TAGS[t])
        .filter((a): a is string => Boolean(a)),
    ),
  ];

  const glutenFree = (p.labels_tags ?? []).includes("en:no-gluten");
  const containsGluten = allergens.includes("gluten") ? true : glutenFree ? false : null;

  // Most specific category last; OFF orders the chain parent-first. Walking
  // back up the chain matters: "en:sweetened-beverages" may map to nothing
  // while its parent "en:beverages" is unambiguous, and a parent group is
  // worth more than a null.
  const categories = (p.categories_tags ?? []).filter((t) => t.startsWith("en:"));
  let foodGroup: string | null = null;
  for (let i = categories.length - 1; i >= 0 && foodGroup === null; i--) {
    foodGroup = foodGroupFrom(categories[i].slice(3));
  }

  const portions: CatalogFood["portions"] = [];
  const serving = num(p.serving_quantity);
  if (serving && serving > 0) {
    portions.push({
      labelEn: (p.serving_size ?? "").trim() || "1 serving",
      grams: serving,
      basis: "vendor",
    });
  }
  const pack = num(p.product_quantity);
  if (pack && pack > 0 && pack <= 5000) {
    portions.push({
      labelEn: (p.quantity ?? "").trim() ? `1 pack (${p.quantity!.trim()})` : "1 pack",
      grams: pack,
      basis: "vendor",
    });
  }

  return {
    externalId: code,
    externalType: "gtin",
    url: `https://world.openfoodfacts.org/product/${code}`,
    slug: catalogSlug("off", code, display),
    nameEn: display,
    nameAr,
    brand,
    countryRegion: (p.countries_tags ?? []).includes("en:egypt") ? "EG" : null,
    // A sealed package is not raw, cooked or prepared in any sense the column
    // means. Saying so is more useful than picking one.
    foodState: "unspecified",
    foodGroup,
    isVegan: dietFlag(p.ingredients_analysis_tags, "vegan"),
    isVegetarian: dietFlag(p.ingredients_analysis_tags, "vegetarian"),
    containsGluten,
    allergens,
    sourceRank: SOURCE_RANK,
    confidence: CONFIDENCE,
    aliases,
    portions,
    nutrients: screened.kept,
  };
}

// ---------------------------------------------------------------------
// The two ways in
// ---------------------------------------------------------------------

const FIELDS = [
  "code",
  "product_name",
  "product_name_en",
  "product_name_ar",
  "brands",
  "quantity",
  "serving_size",
  "serving_quantity",
  "product_quantity",
  "categories_tags",
  "allergens_tags",
  "labels_tags",
  "countries_tags",
  "ingredients_analysis_tags",
  "nutriments",
].join(",");

/**
 * Pages the search API at the rate the service asks for.
 *
 * Six and a half seconds between requests is under the ten-per-minute the
 * documentation requests for search. It is slower than it needs to be for a
 * few thousand Egyptian products and it is the reason this is still welcome to
 * run next month.
 */
async function* fromApi(): AsyncGenerator<OffProduct> {
  const filter = COUNTRIES === "world" || COUNTRIES === ""
    ? ""
    : `&countries_tags_en=${encodeURIComponent(COUNTRIES)}`;

  for (let page = 1;; page++) {
    const url = `https://world.openfoodfacts.org/api/v2/search?page=${page}` +
      `&page_size=100&fields=${FIELDS}${filter}`;
    const res = await fetch(url, { headers: { "User-Agent": UA } });
    if (res.status === 429) {
      console.error("rate limited by Open Food Facts; stopping so the run can resume");
      return;
    }
    if (!res.ok) {
      console.error(`  ! search page ${page}: ${res.status}`);
      return;
    }
    const json = await res.json() as { products?: OffProduct[]; count?: number };
    const products = json.products ?? [];
    if (page === 1 && json.count !== undefined) {
      console.log(`${json.count} products match countries=${COUNTRIES}`);
    }
    if (products.length === 0) return;
    for (const p of products) yield p;
    if (products.length < 100) return;
    // The search API stops serving results past ten thousand.
    if (page * 100 >= 10_000) {
      console.log(
        "reached the search API's 10,000-result ceiling. " +
          "Use --jsonl with the full ODbL export to go past it.",
      );
      return;
    }
    await new Promise((r) => setTimeout(r, 6_500));
  }
}

/** Streams the ODbL export a line at a time, gzipped or not. */
async function* fromJsonl(path: string): AsyncGenerator<OffProduct> {
  const file = await Deno.open(path, { read: true });
  const text: ReadableStream<string> = path.endsWith(".gz")
    ? file.readable
      .pipeThrough(new DecompressionStream("gzip"))
      .pipeThrough(new TextDecoderStream())
    : file.readable.pipeThrough(new TextDecoderStream());

  const reader = text.getReader();
  let carry = "";
  while (true) {
    const { done, value } = await reader.read();
    if (done) break;
    carry += value;
    const lines = carry.split("\n");
    carry = lines.pop() ?? "";
    for (const line of lines) {
      if (!line.trim()) continue;
      try {
        yield JSON.parse(line) as OffProduct;
      } catch {
        // One malformed line in a multi-million-line export is not a reason to
        // throw away the run.
      }
    }
  }
  if (carry.trim()) {
    try {
      yield JSON.parse(carry) as OffProduct;
    } catch { /* same */ }
  }
}

// ---------------------------------------------------------------------
// Run
// ---------------------------------------------------------------------

async function main() {
  requireEnv(DRY_RUN ? [] : ["SUPABASE_URL", "SUPABASE_SERVICE_ROLE_KEY"]);
  if (!DRY_RUN) await assertStorageAllowed(SOURCE_ID);

  const state = DRY_RUN
    ? { linked: new Map<string, string>(), versioned: new Set<string>() }
    : await loadDoneState(SOURCE_ID, OFF_NUTRIENT_SET_VERSION);
  if (!DRY_RUN) {
    console.log(
      `${state.linked.size} products already linked, ` +
        `${state.versioned.size} carrying nutrients at ${OFF_NUTRIENT_SET_VERSION}\n`,
    );
  }

  const source = JSONL ? fromJsonl(JSONL) : fromApi();
  console.log(JSONL ? `reading ${JSONL}` : `paging the search API (countries=${COUNTRIES})`);

  let seen = 0, skipped = 0, created = 0, refreshed = 0, unusable = 0, nutrients = 0;
  let buffer: CatalogFood[] = [];

  const flush = async () => {
    if (buffer.length === 0) return;
    if (!DRY_RUN) {
      const r = await writeBatch(SOURCE_ID, OFF_NUTRIENT_SET_VERSION, buffer, state);
      created += r.created;
      refreshed += r.refreshed;
      nutrients += r.nutrientRows;
    } else {
      created += buffer.length;
    }
    buffer = [];
    console.log(`  ${created} new, ${skipped} already done, ${unusable} unusable, seen ${seen}`);
  };

  for await (const product of source) {
    if (LIMIT > 0 && seen >= LIMIT) break;
    seen++;
    const code = (product.code ?? "").trim();
    if (code && isDone(state, code)) {
      skipped++;
      continue;
    }
    const mapped = toCatalogFood(product);
    if (!mapped) {
      unusable++;
      continue;
    }
    buffer.push(mapped);
    if (buffer.length >= BATCH) await flush();
  }
  await flush();

  console.log(
    `\nsaw ${seen}, created ${created}, refreshed ${refreshed}, ` +
      `already done ${skipped}, unusable ${unusable}, nutrient rows ${nutrients}`,
  );
  if (unusable) {
    console.log(
      `${unusable} products were left out: no barcode, no name, no energy value, ` +
        `or a figure that failed the plausibility screen. Open Food Facts is ` +
        `crowd-sourced and a confident wrong number is worse than a gap.`,
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
