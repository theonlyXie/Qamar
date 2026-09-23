// Qamar+ billing. Paymob is the Egyptian payment gateway: EGP, cards,
// Meeza, and mobile wallets. The phone never holds a Paymob secret and never
// decides that someone has paid — Paymob posts a signed callback here.
//
// Routes:
//   POST /billing/quote          { plan, promo_code? }                 JWT
//   POST /billing/checkout       { plan, promo_code?, first_name? }    JWT
//   POST /billing/entitlement    {}                                    JWT
//   POST /billing/trial/start    {}                                    JWT
//   POST /billing/earned         {}   where the earned month stands       JWT
//   POST /billing/earned/claim   {}   grant it, once the threshold is met  JWT
//   POST /billing/affiliate      {}                                    JWT
//   POST /billing/affiliate/payout { amount_cents? }                   JWT
//   POST /billing/affiliate/clients {}  the professional's consenting clients, this week   JWT
//   POST /billing/webhook        Paymob transaction callback           HMAC
//
// Secrets:
//   PAYMOB_SECRET_KEY
//   PAYMOB_PUBLIC_KEY
//   PAYMOB_HMAC_SECRET
//   PAYMOB_INTEGRATION_IDS   comma-separated integration ids or names (card,wallet)
//   PAYMOB_BASE_URL          optional, defaults to https://accept.paymob.com

import { notYetEarnedMessage, type EarnedStatus } from "./earned.ts";
import { verifyPaymobHmac } from "./hmac.ts";
import { amountMatches, signedOrderId, txnObject, txnOutcome, type OrderRow } from "./webhook.ts";
import {
  MIN_PAYOUT_CENTS,
  PLANS,
  chooseSavedPromo,
  isPlanId,
  normalizePromoCode,
  quotePlus,
  savedProfessional,
  type PlanId,
  type Promo,
  type Quote,
} from "./pricing.ts";

const SUPABASE_URL = Deno.env.get("SUPABASE_URL")!;
const SERVICE_KEY = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!;
const PAYMOB_SECRET = Deno.env.get("PAYMOB_SECRET_KEY") ?? "";
const PAYMOB_PUBLIC = Deno.env.get("PAYMOB_PUBLIC_KEY") ?? "";
const PAYMOB_HMAC = Deno.env.get("PAYMOB_HMAC_SECRET") ?? "";
const PAYMOB_BASE = (Deno.env.get("PAYMOB_BASE_URL") ?? "https://accept.paymob.com").replace(/\/$/, "");

const CORS = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
};

function json(body: unknown, status = 200): Response {
  return new Response(JSON.stringify(body), {
    status,
    headers: { ...CORS, "Content-Type": "application/json" },
  });
}

function paymentMethods(): Array<number | string> {
  const raw = (Deno.env.get("PAYMOB_INTEGRATION_IDS") ?? "").split(",").map((s) => s.trim()).filter(Boolean);
  return raw.map((s) => (/^\d+$/.test(s) ? Number(s) : s));
}

async function authenticate(req: Request): Promise<{ id: string; email?: string } | null> {
  const auth = req.headers.get("Authorization");
  if (!auth?.startsWith("Bearer ")) return null;
  const res = await fetch(`${SUPABASE_URL}/auth/v1/user`, {
    headers: { Authorization: auth, apikey: SERVICE_KEY },
  });
  if (!res.ok) return null;
  const user = await res.json();
  if (!user?.id) return null;
  return { id: user.id as string, email: typeof user.email === "string" ? user.email : undefined };
}

async function db(path: string, init: RequestInit = {}): Promise<Response> {
  return await fetch(`${SUPABASE_URL}/rest/v1/${path}`, {
    ...init,
    headers: {
      "Content-Type": "application/json",
      apikey: SERVICE_KEY,
      Authorization: `Bearer ${SERVICE_KEY}`,
      Prefer: "return=representation",
      ...(init.headers ?? {}),
    },
  });
}

async function rpc(name: string, args: Record<string, unknown>): Promise<unknown> {
  const res = await db(`rpc/${name}`, { method: "POST", body: JSON.stringify(args) });
  if (!res.ok) throw new Error(`${name} failed: ${res.status} ${await res.text()}`);
  return await res.json();
}

