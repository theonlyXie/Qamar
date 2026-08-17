import type { AuthUser } from "../_shared/auth.ts";
import { serviceKey, supabaseUrl } from "../_shared/auth.ts";
import { db } from "../_shared/db.ts";
import { err, ok } from "../_shared/envelope.ts";
import { idempotencyKey, loadIdempotent, storeIdempotent } from "../_shared/idempotency.ts";

const MAX_BYTES = 10 * 1024 * 1024;
const ALLOWED_MIME = new Set([
  "image/jpeg",
  "image/png",
  "image/webp",
  "image/gif",
  "audio/mp4",
  "audio/mpeg",
  "audio/wav",
  "audio/webm",
]);

export async function handleMedia(
  req: Request,
  parts: string[],
  user: AuthUser,
  body: Record<string, unknown>,
): Promise<Response> {
  if (req.method.toUpperCase() !== "POST" || parts[1] !== "upload-url") {
    return err(req, 404, "not_found", "error.not_found");
  }
  const mime = String(body.mime_type ?? "");
  const byteSize = Number(body.byte_size ?? 0);
  const purpose = String(body.purpose ?? "meal_photo");
  if (!ALLOWED_MIME.has(mime)) {
    return err(req, 400, "unsupported_mime", "error.media.unsupported_mime");
  }
  if (!byteSize || byteSize > MAX_BYTES) {
    return err(req, 400, "invalid_size", "error.media.invalid_size");
  }

  const id = crypto.randomUUID();
  const ext = mime.split("/")[1]?.replace("jpeg", "jpg") ?? "bin";
  const objectPath = `${user.id}/${purpose}/${id}.${ext}`;

  const meta = await db("media_objects", {
    method: "POST",
    body: JSON.stringify({
      id,
      user_id: user.id,
      bucket: "private-media",
      object_path: objectPath,
      mime_type: mime,
      byte_size: byteSize,
      purpose,
    }),
  });
  if (!meta.ok) {
    return err(req, 500, "media_meta_failed", "error.media.meta_failed");
  }

  const sign = await fetch(
    `${supabaseUrl()}/storage/v1/object/upload/sign/private-media/${objectPath}`,
    {
      method: "POST",
      headers: {
        "Content-Type": "application/json",
        apikey: serviceKey(),
        Authorization: `Bearer ${serviceKey()}`,
      },
      body: JSON.stringify({}),
    },
  );

  let uploadUrl: string | null = null;
  if (sign.ok) {
    const signed = await sign.json();
    uploadUrl = signed.url
      ? `${supabaseUrl()}/storage/v1${signed.url}`
      : signed.signedUrl ?? null;
  }

  if (!uploadUrl) {
    uploadUrl = `${supabaseUrl()}/storage/v1/object/private-media/${objectPath}`;
  }

  return ok(req, {
    media_id: id,
    bucket: "private-media",
    object_path: objectPath,
    upload_url: uploadUrl,
    expires_in_seconds: 600,
    headers: { "Content-Type": mime, "x-upsert": "true" },
  }, 201);
}

