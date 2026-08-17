import type { AuthUser } from "../_shared/auth.ts";
import { db } from "../_shared/db.ts";
import { err, ok } from "../_shared/envelope.ts";
import { idempotencyKey, loadIdempotent, storeIdempotent } from "../_shared/idempotency.ts";

export async function handlePlans(
  req: Request,
  parts: string[],
  user: AuthUser,
  body: Record<string, unknown>,
): Promise<Response> {
  const method = req.method.toUpperCase();
  const url = new URL(req.url);

  // GET /plans?date=
  if (method === "GET" && parts.length === 1) {
    const date = url.searchParams.get("date");
    let path = `meal_plans?user_id=eq.${user.id}&order=plan_date.desc&limit=14&select=*`;
    if (date) path = `meal_plans?user_id=eq.${user.id}&plan_date=eq.${date}&select=*`;
    const res = await db(path);
    const rows = res.ok ? await res.json() : [];
    return ok(req, { plans: rows });
  }

  // POST /plans — create/upsert from client-provided meals (AI generation stays on ai-gateway)
  if (method === "POST" && parts.length === 1) {
    const key = idempotencyKey(req);
    const prior = await loadIdempotent(user.id, "plan_write", key);
    if (prior) return ok(req, prior.response_body, prior.response_status);

    const planDate = String(body.date ?? body.plan_date ?? new Date().toISOString().slice(0, 10));
    const row = {
      user_id: user.id,
      plan_date: planDate,
      meals: body.meals ?? [],
      target_kcal: Number(body.target_kcal ?? 0),
      rationale_ar: body.rationale_ar ?? null,
      rationale_en: body.rationale_en ?? null,
      sources: body.sources ?? [],
      version: 1,
    };
    if (!row.target_kcal) {
      return err(req, 400, "missing_target", "error.plans.missing_target");
    }
    const res = await db("meal_plans?on_conflict=user_id,plan_date", {
      method: "POST",
      headers: { Prefer: "resolution=merge-duplicates,return=representation" },
      body: JSON.stringify(row),
    });
    if (!res.ok) return err(req, 500, "plan_write_failed", "error.plans.write_failed");
    const plan = (await res.json())[0];
    const payload = { plan };
    if (key) await storeIdempotent(user.id, "plan_write", key, payload, 201, body);
    return ok(req, payload, 201);
  }

  const planId = parts[1];
  if (!planId) return err(req, 404, "not_found", "error.not_found");

  const loadPlan = async () => {
    const res = await db(`meal_plans?id=eq.${planId}&user_id=eq.${user.id}&select=*`);
    const rows = res.ok ? await res.json() : [];
    return rows[0] ?? null;
  };

  // POST /plans/{id}/substitute
  if (method === "POST" && parts[2] === "substitute") {
    const key = idempotencyKey(req);
    const prior = await loadIdempotent(user.id, "plan_sub", key);
    if (prior) return ok(req, prior.response_body, prior.response_status);

    const plan = await loadPlan();
    if (!plan) return err(req, 404, "plan_not_found", "error.plans.not_found");
    const expected = body.expected_version ?? plan.version;
    if (Number(expected) !== Number(plan.version)) {
      return err(req, 409, "version_conflict", "error.plans.version_conflict");
    }
    const slot = Number(body.slot ?? 0);
    const replacement = body.replacement ?? body.meal;
    const meals = [...(plan.meals as unknown[])];
    if (slot < 0 || slot >= meals.length || !replacement) {
      return err(req, 400, "invalid_substitute", "error.plans.invalid_substitute");
    }
    meals[slot] = replacement;
    const res = await db(`meal_plans?id=eq.${planId}`, {
      method: "PATCH",
      body: JSON.stringify({ meals, version: Number(plan.version) + 1 }),
    });
    if (!res.ok) return err(req, 500, "plan_write_failed", "error.plans.write_failed");
    const payload = { plan: (await res.json())[0] };
    if (key) await storeIdempotent(user.id, "plan_sub", key, payload, 200, body);
    return ok(req, payload);
  }

  // POST /plans/{id}/adjust
  if (method === "POST" && parts[2] === "adjust") {
    const key = idempotencyKey(req);
    const prior = await loadIdempotent(user.id, "plan_adj", key);
    if (prior) return ok(req, prior.response_body, prior.response_status);
    const plan = await loadPlan();
    if (!plan) return err(req, 404, "plan_not_found", "error.plans.not_found");
    const patch: Record<string, unknown> = { version: Number(plan.version) + 1 };
    if (body.meals) patch.meals = body.meals;
    if (body.target_kcal) patch.target_kcal = body.target_kcal;
    if (body.rationale_ar) patch.rationale_ar = body.rationale_ar;
    if (body.rationale_en) patch.rationale_en = body.rationale_en;
    const res = await db(`meal_plans?id=eq.${planId}`, {
      method: "PATCH",
      body: JSON.stringify(patch),
    });
    if (!res.ok) return err(req, 500, "plan_write_failed", "error.plans.write_failed");
    const payload = { plan: (await res.json())[0] };
    if (key) await storeIdempotent(user.id, "plan_adj", key, payload, 200, body);
    return ok(req, payload);
  }

  // POST /plans/{id}/mark-eaten
  if (method === "POST" && parts[2] === "mark-eaten") {
    const key = idempotencyKey(req) ?? `plan-eaten:${planId}:${body.slot ?? "all"}`;
    const prior = await loadIdempotent(user.id, "plan_eaten", key);
    if (prior) return ok(req, prior.response_body, prior.response_status);

    const plan = await loadPlan();
    if (!plan) return err(req, 404, "plan_not_found", "error.plans.not_found");
    const meals = plan.meals as Record<string, unknown>[];
    const slot = body.slot != null ? Number(body.slot) : null;
    const toLog = slot != null ? [meals[slot]].filter(Boolean) : meals;

    const created = [];
    for (const m of toLog) {
      const portions = (m.portions as Record<string, unknown>[]) ?? [];
      const kcal = portions.reduce((s, p) => s + Number(p.kcal ?? 0), 0) || Number(m.kcal ?? 0);
      const log = {
        user_id: user.id,
        name: String(m.name_en ?? m.name_ar ?? m.name ?? "Plan meal"),
        source: "plan · marked eaten",
        items: portions.length ? portions : [m],
        kcal: Math.round(kcal),
        protein_g: Math.round(Number(m.protein_g ?? 0)),
        carbs_g: Math.round(Number(m.carbs_g ?? 0)),
        fat_g: Math.round(Number(m.fat_g ?? 0)),
        logged_at: body.logged_at ?? new Date().toISOString(),
      };
      const res = await db("meal_logs", { method: "POST", body: JSON.stringify(log) });
      if (res.ok) created.push((await res.json())[0]);
    }
    const payload = { meals: created };
    await storeIdempotent(user.id, "plan_eaten", key, payload, 201, body);
    return ok(req, payload, 201);
  }

  return err(req, 404, "not_found", "error.not_found");
}

