import { assertEquals } from "jsr:@std/assert@1";
import {
  LIST_MONTHLY_CENTS,
  PLANS,
  PRO_SHARE_MONTHS,
  PRO_SHARE_PERCENT,
  isPlanId,
  normalizePromoCode,
  proShareCents,
  quotePlus,
  type Promo,
} from "./pricing.ts";

const PRO: Promo = {
  id: "promo-1",
  code: "QMR7K2P",
  kind: "affiliate",
  ownerUserId: "dr-sara",
  percentOff: null,
  amountCents: null,
  appliesToPlans: null,
  active: true,
  startsAt: null,
  endsAt: null,
  maxRedemptions: null,
  redemptionCount: 0,
};

Deno.test("Plus is 500 EGP a month, and that is the only plan", () => {
  const q = quotePlus({ plan: "monthly", firstPurchase: false, buyerUserId: "buyer", promo: null });
  assertEquals(q.amountCents, LIST_MONTHLY_CENTS);
  assertEquals(LIST_MONTHLY_CENTS, 50_000);
  assertEquals(q.pricingReason, "list");
  assertEquals(Object.keys(PLANS), ["monthly"]);
  assertEquals(isPlanId("annual"), false);
  assertEquals(isPlanId("quarterly"), false);
});

Deno.test("a first purchase costs the same as every other one", () => {
  const first = quotePlus({ plan: "monthly", firstPurchase: true, buyerUserId: "buyer", promo: null });
  assertEquals(first.amountCents, LIST_MONTHLY_CENTS);
  assertEquals(first.pricingReason, "list");
  assertEquals(first.firstPurchase, true);
});

Deno.test("a professional's code leaves the client's price alone and pays the professional 20%", () => {
  const q = quotePlus({ plan: "monthly", firstPurchase: true, buyerUserId: "client", promo: PRO });
  assertEquals(q.amountCents, LIST_MONTHLY_CENTS);
  assertEquals(q.pricingReason, "affiliate");
  assertEquals(q.affiliateUserId, "dr-sara");
  assertEquals(PRO_SHARE_PERCENT, 20);
  assertEquals(PRO_SHARE_MONTHS, 12);
  assertEquals(q.affiliateCommissionCents, 10_000);
  assertEquals(proShareCents(50_000), 10_000);
  assertEquals(q.promoError, null);
});

Deno.test("you cannot use your own code", () => {
  const q = quotePlus({ plan: "monthly", firstPurchase: true, buyerUserId: "dr-sara", promo: PRO });
  assertEquals(q.pricingReason, "list");
  assertEquals(q.amountCents, LIST_MONTHLY_CENTS);
  assertEquals(q.affiliateCommissionCents, 0);
  assertEquals(q.affiliateUserId, null);
  assertEquals(q.promoError, "You cannot use your own code");
});

Deno.test("an inactive or exhausted code attaches nothing", () => {
  const dead = quotePlus({ plan: "monthly", firstPurchase: false, buyerUserId: "client", promo: { ...PRO, active: false } });
  assertEquals(dead.promoError, "This code is not active");
  assertEquals(dead.affiliateCommissionCents, 0);
  const spent = quotePlus({
    plan: "monthly",
    firstPurchase: false,
    buyerUserId: "client",
    promo: { ...PRO, maxRedemptions: 1, redemptionCount: 1 },
  });
  assertEquals(spent.promoError, "This code is not active");
});

Deno.test("a campaign code is the one thing that can move the price, and it never touches the pro share", () => {
  const campaign: Promo = { ...PRO, id: "sale", code: "RAMADAN", kind: "campaign", ownerUserId: null, percentOff: 50 };
  const q = quotePlus({ plan: "monthly", firstPurchase: false, buyerUserId: "buyer", promo: campaign });
  assertEquals(q.amountCents, 25_000);
  assertEquals(q.pricingReason, "campaign");
  assertEquals(q.affiliateCommissionCents, 0);
  assertEquals(q.affiliateUserId, null);
});

Deno.test("promo codes are compared in uppercase without spaces", () => {
  assertEquals(normalizePromoCode(" qmr 7k2p "), "QMR7K2P");
});
