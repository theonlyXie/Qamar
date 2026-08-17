import type { AuthUser } from "../_shared/auth.ts";
import { db, rpc } from "../_shared/db.ts";
import { err, ok } from "../_shared/envelope.ts";
import { idempotencyKey, loadIdempotent, storeIdempotent } from "../_shared/idempotency.ts";
import { isAdmin } from "../_shared/util.ts";

const EVENT_ALLOWLIST = new Set([
  "app_open",
  "onboarding_step",
  "onboarding_complete",
  "meal_confirm",
  "plan_view",
  "wallet_redeem",
  "paywall_view",
  "purchase_start",
  "purchase_success",
  "purchase_fail",
  "chat_open",
  "quest_complete",
  "auth_merge_requested",
  "reminder_toggled",
  "export_requested",
  "account_deletion_requested",
]);

export async function handleDevices(
  req: Request,
  parts: string[],
  user: AuthUser,
  body: Record<string, unknown>,
): Promise<Response> {
  const method = req.method.toUpperCase();

  if (method === "POST" && parts.length === 1) {
    const token = String(body.push_token ?? body.token ?? "");
    const platform = String(body.platform ?? "");
    if (!token || !["ios", "android", "web"].includes(platform)) {
      return err(req, 400, "invalid_device", "error.devices.invalid");
    }
    const row = {
      user_id: user.id,
      platform,
      push_token: token,
      locale: body.locale ?? "ar",
      timezone: body.timezone ?? null,
      last_seen_at: new Date().toISOString(),
    };
    const res = await db("devices?on_conflict=user_id,push_token", {
      method: "POST",
      headers: { Prefer: "resolution=merge-duplicates,return=representation" },
      body: JSON.stringify(row),
    });
    if (!res.ok) return err(req, 500, "device_write_failed", "error.devices.write_failed");
    return ok(req, { device: (await res.json())[0] }, 201);
  }

  if (method === "DELETE") {
    const token = String(body.push_token ?? body.token ?? parts[1] ?? "");
    if (!token) return err(req, 400, "missing_token", "error.devices.missing_token");
    await db(
      `devices?user_id=eq.${user.id}&push_token=eq.${encodeURIComponent(token)}`,
      { method: "DELETE", headers: { Prefer: "return=minimal" } },
    );
    return ok(req, { deleted: true });
  }

  return err(req, 404, "not_found", "error.not_found");
}

export async function handleReminders(
  req: Request,
  parts: string[],
  user: AuthUser,
  body: Record<string, unknown>,
): Promise<Response> {
  const method = req.method.toUpperCase();

  if (method === "GET" && parts.length === 1) {
    const res = await db(`reminders?user_id=eq.${user.id}&order=local_time.asc&select=*`);
    return ok(req, { reminders: res.ok ? await res.json() : [] });
  }

  if (method === "POST" && parts[1] === "test") {
    // Does not send a real push in MVP without FCM credentials; records intent.
    await db("analytics_events", {
      method: "POST",
      headers: { Prefer: "return=minimal" },
      body: JSON.stringify({
        user_id: user.id,
        name: "reminder_toggled",
        props: { test: true, reminder_id: body.reminder_id ?? null },
      }),
    });
    return ok(req, {
      sent: false,
      message_key: "reminders.test.recorded",
      note: "Push delivery requires FCM/APNs credentials; test event recorded.",
    });
  }

  if (method === "PATCH" && parts[1]) {
    const id = parts[1];
    const allowed = ["kind", "local_time", "days_of_week", "enabled", "template_id"];
    const patch: Record<string, unknown> = { updated_at: new Date().toISOString() };
    for (const k of allowed) if (k in body) patch[k] = body[k];
    const res = await db(`reminders?id=eq.${id}&user_id=eq.${user.id}`, {
      method: "PATCH",
      body: JSON.stringify(patch),
    });
    if (!res.ok) return err(req, 404, "reminder_not_found", "error.reminders.not_found");
    return ok(req, { reminder: (await res.json())[0] });
  }

  // POST create
  if (method === "POST" && parts.length === 1) {
    const row = {
      user_id: user.id,
      kind: String(body.kind ?? "meal"),
      local_time: String(body.local_time ?? "12:00"),
      days_of_week: body.days_of_week ?? [1, 2, 3, 4, 5, 6, 7],
      enabled: body.enabled !== false,
      template_id: body.template_id ?? "generic",
    };
    const res = await db("reminders", { method: "POST", body: JSON.stringify(row) });
    if (!res.ok) return err(req, 500, "reminder_write_failed", "error.reminders.write_failed");
    return ok(req, { reminder: (await res.json())[0] }, 201);
  }

  return err(req, 404, "not_found", "error.not_found");
}

