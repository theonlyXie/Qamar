// The catalogue importers, tested where they can be wrong quietly.
//
// Every case here is a way to write a number that looks fine in the database
// and is wrong on a screen: a milligram stored as a gram, kilojoules stored as
// kilocalories, an unknown vegan status stored as "not vegan", an imported
// food landing on top of an authored Egyptian one. None of them throw. That is
// what makes them worth a test.

import { assert, assertAlmostEquals, assertEquals } from "jsr:@std/assert@1";

import {
  type CatalogFood,
  catalogSlug,
  childRows,
  foodGroupFrom,
  foodRows,
  NUTRIENT_MAX,
  NUTRIENT_UNIT,
  screenNutrients,
  slugify,
  USDA_NUTRIENT_MAP,
  USDA_PREFERRED_IDS,
} from "./catalog.ts";
import { dietFlag, offNutrients, toCatalogFood as offFood } from "./catalog_off.ts";
import { inverted, stateOf, toCatalogFood as usdaFood } from "./catalog_usda.ts";

// ---------------------------------------------------------------------
// Slugs
// ---------------------------------------------------------------------

Deno.test("an imported slug can never collide with an authored one", () => {
  // The seed authored `oats` by hand. USDA has "Oats" too, and if the importer
  // reused that slug its nutrients, aliases and portions would be written onto
  // the Egyptian row.
  assertEquals(catalogSlug("fdc", "169705", "Oats"), "oats__fdc169705");
  assert(catalogSlug("fdc", "169705", "Oats") !== "oats");
});

Deno.test("the same record always produces the same slug", () => {
  const a = catalogSlug("off", "6221031490011", "Juhayna Full Cream Milk");
  const b = catalogSlug("off", "6221031490011", "Juhayna Full Cream Milk");
  assertEquals(a, b);
  assertEquals(a, "juhayna_full_cream_milk__off6221031490011");
});

Deno.test("a name with no Latin characters still gets a usable slug", () => {
  // Arabic-only product names collapse to nothing under slugify; the external
  // id has to carry the row rather than leaving every such product on "".
  assertEquals(slugify("لبن جهينة"), "");
  assertEquals(catalogSlug("off", "622103149", "لبن جهينة"), "off_622103149");
});

Deno.test("a very long name is truncated without leaving a trailing separator", () => {
  const slug = catalogSlug("fdc", "1", "Beef, ground, 80% lean meat / 20% fat, raw, and then some");
  assert(!slug.includes("__fdc") || slug.split("__fdc")[0].length <= 48);
  assert(!slug.split("__fdc")[0].endsWith("_"));
});

// ---------------------------------------------------------------------
// Plausibility
// ---------------------------------------------------------------------

Deno.test("a food with no energy value is not stored at all", () => {
  const r = screenNutrients({ protein_g: 12, carbs_g: 4 });
  assertEquals(r.usable, false);
  assertEquals(r.reason, "no energy value");
});

Deno.test("kilojoules mistyped into the kcal field are rejected", () => {
  // The single most common Open Food Facts error, and exactly 4.184x high.
  // Stored, it would tell a user their yoghurt is 250 kcal per 100 g.
  const r = screenNutrients({
    energy_kcal: 251, // really 251 kJ = 60 kcal
    protein_g: 3.5,
    carbs_g: 4.7,
    fat_g: 3.3,
  });
  assertEquals(r.usable, false);
  assert(r.reason!.includes("does not match macros"));
});

Deno.test("an honest food passes the same check", () => {
  const r = screenNutrients({ energy_kcal: 60, protein_g: 3.5, carbs_g: 4.7, fat_g: 3.3 });
  assertEquals(r.usable, true);
  assertEquals(r.kept.energy_kcal, 60);
});

Deno.test("fibre and polyols may pull stated energy below the Atwater sum", () => {
  // High-fibre foods legitimately report less energy than 4/4/9 predicts. The
  // band has to be wide enough not to throw bran away.
  const r = screenNutrients({ energy_kcal: 216, protein_g: 16, carbs_g: 65, fat_g: 4.3 });
  assertEquals(r.usable, true);
});

Deno.test("near-zero foods are not judged on the energy ratio", () => {
  // Diet cola: 0.3 kcal against essentially no macros. A ratio test here
  // measures rounding noise, so it is not applied.
  const r = screenNutrients({ energy_kcal: 0.3, protein_g: 0, carbs_g: 0, fat_g: 0 });
  assertEquals(r.usable, true);
});