function configured(): string | null {
  if (!PAYMOB_SECRET || !PAYMOB_PUBLIC) return "Paymob keys are not set";
  if (paymentMethods().length === 0) return "Paymob integration IDs are not set";
  return null;
}

function quoteJson(q: Quote) {
  return {
    plan: q.plan,
    days: q.days,
    list_cents: q.listCents,
    amount_cents: q.amountCents,
    currency: "EGP",
    pricing_reason: q.pricingReason,
    first_purchase: q.firstPurchase,
    promo_code: q.promoCode,
    promo_kind: q.promoKind,
    affiliate_commission_cents: q.affiliateCommissionCents,
    promo_note: q.promoNote,
    promo_error: q.promoError,
  };
}

async function firstPurchase(userId: string): Promise<boolean> {
  const paid = await rpc("qamar_has_paid_plus", { p_user_id: userId });
  return paid !== true;
}

async function loadPromo(code: string): Promise<Promo | null> {
  const res = await db(`promo_codes?code=eq.${encodeURIComponent(code)}&select=*`);
  if (!res.ok) return null;
  const rows = await res.json() as Array<Record<string, unknown>>;
  const row = Array.isArray(rows) ? rows[0] : null;
  if (!row) return null;
  const kind = row.kind === "campaign" ? "campaign" : row.kind === "affiliate" ? "affiliate" : null;
  if (!kind) return null;
  const plansRaw = row.applies_to_plans;
  const applies = Array.isArray(plansRaw)
    ? plansRaw.filter((p): p is PlanId => typeof p === "string" && isPlanId(p))
    : null;
  return {
    id: typeof row.id === "string" ? row.id : undefined,
    code: String(row.code),
    kind,
    ownerUserId: typeof row.owner_user_id === "string" ? row.owner_user_id : null,
    percentOff: typeof row.percent_off === "number" ? row.percent_off : null,
    amountCents: typeof row.amount_cents === "number" ? row.amount_cents : null,
    appliesToPlans: applies && applies.length > 0 ? applies : null,
    active: row.active !== false,
    startsAt: typeof row.starts_at === "string" ? new Date(row.starts_at) : null,
    endsAt: typeof row.ends_at === "string" ? new Date(row.ends_at) : null,
    maxRedemptions: typeof row.max_redemptions === "number" ? row.max_redemptions : null,
    redemptionCount: typeof row.redemption_count === "number" ? row.redemption_count : 0,
  };
}

/**
 * The professional this client was referred by, if the referral is still
 * inside its twelve months. Written by qamar_apply_paid_order on the first
 * paid order that carried a professional's code, so a renewal attaches the
 * same share without the client typing the code again.
 */
async function loadReferral(userId: string): Promise<Promo | null> {
  const res = await db(
    `pro_referrals?user_id=eq.${userId}&ends_at=gt.${encodeURIComponent(new Date().toISOString())}` +
      `&select=promo_code_id,affiliate_user_id,promo_codes(code,active)&limit=1`,
  );
  if (!res.ok) return null;
  const rows = await res.json() as Array<Record<string, unknown>>;
  return savedProfessional(Array.isArray(rows) ? rows[0] : null);
}

/**
 * The professional this person named before paying: a code redeemed in Me or
 * through a /p/ link (qamar_redeem_pro_code, 0069). The first payment then
 * carries their share, and pro_referrals starts its twelve months there.
 */
async function loadClaim(userId: string): Promise<Promo | null> {
  const res = await db(
    `pro_code_claims?user_id=eq.${userId}&select=promo_code_id,affiliate_user_id,promo_codes(code,active)&limit=1`,
  );
  if (!res.ok) return null;
  const rows = await res.json() as Array<Record<string, unknown>>;
  return savedProfessional(Array.isArray(rows) ? rows[0] : null);
}

async function buildQuote(userId: string, planRaw: unknown, codeRaw: unknown): Promise<Quote | Response> {
  if (typeof planRaw !== "string" || !isPlanId(planRaw)) {
    return json({ error: "only the monthly plan exists" }, 400);
  }
  const code = normalizePromoCode(typeof codeRaw === "string" ? codeRaw : "");
  let promo: Promo | null = null;
  if (code) {
    promo = await loadPromo(code);
    if (!promo) {
      const first = await firstPurchase(userId);
      const q = quotePlus({ plan: planRaw, firstPurchase: first, buyerUserId: userId, promo: null });
      q.promoError = "This code was not found";
      q.promoCode = code;
      return q;
    }
  } else {
    promo = await chooseSavedPromo(() => loadReferral(userId), () => loadClaim(userId));
  }
  const first = await firstPurchase(userId);
  return quotePlus({ plan: planRaw, firstPurchase: first, buyerUserId: userId, promo });
}

