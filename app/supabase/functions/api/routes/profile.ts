import type { AuthUser } from "../_shared/auth.ts";
import { db } from "../_shared/db.ts";
import { err, ok } from "../_shared/envelope.ts";
import { idempotencyKey, loadIdempotent, storeIdempotent } from "../_shared/idempotency.ts";
import { calculateTarget, type TargetInputs } from "../_shared/targets.ts";

export async function handleConsents(
  req: Request,
  parts: string[],
  user: AuthUser,
  body: Record<string, unknown>,
): Promise<Response> {
  const method = req.method.toUpperCase();

  if (method === "GET" && parts[1] === "current") {
    const res = await db(
      `consents?user_id=eq.${user.id}&order=created_at.desc&select=*`,
    );
    const rows = res.ok ? await res.json() : [];
    const current: Record<string, unknown> = {};
    for (const r of rows) {
      if (!current[r.type]) current[r.type] = r;
    }
    return ok(req, { consents: Object.values(current) });
  }

  if (method === "POST" && parts.length === 1) {
    const type = String(body.type ?? "");
    const version = String(body.version ?? "");
    const granted = body.granted !== false;
    if (!type || !version) {
      return err(req, 400, "missing_fields", "error.consents.missing_fields");
    }
    if (type !== "processing_required" && type !== "improve_optional") {
      return err(req, 400, "invalid_type", "error.consents.invalid_type");
    }
    const row = {
      user_id: user.id,
      type,
      version,
      granted_at: granted ? new Date().toISOString() : null,
      withdrawn_at: granted ? null : new Date().toISOString(),
    };
    const res = await db("consents", { method: "POST", body: JSON.stringify(row) });
    if (!res.ok) return err(req, 500, "consent_write_failed", "error.consents.write_failed");
    return ok(req, (await res.json())[0], 201);
  }

  return err(req, 404, "not_found", "error.not_found");
}

export async function handleProfile(
  req: Request,
  parts: string[],
  user: AuthUser,
  body: Record<string, unknown>,
): Promise<Response> {
  const method = req.method.toUpperCase();

  if (method === "GET" && parts.length === 1) {
    const res = await db(`profiles?user_id=eq.${user.id}&select=*`);
    const rows = res.ok ? await res.json() : [];
    return ok(req, { profile: rows[0] ?? null });
  }

  if (method === "PATCH" && parts.length === 1) {
    const allowed = [
      "name", "locale", "birth_date", "gender", "height_cm", "weight_kg",
      "body_fat_pct", "goal", "activity_factor", "food_exclusions", "eligibility_status",
    ];
    const patch: Record<string, unknown> = { updated_at: new Date().toISOString() };
    for (const k of allowed) {
      if (k in body) patch[k] = body[k];
    }
    // Upsert so first save works without a prior row
    const existing = await db(`profiles?user_id=eq.${user.id}&select=user_id`);
    const rows = existing.ok ? await existing.json() : [];
    let res: Response;
    if (rows.length === 0) {
      res = await db("profiles", {
        method: "POST",
        body: JSON.stringify({ user_id: user.id, ...patch }),
      });
    } else {
      res = await db(`profiles?user_id=eq.${user.id}`, {
        method: "PATCH",
        body: JSON.stringify(patch),
      });
    }
    if (!res.ok) return err(req, 500, "profile_write_failed", "error.profile.write_failed");
    const out = await res.json();
    return ok(req, { profile: Array.isArray(out) ? out[0] : out });
  }

  return err(req, 404, "not_found", "error.not_found");
}

