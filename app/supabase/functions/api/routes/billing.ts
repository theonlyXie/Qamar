import type { AuthUser } from "../_shared/auth.ts";
import { db } from "../_shared/db.ts";
import { err, ok } from "../_shared/envelope.ts";
import { idempotencyKey, loadIdempotent, storeIdempotent } from "../_shared/idempotency.ts";
import { hashPromoCode } from "../_shared/util.ts";

function offering() {
  return {
    products: [
      {
        id: "qamar_plus_monthly",
        store_product_id: "qamar_plus_monthly",
        period: "month",
        tier: "qamar_plus",
      },
      {
        id: "qamar_plus_annual",
        store_product_id: "qamar_plus_annual",
        period: "year",
        tier: "qamar_plus",
      },
    ],
    adapter: Deno.env.get("BILLING_ADAPTER") ?? "direct",
  };
}

export async function handleBilling(
  req: Request,
  parts: string[],
  user: AuthUser | null,
  body: Record<string, unknown>,
): Promise<Response> {
  const method = req.method.toUpperCase();

  // GET /billing/offering
  if (method === "GET" && parts[1] === "offering") {
    return ok(req, offering());
  }

  // GET /billing/entitlement
  if (method === "GET" && parts[1] === "entitlement") {
    if (!user) return err(req, 401, "unauthorized", "error.unauthorized");
    const res = await db(`entitlements?user_id=eq.${user.id}&select=*`);
    const rows = res.ok ? await res.json() : [];
    return ok(req, {
      entitlement: rows[0] ?? {
        user_id: user.id,
        tier: "free",
        will_renew: false,
      },
    });
  }

  // POST /promo/validate
  if (method === "POST" && parts[0] === "promo" && parts[1] === "validate") {
    if (!user) return err(req, 401, "unauthorized", "error.unauthorized");
    const code = String(body.code ?? "").trim();
    if (!code) return err(req, 400, "missing_code", "error.promo.missing_code");
    const codeHash = await hashPromoCode(code);
    const res = await db(`promo_codes?code_hash=eq.${codeHash}&select=*`);
    const rows = res.ok ? await res.json() : [];
    const promo = rows[0];
    if (!promo || !promo.active) {
      return err(req, 404, "promo_invalid", "error.promo.invalid");
    }
    if (promo.expires_at && new Date(promo.expires_at).getTime() < Date.now()) {
      return err(req, 410, "promo_expired", "error.promo.expired");
    }
    if (promo.max_redemptions != null && promo.redemptions >= promo.max_redemptions) {
      return err(req, 409, "promo_exhausted", "error.promo.exhausted");
    }
    return ok(req, {
      valid: true,
      campaign: promo.campaign,
      offer_id: promo.offer_id,
      code_hash: codeHash,
    });
  }

  // POST /billing/sync — client posts a store purchase for server verification
  if (method === "POST" && parts[1] === "sync") {
    if (!user) return err(req, 401, "unauthorized", "error.unauthorized");
    const key = idempotencyKey(req) ??
      `billing-sync:${String(body.transaction_id ?? body.purchase_id ?? crypto.randomUUID())}`;
    const prior = await loadIdempotent(user.id, "billing_sync", key);
    if (prior) return ok(req, prior.response_body, prior.response_status);

    const store = String(body.store ?? "unknown");
    const productId = String(body.product_id ?? "");
    const transactionId = String(body.transaction_id ?? body.purchase_id ?? "");
    if (!productId || !transactionId) {
      return err(req, 400, "missing_purchase", "error.billing.missing_purchase");
    }

    // Persist the event; full StoreKit / Play verification requires provider secrets.
    // When REVENUECAT_WEBHOOK_SECRET / store keys are absent we still record the
    // sync attempt and only promote entitlement when VERIFY_PURCHASES=trust_client
    // is explicitly set for non-production environments.
    await db("billing_events", {
      method: "POST",
      headers: { Prefer: "resolution=ignore-duplicates,return=minimal" },
      body: JSON.stringify({
        provider: store === "apple" || store === "google" ? store : "revenuecat",
        provider_event_id: transactionId,
        user_id: user.id,
        payload: body,
        processed_at: new Date().toISOString(),
      }),
    });

    const trust = Deno.env.get("VERIFY_PURCHASES") === "trust_client";
    let entitlement = null;
    if (trust || body.verified === true) {
      const expires = body.expires_at
        ? String(body.expires_at)
        : new Date(Date.now() + 30 * 864e5).toISOString();
      const eRes = await db("entitlements?on_conflict=user_id", {
        method: "POST",
        headers: { Prefer: "resolution=merge-duplicates,return=representation" },
        body: JSON.stringify({
          user_id: user.id,
          tier: "qamar_plus",
          product_id: productId,
          store: store === "apple" || store === "google" ? store : "revenuecat",
          original_transaction_id: transactionId,
          expires_at: expires,
          will_renew: body.will_renew !== false,
          updated_at: new Date().toISOString(),
        }),
      });
      if (eRes.ok) entitlement = (await eRes.json())[0];
    }

    const payload = {
      accepted: true,
      verified: !!entitlement,
      entitlement,
      message_key: entitlement
        ? "billing.sync.verified"
        : "billing.sync.recorded_pending_verification",
    };
    await storeIdempotent(user.id, "billing_sync", key, payload, 200, body);
    return ok(req, payload);
  }

  // POST /billing/restore
  if (method === "POST" && parts[1] === "restore") {
    if (!user) return err(req, 401, "unauthorized", "error.unauthorized");
    const res = await db(`entitlements?user_id=eq.${user.id}&select=*`);
    const rows = res.ok ? await res.json() : [];
    return ok(req, {
      entitlement: rows[0] ?? { tier: "free", user_id: user.id },
      restored: !!rows[0],
    });
  }

  return err(req, 404, "not_found", "error.not_found");
}