Deno.test("one absurd micronutrient is dropped, the rest of the food is kept", () => {
  const r = screenNutrients({
    energy_kcal: 100,
    protein_g: 5,
    carbs_g: 10,
    fat_g: 4,
    calcium_mg: 120,
    iron_mg: 9_999_999, // somebody typed the barcode into the iron field
  });
  assertEquals(r.usable, true);
  assertEquals(r.kept.calcium_mg, 120);
  assertEquals(r.kept.iron_mg, undefined);
  assertEquals(r.dropped.map((d) => d.code), ["iron_mg"]);
});

Deno.test("negative amounts are dropped, not stored", () => {
  const r = screenNutrients({ energy_kcal: 100, protein_g: 5, carbs_g: 10, fat_g: 4, sodium_mg: -1 });
  assertEquals(r.kept.sodium_mg, undefined);
  assertEquals(r.dropped[0].why, "negative");
});

Deno.test("macros that sum past a hundred grams fail the whole food", () => {
  const r = screenNutrients({ energy_kcal: 500, protein_g: 60, carbs_g: 60, fat_g: 20 });
  assertEquals(r.usable, false);
  assert(r.reason!.includes("macros sum"));
});

Deno.test("pure salt survives the sodium ceiling", () => {
  // 39,300 mg of sodium per 100 g is real. A ceiling that rejects table salt
  // is a ceiling that will reject other true outliers.
  assert(NUTRIENT_MAX.sodium_mg > 39_300);
  const r = screenNutrients({ energy_kcal: 0.1, sodium_mg: 38_758 });
  assertEquals(r.kept.sodium_mg, 38_758);
});

Deno.test("every code the importers can write has a unit and a ceiling", () => {
  for (const code of Object.values(USDA_NUTRIENT_MAP)) {
    assert(code in NUTRIENT_UNIT, `${code} has no unit`);
    assert(code in NUTRIENT_MAX, `${code} has no ceiling`);
  }
});

// ---------------------------------------------------------------------
// Open Food Facts units
// ---------------------------------------------------------------------

Deno.test("grams become milligrams and micrograms", () => {
  // Open Food Facts stores every _100g field except energy in grams. Read at
  // face value, 120 mg of calcium would enter the graph as 0.12 mg and the
  // micronutrient gap report would tell every user they are deficient.
  const n = offNutrients({
    "energy-kcal_100g": 42,
    "proteins_100g": 3.4,
    "calcium_100g": 0.12,
    "iron_100g": 0.0021,
    "vitamin-d_100g": 0.0000012,
    "folates_100g": 0.00005,
  });
  assertEquals(n.energy_kcal, 42);
  assertEquals(n.protein_g, 3.4);
  assertAlmostEquals(n.calcium_mg, 120, 1e-6);
  assertAlmostEquals(n.iron_mg, 2.1, 1e-6);
  assertAlmostEquals(n.vitamin_d_ug, 1.2, 1e-6);
  assertAlmostEquals(n.folate_ug, 50, 1e-6);
});

Deno.test("salt stands in for sodium, but never over it", () => {
  assertAlmostEquals(offNutrients({ "salt_100g": 2.5 }).sodium_mg, 1000, 1e-6);
  // A reported sodium wins: the salt figure is usually derived from it anyway.
  assertAlmostEquals(
    offNutrients({ "salt_100g": 2.5, "sodium_100g": 0.3 }).sodium_mg,
    300,
    1e-6,
  );
});

Deno.test("a kilojoule figure is converted rather than discarded", () => {
  assertAlmostEquals(offNutrients({ "energy-kj_100g": 418.4 }).energy_kcal, 100, 1e-6);
  // And a real kcal figure is never overwritten by one.
  assertEquals(offNutrients({ "energy-kj_100g": 418.4, "energy-kcal_100g": 99 }).energy_kcal, 99);
});

Deno.test("string values from the export are coerced, junk is skipped", () => {
  const n = offNutrients({ "energy-kcal_100g": "250", "proteins_100g": "", "fat_100g": "n/a" });
  assertEquals(n.energy_kcal, 250);
  assertEquals(n.protein_g, undefined);
  assertEquals(n.fat_g, undefined);
});

// ---------------------------------------------------------------------
// Open Food Facts records
// ---------------------------------------------------------------------