export async function handleProgress(
  req: Request,
  parts: string[],
  user: AuthUser,
  body: Record<string, unknown>,
): Promise<Response> {
  const method = req.method.toUpperCase();
  const url = new URL(req.url);

  if (method === "GET" && parts.length === 1) {
    const days = Math.min(Number(url.searchParams.get("days") ?? 7), 60);
    const since = new Date();
    since.setUTCDate(since.getUTCDate() - days);
    const meals = await db(
      `meal_logs?user_id=eq.${user.id}&logged_at=gte.${since.toISOString()}&select=kcal,protein_g,carbs_g,fat_g,logged_at&order=logged_at.asc`,
    );
    const weights = await db(
      `weight_entries?user_id=eq.${user.id}&measured_at=gte.${since.toISOString()}&select=*&order=measured_at.asc`,
    );
    const target = await db(
      `targets?user_id=eq.${user.id}&order=valid_from.desc&limit=1&select=*`,
    );
    return ok(req, {
      window_days: days,
      meals: meals.ok ? await meals.json() : [],
      weights: weights.ok ? await weights.json() : [],
      target: target.ok ? (await target.json())[0] ?? null : null,
    });
  }

  // weight CRUD under /progress/weight or /weight
  if (parts[1] === "weight" || parts[0] === "weight") {
    const weightParts = parts[0] === "weight" ? parts : parts.slice(1);
    if (method === "GET") {
      const res = await db(
        `weight_entries?user_id=eq.${user.id}&order=measured_at.desc&limit=60&select=*`,
      );
      return ok(req, { weights: res.ok ? await res.json() : [] });
    }
    if (method === "POST") {
      const kg = Number(body.value_kg ?? body.kg);
      if (!kg || kg < 30 || kg > 250) {
        return err(req, 400, "invalid_weight", "error.progress.invalid_weight");
      }
      const row = {
        user_id: user.id,
        value_kg: kg,
        measured_at: body.measured_at ?? new Date().toISOString(),
        source: body.source ?? "manual",
      };
      const res = await db("weight_entries", { method: "POST", body: JSON.stringify(row) });
      if (!res.ok) return err(req, 500, "weight_write_failed", "error.progress.weight_failed");
      return ok(req, { weight: (await res.json())[0] }, 201);
    }
    if ((method === "PATCH" || method === "DELETE") && weightParts[1]) {
      const id = weightParts[1];
      if (method === "DELETE") {
        await db(`weight_entries?id=eq.${id}&user_id=eq.${user.id}`, {
          method: "DELETE",
          headers: { Prefer: "return=minimal" },
        });
        return ok(req, { deleted: true });
      }
      const res = await db(`weight_entries?id=eq.${id}&user_id=eq.${user.id}`, {
        method: "PATCH",
        body: JSON.stringify({
          value_kg: body.value_kg ?? body.kg,
          measured_at: body.measured_at,
        }),
      });
      if (!res.ok) return err(req, 404, "weight_not_found", "error.progress.weight_not_found");
      return ok(req, { weight: (await res.json())[0] });
    }
  }

  return err(req, 404, "not_found", "error.not_found");
}