export async function handlePrivacy(
  req: Request,
  parts: string[],
  user: AuthUser,
  body: Record<string, unknown>,
): Promise<Response> {
  const method = req.method.toUpperCase();

  // POST /exports
  if (method === "POST" && parts[0] === "exports" && parts.length === 1) {
    const key = idempotencyKey(req) ?? `export:${user.id}:${new Date().toISOString().slice(0, 10)}`;
    const prior = await loadIdempotent(user.id, "export", key);
    if (prior) return ok(req, prior.response_body, prior.response_status);

    const job = await db("data_exports", {
      method: "POST",
      body: JSON.stringify({ user_id: user.id, status: "queued" }),
    });
    if (!job.ok) return err(req, 500, "export_failed", "error.privacy.export_failed");
    const created = (await job.json())[0];

    // Build export payload synchronously for MVP (small accounts).
    const [profile, meals, weights, ledger, consents] = await Promise.all([
      db(`profiles?user_id=eq.${user.id}&select=*`),
      db(`meal_logs?user_id=eq.${user.id}&select=*`),
      db(`weight_entries?user_id=eq.${user.id}&select=*`),
      db(`su_point_ledger?user_id=eq.${user.id}&select=*`),
      db(`consents?user_id=eq.${user.id}&select=*`),
    ]);
    const exportBody = {
      exported_at: new Date().toISOString(),
      user_id: user.id,
      profile: profile.ok ? (await profile.json())[0] ?? null : null,
      meals: meals.ok ? await meals.json() : [],
      weights: weights.ok ? await weights.json() : [],
      ledger: ledger.ok ? await ledger.json() : [],
      consents: consents.ok ? await consents.json() : [],
    };
    const objectPath = `${user.id}/exports/${created.id}.json`;
    const expires = new Date(Date.now() + 48 * 3600e3).toISOString();
    await db(`data_exports?id=eq.${created.id}`, {
      method: "PATCH",
      headers: { Prefer: "return=minimal" },
      body: JSON.stringify({
        status: "ready",
        object_path: objectPath,
        ready_at: new Date().toISOString(),
        expires_at: expires,
      }),
    });

    const payload = {
      export: {
        id: created.id,
        status: "ready",
        expires_at: expires,
        // Inline for MVP when storage upload is unavailable; download URL follows.
        download: { inline: exportBody, object_path: objectPath },
      },
    };
    await storeIdempotent(user.id, "export", key, payload, 201, body);
    return ok(req, payload, 201);
  }

  // GET /exports/{id}
  if (method === "GET" && parts[0] === "exports" && parts[1]) {
    const res = await db(`data_exports?id=eq.${parts[1]}&user_id=eq.${user.id}&select=*`);
    const rows = res.ok ? await res.json() : [];
    if (!rows[0]) return err(req, 404, "export_not_found", "error.privacy.export_not_found");
    return ok(req, { export: rows[0] });
  }

  // DELETE /conversations/{id}
  if (method === "DELETE" && parts[0] === "conversations" && parts[1]) {
    await db(`chat_messages?conversation_id=eq.${parts[1]}&user_id=eq.${user.id}`, {
      method: "DELETE",
      headers: { Prefer: "return=minimal" },
    });
    await db(`chat_conversations?id=eq.${parts[1]}&user_id=eq.${user.id}`, {
      method: "DELETE",
      headers: { Prefer: "return=minimal" },
    });
    return ok(req, { deleted: true, conversation_id: parts[1] });
  }

  // POST /account-deletion
  if (method === "POST" && parts[0] === "account-deletion") {
    const key = idempotencyKey(req) ?? `account-deletion:${user.id}`;
    const prior = await loadIdempotent(user.id, "account_deletion", key);
    if (prior) return ok(req, prior.response_body, prior.response_status);

    const job = await db("account_deletion_jobs", {
      method: "POST",
      body: JSON.stringify({ user_id: user.id, status: "queued" }),
    });
    if (!job.ok) return err(req, 500, "deletion_failed", "error.privacy.deletion_failed");
    const created = (await job.json())[0];

    // Soft-delete profile data immediately; auth.users deletion requires admin API
    // and is completed by a follow-up job / founder ops.
    await db(`profiles?user_id=eq.${user.id}`, {
      method: "PATCH",
      headers: { Prefer: "return=minimal" },
      body: JSON.stringify({
        name: null,
        eligibility_status: "blocked_safety",
        updated_at: new Date().toISOString(),
      }),
    });
    await db("analytics_events", {
      method: "POST",
      headers: { Prefer: "return=minimal" },
      body: JSON.stringify({
        user_id: user.id,
        name: "account_deletion_requested",
        props: { job_id: created.id },
      }),
    });

    const payload = { job: created, status: "queued" };
    await storeIdempotent(user.id, "account_deletion", key, payload, 202, body);
    return ok(req, payload, 202);
  }

  return err(req, 404, "not_found", "error.not_found");
}