const JUHAYNA = {
  code: "6221031490011",
  product_name: "Full Cream Milk",
  product_name_ar: "لبن كامل الدسم",
  brands: "Juhayna",
  quantity: "1 L",
  serving_size: "200 ml",
  serving_quantity: 200,
  categories_tags: ["en:dairies", "en:milks", "en:whole-milks"],
  allergens_tags: ["en:milk"],
  countries_tags: ["en:egypt"],
  ingredients_analysis_tags: ["en:vegetarian", "en:non-vegan"],
  nutriments: {
    "energy-kcal_100g": 61,
    "proteins_100g": 3.2,
    "carbohydrates_100g": 4.8,
    "fat_100g": 3.3,
    "calcium_100g": 0.113,
  },
};

Deno.test("an Egyptian product maps end to end", () => {
  const f = offFood(JUHAYNA)!;
  assert(f);
  assertEquals(f.externalId, "6221031490011");
  assertEquals(f.externalType, "gtin");
  assertEquals(f.brand, "Juhayna");
  assertEquals(f.countryRegion, "EG");
  assertEquals(f.nameAr, "لبن كامل الدسم");
  assertEquals(f.allergens, ["dairy"]);
  assertEquals(f.foodGroup, "dairy");
  assertAlmostEquals(f.nutrients.calcium_mg, 113, 1e-6);
  assertEquals(f.portions[0], { labelEn: "200 ml", grams: 200, basis: "vendor" });
  // Below the authored seed's 50 and below every USDA dataset: crowd-sourced
  // label transcription must not win a tie-break against a measured food.
  assert(f.sourceRank < 50);
  // And below the 100 an authored hand-written alias carries, which is the
  // half of the contract that actually decides a tie at equal score. Verified
  // against a real Postgres: with both an authored loaf and an imported bread
  // answering to عيش at score 1.0, priority is what puts baladi_bread first.
  for (const a of f.aliases) assert(a.priority < 100, `${a.alias} at ${a.priority}`);
});

Deno.test("the Arabic name is an alias, so Arabic input resolves locally", () => {
  const f = offFood(JUHAYNA)!;
  const ar = f.aliases.find((a) => a.lang === "ar");
  assertEquals(ar?.alias, "لبن كامل الدسم");
});

Deno.test("a product with no barcode or no name is refused", () => {
  assertEquals(offFood({ ...JUHAYNA, code: "" }), null);
  assertEquals(offFood({ ...JUHAYNA, code: "not-a-barcode" }), null);
  assertEquals(offFood({ ...JUHAYNA, product_name: "", product_name_ar: "" }), null);
});

Deno.test("an unknown vegan status stays unknown", () => {
  // NULL means unestablished and never "no". Collapsing it to false would hide
  // every uncertain product from a vegetarian filtering on the column.
  assertEquals(dietFlag(["en:vegan-status-unknown"], "vegan"), null);
  assertEquals(dietFlag(undefined, "vegan"), null);
  assertEquals(dietFlag(["en:non-vegan"], "vegan"), false);
  assertEquals(dietFlag(["en:vegan"], "vegan"), true);

  const f = offFood({ ...JUHAYNA, ingredients_analysis_tags: ["en:vegan-status-unknown"] })!;
  assertEquals(f.isVegan, null);
  assertEquals(f.isVegetarian, null);
});

Deno.test("gluten is asserted from allergens, denied only from a label", () => {
  assertEquals(offFood(JUHAYNA)!.containsGluten, null);
  assertEquals(offFood({ ...JUHAYNA, allergens_tags: ["en:gluten"] })!.containsGluten, true);
  assertEquals(offFood({ ...JUHAYNA, labels_tags: ["en:no-gluten"] })!.containsGluten, false);
});

// ---------------------------------------------------------------------
// USDA records
// ---------------------------------------------------------------------

const BROCCOLI = {
  fdcId: 170379,
  description: "Broccoli, raw",
  foodCategory: { description: "Vegetables and Vegetable Products" },
  foodNutrients: [
    { nutrient: { id: 1008 }, amount: 34 },
    { nutrient: { id: 1003 }, amount: 2.82 },
    { nutrient: { id: 1005 }, amount: 6.64 },
    { nutrient: { id: 1004 }, amount: 0.37 },
    { nutrient: { id: 1087 }, amount: 47 },
  ],
  foodPortions: [
    { amount: 1, gramWeight: 91, measureUnit: { name: "cup" }, modifier: "chopped" },
  ],
};

