import { assertEquals } from "jsr:@std/assert@1";
import {
  AFFILIATE_COMMISSION_CENTS,
  AFFILIATE_MONTHLY_CENTS,
  AFFILIATE_NET_CENTS,
  FIRST_USER_MONTHLY_CENTS,
  FIRST_USER_OFF_PERCENT,
  LIST_MONTHLY_CENTS,
  PACK_CENTS,
  normalizePromoCode,
  quotePlus,
  type Promo,
} from "./pricing.ts";

const AFFILIATE: Promo = {
  id: "promo-1",
  code: "QMR7K2P",
  kind: "affiliate",
  ownerUserId: "affiliate-user",
  percentOff: null,
  amountCents: null,
  appliesToPlans: null,
  active: true,
  startsAt: null,
  endsAt: null,
  maxRedemptions: null,
  redemptionCount: 0,
};

Deno.test("list Plus is 500 EGP a month", () => {
  const q = quotePlus({ plan: "monthly", firstPurchase: false, buyerUserId: "buyer", promo: null });
  assertEquals(q.amountCents, LIST_MONTHLY_CENTS);
  assertEquals(LIST_MONTHLY_CENTS, 50_000);
  assertEquals(q.pricingReason, "list");
});

Deno.test("every first user gets 30% off the 500 list", () => {
  assertEquals(FIRST_USER_OFF_PERCENT, 30);
  assertEquals(FIRST_USER_MONTHLY_CENTS, Math.round(LIST_MONTHLY_CENTS * 0.7));
  const q = quotePlus({ plan: "monthly", firstPurchase: true, buyerUserId: "buyer", promo: null });
  assertEquals(q.amountCents, 35_000);
  assertEquals(q.pricingReason, "first_user");
});

Deno.test("an affiliate code is 299 for the buyer, 50 for the marketer, 249 net", () => {
  const q = quotePlus({
    plan: "monthly",
    firstPurchase: true,
    buyerUserId: "buyer",
    promo: AFFILIATE,
  });
  assertEquals(q.amountCents, AFFILIATE_MONTHLY_CENTS);
  assertEquals(AFFILIATE_MONTHLY_CENTS, 29_900);
  assertEquals(q.affiliateCommissionCents, AFFILIATE_COMMISSION_CENTS);
  assertEquals(AFFILIATE_COMMISSION_CENTS, 5_000);
  assertEquals(q.amountCents - q.affiliateCommissionCents, AFFILIATE_NET_CENTS);
  assertEquals(AFFILIATE_NET_CENTS, PACK_CENTS);
  assertEquals(q.pricingReason, "affiliate");
  assertEquals(q.affiliateUserId, "affiliate-user");
});

Deno.test("you cannot use your own affiliate code", () => {
  const q = quotePlus({
    plan: "monthly",
    firstPurchase: true,
    buyerUserId: "affiliate-user",
    promo: AFFILIATE,
  });
  assertEquals(q.pricingReason, "first_user");
  assertEquals(q.amountCents, FIRST_USER_MONTHLY_CENTS);
  assertEquals(q.affiliateCommissionCents, 0);
  assertEquals(q.promoError, "You cannot use your own affiliate code");
});

Deno.test("affiliate codes do not raise the 249 packs", () => {
  for (const plan of ["quarterly", "annual"] as const) {
    const q = quotePlus({
      plan,
      firstPurchase: true,
      buyerUserId: "buyer",
      promo: AFFILIATE,
    });
    assertEquals(q.amountCents, PACK_CENTS);
    assertEquals(q.affiliateCommissionCents, 0);
    assertEquals(q.promoNote?.includes("299"), true);
  }
});

Deno.test("1 year is 50% off the 500 list, priced at 249, and 3 months matches that cash", () => {
  assertEquals(PACK_CENTS, 24_900);
  const year = quotePlus({ plan: "annual", firstPurchase: false, buyerUserId: "buyer", promo: null });
  const three = quotePlus({ plan: "quarterly", firstPurchase: false, buyerUserId: "buyer", promo: null });
  assertEquals(year.amountCents, PACK_CENTS);
  assertEquals(three.amountCents, PACK_CENTS);
  assertEquals(year.days, 365);
  assertEquals(three.days, 90);
  assertEquals(year.pricingReason, "annual_half");
  assertEquals(three.pricingReason, "quarterly_pack");
});

Deno.test("a later campaign code can undercut the list without touching affiliate math", () => {
  const campaign: Promo = {
    ...AFFILIATE,
    id: "sale",
    code: "RAMADAN",
    kind: "campaign",
    ownerUserId: null,
    percentOff: 50,
  };
  const q = quotePlus({
    plan: "monthly",
    firstPurchase: false,
    buyerUserId: "buyer",
    promo: campaign,
  });
  assertEquals(q.amountCents, 25_000);
  assertEquals(q.pricingReason, "campaign");
  assertEquals(q.affiliateCommissionCents, 0);
});

Deno.test("first-user 350 beats a weaker campaign", () => {
  const campaign: Promo = {
    ...AFFILIATE,
    kind: "campaign",
    ownerUserId: null,
    percentOff: 20,
    code: "SAVE20",
  };
  const q = quotePlus({
    plan: "monthly",
    firstPurchase: true,
    buyerUserId: "buyer",
    promo: campaign,
  });
  assertEquals(q.amountCents, FIRST_USER_MONTHLY_CENTS);
  assertEquals(q.pricingReason, "first_user");
});

Deno.test("promo codes are compared in uppercase without spaces", () => {
  assertEquals(normalizePromoCode(" qmr 7k2p "), "QMR7K2P");
});