export async function handleInsights(
  req: Request,
  parts: string[],
  user: AuthUser,
  body: Record<string, unknown>,
): Promise<Response> {
  const method = req.method.toUpperCase();

  if (method === "GET" && parts.length === 1) {
    const res = await db(
      `insights?user_id=eq.${user.id}&order=created_at.desc&limit=20&select=*`,
    );
    return ok(req, { insights: res.ok ? await res.json() : [] });
  }

  if (method === "POST" && parts.length === 1) {
    const row = {
      user_id: user.id,
      title: String(body.title ?? ""),
      body: String(body.body ?? ""),
      evidence_ids: body.evidence_ids ?? [],
    };
    if (!row.title || !row.body) {
      return err(req, 400, "missing_fields", "error.insights.missing_fields");
    }
    const res = await db("insights", { method: "POST", body: JSON.stringify(row) });
    if (!res.ok) return err(req, 500, "insight_write_failed", "error.insights.write_failed");
    return ok(req, { insight: (await res.json())[0] }, 201);
  }

  if (method === "POST" && parts[2] === "action") {
    const id = parts[1];
    const res = await db(`insights?id=eq.${id}&user_id=eq.${user.id}`, {
      method: "PATCH",
      body: JSON.stringify({ action_taken: String(body.action ?? body.action_taken ?? "done") }),
    });
    if (!res.ok) return err(req, 404, "insight_not_found", "error.insights.not_found");
    return ok(req, { insight: (await res.json())[0] });
  }

  return err(req, 404, "not_found", "error.not_found");
}