Deno.test("a USDA record maps end to end", () => {
  const f = usdaFood(BROCCOLI, { rank: 40, confidence: 0.85 })!;
  assertEquals(f.externalId, "170379");
  assertEquals(f.externalType, "fdc_id");
  assertEquals(f.foodState, "raw");
  assertEquals(f.foodGroup, "vegetable");
  assertEquals(f.nutrients.energy_kcal, 34);
  assertEquals(f.nutrients.calcium_mg, 47);
  assertEquals(f.portions[0], { labelEn: "1 cup, chopped", grams: 91, basis: "measured" });
  assert(f.sourceRank < 50);
  for (const a of f.aliases) assert(a.priority < 100, `${a.alias} at ${a.priority}`);
});

Deno.test("USDA says nothing about diet suitability, so nothing is claimed", () => {
  const f = usdaFood(BROCCOLI, { rank: 40, confidence: 0.85 })!;
  assertEquals(f.isVegan, null);
  assertEquals(f.isVegetarian, null);
  assertEquals(f.containsGluten, null);
});

Deno.test("folate DFE wins over total folate whichever arrives first", () => {
  // The DRI is set in dietary folate equivalents, and fortified baladi flour is
  // exactly where the two figures diverge. Taking the last one in the array
  // would make the folate column mean different things for different foods.
  const dfeLast = usdaFood({
    ...BROCCOLI,
    foodNutrients: [
      ...BROCCOLI.foodNutrients,
      { nutrient: { id: 1177 }, amount: 63 },
      { nutrient: { id: 1190 }, amount: 107 },
    ],
  }, { rank: 40, confidence: 0.85 })!;
  const dfeFirst = usdaFood({
    ...BROCCOLI,
    foodNutrients: [
      ...BROCCOLI.foodNutrients,
      { nutrient: { id: 1190 }, amount: 107 },
      { nutrient: { id: 1177 }, amount: 63 },
    ],
  }, { rank: 40, confidence: 0.85 })!;
  assertEquals(dfeLast.nutrients.folate_ug, 107);
  assertEquals(dfeFirst.nutrients.folate_ug, 107);
  assert(USDA_PREFERRED_IDS.has(1190));
});

Deno.test("the comma-inverted description becomes the alias people type", () => {
  assertEquals(inverted("Broccoli, raw"), "raw broccoli");
  assertEquals(inverted("Rice, white, long-grain, cooked"), "white long-grain cooked rice");
  assertEquals(inverted("Oats"), null);
});

Deno.test("no bare head term is ever added as an alias", () => {
  // Several hundred USDA rows begin "Cheese,". If each claimed the bare word at
  // the same priority and the same score, a user typing جبنة would get whichever
  // the tie-break reached — a confident wrong answer in place of a clean miss.
  const f = usdaFood({ ...BROCCOLI, description: "Cheese, feta" }, {
    rank: 40,
    confidence: 0.85,
  })!;
  assertEquals(f.aliases.map((a) => a.alias), ["Cheese, feta", "feta cheese"]);
  assert(!f.aliases.some((a) => a.alias.toLowerCase() === "cheese"));
});

Deno.test("an unreasonably long tail is not inverted into nonsense", () => {
  assertEquals(
    inverted("Beef, round, top round roast, boneless, separable lean only, trimmed to 0 inch fat"),
    null,
  );
});

Deno.test("the cooking state is read off the description", () => {
  // Boiled rice and raw rice are wildly different per 100 g, and food_state is
  // what stops the graph treating them as one food.
  assertEquals(stateOf("Rice, white, cooked"), "cooked");
  assertEquals(stateOf("Rice, white, raw"), "raw");
  assertEquals(stateOf("Chicken, broilers, breast, roasted"), "baked");
  assertEquals(stateOf("Beans, fava, boiled"), "boiled");
  assertEquals(stateOf("Molokhia"), "unspecified");
});

Deno.test("a USDA record that fails the screen is refused, not stored empty", () => {
  assertEquals(
    usdaFood({ ...BROCCOLI, foodNutrients: [{ nutrient: { id: 1003 }, amount: 2.8 }] }, {
      rank: 40,
      confidence: 0.85,
    }),
    null,
  );
  assertEquals(usdaFood({ ...BROCCOLI, description: "  " }, { rank: 40, confidence: 0.85 }), null);
});

// ---------------------------------------------------------------------
// Food groups
// ---------------------------------------------------------------------

