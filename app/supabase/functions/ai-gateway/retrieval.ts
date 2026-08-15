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
