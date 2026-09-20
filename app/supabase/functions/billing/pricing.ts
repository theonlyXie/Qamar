// Qamar+ price list. The phone may display these numbers; only this module
// (and the checkout that calls it) may stamp what Paymob is asked to collect.
// Amounts are piastres (cents of an Egyptian pound).
//
// One plan: 500 EGP a month. That is the blueprint's decision, not a gap —
// annual and family tiers wait on month-2 retention, and discount marketing
// is out entirely. The only thing that ever moves the price is a campaign
// code, which the schema supports and nobody has issued.
//
// A professional's code (a nutritionist, a coach) does not change what the
// client pays. It attaches a 20% recurring share — EGP 100 of the 500 — to
// the professional for twelve months. "You earn EGP 100 a month for every
// patient on it, for a year" is the pitch, and the arithmetic here is that
// sentence.

export const CURRENCY = "EGP";

export const LIST_MONTHLY_CENTS = 50_000;

/** The professional's recurring share of every payment their referral makes. */
export const PRO_SHARE_PERCENT = 20;
export const PRO_SHARE_MONTHS = 12;
export const MIN_PAYOUT_CENTS = 5_000;

export const PLANS = {
  monthly: {
    days: 30,
    listCents: LIST_MONTHLY_CENTS,
    nameAr: "قمر+ شهري",
    nameEn: "Qamar+ monthly",
  },
} as const;

export type PlanId = keyof typeof PLANS;
export type PromoKind = "affiliate" | "campaign";

/**
 * Why the order carries the amount it does. "affiliate" means the list price
 * with a professional's share attached, not a discount — the client pays 500
 * either way.
 */
export type PricingReason = "list" | "affiliate" | "campaign";

export function isPlanId(value: string): value is PlanId {
  return value === "monthly";
}

export function normalizePromoCode(raw: string | null | undefined): string {
  if (!raw) return "";
  return raw.trim().toUpperCase().replace(/\s+/g, "");
}

export function proShareCents(amountCents: number): number {
  return Math.round(amountCents * PRO_SHARE_PERCENT / 100);
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
  /** Kept for the client's copy ("your first month"); it never moves the price. */
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
  let pricingReason: PricingReason = "list";

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
        promoError = "You cannot use your own code";
        promoId = null;
      } else {
        // The price does not move. The professional's share is carved out of
        // the same 500 the client was paying anyway.
        pricingReason = "affiliate";
        affiliateUserId = promo.ownerUserId;
        affiliateCommissionCents = proShareCents(amountCents);
        promoNote = "Your nutritionist follows your plan and earns a share of this subscription. The price is the same.";
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
