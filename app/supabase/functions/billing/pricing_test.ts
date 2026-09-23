import { assertEquals } from "jsr:@std/assert@1";
import {
  LIST_MONTHLY_CENTS,
  PLANS,
  PRO_SHARE_MONTHS,
  PRO_SHARE_PERCENT,
  chooseSavedPromo,
  isPlanId,
  normalizePromoCode,
  paymentConfig,
  proShareCents,
  quotePlus,
  savedProfessional,
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

Deno.test("a code redeemed before paying is read back as that professional's code", () => {
  // The pro_code_claims row the billing function reads (0069), promo_codes embedded.
  const claim = savedProfessional({
    promo_code_id: "promo-sara",
    affiliate_user_id: "dr-sara",
    promo_codes: { code: "QMRSARA1", active: true },
  });
  assertEquals(claim?.kind, "affiliate");
  assertEquals(claim?.ownerUserId, "dr-sara");
  assertEquals(claim?.code, "QMRSARA1");
  assertEquals(claim?.id, "promo-sara");
  // Checkout with no typed code then pays the professional, at the same price.
  const q = quotePlus({ plan: "monthly", firstPurchase: true, buyerUserId: "client", promo: claim });
  assertEquals(q.amountCents, LIST_MONTHLY_CENTS);
  assertEquals(q.pricingReason, "affiliate");
  assertEquals(q.affiliateUserId, "dr-sara");
  assertEquals(q.affiliateCommissionCents, 10_000);
  // A row that names nobody attaches nothing.
  assertEquals(savedProfessional(null), null);
  assertEquals(savedProfessional({ promo_code_id: "x" }), null);
  // A professional who has been switched off is read as inactive, and earns nothing.
  const off = savedProfessional({ affiliate_user_id: "dr-sara", promo_codes: { code: "QMRSARA1", active: false } });
  assertEquals(quotePlus({ plan: "monthly", firstPurchase: true, buyerUserId: "client", promo: off }).affiliateCommissionCents, 0);
});

Deno.test("with no typed code, the referral wins, and the claim is read only when there is none", async () => {
  const referral: Promo = { ...PRO, ownerUserId: "dr-referral" };
  const claim: Promo = { ...PRO, ownerUserId: "dr-claim" };
  let claimReads = 0;
  const readClaim = () => { claimReads++; return Promise.resolve(claim); };
  assertEquals((await chooseSavedPromo(() => Promise.resolve(referral), readClaim))?.ownerUserId, "dr-referral");
  assertEquals(claimReads, 0);
  assertEquals((await chooseSavedPromo(() => Promise.resolve(null), readClaim))?.ownerUserId, "dr-claim");
  assertEquals(claimReads, 1);
  assertEquals(await chooseSavedPromo(() => Promise.resolve(null), () => Promise.resolve(null)), null);
});

Deno.test("checkout gets every integration id; the paywall names only the rails that are labelled", () => {
  const labelled = paymentConfig("card:123456, meeza:123456 ,wallet:789012");
  assertEquals(labelled.methods, [123456, 789012], "each id once, labels removed, as numbers");
  assertEquals(labelled.kinds, ["card", "meeza", "wallet"]);

  // Before labels existed: ids only. Checkout still works; the paywall names no rail.
  const bare = paymentConfig("123456,789012");
  assertEquals(bare.methods, [123456, 789012]);
  assertEquals(bare.kinds, []);

  // A card integration alone: no wallet is promised.
  assertEquals(paymentConfig("card:123456").kinds, ["card"]);
  // Names pass through as names; unknown labels name nothing.
  assertEquals(paymentConfig("wallet:MIGS-online, kiosk:555").methods, ["MIGS-online", 555]);
  assertEquals(paymentConfig("wallet:MIGS-online, kiosk:555").kinds, ["wallet"]);
  assertEquals(paymentConfig("").methods, []);
  assertEquals(paymentConfig(undefined).kinds, []);
});