export async function handleAnalytics(
  req: Request,
  parts: string[],
  user: AuthUser | null,
  body: Record<string, unknown>,
): Promise<Response> {
  const method = req.method.toUpperCase();

  if (method === "POST" && parts[0] === "events" && parts[1] === "batch") {
    const events = (body.events as Record<string, unknown>[]) ?? [];
    const rows = [];
    for (const e of events.slice(0, 50)) {
      const name = String(e.name ?? "");
      if (!EVENT_ALLOWLIST.has(name)) continue;
      const props = (e.props as Record<string, unknown>) ?? {};
      // Strip anything that looks like free-text content
      const clean: Record<string, unknown> = {};
      for (const [k, v] of Object.entries(props)) {
        if (typeof v === "string" && v.length > 64) continue;
        if (["message", "text", "meal", "body", "email"].includes(k)) continue;
        clean[k] = v;
      }
      rows.push({
        user_id: user?.id ?? null,
        name,
        props: clean,
        client_ts: e.ts ?? e.client_ts ?? null,
      });
    }
    if (rows.length) {
      await db("analytics_events", {
        method: "POST",
        headers: { Prefer: "return=minimal" },
        body: JSON.stringify(rows),
      });
    }
    return ok(req, { accepted: rows.length, dropped: events.length - rows.length });
  }

  if (method === "POST" && parts[0] === "feedback") {
    if (!user) return err(req, 401, "unauthorized", "error.unauthorized");
    const text = String(body.body ?? body.message ?? "").trim();
    if (!text) return err(req, 400, "missing_body", "error.feedback.missing_body");
    const res = await db("feedback", {
      method: "POST",
      body: JSON.stringify({
        user_id: user.id,
        category: String(body.category ?? "general"),
        body: text.slice(0, 4000),
      }),
    });
    if (!res.ok) return err(req, 500, "feedback_failed", "error.feedback.write_failed");
    return ok(req, { feedback: (await res.json())[0] }, 201);
  }

  if (method === "GET" && parts[0] === "support-code") {
    if (!user) return err(req, 401, "unauthorized", "error.unauthorized");
    const result = await rpc<string>("qamar_support_code", { uid: user.id });
    const code = typeof result.data === "string"
      ? result.data
      : `Q-${user.id.replace(/-/g, "").slice(0, 8).toUpperCase()}`;
    return ok(req, { support_code: code });
  }

  return err(req, 404, "not_found", "error.not_found");
}