async function quoteRoute(userId: string, body: Record<string, unknown>): Promise<Response> {
  const built = await buildQuote(userId, body.plan, body.promo_code);
  if (built instanceof Response) return built;
  return json(quoteJson(built));
}

async function checkout(user: { id: string; email?: string }, body: Record<string, unknown>): Promise<Response> {
  const missing = configured();
  if (missing) return json({ error: missing }, 503);

  const built = await buildQuote(user.id, body.plan, body.promo_code);
  if (built instanceof Response) return built;
  if (built.promoError) return json({ error: built.promoError, quote: quoteJson(built) }, 400);

  const plan = built.plan;
  const product = PLANS[plan];

  const created = await db("billing_orders", {
    method: "POST",
    body: JSON.stringify({
      user_id: user.id,
      plan,
      amount_cents: built.amountCents,
      currency: "EGP",
      status: "pending",
      pricing_reason: built.pricingReason,
      promo_code_id: built.promoId,
      affiliate_user_id: built.affiliateUserId,
      affiliate_commission_cents: built.affiliateCommissionCents,
    }),
  });
  if (!created.ok) return json({ error: `could not open an order: ${await created.text()}` }, 500);
  const order = (await created.json()) as { id: string };
  const orderId = Array.isArray(order) ? order[0]?.id : order.id;
  if (!orderId) return json({ error: "order did not return an id" }, 500);

  const notify = `${SUPABASE_URL}/functions/v1/billing/webhook`;
  const redirect = "com.qamar.app://plus/return";
  const first = (typeof body.first_name === "string" && body.first_name.trim()) || "Qamar";
  const last = (typeof body.last_name === "string" && body.last_name.trim()) || "Member";
  const phone = (typeof body.phone === "string" && body.phone.trim()) || "NA";
  const email = (typeof body.email === "string" && body.email.trim()) || user.email || "plus@dr-qamar.com";

  const intention = await fetch(`${PAYMOB_BASE}/v1/intention/`, {
    method: "POST",
    headers: {
      "Content-Type": "application/json",
      Authorization: `Token ${PAYMOB_SECRET}`,
    },
    body: JSON.stringify({
      amount: built.amountCents,
      currency: "EGP",
      payment_methods: paymentMethods(),
      items: [{
        name: product.nameEn,
        amount: built.amountCents,
        description: product.nameAr,
        quantity: 1,
      }],
      billing_data: {
        apartment: "NA",
        first_name: first,
        last_name: last,
        street: "NA",
        building: "NA",
        phone_number: phone,
        city: "Cairo",
        country: "EG",
        email,
        floor: "NA",
        state: "Cairo",
        postal_code: "NA",
      },
      extras: {
        qamar_order_id: orderId,
        qamar_user_id: user.id,
        qamar_plan: plan,
        qamar_pricing_reason: built.pricingReason,
      },
      special_reference: orderId,
      notification_url: notify,
      redirection_url: redirect,
    }),
  });

  if (!intention.ok) {
    await db(`billing_orders?id=eq.${orderId}`, {
      method: "PATCH",
      body: JSON.stringify({ status: "failed" }),
    });
    return json({ error: `Paymob refused the checkout: ${await intention.text()}` }, 502);
  }

  const paid = await intention.json() as {
    id?: string;
    client_secret?: string;
    intention_order_id?: number;
  };
  if (!paid.client_secret) {
    return json({ error: "Paymob returned no checkout secret" }, 502);
  }

  await db(`billing_orders?id=eq.${orderId}`, {
    method: "PATCH",
    body: JSON.stringify({
      paymob_intention_id: paid.id ?? null,
      paymob_order_id: paid.intention_order_id != null ? String(paid.intention_order_id) : null,
    }),
  });

  const checkoutUrl =
    `${PAYMOB_BASE}/unifiedcheckout/?publicKey=${encodeURIComponent(PAYMOB_PUBLIC)}` +
    `&clientSecret=${encodeURIComponent(paid.client_secret)}`;

  return json({
    checkout_url: checkoutUrl,
    order_id: orderId,
    plan,
    amount_cents: built.amountCents,
    currency: "EGP",
    provider: "paymob",
    pricing_reason: built.pricingReason,
  });
}

