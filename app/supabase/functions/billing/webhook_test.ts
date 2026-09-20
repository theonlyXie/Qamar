import { assertEquals } from "jsr:@std/assert@1";
import { amountMatches, flag, signedOrderId, txnObject, txnOutcome, type OrderRow } from "./webhook.ts";

const order: OrderRow = {
  id: "4b1f3f2e-9c1e-4a1c-8e0e-1c2d3e4f5a6b",
  user_id: "u1",
  plan: "monthly",
  amount_cents: 50_000,
  currency: "EGP",
  status: "pending",
};

Deno.test("the transaction is read from obj on JSON callbacks and flat on query-string ones", () => {
  assertEquals(txnObject({ obj: { id: 1, success: true } }), { id: 1, success: true });
  assertEquals(txnObject({ id: "1", success: "true" }), { id: "1", success: "true" });
  assertEquals(txnObject({ hello: "world" }), null);
  assertEquals(txnObject(null), null);
});

Deno.test("flags accept Paymob's booleans and its string booleans, nothing else", () => {
  assertEquals(flag(true), true);
  assertEquals(flag("true"), true);
  assertEquals(flag(false), false);
  assertEquals(flag("false"), false);
  assertEquals(flag("pending"), false);
  assertEquals(flag(1), false);
});

Deno.test("a pending transaction is pending even when Paymob spells it as a string", () => {
  const o = txnOutcome({ success: "true", pending: "true", is_voided: false, is_refunded: false });
  assertEquals(o.success, true);
  assertEquals(o.pending, true);
});

Deno.test("the order id comes only from the signed order.id", () => {
  assertEquals(signedOrderId({ order: { id: 987654 } }), "987654");
  assertEquals(signedOrderId({ order: { id: "987654" } }), "987654");
  // The fields the old webhook trusted are ignored even when present.
  assertEquals(
    signedOrderId({
      merchant_order_id: "attacker-order",
      payment_key_claims: { extra: { qamar_order_id: "attacker-order" } },
    }),
    null,
  );
  assertEquals(signedOrderId({ order: {} }), null);
  assertEquals(signedOrderId({}), null);
});

Deno.test("the collected amount and currency must equal the order", () => {
  assertEquals(amountMatches({ amount_cents: 50_000, currency: "EGP" }, order), true);
  assertEquals(amountMatches({ amount_cents: "50000", currency: "egp" }, order), true);
  assertEquals(amountMatches({ amount_cents: 100, currency: "EGP" }, order), false);
  assertEquals(amountMatches({ amount_cents: 50_000, currency: "USD" }, order), false);
  assertEquals(amountMatches({ currency: "EGP" }, order), false);
});