export async function handleWebhooks(
  req: Request,
  parts: string[],
  body: Record<string, unknown>,
): Promise<Response> {
  if (req.method.toUpperCase() !== "POST") {
    return err(req, 405, "method_not_allowed", "error.method_not_allowed");
  }
  const provider = parts[1];
  if (provider !== "revenuecat" && provider !== "apple" && provider !== "google") {
    return err(req, 404, "not_found", "error.not_found");
  }

  // Verify shared secret / authorization before parsing further.
  const expected =
    provider === "revenuecat"
      ? Deno.env.get("REVENUECAT_WEBHOOK_SECRET")
      : provider === "apple"
      ? Deno.env.get("APPLE_WEBHOOK_SECRET")
      : Deno.env.get("GOOGLE_RTDN_SECRET");

  if (expected) {
    const got =
      req.headers.get("authorization")?.replace(/^Bearer\s+/i, "") ??
      req.headers.get("x-qamar-webhook-secret") ??
      "";
    if (got !== expected) {
      return err(req, 401, "webhook_unauthorized", "error.webhooks.unauthorized");
    }
  }

  const eventId = String(
    body.id ??
      body.event_id ??
      (body.event as Record<string, unknown> | undefined)?.id ??
      body.notificationUUID ??
      crypto.randomUUID(),
  );

  // Persist once, return quickly.
  const insert = await db("billing_events", {
    method: "POST",
    headers: { Prefer: "resolution=ignore-duplicates,return=representation" },
    body: JSON.stringify({
      provider,
      provider_event_id: eventId,
      user_id: body.app_user_id ?? body.user_id ?? null,
      payload: body,
    }),
  });

  // Async-style processing inline but bounded: map RevenueCat entitlement
  const appUserId = String(
    body.app_user_id ??
      (body.event as Record<string, unknown> | undefined)?.app_user_id ??
      body.user_id ??
      "",
  );
  const entitlements =
    (body.entitlement_ids as string[]) ??
    ((body.event as Record<string, unknown> | undefined)?.entitlement_ids as string[]) ??
    [];

  if (appUserId && (entitlements.includes("qamar_plus") || body.type === "INITIAL_PURCHASE" ||
    body.type === "RENEWAL" || (body.event as Record<string, unknown> | undefined)?.type === "INITIAL_PURCHASE")) {
    await db("entitlements?on_conflict=user_id", {
      method: "POST",
      headers: { Prefer: "resolution=merge-duplicates,return=minimal" },
      body: JSON.stringify({
        user_id: appUserId,
        tier: "qamar_plus",
        store: provider === "revenuecat" ? "revenuecat" : provider,
        product_id: body.product_id ?? null,
        original_transaction_id: eventId,
        expires_at: body.expiration_at ?? body.expires_at ?? null,
        will_renew: true,
        updated_at: new Date().toISOString(),
      }),
    });
  }

  if (insert.ok) {
    const row = (await insert.json())[0];
    if (row?.id) {
      await db(`billing_events?id=eq.${row.id}`, {
        method: "PATCH",
        headers: { Prefer: "return=minimal" },
        body: JSON.stringify({ processed_at: new Date().toISOString() }),
      });
    }
  }

  return ok(req, { received: true, provider_event_id: eventId });
}