Deno.test("every USDA category lands in the seed's vocabulary or in nothing", () => {
  // The seed established ten groups. If an importer writes "Sausages and
  // Luncheon Meats" into the column, grouping by food_group stops working the
  // day the first catalogue lands, and nothing raises an error.
  const SEED_GROUPS = new Set([
    "vegetable", "dish", "protein", "fruit", "grain",
    "sweet", "fat", "legume", "drink", "dairy",
  ]);
  const expected: Record<string, string | null> = {
    "Dairy and Egg Products": "dairy",
    "Fats and Oils": "fat",
    "Poultry Products": "protein",
    "Soups, Sauces, and Gravies": "dish",
    "Sausages and Luncheon Meats": "protein",
    "Breakfast Cereals": "grain",
    "Fruits and Fruit Juices": "fruit",
    "Vegetables and Vegetable Products": "vegetable",
    "Nut and Seed Products": "protein",
    "Beverages": "drink",
    "Finfish and Shellfish Products": "protein",
    "Legumes and Legume Products": "legume",
    "Lamb, Veal, and Game Products": "protein",
    "Baked Products": "grain",
    "Sweets": "sweet",
    "Cereal Grains and Pasta": "grain",
    "Fast Foods": "dish",
    "Meals, Entrees, and Side Dishes": "dish",
    "Restaurant Foods": "dish",
    // No confident rule, so no guess. Snacks and spices genuinely are not one
    // of the ten, and a wrong group is worse than an absent one.
    "Snacks": null,
    "Spices and Herbs": null,
    "Baby Foods": null,
  };
  for (const [category, group] of Object.entries(expected)) {
    assertEquals(foodGroupFrom(category), group, category);
    if (group !== null) assert(SEED_GROUPS.has(group));
  }
});

Deno.test("butter is a fat and ice cream is a sweet, as the seed has them", () => {
  // Both would be claimed by the dairy rule if the order were different.
  assertEquals(foodGroupFrom("Butter"), "fat");
  assertEquals(foodGroupFrom("en:ice-creams"), "sweet");
  assertEquals(foodGroupFrom("en:whole-milks"), "dairy");
});

Deno.test("an Open Food Facts chain falls back to a parent that does map", () => {
  // The most specific tag is often a marketing word. A parent group is worth
  // more than a null.
  const f = offFood({
    ...JUHAYNA,
    categories_tags: ["en:beverages", "en:sweetened-beverages", "en:tamarind-drinks"],
  })!;
  assertEquals(f.foodGroup, "drink");
});

Deno.test("nothing recognisable stays null rather than becoming a guess", () => {
  assertEquals(foodGroupFrom("en:some-brand-invention"), null);
  assertEquals(foodGroupFrom(null), null);
  assertEquals(foodGroupFrom(""), null);
});

// ---------------------------------------------------------------------
// What gets written
// ---------------------------------------------------------------------

function food(over: Partial<CatalogFood> & { externalId: string }): CatalogFood {
  return {
    externalType: "fdc_id",
    url: null,
    slug: `f_${over.externalId}`,
    nameEn: `Food ${over.externalId}`,
    foodState: "unspecified",
    allergens: [],
    sourceRank: 40,
    confidence: 0.85,
    aliases: [],
    portions: [],
    nutrients: { energy_kcal: 100 },
    ...over,
  };
}

const idOf = (f: CatalogFood) => `id-${f.externalId}`;

Deno.test("an authored food that a source already links gets numbers and nothing else", () => {
  // ingest_usda.ts maps fdcIds onto the hand-authored Egyptian seed. When the
  // catalogue importer meets one of those ids it must refresh the values and
  // stop: appending "Beans, fava, mature seeds, cooked" to the aliases of
  // فول مدمس, and a USDA cup measure to its portions, is how the authored
  // layer stops being worth having.
  const authored = food({
    externalId: "175202",
    aliases: [{ alias: "Beans, fava, mature seeds, cooked", lang: "en", priority: 70 }],
    portions: [{ labelEn: "1 cup", grams: 170, basis: "measured" }],
    nutrients: { energy_kcal: 110, protein_g: 7.6 },
  });

  const rows = childRows("usda_fdc", "fdc-2026-08", [authored], idOf, new Set());
  assertEquals(rows.aliases.length, 0);
  assertEquals(rows.portions.length, 0);
  assertEquals(rows.nutrients.length, 2);
  assertEquals(rows.links.length, 1);
});

