// Qamar+ billing. Paymob is the Egyptian payment gateway: EGP, cards,
// Meeza, and mobile wallets. The phone never holds a Paymob secret and never
// decides that someone has paid — Paymob posts a signed callback here.
//
// Routes:
//   POST /billing/checkout     { plan: "monthly"|"annual" }   JWT
//   POST /billing/entitlement  {}                             JWT
//   POST /billing/webhook      Paymob transaction callback    HMAC
//
// Secrets:
//   PAYMOB_SECRET_KEY
//   PAYMOB_PUBLIC_KEY
//   PAYMOB_HMAC_SECRET
//   PAYMOB_INTEGRATION_IDS   comma-separated integration ids or names (card,wallet)
//   PAYMOB_BASE_URL          optional, defaults to https://accept.paymob.com

import { verifyPaymobHmac } from "./hmac.ts";

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

const CATALOG = {
  monthly: { amountCents: 19900, days: 30, nameAr: "قمر+ شهري", nameEn: "Qamar+ monthly" },
  annual: { amountCents: 159000, days: 365, nameAr: "قمر+ سنوي", nameEn: "Qamar+ annual" },
} as const;

type PlanId = keyof typeof CATALOG;

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

async function checkout(user: { id: string; email?: string }, body: Record<string, unknown>): Promise<Response> {
  const missing = configured();
  if (missing) return json({ error: missing }, 503);

  const plan = body.plan === "annual" ? "annual" : body.plan === "monthly" ? "monthly" : null;
  if (!plan) return json({ error: "choose monthly or annual" }, 400);
  const product = CATALOG[plan as PlanId];

  const created = await db("billing_orders", {
    method: "POST",
    body: JSON.stringify({
      user_id: user.id,
      plan,
      amount_cents: product.amountCents,
      currency: "EGP",
      status: "pending",
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
      amount: product.amountCents,
      currency: "EGP",
      payment_methods: paymentMethods(),
      items: [{
        name: product.nameEn,
        amount: product.amountCents,
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
      extras: { qamar_order_id: orderId, qamar_user_id: user.id, qamar_plan: plan },
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
    amount_cents: product.amountCents,
    currency: "EGP",
    provider: "paymob",
  });
}

async function entitlement(userId: string): Promise<Response> {
  const snap = await rpc("qamar_entitlement_snapshot", { p_user_id: userId });
  return json(snap);
}

function txnObject(body: unknown): Record<string, unknown> | null {
  if (!body || typeof body !== "object") return null;
  const o = body as Record<string, unknown>;
  if (o.obj && typeof o.obj === "object") return o.obj as Record<string, unknown>;
  if (typeof o.id !== "undefined" && typeof o.success !== "undefined") return o;
  return null;
}

function orderIdFrom(obj: Record<string, unknown>): string | null {
  const extras = obj.payment_key_claims;
  if (extras && typeof extras === "object") {
    const extraBag = (extras as { extra?: Record<string, unknown> }).extra;
    const fromExtra = extraBag?.qamar_order_id;
    if (typeof fromExtra === "string" && fromExtra) return fromExtra;
  }
  const merchant = obj.merchant_order_id ?? (obj.order as { merchant_order_id?: unknown } | undefined)?.merchant_order_id;
  if (typeof merchant === "string" && merchant) return merchant;
  return null;
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

  const success = obj.success === true || obj.success === "true";
  const pending = obj.pending === true || obj.pending === "pending";
  const voided = obj.is_voided === true;
  const refunded = obj.is_refunded === true;
  const txnId = String(obj.id ?? "");
  const orderId = orderIdFrom(obj);

  if (!success || pending || voided || refunded) {
    if (orderId) {
      await db(`billing_orders?id=eq.${orderId}&status=eq.pending`, {
        method: "PATCH",
        body: JSON.stringify({ status: "failed", paymob_txn_id: txnId || null }),
      });
    }
    return json({ ok: true, applied: false });
  }

  if (!orderId || !txnId) return json({ error: "missing order or transaction id" }, 400);

  try {
    const snap = await rpc("qamar_apply_paid_order", { p_order_id: orderId, p_txn_id: txnId });
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
      case "/checkout":
        return await checkout(user, body);
      case "/entitlement":
        return await entitlement(user.id);
      default:
        return json({ error: `unknown route ${route}` }, 404);
    }
  } catch (e) {
    console.error("billing", route, e);
    return json({ error: "billing error" }, 500);
  }
});