export async function handleTargets(
  req: Request,
  parts: string[],
  user: AuthUser,
  body: Record<string, unknown>,
): Promise<Response> {
  const method = req.method.toUpperCase();

  if (method === "POST" && parts[1] === "calculate") {
    const inputs = body as unknown as TargetInputs;
    if (!inputs.birth_date || !inputs.gender || !inputs.height_cm || !inputs.weight_kg) {
      return err(req, 400, "missing_inputs", "error.targets.missing_inputs");
    }
    const result = calculateTarget({
      birth_date: String(inputs.birth_date),
      gender: inputs.gender,
      height_cm: Number(inputs.height_cm),
      weight_kg: Number(inputs.weight_kg),
      activity_factor: Number(inputs.activity_factor ?? 1.55),
      goal: (inputs.goal as TargetInputs["goal"]) ?? "maintain",
    });
    return ok(req, { draft: result });
  }

  if (method === "POST" && parts[2] === "confirm") {
    const targetId = parts[1];
    const key = idempotencyKey(req);
    const prior = await loadIdempotent(user.id, "target_confirm", key);
    if (prior) {
      return ok(req, prior.response_body, prior.response_status);
    }

    // If targetId is "new", create from body; else stamp confirmed_at
    if (targetId === "new") {
      const draft = body.draft as Record<string, unknown> | undefined;
      if (!draft?.kcal) {
        return err(req, 400, "missing_draft", "error.targets.missing_draft");
      }
      const row = {
        user_id: user.id,
        kcal: draft.kcal,
        protein_g: draft.protein_g,
        carbs_g: draft.carbs_g,
        fat_g: draft.fat_g,
        formula_version: draft.formula_version ?? "calc v2.0",
        inputs: draft.inputs ?? {},
        confirmed_at: new Date().toISOString(),
      };
      // Close previous targets
      await db(`targets?user_id=eq.${user.id}&valid_to=is.null`, {
        method: "PATCH",
        headers: { Prefer: "return=minimal" },
        body: JSON.stringify({ valid_to: new Date().toISOString() }),
      });
      const res = await db("targets", { method: "POST", body: JSON.stringify(row) });
      if (!res.ok) return err(req, 500, "target_confirm_failed", "error.targets.confirm_failed");
      const saved = (await res.json())[0];
      const payload = { target: saved };
      if (key) await storeIdempotent(user.id, "target_confirm", key, payload, 201, body);
      return ok(req, payload, 201);
    }

    const res = await db(`targets?id=eq.${targetId}&user_id=eq.${user.id}`, {
      method: "PATCH",
      body: JSON.stringify({ confirmed_at: new Date().toISOString() }),
    });
    if (!res.ok) return err(req, 404, "target_not_found", "error.targets.not_found");
    const saved = (await res.json())[0];
    const payload = { target: saved };
    if (key) await storeIdempotent(user.id, "target_confirm", key, payload, 200, body);
    return ok(req, payload);
  }

  return err(req, 404, "not_found", "error.not_found");
}

export async function handleGuidance(
  req: Request,
  parts: string[],
  user: AuthUser,
): Promise<Response> {
  if (req.method.toUpperCase() !== "GET") {
    return err(req, 405, "method_not_allowed", "error.method_not_allowed");
  }

  if (parts[1] === "sources" && parts[2]) {
    const claimId = parts[2];
    const claimRes = await db(`guidance_claims?id=eq.${encodeURIComponent(claimId)}&select=*`);
    const claims = claimRes.ok ? await claimRes.json() : [];
    if (!claims[0]) return err(req, 404, "claim_not_found", "error.guidance.not_found");

    const sourceIds: string[] = claims[0].source_ids ?? [];
    let documents: unknown[] = [];
    if (sourceIds.length > 0) {
      const ids = sourceIds.map((id) => `"${id}"`).join(",");
      const dRes = await db(`kb_documents?id=in.(${ids})&select=id,source,title,url,licence,domain`);
      documents = dRes.ok ? await dRes.json() : [];
    }
    return ok(req, { claim: claims[0], documents });
  }

  if (parts[1] === "why" && parts[2]) {
    const decisionId = parts[2];
    const tRes = await db(
      `decision_traces?id=eq.${decisionId}&user_id=eq.${user.id}&select=*`,
    );
    const traces = tRes.ok ? await tRes.json() : [];
    if (!traces[0]) return err(req, 404, "decision_not_found", "error.guidance.decision_not_found");
    const claimIds: string[] = traces[0].claim_ids ?? [];
    let claims: unknown[] = [];
    if (claimIds.length > 0) {
      const ids = claimIds.map((id) => `"${id}"`).join(",");
      const cRes = await db(`guidance_claims?id=in.(${ids})&select=*`);
      claims = cRes.ok ? await cRes.json() : [];
    }
    return ok(req, { decision: traces[0], claims });
  }

  return err(req, 404, "not_found", "error.not_found");
}
