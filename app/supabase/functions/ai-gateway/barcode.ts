// Reading a barcode, and knowing how much of the pack was eaten.
//
// The graph answers first, as everywhere else: a barcode seen before is a
// local row and costs nothing. A miss goes to Open Food Facts, then to USDA's
// branded table, and whatever comes back is written into the graph so the
// second person to scan that packet gets it free — and so the product carries
// micronutrients rather than four macros.
//
// The part that is easy to get wrong is the portion. A nutrition table is per
// 100 g; a packet of chips is 25 g and a bottle of Coca-Cola is 330 ml. Logging
// "100 g of crisps" for a bag somebody actually ate is a 4x error on a number
// this app exists to get right, so the pack size is parsed and carried
// separately from the per-100 g figures, and the caller is told which it has.

import type { FoodFacts } from "./retrieval.ts";

const UA = "Qamar/0.9 (https://dr-qamar.com; contact: support@dr-qamar.com)";

/** Per 100 g, in Qamar nutrient codes. */
export type Per100g = Record<string, number>;

export interface ScannedProduct {
  barcode: string;
  name: string;
  brand: string | null;
  /** Per 100 g / 100 ml, in Qamar nutrient codes. */
  per100g: Per100g;
  /** The whole pack in grams, when the packaging says. Null when it does not. */
  packGrams: number | null;
  /** One serving in grams, when the packaging says. */
  servingGrams: number | null;
  /** Human label for the pack, as printed: "330 ml", "25 g". */
  packLabel: string | null;
  source: "graph" | "open_food_facts" | "usda_branded";
  sourceUrl: string | null;
}

// ---- units ---------------------------------------------------------------

/**
 * Grams from a packaging string.
 *
 * Open Food Facts stores this as free text because it is copied off a packet:
 * "330 ml", "25g", "1 portion (330 ml)", "٢٥ جم". Millilitres are treated as
 * grams, which is right for water and drinks and close enough for everything
 * else this will meet — and it is the assumption the caller is told about
 * rather than one made silently.
 */
export function parseGrams(text: string | null | undefined): number | null {
  if (!text) return null;
  // Arabic-Indic digits and the Arabic decimal separator both appear on
  // Egyptian packaging.
  const ascii = text
    .replace(/[٠-٩]/g, (d) => String(d.codePointAt(0)! - 0x0660))
    .replace(/\u066B/g, ".")
    .replace(/\u066C/g, "");

  // Units longest-first, so "grams" is not read as "g" with a stray suffix,
  // and "kg" is not read as "g".
  //
  // The boundary is a negative lookahead rather than \b. \b is defined on
  // [A-Za-z0-9_], so it never matches after an Arabic letter — which meant
  // "٢٥ جم" and "٥٠٠ مل", the way an Egyptian packet is actually printed,
  // both parsed as nothing at all.
  const m = ascii.match(
    /(\d+(?:[.,]\d+)?)\s*(kg|كجم|grams?|gm|gr|جرام|جم|ml|مل|cl|lt|لتر|l|g)(?![a-z])/i,
  );
  if (!m) return null;
  const n = Number(m[1].replace(",", "."));
  if (!Number.isFinite(n) || n <= 0) return null;
  const unit = m[2].toLowerCase();
  if (unit === "kg" || unit === "كجم") return n * 1000;
  if (unit === "l" || unit === "لتر") return n * 1000;
  if (unit === "cl") return n * 10;
  return n; // g, ml, and the Arabic equivalents
}

/** Scales a per-100 g table to a real weight. */
export function scaleTo(per100g: Per100g, grams: number): Per100g {
  const out: Per100g = {};
  const factor = grams / 100;
  for (const [code, v] of Object.entries(per100g)) {
    out[code] = Math.round(v * factor * 100) / 100;
  }
  return out;
}

// ---- Open Food Facts -----------------------------------------------------

