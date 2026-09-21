// The machinery both catalogue importers stand on.
//
// ingest_usda.ts fills nutrient numbers onto the 131 foods the Egyptian seed
// authored by hand. This module is for the other direction: bringing whole
// external catalogues *into* the graph as new foods, so the resolver answers
// locally instead of falling through to a paid lookup on every phrase the seed
// never anticipated.
//
// Three rules are enforced here rather than in each importer, because they are
// the rules that get skipped when someone is in a hurry:
//
//   1. Nothing is written for a source the registry has not cleared. Same gate
//      ingest_usda.ts uses. There is no path around it, and "just this once"
//      is how an unlicensed dependency becomes a production dependency.
//
//   2. An imported food never overwrites an authored one. Slugs carry their
//      external id, so a catalogue row cannot collide with `baladi_bread`, and
//      a food already linked to an authored row is refreshed at the nutrient
//      level only — never given new aliases, portions or names. The Egyptian
//      layer is the asset; a bulk importer is not allowed to edit it.
//
//   3. An implausible number is dropped, not stored. Crowd-sourced data has
//      sodium typed into a grams field and kilojoules typed into a kcal field.
//      Both produce a confident, wrong figure, which is worse than a missing
//      one because a missing one shows as an estimate the user can correct.

// ---------------------------------------------------------------------
// Environment, read lazily
// ---------------------------------------------------------------------
// Lazily on purpose: the pure helpers below are unit-tested, and a module that
// exits at import time cannot be imported by a test.

function env(name: string): string {
  const v = Deno.env.get(name);
  if (!v) throw new Error(`${name} is not set`);
  return v;
}

/** Fails early, naming every missing variable rather than the first one. */
export function requireEnv(names: string[]): void {
  const missing = names.filter((n) => !Deno.env.get(n));
  if (missing.length) {
    console.error(`missing environment: ${missing.join(", ")}`);
    Deno.exit(1);
  }
}

export async function db(path: string, init: RequestInit = {}): Promise<Response> {
  const key = env("SUPABASE_SERVICE_ROLE_KEY");
  return await fetch(`${env("SUPABASE_URL")}/rest/v1/${path}`, {
    ...init,
    headers: {
      "Content-Type": "application/json",
      apikey: key,
      Authorization: `Bearer ${key}`,
      ...(init.headers ?? {}),
    },
  });
}

/**
 * Refuses to run if the registry does not permit storing this source.
 *
 * Deliberately duplicated in spirit from ingest_usda.ts: every ingestion path
 * asks the same question of the same table, and the first script that skips the
 * question is the one that causes the licensing incident.
 */
