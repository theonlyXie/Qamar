// Where the assistant's facts come from.
//
// Two separate sources, deliberately not mixed:
//
//   * the knowledge base (kb_chunks) — guidance and principles, retrieved by
//     vector similarity, used to reason about *what* to advise,
//   * food databases — per-item nutrition numbers, looked up by name, used for
//     *quantities*. A model must never invent a calorie count; if the lookup
//     fails, the number is reported as an estimate and marked low confidence.

import type { Domain } from "./scope.ts";

export interface Source {
  source: string;
  title: string;
  url: string | null;
}

export interface Passage extends Source {
  content: string;
  similarity: number;
}

export interface FoodFacts {
  name: string;
  per100g: { kcal: number; protein: number; carbs: number; fat: number };
  source: string;
  url: string | null;
}

// ---- embeddings ---------------------------------------------------------

/**
 * Embeds text for retrieval. Anthropic does not serve embeddings, so this uses
 * Voyage (their documented recommendation) with OpenAI as an alternative.
 * The dimension must match kb_chunks.embedding — vector(1024), which is
 * voyage-3's default. Changing provider means re-embedding the whole base.
 */
export async function embed(text: string): Promise<number[] | null> {
  const voyage = Deno.env.get("VOYAGE_API_KEY");
  if (voyage) {
    const res = await fetch("https://api.voyageai.com/v1/embeddings", {
      method: "POST",
      headers: { "Content-Type": "application/json", Authorization: `Bearer ${voyage}` },
      body: JSON.stringify({
        model: Deno.env.get("EMBEDDING_MODEL") ?? "voyage-3",
        input: [text],
        input_type: "query",
      }),
    });
    if (!res.ok) return null;
    const json = await res.json();
    return json.data?.[0]?.embedding ?? null;
  }

  const openai = Deno.env.get("OPENAI_API_KEY");
  if (openai) {
    const res = await fetch("https://api.openai.com/v1/embeddings", {
      method: "POST",
      headers: { "Content-Type": "application/json", Authorization: `Bearer ${openai}` },
      body: JSON.stringify({
        model: "text-embedding-3-small",
        input: text,
        dimensions: 1024, // match kb_chunks.embedding
      }),
    });
    if (!res.ok) return null;
    const json = await res.json();
    return json.data?.[0]?.embedding ?? null;
  }

  // No embedding provider configured: retrieval is skipped, and the caller
  // refuses rather than answering ungrounded.
  return null;
}

// ---- knowledge base -----------------------------------------------------

/**
 * Nearest chunks for a question. Returns [] when there is no embedding
 * provider or nothing clears the similarity floor — both of which the caller
 * treats as "cannot answer", never as "answer from memory".
 */
export async function retrieve(
  supabaseUrl: string,
  serviceKey: string,
  question: string,
  domain: Domain,
  count = 6,
): Promise<Passage[]> {
  const vector = await embed(question);
  if (!vector) return [];

  const res = await fetch(`${supabaseUrl}/rest/v1/rpc/match_kb_chunks`, {
    method: "POST",
    headers: {
      "Content-Type": "application/json",
      apikey: serviceKey,
      Authorization: `Bearer ${serviceKey}`,
    },
    body: JSON.stringify({
      query_embedding: vector,
      match_domain: domain,
      match_count: count,
      min_similarity: 0.25,
    }),
  });
  if (!res.ok) return [];
  return (await res.json()) as Passage[];
}

// ---- food databases -----------------------------------------------------

/**
 * Open Food Facts. Free, no key, worldwide, and strongest on packaged goods.
 * Tried first because it needs no configuration.
 */
async function openFoodFacts(query: string): Promise<FoodFacts | null> {
  const url =
    `https://world.openfoodfacts.org/cgi/search.pl?search_terms=${encodeURIComponent(query)}` +
    `&search_simple=1&action=process&json=1&page_size=1` +
    `&fields=product_name,nutriments,code`;
  try {
    const res = await fetch(url, {
      headers: { "User-Agent": "Qamar/0.6 (https://dr-qamar.com; contact: support@dr-qamar.com)" },
    });
    if (!res.ok) return null;
    const json = await res.json();
    const p = json.products?.[0];
    const n = p?.nutriments;
    if (!p || !n || n["energy-kcal_100g"] == null) return null;
    return {
      name: p.product_name ?? query,
      per100g: {
        kcal: Math.round(n["energy-kcal_100g"]),
        protein: Math.round(n["proteins_100g"] ?? 0),
        carbs: Math.round(n["carbohydrates_100g"] ?? 0),
        fat: Math.round(n["fat_100g"] ?? 0),
      },
      source: "Open Food Facts",
      url: p.code ? `https://world.openfoodfacts.org/product/${p.code}` : null,
    };
  } catch {
    return null;
  }
}

/**
 * USDA FoodData Central. Better for raw and cooked whole foods, which is most
 * of what an Egyptian home-cooked plate is made of. Needs a free API key.
 */
async function usda(query: string): Promise<FoodFacts | null> {
  const key = Deno.env.get("USDA_API_KEY");
  if (!key) return null;
  try {
    const res = await fetch(
      `https://api.nal.usda.gov/fdc/v1/foods/search?query=${encodeURIComponent(query)}` +
        `&pageSize=1&dataType=SR%20Legacy,Foundation&api_key=${key}`,
    );
    if (!res.ok) return null;
    const json = await res.json();
    const food = json.foods?.[0];
    if (!food) return null;

    const pick = (id: number) =>
      Math.round(food.foodNutrients?.find((n: { nutrientId: number }) => n.nutrientId === id)?.value ?? 0);
    const kcal = pick(1008);
    if (!kcal) return null;

    return {
      name: food.description ?? query,
      per100g: { kcal, protein: pick(1003), carbs: pick(1005), fat: pick(1004) },
      source: "USDA FoodData Central",
      url: food.fdcId ? `https://fdc.nal.usda.gov/food-details/${food.fdcId}` : null,
    };
  } catch {
    return null;
  }
}

