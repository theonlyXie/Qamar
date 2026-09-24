// The parts of Paymob's transaction callback that can be reasoned about with
// no network: which fields to trust, what the flags mean, and whether the
// money matches the order.
//
// The rule that shapes this file: only fields inside HMAC_FIELDS (hmac.ts) are
// evidence. `order.id` is signed. `merchant_order_id` and everything under
// `payment_key_claims.extra` are not — Paymob echoes them back untouched, and
// a caller who can produce one validly-signed callback (their own EGP 1
// transaction) can rewrite them to point at any pending order they like. The
// webhook used to read `payment_key_claims.extra.qamar_order_id` first.

import type { PlanId } from "./pricing.ts";

export interface TxnOutcome {
  success: boolean;
  pending: boolean;
  voided: boolean;
  refunded: boolean;
}

/** The order row the webhook resolves the signed Paymob order id to. */
export interface OrderRow {
  id: string;
  user_id: string;
  plan: PlanId | string;
  amount_cents: number;
  currency: string;
  status: string;
}

/**
 * Paymob wraps the transaction in `obj` on JSON callbacks and sends it flat on
 * query-string callbacks. Either way this returns the transaction itself.
 */
export function txnObject(body: unknown): Record<string, unknown> | null {
  if (!body || typeof body !== "object") return null;
  const o = body as Record<string, unknown>;
  if (o.obj && typeof o.obj === "object") return o.obj as Record<string, unknown>;
  if (typeof o.id !== "undefined" && typeof o.success !== "undefined") return o;
  return null;
}

/** Paymob sends booleans in JSON and the strings "true"/"false" in query strings. */
export function flag(v: unknown): boolean {
  return v === true || v === "true";
}

export function txnOutcome(obj: Record<string, unknown>): TxnOutcome {
  return {
    success: flag(obj.success),
    // Was `=== "pending"`, a value Paymob never sends: a string "true" read as
    // not pending, and a settling transaction could open Qamar+.
    pending: flag(obj.pending),
    voided: flag(obj.is_voided),
    refunded: flag(obj.is_refunded),
  };
}

/**
 * The Paymob order id, from the one place it is signed. Checkout stores this
 * on billing_orders.paymob_order_id when the intention is created, so the
 * webhook resolves the order by it and never by anything the caller typed.
 */
export function signedOrderId(obj: Record<string, unknown>): string | null {
  const order = obj.order;
  if (!order || typeof order !== "object") return null;
  const id = (order as { id?: unknown }).id;
  if (typeof id === "number" && Number.isFinite(id)) return String(id);
  if (typeof id === "string" && id.trim()) return id.trim();
  return null;
}

/**
 * What Paymob says was collected must equal what the order says was owed.
 * Both fields are signed. A mismatch is either tampering or a partial capture,
 * and neither should open a subscription.
 */
export function amountMatches(obj: Record<string, unknown>, order: OrderRow): boolean {
  const cents = typeof obj.amount_cents === "number"
    ? obj.amount_cents
    : typeof obj.amount_cents === "string"
    ? Number(obj.amount_cents)
    : NaN;
  if (!Number.isInteger(cents) || cents !== order.amount_cents) return false;
  const currency = String(obj.currency ?? "").toUpperCase();
  return currency === order.currency.toUpperCase();
}