async function entitlement(userId: string): Promise<Response> {
  const snap = await rpc("qamar_entitlement_snapshot", { p_user_id: userId });
  const first = await firstPurchase(userId);
  const body = snap && typeof snap === "object" ? { ...(snap as Record<string, unknown>), first_purchase: first } : { first_purchase: first };
  return json(body);
}

/**
 * Seven days of Qamar+, once, before any payment. The database decides
 * eligibility (plus_trials, paid orders, current entitlement) — this only
 * turns its refusals into 400s the app can show.
 */
async function startTrial(userId: string): Promise<Response> {
  try {
    const snap = await rpc("qamar_start_trial", { p_user_id: userId });
    return json(snap);
  } catch (e) {
    const message = e instanceof Error ? e.message : "trial failed";
    if (message.includes("already used")) return json({ error: "The free week has already been used on this account." }, 400);
    if (message.includes("first-time")) return json({ error: "The free week is for first-time members." }, 400);
    if (message.includes("already Qamar+")) return json({ error: "Qamar+ is already on." }, 400);
    throw e;
  }
}

// The earned month (0052, threshold since 0058): the logged days
// billing_config asks for (20 at launch) in the first 30 of membership, and
// the next 30 are on us. The status is a read; the claim re-checks under a
// lock in the database and refuses with a reason the app can show, stating
// the database's numbers rather than its own.
async function earnedStatus(userId: string): Promise<Response> {
  return json(await rpc("qamar_earned_month_status", { p_user_id: userId }));
}

async function earnedClaim(userId: string): Promise<Response> {
  try {
    return json(await rpc("qamar_claim_earned_month", { p_user_id: userId }));
  } catch (e) {
    const message = e instanceof Error ? e.message : "claim failed";
    if (message.includes("already granted")) return json({ error: "The earned month has already been granted on this account." }, 400);
    if (message.includes("not yet earned")) {
      const status = (await rpc("qamar_earned_month_status", { p_user_id: userId }).catch(() => null)) as EarnedStatus | null;
      return json({ error: notYetEarnedMessage(status) }, 400);
    }
    throw e;
  }
}

async function affiliate(userId: string): Promise<Response> {
  await rpc("qamar_ensure_affiliate_code", { p_user_id: userId });
  const snap = await rpc("qamar_affiliate_snapshot", { p_user_id: userId });
  return json(snap);
}

// The professional's dashboard (0053): each client who typed this person's
// code and said yes to sharing, with the week's adherence. The consent gate
// is in the database function; a client who withdraws disappears here.
async function affiliateClients(userId: string): Promise<Response> {
  return json(await rpc("qamar_pro_clients", { p_user_id: userId }));
}

async function affiliatePayout(userId: string, body: Record<string, unknown>): Promise<Response> {
  const raw = body.amount_cents;
  const amount = typeof raw === "number" && Number.isFinite(raw) ? Math.floor(raw) : null;
  try {
    const snap = await rpc("qamar_request_affiliate_payout", {
      p_user_id: userId,
      p_amount_cents: amount,
    });
    return json(snap);
  } catch (e) {
    const message = e instanceof Error ? e.message : "payout failed";
    if (message.includes("minimum payout")) {
      return json({ error: `Minimum payout is EGP ${MIN_PAYOUT_CENTS / 100}` }, 400);
    }
    if (message.includes("not enough")) {
      return json({ error: "Not enough affiliate balance to redeem" }, 400);
    }
    throw e;
  }
}

/**
 * The billing_orders row for a Paymob order id, or null. Resolved by the
 * signed `order.id` that checkout stored as paymob_order_id, so the webhook
 * never acts on an order id the caller supplied.
 */
async function loadOrderByPaymobId(paymobOrderId: string): Promise<OrderRow | null> {
  const res = await db(
    `billing_orders?paymob_order_id=eq.${encodeURIComponent(paymobOrderId)}` +
      `&select=id,user_id,plan,amount_cents,currency,status&limit=1`,
  );
  if (!res.ok) return null;
  const rows = await res.json() as OrderRow[];
  return Array.isArray(rows) && rows[0] ? rows[0] : null;
}