export async function handleAdmin(
  req: Request,
  parts: string[],
  user: AuthUser,
  body: Record<string, unknown>,
): Promise<Response> {
  if (!(await isAdmin(user.id))) {
    return err(req, 403, "forbidden", "error.admin.forbidden");
  }

  const method = req.method.toUpperCase();
  const resource = parts[1]; // config | nutrition-sources | ...

  if (method === "GET" && resource === "config") {
    const res = await db("app_config?select=*");
    return ok(req, { config: res.ok ? await res.json() : [] });
  }

  if (method === "PATCH" && resource === "config") {
    const key = String(body.key ?? parts[2] ?? "");
    if (!key || body.value === undefined) {
      return err(req, 400, "missing_fields", "error.admin.missing_fields");
    }
    const res = await db("app_config?on_conflict=key", {
      method: "POST",
      headers: { Prefer: "resolution=merge-duplicates,return=representation" },
      body: JSON.stringify({
        key,
        value: body.value,
        updated_at: new Date().toISOString(),
        updated_by: user.id,
      }),
    });
    if (!res.ok) return err(req, 500, "config_write_failed", "error.admin.config_failed");
    return ok(req, { config: (await res.json())[0] });
  }

  if (resource === "nutrition-sources") {
    if (method === "GET") {
      const res = await db("kb_documents?select=*&order=retrieved_at.desc&limit=100");
      return ok(req, { documents: res.ok ? await res.json() : [] });
    }
  }

  if (resource === "corrections") {
    if (method === "GET") {
      const res = await db(
        "food_corrections?status=eq.queued&order=created_at.asc&limit=100&select=*",
      );
      return ok(req, { corrections: res.ok ? await res.json() : [] });
    }
    if (method === "PATCH" && parts[2]) {
      const res = await db(`food_corrections?id=eq.${parts[2]}`, {
        method: "PATCH",
        body: JSON.stringify({
          status: body.status ?? "approved",
          reviewed_at: new Date().toISOString(),
        }),
      });
      if (!res.ok) return err(req, 404, "not_found", "error.not_found");
      return ok(req, { correction: (await res.json())[0] });
    }
  }

  if (resource === "billing" && method === "GET") {
    const res = await db("billing_events?order=created_at.desc&limit=50&select=*");
    return ok(req, { events: res.ok ? await res.json() : [] });
  }

  if (resource === "usage" && method === "GET") {
    const res = await db("rate_limits?order=day.desc&limit=100&select=*");
    return ok(req, { rate_limits: res.ok ? await res.json() : [] });
  }

  if (resource === "safety" && method === "GET") {
    const res = await db(
      "ai_interactions?in_scope=eq.false&order=created_at.desc&limit=50&select=*",
    );
    return ok(req, { refusals: res.ok ? await res.json() : [] });
  }

  if (resource === "evals" && method === "GET") {
    return ok(req, {
      evals: [],
      message_key: "admin.evals.empty",
      note: "Eval harness results are published here once the bakeoff runner lands.",
    });
  }

  if (resource === "target-policies") {
    if (method === "GET") {
      return ok(req, {
        policies: [{ id: "calc_v2", formula_version: "calc v2.0", active: true }],
      });
    }
  }

  if (resource === "provider-routing") {
    if (method === "GET") {
      return ok(req, {
        routing: {
          chat: "anthropic",
          meal_vision: "anthropic",
          embeddings: Deno.env.get("VOYAGE_API_KEY") ? "voyage" : "openai",
          barcode: "open_food_facts",
          generic_food: Deno.env.get("USDA_API_KEY") ? "usda" : "open_food_facts",
        },
      });
    }
    if (method === "PATCH") {
      await db("app_config?on_conflict=key", {
        method: "POST",
        headers: { Prefer: "resolution=merge-duplicates,return=minimal" },
        body: JSON.stringify({
          key: "provider_routing",
          value: body,
          updated_at: new Date().toISOString(),
          updated_by: user.id,
        }),
      });
      return ok(req, { routing: body });
    }
  }

  return err(req, 404, "not_found", "error.not_found");
}