/** Their nutriment keys to ours. Anything absent is simply not claimed. */
const OFF_MAP: Record<string, string> = {
  "energy-kcal_100g": "energy_kcal",
  "proteins_100g": "protein_g",
  "carbohydrates_100g": "carbs_g",
  "fat_100g": "fat_g",
  "fiber_100g": "fiber_g",
  "sugars_100g": "sugars_g",
  "saturated-fat_100g": "sat_fat_g",
  "sodium_100g": "sodium_mg",
  "calcium_100g": "calcium_mg",
  "iron_100g": "iron_mg",
  "potassium_100g": "potassium_mg",
  "magnesium_100g": "magnesium_mg",
  "zinc_100g": "zinc_mg",
  "vitamin-c_100g": "vitamin_c_mg",
  "vitamin-a_100g": "vitamin_a_ug",
  "vitamin-d_100g": "vitamin_d_ug",
};

/**
 * Open Food Facts reports minerals in grams, and we store milligrams.
 *
 * Getting this backwards would report 0 mg of sodium for a packet of crisps,
 * which is both wrong and the exact direction that flatters a bad food.
 */
const OFF_SCALE: Record<string, number> = {
  sodium_mg: 1000,
  calcium_mg: 1000,
  iron_mg: 1000,
  potassium_mg: 1000,
  magnesium_mg: 1000,
  zinc_mg: 1000,
  vitamin_c_mg: 1000,
  vitamin_a_ug: 1_000_000,
  vitamin_d_ug: 1_000_000,
};

export function per100FromOff(nutriments: Record<string, unknown>): Per100g {
  const out: Per100g = {};
  for (const [key, code] of Object.entries(OFF_MAP)) {
    const raw = nutriments[key];
    if (typeof raw !== "number" || !Number.isFinite(raw)) continue;
    const scaled = raw * (OFF_SCALE[code] ?? 1);
    // Two decimals is plenty for a label, and stops 0.30000000000000004.
    out[code] = Math.round(scaled * 100) / 100;
  }
  return out;
}

interface OffProduct {
  code?: string;
  product_name?: string;
  brands?: string;
  quantity?: string;
  serving_size?: string;
  serving_quantity?: number | string;
  nutriments?: Record<string, unknown>;
}

async function fromOpenFoodFacts(barcode: string): Promise<ScannedProduct | null> {
  const fields = "code,product_name,brands,quantity,serving_size,serving_quantity,nutriments";
  const url = `https://world.openfoodfacts.org/api/v2/product/${
    encodeURIComponent(barcode)
  }.json?fields=${fields}`;
  try {
    const res = await fetch(url, { headers: { "User-Agent": UA } });
    if (!res.ok) return null;
    const json = await res.json() as { status?: number; product?: OffProduct };
    if (json.status !== 1 || !json.product) return null;
    const p = json.product;
    const per100g = per100FromOff(p.nutriments ?? {});
    // Without energy there is nothing to add to a day, and a product row with
    // no calories is worse than no row: it looks resolved.
    if (per100g.energy_kcal == null) return null;

    const servingGrams = parseGrams(p.serving_size) ??
      (typeof p.serving_quantity === "number" ? p.serving_quantity : null);

    return {
      barcode,
      name: (p.product_name ?? "").trim() || barcode,
      brand: (p.brands ?? "").split(",")[0].trim() || null,
      per100g,
      packGrams: parseGrams(p.quantity),
      servingGrams,
      packLabel: (p.quantity ?? "").trim() || null,
      source: "open_food_facts",
      sourceUrl: `https://world.openfoodfacts.org/product/${barcode}`,
    };
  } catch {
    return null;
  }
}

// ---- USDA branded --------------------------------------------------------

const USDA_MAP: Record<string, string> = {
  "1008": "energy_kcal",
  "1003": "protein_g",
  "1005": "carbs_g",
  "1004": "fat_g",
  "1079": "fiber_g",
  "2000": "sugars_g",
  "1258": "sat_fat_g",
  "1093": "sodium_mg",
  "1087": "calcium_mg",
  "1089": "iron_mg",
  "1092": "potassium_mg",
};

