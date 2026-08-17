import type { AuthUser } from "../_shared/auth.ts";
import { anonKey, serviceKey, supabaseUrl } from "../_shared/auth.ts";
import { db } from "../_shared/db.ts";
import { err, ok } from "../_shared/envelope.ts";

async function configMap(): Promise<Record<string, unknown>> {
  const res = await db("app_config?select=key,value");
  const rows = res.ok ? await res.json() : [];
  const out: Record<string, unknown> = {};
  for (const r of rows) out[r.key] = r.value;
  return out;
}

export async function handleBootstrap(req: Request, user: AuthUser | null): Promise<Response> {
  const cfg = await configMap();
  let profile = null;
  let entitlement: Record<string, unknown> = { tier: "free" };
  let wallet = { available_points: 0, lifetime_earned: 0 };

  if (user) {
    const [pRes, eRes, wRes] = await Promise.all([
      db(`profiles?user_id=eq.${user.id}&select=*`),
      db(`entitlements?user_id=eq.${user.id}&select=*`),
      db(`wallet_accounts?user_id=eq.${user.id}&select=available_points,lifetime_earned`),
    ]);
    if (pRes.ok) profile = (await pRes.json())[0] ?? null;
    if (eRes.ok) entitlement = (await eRes.json())[0] ?? entitlement;
    if (wRes.ok) wallet = (await wRes.json())[0] ?? wallet;
  }

  return ok(req, {
    user: user
      ? { id: user.id, is_anonymous: !!user.is_anonymous, email: user.email ?? null }
      : null,
    profile,
    entitlement,
    wallet,
    config: {
      min_app_version: cfg.min_app_version ?? "0.9.0",
      flags: cfg.flags ?? {},
      quotas: cfg.quotas ?? {},
      wallet_ruleset: cfg.wallet_ruleset ?? {},
      journey_ruleset: cfg.journey_ruleset ?? {},
    },
    server_time: new Date().toISOString(),
  });
}

export async function handleConfig(req: Request): Promise<Response> {
  const cfg = await configMap();
  return ok(req, {
    min_app_version: cfg.min_app_version ?? "0.9.0",
    flags: cfg.flags ?? {},
    quotas: cfg.quotas ?? {},
    wallet_ruleset: cfg.wallet_ruleset ?? {},
    journey_ruleset: cfg.journey_ruleset ?? {},
  });
}