/**
 * Looks a food up across the configured databases, preferring whole-food data
 * for plain names. Returns null rather than a guess — the caller marks
 * anything unresolved as an estimate so the user can see which numbers are
 * measured and which are not.
 */
export async function lookupFood(query: string): Promise<FoodFacts | null> {
  const [fromUsda, fromOff] = await Promise.all([usda(query), openFoodFacts(query)]);
  return fromUsda ?? fromOff;
}

// lookupFoods() used to batch this for the gateway. graph.ts owns that job now:
// it resolves against the Qamar graph first and calls lookupFood() only for
// what the graph cannot answer. Two entry points into food resolution would be
// two places for the source-router rule to be forgotten, so there is one.

const OFF_UA = "Qamar/0.6 (https://dr-qamar.com; contact: support@dr-qamar.com)";

export interface BarcodeProduct {
  code: string;
  name: string;
  nameAr: string | null;
  servingGrams: number;
  per100g: { kcal: number; protein: number; carbs: number; fat: number };
  url: string | null;
}

/** Household serving, or 100 g when Open Food Facts has no serving weight. */
export function servingGramsFromOff(product: {
  serving_quantity?: unknown;
  serving_size?: unknown;
}): number {
  const qty = Number(product.serving_quantity);
  if (Number.isFinite(qty) && qty > 0 && qty <= 2000) return Math.round(qty);
  const size = String(product.serving_size ?? "");
  const fromSize = size.match(/(\d+(?:\.\d+)?)\s*g/i);
  if (fromSize) {
    const g = Number(fromSize[1]);
    if (Number.isFinite(g) && g > 0 && g <= 2000) return Math.round(g);
  }
  return 100;
}

export function scalePer100g(
  per100g: { kcal: number; protein: number; carbs: number; fat: number },
  grams: number,
): { kcal: number; protein: number; carbs: number; fat: number } {
  const factor = grams / 100;
  return {
    kcal: Math.round(per100g.kcal * factor),
    protein: Math.round(per100g.protein * factor),
    carbs: Math.round(per100g.carbs * factor),
    fat: Math.round(per100g.fat * factor),
  };
}

export function barcodeProductFromOff(json: {
  status?: number;
  product?: {
    code?: string;
    product_name?: string;
    product_name_en?: string;
    product_name_ar?: string;
    nutriments?: Record<string, unknown>;
    serving_quantity?: unknown;
    serving_size?: unknown;
  };
}): BarcodeProduct | null {
  const p = json.product;
  const n = p?.nutriments;
  if (json.status === 0 || !p || !n || n["energy-kcal_100g"] == null) return null;
  const kcal = Number(n["energy-kcal_100g"]);
  if (!Number.isFinite(kcal) || kcal <= 0) return null;
  const code = String(p.code ?? "").replace(/\D/g, "");
  const name = (p.product_name_en || p.product_name || code).trim();
  const nameAr = typeof p.product_name_ar === "string" && p.product_name_ar.trim()
    ? p.product_name_ar.trim()
    : null;
  return {
    code,
    name,
    nameAr,
    servingGrams: servingGramsFromOff(p),
    per100g: {
      kcal: Math.round(kcal),
      protein: Math.round(Number(n["proteins_100g"] ?? 0) || 0),
      carbs: Math.round(Number(n["carbohydrates_100g"] ?? 0) || 0),
      fat: Math.round(Number(n["fat_100g"] ?? 0) || 0),
    },
    url: code ? `https://world.openfoodfacts.org/product/${code}` : null,
  };
}

export function itemsFromBarcode(product: BarcodeProduct, lang: "ar" | "en") {
  const macros = scalePer100g(product.per100g, product.servingGrams);
  const ar = product.nameAr ?? product.name;
  const en = product.name;
  const portionAr = `${product.servingGrams} جم`;
  const portionEn = `${product.servingGrams} g`;
  return [{
    ar: lang === "ar" ? ar : product.nameAr ?? ar,
    en,
    portionAr,
    portionEn,
    confidence: "high" as const,
    kcal: macros.kcal,
    proteinG: macros.protein,
    carbsG: macros.carbs,
    fatG: macros.fat,
    grams: product.servingGrams,
    portion_matched: true,
  }];
}

/**
 * Packaged-goods barcode lookup. No model, no daily AI use. Returns null
 * when Open Food Facts has no usable per-100 g energy for the code.
 */
export async function lookupBarcode(code: string): Promise<BarcodeProduct | null> {
  const digits = code.replace(/\D/g, "");
  if (digits.length < 8 || digits.length > 14) return null;
  try {
    const res = await fetch(
      `https://world.openfoodfacts.org/api/v2/product/${digits}.json` +
        `?fields=code,product_name,product_name_en,product_name_ar,nutriments,serving_quantity,serving_size`,
      { headers: { "User-Agent": OFF_UA } },
    );
    if (!res.ok) return null;
    return barcodeProductFromOff(await res.json());
  } catch {
    return null;
  }
}