export async function handleMealDrafts(
  req: Request,
  parts: string[],
  user: AuthUser,
  body: Record<string, unknown>,
): Promise<Response> {
  const method = req.method.toUpperCase();

  // POST /meal-drafts
  if (method === "POST" && parts.length === 1) {
    const inputType = String(body.input_type ?? body.inputType ?? "text");
    const items = body.candidate_items ?? body.items ?? [];
    const row = {
      user_id: user.id,
      input_type: inputType,
      candidate_items: items,
      raw_text: body.raw_text ?? body.text ?? null,
      media_path: body.media_path ?? null,
    };
    const res = await db("meal_drafts", { method: "POST", body: JSON.stringify(row) });
    if (!res.ok) return err(req, 500, "draft_create_failed", "error.meals.draft_failed");
    return ok(req, { draft: (await res.json())[0] }, 201);
  }

  const draftId = parts[1];
  if (!draftId) return err(req, 404, "not_found", "error.not_found");

  // POST /meal-drafts/{id}/parse — re-normalize candidate items (deterministic stub)
  if (method === "POST" && parts[2] === "parse") {
    const dRes = await db(`meal_drafts?id=eq.${draftId}&user_id=eq.${user.id}&select=*`);
    const drafts = dRes.ok ? await dRes.json() : [];
    if (!drafts[0]) return err(req, 404, "draft_not_found", "error.meals.draft_not_found");
    const items = (drafts[0].candidate_items as unknown[]).map((it) => {
      const row = it as Record<string, unknown>;
      return {
        ...row,
        kcal: Math.round(Number(row.kcal ?? 0)),
        protein_g: Math.round(Number(row.protein_g ?? 0)),
        carbs_g: Math.round(Number(row.carbs_g ?? 0)),
        fat_g: Math.round(Number(row.fat_g ?? 0)),
        qty: Number(row.qty ?? 1),
      };
    });
    await db(`meal_drafts?id=eq.${draftId}`, {
      method: "PATCH",
      headers: { Prefer: "return=minimal" },
      body: JSON.stringify({ candidate_items: items }),
    });
    return ok(req, { draft_id: draftId, candidate_items: items });
  }

  // POST /meal-drafts/{id}/clarify
  if (method === "POST" && parts[2] === "clarify") {
    const answer = body.answer ?? body.clarification;
    if (answer == null) {
      return ok(req, {
        question: "How large was the portion relative to your palm?",
        options: ["small", "medium", "large"],
      });
    }
    const dRes = await db(`meal_drafts?id=eq.${draftId}&user_id=eq.${user.id}&select=*`);
    const drafts = dRes.ok ? await dRes.json() : [];
    if (!drafts[0]) return err(req, 404, "draft_not_found", "error.meals.draft_not_found");
    const factor = String(answer) === "small" ? 0.7 : String(answer) === "large" ? 1.3 : 1;
    const items = (drafts[0].candidate_items as Record<string, unknown>[]).map((it) => ({
      ...it,
      kcal: Math.round(Number(it.kcal ?? 0) * factor),
      protein_g: Math.round(Number(it.protein_g ?? 0) * factor),
      carbs_g: Math.round(Number(it.carbs_g ?? 0) * factor),
      fat_g: Math.round(Number(it.fat_g ?? 0) * factor),
    }));
    await db(`meal_drafts?id=eq.${draftId}`, {
      method: "PATCH",
      headers: { Prefer: "return=minimal" },
      body: JSON.stringify({ candidate_items: items }),
    });
    return ok(req, { draft_id: draftId, candidate_items: items, clarification: answer });
  }

  // POST /meal-drafts/{id}/confirm
  if (method === "POST" && parts[2] === "confirm") {
    const key = idempotencyKey(req) ?? `meal-confirm:${draftId}`;
    const prior = await loadIdempotent(user.id, "meal_confirm", key);
    if (prior) return ok(req, prior.response_body, prior.response_status);

    const dRes = await db(`meal_drafts?id=eq.${draftId}&user_id=eq.${user.id}&select=*`);
    const drafts = dRes.ok ? await dRes.json() : [];
    if (!drafts[0]) return err(req, 404, "draft_not_found", "error.meals.draft_not_found");

    const items = (body.items as unknown[]) ?? drafts[0].candidate_items;
    const list = items as Record<string, unknown>[];
    const kcal = list.reduce((s, i) => s + Number(i.kcal ?? 0) * Number(i.qty ?? 1), 0);
    const protein_g = list.reduce((s, i) => s + Number(i.protein_g ?? 0) * Number(i.qty ?? 1), 0);
    const carbs_g = list.reduce((s, i) => s + Number(i.carbs_g ?? 0) * Number(i.qty ?? 1), 0);
    const fat_g = list.reduce((s, i) => s + Number(i.fat_g ?? 0) * Number(i.qty ?? 1), 0);
    const name = String(body.name ?? list.map((i) => i.name).filter(Boolean).join(" · ") ?? "Meal");

    const log = {
      user_id: user.id,
      draft_id: draftId,
      name,
      source: String(body.source ?? `${drafts[0].input_type} · confirmed`),
      items: list,
      kcal: Math.round(kcal),
      protein_g: Math.round(protein_g),
      carbs_g: Math.round(carbs_g),
      fat_g: Math.round(fat_g),
      logged_at: body.logged_at ?? new Date().toISOString(),
    };
    const res = await db("meal_logs", { method: "POST", body: JSON.stringify(log) });
    if (!res.ok) return err(req, 500, "meal_confirm_failed", "error.meals.confirm_failed");
    const meal = (await res.json())[0];
    const payload = { meal };
    await storeIdempotent(user.id, "meal_confirm", key, payload, 201, body);
    return ok(req, payload, 201);
  }

  return err(req, 404, "not_found", "error.not_found");
}

export async function handleMeals(
  req: Request,
  parts: string[],
  user: AuthUser,
  body: Record<string, unknown>,
): Promise<Response> {
  const method = req.method.toUpperCase();
  const mealId = parts[1];
  if (!mealId) return err(req, 404, "not_found", "error.not_found");

  if (method === "GET") {
    const res = await db(`meal_logs?id=eq.${mealId}&user_id=eq.${user.id}&select=*`);
    const rows = res.ok ? await res.json() : [];
    if (!rows[0]) return err(req, 404, "meal_not_found", "error.meals.not_found");
    return ok(req, { meal: rows[0] });
  }

  if (method === "PATCH") {
    const allowed = ["name", "items", "kcal", "protein_g", "carbs_g", "fat_g", "logged_at"];
    const patch: Record<string, unknown> = {};
    for (const k of allowed) if (k in body) patch[k] = body[k];
    const res = await db(`meal_logs?id=eq.${mealId}&user_id=eq.${user.id}`, {
      method: "PATCH",
      body: JSON.stringify(patch),
    });
    if (!res.ok) return err(req, 404, "meal_not_found", "error.meals.not_found");
    return ok(req, { meal: (await res.json())[0] });
  }

  if (method === "DELETE") {
    const res = await db(`meal_logs?id=eq.${mealId}&user_id=eq.${user.id}`, {
      method: "DELETE",
      headers: { Prefer: "return=minimal" },
    });
    if (!res.ok) return err(req, 404, "meal_not_found", "error.meals.not_found");
    return ok(req, { deleted: true, id: mealId });
  }

  return err(req, 405, "method_not_allowed", "error.method_not_allowed");
}