export async function assertStorageAllowed(sourceId: string): Promise<void> {
  const res = await db(
    `source_registry?source_id=eq.${sourceId}&select=status,storage_rights,license_class,ai_advice_rights`,
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
  console.log(
    `registry: ${sourceId} ok (${s.license_class}, ${s.storage_rights}, ` +
      `advice rights ${s.ai_advice_rights === true ? "yes" : "not established"})`,
  );
}

// ---------------------------------------------------------------------
// The nutrient set
// ---------------------------------------------------------------------

/**
 * USDA nutrient IDs to Qamar nutrient codes. Anything not listed is ignored
 * rather than guessed at.
 *
 * Lives here, not in ingest_usda.ts where it was written, because three
 * importers now read it. Two of them writing different nutrient sets under the
 * same nutrient_definition_version is precisely the bug that version string
 * exists to prevent, and a second copy of this table is how that would have
 * happened.
 */
export const USDA_NUTRIENT_MAP: Record<number, string> = {
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
  1190: "folate_ug", // Folate, DFE — see USDA_PREFERRED_IDS
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
export const USDA_PREFERRED_IDS = new Set([1190]);

/**
 * Which set of nutrients the USDA importers know how to fetch.
 *
 * Bump this whenever USDA_NUTRIENT_MAP gains a code. It is stored on every row
 * they write, and it is how a run decides a food is done.
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
export const NUTRIENT_SET_VERSION = "fdc-2026-08";

/**
 * Open Food Facts carries a different, smaller set, so it gets its own marker
 * and its own bump. Sharing the USDA version string would have meant that
 * widening the USDA map marked every Open Food Facts product as needing a
 * re-fetch it cannot benefit from, and — worse in the other direction — that a
 * product loaded from OFF counted as done for a nutrient set it never had.
 */
export const OFF_NUTRIENT_SET_VERSION = "off-2026-09";

/**
 * The unit each code is stored in. Open Food Facts reports everything except
 * energy in grams, so this is what the conversion is driven from — and getting
 * it wrong turns 120 mg of calcium into 0.12 mg without anything looking odd.
 */
export const NUTRIENT_UNIT: Record<string, "kcal" | "g" | "mg" | "ug"> = {
  energy_kcal: "kcal",
  protein_g: "g",
  carbs_g: "g",
  fat_g: "g",
  fiber_g: "g",
  sugars_g: "g",
  sat_fat_g: "g",
  water_g: "g",
  sodium_mg: "mg",
  potassium_mg: "mg",
  calcium_mg: "mg",
  iron_mg: "mg",
  zinc_mg: "mg",
  magnesium_mg: "mg",
  vitamin_c_mg: "mg",
  vitamin_e_mg: "mg",
  thiamin_mg: "mg",
  riboflavin_mg: "mg",
  niacin_mg: "mg",
  vitamin_b6_mg: "mg",
  vitamin_d_ug: "ug",
  vitamin_b12_ug: "ug",
  folate_ug: "ug",
  vitamin_a_ug: "ug",
  iodine_ug: "ug",
  selenium_ug: "ug",
};

/**
 * Per-100 g ceilings, above which a value is a data-entry error rather than a
 * remarkable food. Set generously against the real record holders — pure salt
 * is 39,300 mg sodium, brazil nuts reach 1,900 µg selenium, cod liver oil
 * 30,000 µg vitamin A — so a legitimate outlier survives and an order-of-
 * magnitude unit slip does not.
 */
export const NUTRIENT_MAX: Record<string, number> = {
  energy_kcal: 950, // pure fat is ~900
  protein_g: 100,
  carbs_g: 100,
  fat_g: 100,
  fiber_g: 100,
  sugars_g: 100,
  sat_fat_g: 100,
  water_g: 100,
  sodium_mg: 40_000,
  potassium_mg: 20_000,
  calcium_mg: 30_000,
  iron_mg: 1_000,
  zinc_mg: 500,
  magnesium_mg: 2_000,
  vitamin_c_mg: 5_000,
  vitamin_e_mg: 1_000,
  thiamin_mg: 500,
  riboflavin_mg: 500,
  niacin_mg: 1_000,
  vitamin_b6_mg: 500,
  vitamin_d_ug: 2_000,
  vitamin_b12_ug: 1_000,
  folate_ug: 5_000,
  vitamin_a_ug: 100_000,
  iodine_ug: 100_000,
  selenium_ug: 10_000,
};

// ---------------------------------------------------------------------
// Plausibility
// ---------------------------------------------------------------------

export interface Plausibility {
  /** Values that survived, rounded to the column's scale. */
  kept: Record<string, number>;
  /** Codes dropped, with why — reported so a bad source is visible, not silent. */
  dropped: { code: string; amount: number; why: string }[];
  /** False when the whole food is unusable. `kept` is meaningless then. */
  usable: boolean;
  reason?: string;
}

/**
 * Filters one food's per-100 g values.
 *
 * A single bad nutrient drops that nutrient. A bad energy figure drops the
 * whole food, because energy is the number every screen in the app is built on
 * and there is nothing to show without it.
 *
 * The Atwater band is the one check that earns its keep on crowd-sourced data.
 * Kilojoules typed into the kcal field is the single most common Open Food
 * Facts error and it is exactly 4.184x high, so a food whose stated energy is
 * far above what its own macros can produce is rejected rather than stored as
 * a confident number that is four times wrong. The band is wide because fibre,
 * polyols and rounding all move stated energy legitimately, and it is only
 * applied once the macros imply enough energy for the ratio to mean anything.
 */
export function screenNutrients(raw: Record<string, number>): Plausibility {
  const kept: Record<string, number> = {};
  const dropped: Plausibility["dropped"] = [];

  for (const [code, amount] of Object.entries(raw)) {
    if (!(code in NUTRIENT_UNIT)) continue; // not a code we store
    if (!Number.isFinite(amount)) {
      dropped.push({ code, amount, why: "not a number" });
      continue;
    }
    if (amount < 0) {
      dropped.push({ code, amount, why: "negative" });
      continue;
    }
    const max = NUTRIENT_MAX[code];
    if (max !== undefined && amount > max) {
      dropped.push({ code, amount, why: `above ${max} per 100 g` });
      continue;
    }
    kept[code] = Math.round(amount * 10_000) / 10_000;
  }

  const kcal = kept.energy_kcal;
  if (kcal === undefined) {
    return { kept, dropped, usable: false, reason: "no energy value" };
  }

  const macros = (kept.protein_g ?? 0) + (kept.carbs_g ?? 0) + (kept.fat_g ?? 0);
  if (macros > 105) {
    return { kept, dropped, usable: false, reason: `macros sum to ${macros.toFixed(1)} g` };
  }

  const atwater = 4 * (kept.protein_g ?? 0) + 4 * (kept.carbs_g ?? 0) + 9 * (kept.fat_g ?? 0);
  if (atwater >= 50 && (kcal > atwater * 1.9 || kcal < atwater * 0.45)) {
    return {
      kept,
      dropped,
      usable: false,
      reason: `energy ${kcal} kcal does not match macros (~${Math.round(atwater)} kcal)`,
    };
  }

  return { kept, dropped, usable: true };
}

// ---------------------------------------------------------------------
// Identity
// ---------------------------------------------------------------------

/** ASCII slug body. Non-Latin names collapse to empty, which the caller handles. */
export function slugify(name: string): string {
  return name
    .toLowerCase()
    .normalize("NFKD")
    .replace(/[̀-ͯ]/g, "")
    .replace(/[^a-z0-9]+/g, "_")
    .replace(/^_+|_+$/g, "")
    .slice(0, 48)
    .replace(/_+$/g, "");
}

/**
 * A slug that cannot collide with an authored one, ever.
 *
 * The external id is part of the slug rather than a fallback on collision. That
 * costs some prettiness and buys three things: the importer needs no read of
 * the existing slug table, a re-run is byte-identical, and there is no path by
 * which "Oats" from a catalogue lands on the hand-authored `oats` row and
 * quietly inherits its Egyptian aliases.
 */
export function catalogSlug(tag: string, externalId: string, name: string): string {
  const base = slugify(name);
  return base ? `${base}__${tag}${externalId}` : `${tag}_${externalId}`;
}

/**
 * A source's own category, mapped onto the ten groups the Egyptian seed uses.
 *
 * The seed established a controlled vocabulary — vegetable, dish, protein,
 * fruit, grain, sweet, fat, legume, drink, dairy — and writing USDA's
 * "Sausages and Luncheon Meats" or one of Open Food Facts' several thousand
 * category tags straight into the column would end that, quietly, on the first
 * import. The next person to group by food_group would get ten sensible rows
 * and a long tail of noise.
 *
 * First rule wins, so the order is the ruling. Fat is tested before dairy so
 * butter lands where the seed puts it; fruit before drink so "Fruits and Fruit
 * Juices" is fruit while "Beverages" is a drink; dairy before protein so "Dairy
 * and Egg Products" is not claimed by the word egg.
 *
 * Anything with no confident rule returns NULL rather than a guess. Snacks and
 * spices genuinely do not belong to one of these ten, and the source's own
 * category is always recoverable from the URL in food_source_links.
 */
const GROUP_RULES: [RegExp, string][] = [
  [/ice.?creams?|sorbets?|gelato/, "sweet"],
  [/\b(fats?|oils?|margarines?|butters?|ghee|shortening)\b/, "fat"],
  [/\b(dairy|milks?|cheeses?|yogh?urts?|creams?)\b/, "dairy"],
  [/\b(legumes?|lentils?|chickpeas?|fava|pulses?|beans?)\b/, "legume"],
  [/\b(cereals?|grains?|pasta|breads?|rice|noodles?|flours?|baked)\b/, "grain"],
  [/\b(fruits?|berry|berries|melons?)\b/, "fruit"],
  [/\b(vegetables?|salads?|mushrooms?|potato|potatoes|tubers?)\b/, "vegetable"],
  [
    /\b(meats?|poultry|beef|pork|lambs?|veal|game|chicken|turkey|fish|finfish|shellfish|seafood|eggs?|sausages?|nuts?|seeds?)\b/,
    "protein",
  ],
  [
    /\b(sweets?|candy|candies|chocolates?|desserts?|sugars?|confectionery|jams?|honey|biscuits?|cookies?|cakes?|pastry|pastries)\b/,
    "sweet",
  ],
  [/\b(beverages?|drinks?|juices?|sodas?|waters?|teas?|coffees?)\b/, "drink"],
  [
    /\b(meals?|dishes|entrees?|soups?|pizzas?|sandwich|sandwiches|prepared|fast foods?|restaurant)\b/,
    "dish",
  ],
];

export function foodGroupFrom(category: string | null | undefined): string | null {
  if (!category) return null;
  const text = category.toLowerCase().replace(/[-_]+/g, " ");
  for (const [re, group] of GROUP_RULES) if (re.test(text)) return group;
  return null;
}

// ---------------------------------------------------------------------
// The normalized shape both importers produce
// ---------------------------------------------------------------------

export interface CatalogAlias {
  alias: string;
  lang: "en" | "ar" | "eg" | "translit";
  priority: number;
}

export interface CatalogPortion {
  labelEn: string;
  labelAr?: string | null;
  grams: number;
  basis: "measured" | "density" | "yield" | "vendor" | "estimated";
}

export interface CatalogFood {
  externalId: string;
  externalType: "fdc_id" | "gtin" | "vendor_id" | "fct_entry" | "url" | "other";
  url: string | null;

  slug: string;
  nameEn: string;
  nameAr?: string | null;
  brand?: string | null;
  countryRegion?: string | null;
  foodState: string;
  foodGroup?: string | null;

  isVegan?: boolean | null;
  isVegetarian?: boolean | null;
  containsGluten?: boolean | null;
  allergens: string[];

  sourceRank: number;
  confidence: number;

  aliases: CatalogAlias[];
  portions: CatalogPortion[];
  /** Per 100 g, already in Qamar units. Screened before writing. */
  nutrients: Record<string, number>;
}

// ---------------------------------------------------------------------
// Resume state
// ---------------------------------------------------------------------

export interface DoneState {
  /** external_id -> qamar_food_id, for every food this source has already linked. */
  linked: Map<string, string>;
  /** qamar_food_ids carrying nutrients at the current set version. */
  versioned: Set<string>;
}

/** Reads a page at a time; PostgREST caps a single response well below a catalogue. */
async function selectAll<T>(path: string, pageSize = 1000): Promise<T[]> {
  const out: T[] = [];
  for (let offset = 0;; offset += pageSize) {
    const res = await db(`${path}&limit=${pageSize}&offset=${offset}`);
    if (!res.ok) throw new Error(`select ${path}: ${res.status} ${await res.text()}`);
    const rows = (await res.json()) as T[];
    out.push(...rows);
    if (rows.length < pageSize) return out;
  }
}

/**
 * What a previous run already finished.
 *
 * "Finished" is link *and* nutrients at the current set version, not link
 * alone. A run killed between writing the food and writing its nutrients
 * leaves a row that looks imported and carries no numbers; defining done by
 * the link alone would make that state permanent, which is the same bug the
 * knowledge-base ingest had.
 */
export async function loadDoneState(
  sourceId: string,
  setVersion: string,
): Promise<DoneState> {
  const links = await selectAll<{ external_id: string; qamar_food_id: string }>(
    `food_source_links?source_id=eq.${sourceId}&select=external_id,qamar_food_id&order=external_id`,
  );
  const linked = new Map(links.map((l) => [l.external_id, l.qamar_food_id]));

  const rows = await selectAll<{ qamar_food_id: string }>(
    `food_nutrients?nutrient_definition_version=eq.${setVersion}` +
      `&select=qamar_food_id&order=qamar_food_id`,
  );
  return { linked, versioned: new Set(rows.map((r) => r.qamar_food_id)) };
}

export function isDone(state: DoneState, externalId: string): boolean {
  const id = state.linked.get(externalId);
  return id !== undefined && state.versioned.has(id);
}

// ---------------------------------------------------------------------
// Writing
// ---------------------------------------------------------------------

/** Last write wins on a duplicate key, which is what an upsert means anyway. */
function dedupe<T>(rows: T[], key: (r: T) => string): T[] {
  const seen = new Map<string, T>();
  for (const r of rows) seen.set(key(r), r);
  return [...seen.values()];
}

async function post(
  path: string,
  rows: unknown[],
  resolution: "merge-duplicates" | "ignore-duplicates",
  label: string,
): Promise<void> {
  if (rows.length === 0) return;
  const res = await db(path, {
    method: "POST",
    headers: { Prefer: `resolution=${resolution}` },
    body: JSON.stringify(rows),
  });
  if (!res.ok) console.error(`  ! ${label}: ${res.status} ${await res.text()}`);
}

export interface FoodRow {
  slug: string;
  name_en: string;
  name_ar: string | null;
  brand: string | null;
  country_region: string | null;
  food_state: string;
  food_group: string | null;
  is_vegan: boolean | null;
  is_vegetarian: boolean | null;
  contains_gluten: boolean | null;
  allergens: string[];
  is_recipe: boolean;
  source_rank: number;
  confidence: number;
  human_reviewed: boolean;
}

export interface ChildRows {
  links: Record<string, unknown>[];
  aliases: Record<string, unknown>[];
  portions: Record<string, unknown>[];
  nutrients: Record<string, unknown>[];
}

export function foodRows(fresh: CatalogFood[]): FoodRow[] {
  return dedupe(
    fresh.map((f) => ({
      slug: f.slug,
      name_en: f.nameEn,
      name_ar: f.nameAr ?? null,
      brand: f.brand ?? null,
      country_region: f.countryRegion ?? null,
      food_state: f.foodState,
      food_group: f.foodGroup ?? null,
      is_vegan: f.isVegan ?? null,
      is_vegetarian: f.isVegetarian ?? null,
      contains_gluten: f.containsGluten ?? null,
      allergens: f.allergens,
      is_recipe: false,
      source_rank: f.sourceRank,
      confidence: f.confidence,
      human_reviewed: false,
    })),
    (r) => r.slug,
  );
}

/**
 * Everything that hangs off a food, for one batch.
 *
 * `createdHere` is the line between the two kinds of row, and it is the most
 * important thing in this file. A food this run created is ours: it gets names
 * and portions. A food that was already linked is not — it is an authored
 * Egyptian row that ingest_usda.ts mapped to an fdcId — and it gets nutrient
 * values and nothing else. Letting a bulk importer append "Beans, fava,
 * mature seeds, cooked" to the aliases of فول مدمس, and a USDA cup measure to
 * its portions, is how the authored layer stops being the asset it is.
 *
 * Every list is de-duplicated on the key its table is unique over. For the two
 * upserts that merge rather than ignore, that is not tidiness: Postgres raises
 * "ON CONFLICT DO UPDATE command cannot affect row a second time" when one
 * statement carries the same key twice, which would fail the whole batch.
 */
export function childRows(
  sourceId: string,
  setVersion: string,
  batch: CatalogFood[],
  idOf: (f: CatalogFood) => string | undefined,
  createdHere: ReadonlySet<string>,
): ChildRows {
  const resolved = batch.filter((f) => idOf(f) !== undefined);
  const ours = resolved.filter((f) => createdHere.has(f.externalId));

  const links = dedupe(
    resolved.map((f) => ({
      qamar_food_id: idOf(f)!,
      source_id: sourceId,
      external_id: f.externalId,
      external_type: f.externalType,
      url: f.url,
      field_provenance: Object.fromEntries(Object.keys(f.nutrients).map((c) => [c, sourceId])),
    })),
    (r) => `${r.qamar_food_id}|${r.external_id}`,
  );

  const aliases = dedupe(
    ours.flatMap((f) =>
      f.aliases
        .map((a) => ({ ...a, alias: a.alias.trim() }))
        .filter((a) => a.alias.length >= 3)
        .map((a) => ({
          qamar_food_id: idOf(f)!,
          alias: a.alias,
          lang: a.lang,
          priority: a.priority,
        }))
    ),
    (r) => `${r.qamar_food_id}|${r.alias.toLowerCase()}|${r.lang}`,
  );

  const portions = dedupe(
    ours.flatMap((f) =>
      f.portions
        .filter((p) => p.grams > 0 && p.grams < 10_000 && p.labelEn.trim().length > 0)
        .slice(0, 12)
        .map((p, i) => ({
          qamar_food_id: idOf(f)!,
          label_en: p.labelEn.trim().slice(0, 120),
          label_ar: p.labelAr ?? null,
          grams: Math.round(p.grams * 100) / 100,
          is_household: true,
          // Exactly one, and only on a food this run created. The partial
          // unique index on (food) where is_default is not covered by the
          // on_conflict target used for portions, so a second default would
          // fail the whole batch rather than skip one row.
          is_default: i === 0,
          basis: p.basis,
          source_id: sourceId,
          confidence: 0.6,
        }))
    ),
    (r) => `${r.qamar_food_id}|${r.label_en.toLowerCase()}`,
  );

  const nutrients = dedupe(
    resolved.flatMap((f) =>
      Object.entries(f.nutrients).map(([code, amount]) => ({
        qamar_food_id: idOf(f)!,
        nutrient_code: code,
        amount,
        per_basis: "per_100g",
        source_id: sourceId,
        nutrient_definition_version: setVersion,
        confidence: f.confidence,
      }))
    ),
    (r) => `${r.qamar_food_id}|${r.nutrient_code}|${r.per_basis}`,
  );

  return { links, aliases, portions, nutrients };
}

export interface WriteResult {
  created: number;
  refreshed: number;
  nutrientRows: number;
}

/**
 * Writes one batch.
 *
 * Order matters. The source link goes in immediately after the food, before
 * aliases and portions, so that a run killed mid-batch leaves a food the next
 * run can recognise and finish rather than a nameless orphan it duplicates.
 */
export async function writeBatch(
  sourceId: string,
  setVersion: string,
  batch: CatalogFood[],
  state: DoneState,
): Promise<WriteResult> {
  const fresh = batch.filter((f) => !state.linked.has(f.externalId));
  const known = batch.length - fresh.length;

  if (fresh.length) {
    // ignore-duplicates, never merge: an existing row is either a previous
    // run's or something authored, and neither is ours to rewrite.
    await post("foods?on_conflict=slug", foodRows(fresh), "ignore-duplicates", "foods");

    // Read the ids back rather than trusting the insert's representation:
    // ignore-duplicates returns only the rows it actually inserted, and a
    // resumed run needs the ones it skipped just as much.
    //
    // Fifty at a time regardless of --batch, because this filter goes in the
    // query string. A barcode slug runs to sixty-odd characters and a large
    // batch would put the request line past what sits in front of PostgREST —
    // a failure that would appear as an intermittent 414 under load and
    // nowhere in testing.
    const bySlug = new Map<string, string>();
    const slugs = fresh.map((f) => f.slug);
    for (let i = 0; i < slugs.length; i += 50) {
      const chunk = slugs.slice(i, i + 50);
      const res = await db(
        `foods?slug=in.(${chunk.map((s) => `"${s}"`).join(",")})&select=qamar_food_id,slug`,
      );
      if (!res.ok) throw new Error(`reading back foods: ${res.status} ${await res.text()}`);
      for (const r of (await res.json()) as { qamar_food_id: string; slug: string }[]) {
        bySlug.set(r.slug, r.qamar_food_id);
      }
    }
    for (const f of fresh) {
      const id = bySlug.get(f.slug);
      if (id) state.linked.set(f.externalId, id);
    }
  }

  const createdHere = new Set(
    fresh.filter((f) => state.linked.has(f.externalId)).map((f) => f.externalId),
  );
  const rows = childRows(
    sourceId,
    setVersion,
    batch,
    (f) => state.linked.get(f.externalId),
    createdHere,
  );

  // Links first, so a kill here is recoverable.
  await post(
    "food_source_links?on_conflict=qamar_food_id,source_id,external_id",
    rows.links,
    "merge-duplicates",
    "source links",
  );
  await post(
    "food_aliases?on_conflict=qamar_food_id,alias,lang",
    rows.aliases,
    "ignore-duplicates",
    "aliases",
  );
  await post(
    "food_portions?on_conflict=qamar_food_id,label_en",
    rows.portions,
    "ignore-duplicates",
    "portions",
  );
  await post(
    "food_nutrients?on_conflict=qamar_food_id,nutrient_code,per_basis",
    rows.nutrients,
    "merge-duplicates",
    "nutrients",
  );

  for (const f of batch) {
    const id = state.linked.get(f.externalId);
    if (id) state.versioned.add(id);
  }

  return { created: createdHere.size, refreshed: known, nutrientRows: rows.nutrients.length };
}