Deno.test("a food this run created gets its names and portions", () => {
  const fresh = food({
    externalId: "170379",
    aliases: [{ alias: "Broccoli, raw", lang: "en", priority: 70 }],
    portions: [{ labelEn: "1 cup", grams: 91, basis: "measured" }],
  });
  const rows = childRows("usda_fdc", "fdc-2026-08", [fresh], idOf, new Set(["170379"]));
  assertEquals(rows.aliases.length, 1);
  assertEquals(rows.portions.length, 1);
});

Deno.test("exactly one portion per food is the default", () => {
  // There is a partial unique index on (food) where is_default, and the
  // on_conflict target used for portions does not cover it — a second default
  // fails the whole batch rather than skipping one row.
  const f = food({
    externalId: "1",
    portions: [
      { labelEn: "1 cup", grams: 91, basis: "measured" },
      { labelEn: "1 spear", grams: 31, basis: "measured" },
      { labelEn: "1 floweret", grams: 11, basis: "measured" },
    ],
  });
  const rows = childRows("usda_fdc", "v", [f], idOf, new Set(["1"]));
  assertEquals(rows.portions.filter((p) => p.is_default).length, 1);
  assertEquals(rows.portions[0].is_default, true);
});

Deno.test("a food with every portion filtered out contributes no default", () => {
  const f = food({
    externalId: "1",
    portions: [{ labelEn: "   ", grams: 91, basis: "measured" }, {
      labelEn: "absurd",
      grams: 99_999,
      basis: "measured",
    }],
  });
  assertEquals(childRows("usda_fdc", "v", [f], idOf, new Set(["1"])).portions.length, 0);
});

Deno.test("duplicate keys within one batch are collapsed before they reach Postgres", () => {
  // The nutrient and link upserts merge rather than ignore, and Postgres
  // raises "ON CONFLICT DO UPDATE command cannot affect row a second time"
  // when one statement carries a key twice. That fails the whole batch, not
  // the duplicate row.
  const same = [food({ externalId: "9" }), food({ externalId: "9" })];
  const rows = childRows("usda_fdc", "v", same, idOf, new Set(["9"]));
  assertEquals(rows.nutrients.length, 1);
  assertEquals(rows.links.length, 1);
});

Deno.test("two portions with the same label collapse to one", () => {
  const f = food({
    externalId: "1",
    portions: [
      { labelEn: "1 cup", grams: 91, basis: "measured" },
      { labelEn: "1 Cup", grams: 92, basis: "measured" },
    ],
  });
  assertEquals(childRows("usda_fdc", "v", [f], idOf, new Set(["1"])).portions.length, 1);
});

Deno.test("aliases too short to be worth matching are dropped", () => {
  // A two-character alias matches half the graph under trigram similarity.
  const f = food({
    externalId: "1",
    aliases: [
      { alias: "Oat", lang: "en", priority: 70 },
      { alias: "  ", lang: "en", priority: 70 },
      { alias: "x", lang: "en", priority: 70 },
    ],
  });
  const rows = childRows("usda_fdc", "v", [f], idOf, new Set(["1"]));
  assertEquals(rows.aliases.map((a) => a.alias), ["Oat"]);
});

Deno.test("a food whose insert failed is left out entirely, to be retried", () => {
  // idOf returns undefined when the read-back found no row. Writing children
  // for it would mean a null foreign key; skipping it means the next run picks
  // it up, because nothing was linked.
  const f = food({ externalId: "1", aliases: [{ alias: "Thing", lang: "en", priority: 70 }] });
  const rows = childRows("usda_fdc", "v", [f], () => undefined, new Set(["1"]));
  assertEquals(rows.links.length, 0);
  assertEquals(rows.nutrients.length, 0);
  assertEquals(rows.aliases.length, 0);
});

Deno.test("provenance is recorded per nutrient, not per row", () => {
  // A dish routinely takes its energy from one source and its portion from
  // another, which is why field_provenance exists at all.
  const f = food({ externalId: "1", nutrients: { energy_kcal: 100, calcium_mg: 12 } });
  const link = childRows("open_food_facts", "v", [f], idOf, new Set(["1"])).links[0];
  assertEquals(link.field_provenance, {
    energy_kcal: "open_food_facts",
    calcium_mg: "open_food_facts",
  });
});

Deno.test("a new food row never claims to be human reviewed", () => {
  const rows = foodRows([food({ externalId: "1" })]);
  assertEquals(rows[0].human_reviewed, false);
  assertEquals(rows[0].is_recipe, false);
  assert(rows[0].source_rank < 50);
});