/**
 * USDA's Branded table, searched by the barcode itself.
 *
 * Second rather than first: Open Food Facts is crowd-sourced but it is where
 * Egyptian retail products actually are, and USDA Branded is almost entirely
 * American.
 */
async function fromUsdaBranded(barcode: string): Promise<ScannedProduct | null> {
  const key = Deno.env.get("USDA_API_KEY");
  if (!key) return null;
  const url = `https://api.nal.usda.gov/fdc/v1/foods/search?query=${
    encodeURIComponent(barcode)
  }&dataType=Branded&pageSize=1&api_key=${key}`;
  try {
    const res = await fetch(url);
    if (!res.ok) return null;
    const json = await res.json();
    const f = json.foods?.[0];
    if (!f || f.gtinUpc?.replace(/^0+/, "") !== barcode.replace(/^0+/, "")) return null;

    const per100g: Per100g = {};
    for (const n of f.foodNutrients ?? []) {
      const code = USDA_MAP[String(n.nutrientId)];
      if (code && typeof n.value === "number") per100g[code] = n.value;
    }
    if (per100g.energy_kcal == null) return null;

    return {
      barcode,
      name: (f.description ?? "").trim() || barcode,
      brand: (f.brandOwner ?? f.brandName ?? "").trim() || null,
      per100g,
      packGrams: parseGrams(f.packageWeight),
      servingGrams: typeof f.servingSize === "number" &&
          /^g|gram/i.test(f.servingSizeUnit ?? "")
        ? f.servingSize
        : null,
      packLabel: (f.packageWeight ?? "").trim() || null,
      source: "usda_branded",
      sourceUrl: f.fdcId ? `https://fdc.nal.usda.gov/food-details/${f.fdcId}` : null,
    };
  } catch {
    return null;
  }
}

/**
 * A barcode, from whichever source can answer.
 *
 * Returns null when nobody knows the product. That is a real outcome for a
 * local Egyptian brand and the caller must handle it by asking rather than by
 * inventing a plausible packet of crisps.
 */
export async function lookupBarcode(barcode: string): Promise<ScannedProduct | null> {
  const clean = barcode.replace(/\D/g, "");
  if (clean.length < 8 || clean.length > 14) return null;
  return (await fromOpenFoodFacts(clean)) ?? (await fromUsdaBranded(clean));
}

/** What to log when someone says they ate the whole thing. */
export function eatenPortion(p: ScannedProduct): { grams: number; label: string; assumed: boolean } {
  if (p.packGrams && p.packGrams > 0 && p.packGrams <= 2000) {
    return { grams: p.packGrams, label: p.packLabel ?? `${p.packGrams} g`, assumed: false };
  }
  if (p.servingGrams && p.servingGrams > 0) {
    return { grams: p.servingGrams, label: `${p.servingGrams} g`, assumed: false };
  }
  // Nothing on the packet said. 100 g is the table's own basis, and it is
  // flagged as an assumption so the app asks rather than states.
  return { grams: 100, label: "100 g", assumed: true };
}

/** The four macros, in the shape the rest of the gateway passes around. */
export function asFoodFacts(p: ScannedProduct): FoodFacts {
  return {
    name: p.brand ? `${p.brand} ${p.name}` : p.name,
    per100g: {
      kcal: Math.round(p.per100g.energy_kcal ?? 0),
      protein: Math.round(p.per100g.protein_g ?? 0),
      carbs: Math.round(p.per100g.carbs_g ?? 0),
      fat: Math.round(p.per100g.fat_g ?? 0),
    },
    source: p.source === "open_food_facts" ? "Open Food Facts" : "USDA Branded",
    url: p.sourceUrl,
  };
}