export async function handleAuth(
  req: Request,
  parts: string[],
  user: AuthUser | null,
  body: Record<string, unknown>,
): Promise<Response> {
  const method = req.method.toUpperCase();

  // POST /auth/anonymous — GoTrue anonymous grant, with admin fallback
  if (method === "POST" && parts[1] === "anonymous") {
    const result = await fetch(`${supabaseUrl()}/auth/v1/token?grant_type=anonymous`, {
      method: "POST",
      headers: {
        "Content-Type": "application/json",
        apikey: anonKey(),
        Authorization: `Bearer ${anonKey()}`,
      },
      body: JSON.stringify({}),
    });
    if (result.ok) return ok(req, await result.json(), 201);

    const admin = await fetch(`${supabaseUrl()}/auth/v1/admin/users`, {
      method: "POST",
      headers: {
        "Content-Type": "application/json",
        apikey: serviceKey(),
        Authorization: `Bearer ${serviceKey()}`,
      },
      body: JSON.stringify({
        email: `anon+${crypto.randomUUID()}@qamar.local`,
        email_confirm: true,
        user_metadata: { anonymous: true },
        app_metadata: { provider: "anonymous" },
      }),
    });
    if (!admin.ok) {
      return err(req, 502, "auth_anonymous_failed", "error.auth.anonymous_failed", {
        retryable: true,
      });
    }
    const created = await admin.json();
    return ok(
      req,
      {
        user: { id: created.id, is_anonymous: true },
        session: null,
        note: "use_supabase_anonymous_sdk",
      },
      201,
    );
  }

  // POST /auth/exchange/apple|google
  if (method === "POST" && parts[1] === "exchange" && parts[2]) {
    const provider = parts[2];
    if (provider !== "apple" && provider !== "google" && provider !== "facebook") {
      return err(req, 400, "unsupported_provider", "error.auth.unsupported_provider");
    }
    const idToken = String(body.id_token ?? body.identity_token ?? "");
    const nonce = body.nonce ? String(body.nonce) : undefined;
    if (!idToken) {
      return err(req, 400, "missing_id_token", "error.auth.missing_id_token", {
        field_errors: { id_token: "required" },
      });
    }
    const res = await fetch(`${supabaseUrl()}/auth/v1/token?grant_type=id_token`, {
      method: "POST",
      headers: { "Content-Type": "application/json", apikey: anonKey() },
      body: JSON.stringify({ provider, id_token: idToken, nonce }),
    });
    if (!res.ok) return err(req, 401, "exchange_failed", "error.auth.exchange_failed");
    return ok(req, await res.json());
  }

  // POST /auth/otp/start
  if (method === "POST" && parts[1] === "otp" && parts[2] === "start") {
    const email = String(body.email ?? "").trim().toLowerCase();
    if (!email || !email.includes("@")) {
      return err(req, 400, "invalid_email", "error.auth.invalid_email", {
        field_errors: { email: "invalid" },
      });
    }
    const res = await fetch(`${supabaseUrl()}/auth/v1/otp`, {
      method: "POST",
      headers: { "Content-Type": "application/json", apikey: anonKey() },
      body: JSON.stringify({ email, create_user: true }),
    });
    if (!res.ok) {
      return err(req, 429, "otp_start_failed", "error.auth.otp_start_failed", { retryable: true });
    }
    return ok(req, { sent: true, email });
  }

  // POST /auth/otp/verify
  if (method === "POST" && parts[1] === "otp" && parts[2] === "verify") {
    const email = String(body.email ?? "").trim().toLowerCase();
    const token = String(body.token ?? body.code ?? "");
    if (!email || !token) {
      return err(req, 400, "missing_fields", "error.auth.missing_otp_fields");
    }
    const res = await fetch(`${supabaseUrl()}/auth/v1/verify`, {
      method: "POST",
      headers: { "Content-Type": "application/json", apikey: anonKey() },
      body: JSON.stringify({ email, token, type: "email" }),
    });
    if (!res.ok) return err(req, 401, "otp_invalid", "error.auth.otp_invalid");
    return ok(req, await res.json());
  }

  // POST /auth/link
  if (method === "POST" && parts[1] === "link") {
    if (!user) return err(req, 401, "unauthorized", "error.unauthorized");
    const provider = String(body.provider ?? "");
    const idToken = String(body.id_token ?? "");
    if (!provider || !idToken) {
      return err(req, 400, "missing_fields", "error.auth.missing_link_fields");
    }
    const res = await fetch(`${supabaseUrl()}/auth/v1/user/identities/link`, {
      method: "POST",
      headers: {
        "Content-Type": "application/json",
        apikey: anonKey(),
        Authorization: req.headers.get("Authorization") ?? "",
      },
      body: JSON.stringify({ provider, id_token: idToken, nonce: body.nonce }),
    });
    if (!res.ok) {
      return err(req, 502, "link_failed", "error.auth.link_failed", { retryable: true });
    }
    return ok(req, await res.json());
  }

  // POST /auth/merge
  if (method === "POST" && parts[1] === "merge") {
    if (!user) return err(req, 401, "unauthorized", "error.unauthorized");
    const targetUserId = String(body.target_user_id ?? "");
    if (!targetUserId) {
      return err(req, 400, "missing_target", "error.auth.missing_merge_target");
    }
    await db("analytics_events", {
      method: "POST",
      headers: { Prefer: "return=minimal" },
      body: JSON.stringify({
        user_id: user.id,
        name: "auth_merge_requested",
        props: { target_user_id: targetUserId },
      }),
    });
    return ok(
      req,
      { status: "queued", from: user.id, to: targetUserId, message_key: "auth.merge.queued" },
      202,
    );
  }

  // GET /auth/sessions
  if (method === "GET" && parts[1] === "sessions") {
    if (!user) return err(req, 401, "unauthorized", "error.unauthorized");
    return ok(req, {
      sessions: [
        { user_id: user.id, is_anonymous: !!user.is_anonymous, email: user.email ?? null },
      ],
    });
  }

  // DELETE /auth/sessions
  if (method === "DELETE" && parts[1] === "sessions") {
    await fetch(`${supabaseUrl()}/auth/v1/logout`, {
      method: "POST",
      headers: {
        "Content-Type": "application/json",
        apikey: anonKey(),
        Authorization: req.headers.get("Authorization") ?? "",
      },
      body: JSON.stringify({ scope: "global" }),
    });
    return ok(req, { revoked: true });
  }

  return err(req, 404, "not_found", "error.not_found");
}
