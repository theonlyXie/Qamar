// Qamar+ price list. The phone may display these numbers; only this module
// (and the checkout that calls it) may stamp what Paymob is asked to collect.
// Amounts are piastres (cents of an Egyptian pound).
//
// List:            500 EGP a month
// First purchase:  30% off → 350 EGP a month
// Affiliate code:  buyer pays 299 EGP; affiliate is owed 50 EGP cash (not Su);
//                  Qamar's net is 249 EGP
// 3-month pack:    249 EGP (90 days)
// 1-year:          249 EGP (365 days) — 50% off the 500 list, and the plan we push

export const CURRENCY = "EGP";

export const LIST_MONTHLY_CENTS = 50_000;
export const FIRST_USER_OFF_PERCENT = 30;
export const FIRST_USER_MONTHLY_CENTS = 35_000;
export const AFFILIATE_MONTHLY_CENTS = 29_900;
export const AFFILIATE_COMMISSION_CENTS = 5_000;
export const AFFILIATE_NET_CENTS = 24_900;
export const PACK_CENTS = 24_900;
export const MIN_PAYOUT_CENTS = 5_000;

export const PLANS = {
  monthly: {
    days: 30,
    listCents: LIST_MONTHLY_CENTS,
    nameAr: "قمر+ شهري",
    nameEn: "Qamar+ monthly",
  },
  quarterly: {
    days: 90,
    listCents: PACK_CENTS,
    nameAr: "قمر+ ٣ شهور",
    nameEn: "Qamar+ 3 months",
  },
  annual: {
    days: 365,
    listCents: PACK_CENTS,
    nameAr: "قمر+ سنوي",
    nameEn: "Qamar+ 1 year",
  },
} as const;

export type PlanId = keyof typeof PLANS;
export type PromoKind = "affiliate" | "campaign";
export type PricingReason =
  | "list"
  | "first_user"
  | "affiliate"
  | "campaign"
  | "annual_half"
  | "quarterly_pack";

export function isPlanId(value: string): value is PlanId {
  return value === "monthly" || value === "quarterly" || value === "annual";
}

export function normalizePromoCode(raw: string | null | undefined): string {
  if (!raw) return "";
  return raw.trim().toUpperCase().replace(/\s+/g, "");
}

export type Promo = {
  id?: string;
  code: string;
  kind: PromoKind;
  ownerUserId: string | null;
  percentOff: number | null;
  amountCents: number | null;
  appliesToPlans: PlanId[] | null;
  active: boolean;
  startsAt: Date | null;
  endsAt: Date | null;
  maxRedemptions: number | null;
  redemptionCount: number;
};

export type Quote = {
  plan: PlanId;
  days: number;
  listCents: number;
  amountCents: number;
  pricingReason: PricingReason;
  firstPurchase: boolean;
  promoCode: string | null;
  promoKind: PromoKind | null;
  promoId: string | null;
  affiliateUserId: string | null;
  affiliateCommissionCents: number;
  promoNote: string | null;
  promoError: string | null;
};

function promoLive(promo: Promo, now: Date): boolean {
  if (!promo.active) return false;
  if (promo.startsAt && now < promo.startsAt) return false;
  if (promo.endsAt && now > promo.endsAt) return false;
  if (promo.maxRedemptions != null && promo.redemptionCount >= promo.maxRedemptions) {
    return false;
  }
  return true;
}

function baseReason(plan: PlanId): PricingReason {
  if (plan === "annual") return "annual_half";
  if (plan === "quarterly") return "quarterly_pack";
  return "list";
}

function campaignAmount(plan: PlanId, promo: Promo): number | null {
  if (promo.appliesToPlans && promo.appliesToPlans.length > 0 && !promo.appliesToPlans.includes(plan)) {
    return null;
  }
  const list = PLANS[plan].listCents;
  if (promo.amountCents != null && promo.amountCents > 0) return promo.amountCents;
  if (promo.percentOff != null && promo.percentOff > 0) {
    return Math.round(list * (100 - promo.percentOff) / 100);
  }
  return null;
}

export function quotePlus(input: {
  plan: PlanId;
  firstPurchase: boolean;
  buyerUserId: string;
  promo: Promo | null;
  now?: Date;
}): Quote {
  const now = input.now ?? new Date();
  const spec = PLANS[input.plan];
  let amountCents: number = spec.listCents;
  let pricingReason = baseReason(input.plan);

  if (input.plan === "monthly" && input.firstPurchase) {
    amountCents = FIRST_USER_MONTHLY_CENTS;
    pricingReason = "first_user";
  }

  let promoCode: string | null = null;
  let promoKind: PromoKind | null = null;
  let promoId: string | null = input.promo?.id ?? null;
  let affiliateUserId: string | null = null;
  let affiliateCommissionCents = 0;
  let promoNote: string | null = null;
  let promoError: string | null = null;

  const promo = input.promo;
  if (promo) {
    if (!promoLive(promo, now)) {
      promoError = "This code is not active";
      promoId = null;
    } else if (promo.kind === "affiliate") {
      promoCode = promo.code;
      promoKind = "affiliate";
      if (!promo.ownerUserId) {
        promoError = "This code is not active";
        promoId = null;
      } else if (promo.ownerUserId === input.buyerUserId) {
        promoError = "You cannot use your own affiliate code";
        promoId = null;
      } else if (input.plan !== "monthly") {
        promoNote =
          "Affiliate codes apply to monthly Plus at EGP 299. The 3-month and 1-year packs are already EGP 249.";
        promoId = null;
      } else {
        amountCents = AFFILIATE_MONTHLY_CENTS;
        pricingReason = "affiliate";
        affiliateUserId = promo.ownerUserId;
        affiliateCommissionCents = AFFILIATE_COMMISSION_CENTS;
      }
    } else {
      const next = campaignAmount(input.plan, promo);
      promoCode = promo.code;
      promoKind = "campaign";
      if (next == null) {
        promoError = "This code does not apply to this plan";
        promoId = null;
      } else if (next <= 0) {
        promoError = "This code is not active";
        promoId = null;
      } else if (next < amountCents) {
        amountCents = next;
        pricingReason = "campaign";
      } else {
        promoNote = "Your current price is already lower than this code";
        promoId = null;
      }
    }
  }

  return {
    plan: input.plan,
    days: spec.days,
    listCents: spec.listCents,
    amountCents,
    pricingReason,
    firstPurchase: input.firstPurchase,
    promoCode,
    promoKind,
    promoId,
    affiliateUserId,
    affiliateCommissionCents,
    promoNote,
    promoError,
  };
}
