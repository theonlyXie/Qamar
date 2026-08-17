import type { AuthUser } from "../_shared/auth.ts";
import { db, rpc } from "../_shared/db.ts";
import { err, ok } from "../_shared/envelope.ts";

async function offBarcode(gtin: string): Promise<Record<string, unknown> | null> {
  try {
    const res = await fetch(`https://world.openfoodfacts.org/api/v2/product/${gtin}.json`, {
      headers: {
        "User-Agent": "Qamar/0.9 (https://dr-qamar.com; contact: support@dr-qamar.com)",
      },
    });
    if (!res.ok) return null;
    const json = await res.json();
    if (json.status !== 1 || !json.product) return null;
    const p = json.product;
    const n = p.nutriments ?? {};
    return {
      gtin,
      name: p.product_name ?? p.product_name_en ?? gtin,
      brand: p.brands ?? null,
      per_100g: {
        kcal: Math.round(n["energy-kcal_100g"] ?? 0),
        protein_g: Math.round(n.proteins_100g ?? 0),
        carbs_g: Math.round(n.carbohydrates_100g ?? 0),
        fat_g: Math.round(n.fat_100g ?? 0),
      },
      source: "Open Food Facts",
      source_url: `https://world.openfoodfacts.org/product/${gtin}`,
      provider_payload: { code: p.code, product_name: p.product_name },
    };
  } catch {
    return null;
  }
}

async function usdaSearch(query: string): Promise<Record<string, unknown>[]> {
  const key = Deno.env.get("USDA_API_KEY");
  if (!key) return [];
  try {
    const res = await fetch(
      `https://api.nal.usda.gov/fdc/v1/foods/search?query=${encodeURIComponent(query)}` +
        `&pageSize=10&dataType=SR%20Legacy,Foundation&api_key=${key}`,
    );
    if (!res.ok) return [];
    const json = await res.json();
    return (json.foods ?? []).map((food: Record<string, unknown>) => {
      const nutrients = (food.foodNutrients as { nutrientId: number; value?: number }[]) ?? [];
      const pick = (id: number) =>
        Math.round(nutrients.find((n) => n.nutrientId === id)?.value ?? 0);
      return {
        id: `fdc:${food.fdcId}`,
        canonical_name: food.description,
        per_100g: {
          kcal: pick(1008),
          protein_g: pick(1003),
          carbs_g: pick(1005),
          fat_g: pick(1004),
        },
        source: "USDA FoodData Central",
        source_url: `https://fdc.nal.usda.gov/food-details/${food.fdcId}`,
        source_ref: String(food.fdcId),
      };
    });
  } catch {
    return [];
  }
}

export async function handleFoods(
  req: Request,
  parts: string[],
  user: AuthUser,
  body: Record<string, unknown>,
): Promise<Response> {
  const method = req.method.toUpperCase();
  const url = new URL(req.url);

  // GET /foods/search?q=
  if (method === "GET" && parts[1] === "search") {
    const q = (url.searchParams.get("q") ?? url.searchParams.get("query") ?? "").trim();
    if (!q) return err(req, 400, "missing_query", "error.foods.missing_query");

    const local = await rpc<Record<string, unknown>[]>("search_foods", {
      query: q,
      match_count: 20,
    });
    const usda = await usdaSearch(q);
    return ok(req, {
      results: [...(local.data ?? []), ...usda],
      query: q,
    });
  }

  // GET /foods/recent
  if (method === "GET" && parts[1] === "recent") {
    const meals = await db(
      `meal_logs?user_id=eq.${user.id}&select=items,logged_at&order=logged_at.desc&limit=20`,
    );
    const rows = meals.ok ? await meals.json() : [];
    const seen = new Set<string>();
    const recent: unknown[] = [];
    for (const m of rows) {
      for (const it of m.items ?? []) {
        const name = String(it.name ?? "");
        if (!name || seen.has(name)) continue;
        seen.add(name);
        recent.push(it);
        if (recent.length >= 20) break;
      }
      if (recent.length >= 20) break;
    }
    return ok(req, { foods: recent });
  }

  // GET /foods/{id}
  if (method === "GET" && parts[1] && parts[1] !== "search" && parts[1] !== "recent") {
    const id = parts[1];
    if (id.startsWith("fdc:")) {
      return ok(req, { food: { id, source: "USDA FoodData Central", note: "provider_ref" } });
    }
    const res = await db(`foods?id=eq.${id}&select=*`);
    const rows = res.ok ? await res.json() : [];
    if (!rows[0]) return err(req, 404, "food_not_found", "error.foods.not_found");
    return ok(req, { food: rows[0] });
  }

  // POST /product-label-drafts
  if (method === "POST" && parts[0] === "product-label-drafts" && parts.length === 1) {
    const row = {
      user_id: user.id,
      media_id: body.media_id ?? null,
      parsed: body.parsed ?? {},
      status: "draft",
    };
    const res = await db("product_label_drafts", { method: "POST", body: JSON.stringify(row) });
    if (!res.ok) return err(req, 500, "label_draft_failed", "error.foods.label_draft_failed");
    return ok(req, { draft: (await res.json())[0] }, 201);
  }

  // POST /product-label-drafts/{id}/confirm  — routed via parts[0]
  if (method === "POST" && parts[0] === "product-label-drafts" && parts[2] === "confirm") {
    const id = parts[1];
    const res = await db(`product_label_drafts?id=eq.${id}&user_id=eq.${user.id}`, {
      method: "PATCH",
      body: JSON.stringify({
        status: "confirmed",
        confirmed_at: new Date().toISOString(),
        parsed: body.parsed ?? undefined,
      }),
    });
    if (!res.ok) return err(req, 404, "draft_not_found", "error.foods.draft_not_found");
    return ok(req, { draft: (await res.json())[0] });
  }

  // POST /food-corrections
  if (method === "POST" && parts[0] === "food-corrections") {
    const row = {
      user_id: user.id,
      food_id: body.food_id ?? null,
      meal_log_id: body.meal_log_id ?? null,
      proposed: body.proposed ?? body,
      status: "queued",
    };
    const res = await db("food_corrections", { method: "POST", body: JSON.stringify(row) });
    if (!res.ok) return err(req, 500, "correction_failed", "error.foods.correction_failed");
    return ok(req, { correction: (await res.json())[0] }, 201);
  }

  return err(req, 404, "not_found", "error.not_found");
}

export async function handleBarcodes(
  req: Request,
  parts: string[],
  _user: AuthUser,
): Promise<Response> {
  if (req.method.toUpperCase() !== "GET" || !parts[1]) {
    return err(req, 404, "not_found", "error.not_found");
  }
  const gtin = parts[1].replace(/\D/g, "");
  if (gtin.length < 8) {
    return err(req, 400, "invalid_gtin", "error.foods.invalid_gtin");
  }

  const cached = await db(`barcode_cache?gtin=eq.${gtin}&select=*`);
  if (cached.ok) {
    const rows = await cached.json();
    if (rows[0]) {
      return ok(req, { barcode: gtin, cached: true, product: rows[0].payload, food_id: rows[0].food_id });
    }
  }

  const product = await offBarcode(gtin);
  if (!product) {
    return err(req, 404, "barcode_not_found", "error.foods.barcode_not_found");
  }

  await db("barcode_cache", {
    method: "POST",
    headers: { Prefer: "resolution=merge-duplicates,return=minimal" },
    body: JSON.stringify({
      gtin,
      provider: "open_food_facts",
      payload: product,
    }),
  });

  return ok(req, { barcode: gtin, cached: false, product });
}