async function webhook(req: Request): Promise<Response> {
  if (!PAYMOB_HMAC) return json({ error: "hmac secret missing" }, 503);
  const url = new URL(req.url);
  let raw: unknown;
  try {
    raw = await req.json();
  } catch {
    return json({ error: "invalid JSON" }, 400);
  }
  const hmac = url.searchParams.get("hmac") ??
    (raw && typeof raw === "object" && typeof (raw as Record<string, unknown>).hmac === "string"
      ? String((raw as Record<string, unknown>).hmac)
      : "");
  const obj = txnObject(raw);
  if (!obj) return json({ error: "no transaction" }, 400);

  if (!await verifyPaymobHmac(PAYMOB_HMAC, obj, hmac)) {
    return json({ error: "hmac mismatch" }, 401);
  }

  // From here on, only signed fields decide anything: order.id, amount_cents,
  // currency, success, pending, is_voided, is_refunded and the transaction id.
  const outcome = txnOutcome(obj);
  const txnId = String(obj.id ?? "");
  const paymobOrderId = signedOrderId(obj);
  if (!paymobOrderId || !txnId) return json({ error: "missing order or transaction id" }, 400);

  const order = await loadOrderByPaymobId(paymobOrderId);
  if (!order) {
    // Not one of ours, or checkout never stored the intention's order id.
    // Acknowledged so Paymob does not retry forever; logged so someone sees it.
    console.error("billing webhook: no order for paymob order", paymobOrderId, "txn", txnId);
    return json({ ok: true, applied: false, reason: "unknown order" });
  }

  if (!outcome.success || outcome.pending || outcome.voided || outcome.refunded) {
    await db(`billing_orders?id=eq.${order.id}&status=eq.pending`, {
      method: "PATCH",
      body: JSON.stringify({ status: "failed", paymob_txn_id: txnId }),
    });
    return json({ ok: true, applied: false });
  }

  if (!amountMatches(obj, order)) {
    // Signed amount disagrees with the order it is paying for. Nothing is
    // applied and the order is left as it was; this is the row to read when
    // someone asks why a payment "went through" and Plus did not turn on.
    console.error(
      "billing webhook: amount mismatch",
      { order: order.id, expected: order.amount_cents, currency: order.currency, got: obj.amount_cents, txn: txnId },
    );
    return json({ error: "amount mismatch" }, 409);
  }

  try {
    const snap = await rpc("qamar_apply_paid_order", { p_order_id: order.id, p_txn_id: txnId });
    return json({ ok: true, applied: true, entitlement: snap });
  } catch (e) {
    console.error("billing apply", e);
    return json({ error: "could not apply payment" }, 500);
  }
}

Deno.serve(async (req) => {
  if (req.method === "OPTIONS") return new Response("ok", { headers: CORS });
  if (req.method !== "POST") return json({ error: "POST only" }, 405);

  const route = new URL(req.url).pathname.replace(/^\/billing/, "").replace(/\/$/, "") || "/";

  if (route === "/webhook") {
    try {
      return await webhook(req);
    } catch (e) {
      console.error("billing webhook", e);
      return json({ error: "webhook error" }, 500);
    }
  }

  const user = await authenticate(req);
  if (!user) return json({ error: "unauthorized" }, 401);

  let body: Record<string, unknown> = {};
  try {
    body = await req.json();
  } catch {
    body = {};
  }

  try {
    switch (route) {
      case "/quote":
        return await quoteRoute(user.id, body);
      case "/checkout":
        return await checkout(user, body);
      case "/entitlement":
        return await entitlement(user.id);
      case "/trial/start":
        return await startTrial(user.id);
      case "/earned":
        return await earnedStatus(user.id);
      case "/earned/claim":
        return await earnedClaim(user.id);
      case "/affiliate":
        return await affiliate(user.id);
      case "/affiliate/payout":
        return await affiliatePayout(user.id, body);
      case "/affiliate/clients":
        return await affiliateClients(user.id);
      default:
        return json({ error: `unknown route ${route}` }, 404);
    }
  } catch (e) {
    console.error("billing", route, e);
    return json({ error: "billing error" }, 500);
  }
});
