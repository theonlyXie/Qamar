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
  /**
   * Why a typed professional's code is not the one that is paid (the phone
   * says it in the person's language): "referral_ended" — their twelve months
   * are over; "other_professional" — another professional is on the account;
   * "unchecked" — the account's referral could not be read. Null otherwise.
   */
  promoNotice: PromoNotice | null;
};

export type PromoNotice = "referral_ended" | "other_professional" | "unchecked";

/**
 * A professional already on this person's account, read back from a
 * pro_referrals row (written at the first payment that carried their code,
 * 0039) or a pro_code_claims row (a code redeemed in Me or through a /p/ link
 * before paying, 0069). Either row carries affiliate_user_id, promo_code_id
 * and the embedded promo_codes(code, active). Null when it names nobody.
 */
export function savedProfessional(row: Record<string, unknown> | null | undefined): Promo | null {
  if (!row || typeof row.affiliate_user_id !== "string") return null;
  const code = row.promo_codes as { code?: unknown; active?: unknown } | null | undefined;
  return {
    id: typeof row.promo_code_id === "string" ? row.promo_code_id : undefined,
    code: typeof code?.code === "string" ? code.code : "PRO",
    kind: "affiliate",
    ownerUserId: row.affiliate_user_id,
    percentOff: null,
    amountCents: null,
    appliesToPlans: null,
    // A professional who has been switched off stops earning, but the client
    // is not asked to do anything about it.
    active: code?.active !== false,
    startsAt: null,
    endsAt: null,
    maxRedemptions: null,
    redemptionCount: 0,
  };
}

/**
 * What checkout learned about this person's pro_referrals row: the lookup
 * failed ({ ok: false }), or it answered with the row or with none. The row
 * is read whatever its ends_at, because an expired referral is an answer too.
 */
export type ReferralLookup = { ok: false } | { ok: true; row: Record<string, unknown> | null };

/**
 * Which professional, if any, a checkout pays — the one rule for every path,
 * a code typed at checkout or none. The blueprint pays a professional EGP 100
 * a month for twelve months from the client's first payment, and one
 * professional per client (0039: "first professional wins"; 0069 the same
 * before the first payment). So the professional already on the account
 * decides, whatever is typed:
 * - A referral row inside its twelve months (ends_at after [now]): that
 *   professional. Their own code typed again pays them; another
 *   professional's typed code does not switch the share ("other_professional").
 * - A referral row past its twelve months: nobody, typed code or claim
 *   ("referral_ended" when a code was typed).
 * - No referral row: the claim made before paying (pro_code_claims, 0069),
 *   which a different typed code does not replace; with no claim, the typed
 *   code. Either carries the first payment only: that payment writes the
 *   referral row, and the row decides from then on.
 * - A referral lookup that failed: nobody. A share is never attached on a
 *   guess ("unchecked" when a code was typed).
 * A typed campaign code is a discount, not a professional: it is left as it
 * is and nothing here is read for it.
 */
export async function attachPromo(input: {
  typed: Promo | null;
  referral: () => Promise<ReferralLookup>;
  now: Date;
  claim: () => Promise<Promo | null>;
}): Promise<{ promo: Promo | null; notice: PromoNotice | null }> {
  const { typed, now } = input;
  if (typed && typed.kind !== "affiliate") return { promo: typed, notice: null };
  const referral = await input.referral();
  if (!referral.ok) return { promo: null, notice: typed ? "unchecked" : null };
  const row = referral.row;
  if (row) {
    const ends = typeof row.ends_at === "string" ? new Date(row.ends_at) : null;
    if (!ends || Number.isNaN(ends.getTime()) || ends <= now) {
      return { promo: null, notice: typed ? "referral_ended" : null };
    }
    const saved = savedProfessional(row);
    if (typed && saved && typed.ownerUserId !== saved.ownerUserId) return { promo: saved, notice: "other_professional" };
    return { promo: typed ?? saved, notice: null };
  }
  const claimed = await input.claim();
  if (typed && claimed && typed.ownerUserId !== claimed.ownerUserId) return { promo: claimed, notice: "other_professional" };
  return { promo: typed ?? claimed, notice: null };
}

/**
 * The same rule for a checkout with no typed code (kept for its callers and
 * tests): the referral inside its twelve months, nobody after them, the claim
 * only when there is no referral row, nobody on a failed lookup.
 */
export async function chooseSavedPromo(
  referral: ReferralLookup,
  now: Date,
  claim: () => Promise<Promo | null>,
): Promise<Promo | null> {
  return (await attachPromo({ typed: null, referral: () => Promise.resolve(referral), now, claim })).promo;
}

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
    promoNotice: null,
  };
}

/** The payment rails a checkout can offer, as the paywall names them. */
export type PaymentKind = "card" | "meeza" | "wallet";
const PAYMENT_KINDS: readonly PaymentKind[] = ["card", "meeza", "wallet"];

/**
 * PAYMOB_INTEGRATION_IDS, read two ways. Each entry is an integration id or
 * name, optionally labelled with the rail it is: `card:123456,wallet:789012`.
 * A Meeza card usually rides on the card integration; label it too when
 * Paymob has enabled it on the account (`meeza:123456` beside `card:123456`).
 *
 * - [methods] is what Paymob's intention is given: every id, labels
 *   removed, each once, numbers as numbers, exactly as before.
 * - [kinds] is what the paywall may name. Only labelled entries count: an
 *   unlabelled id could be any rail, so the paywall then names none rather
 *   than promise Vodafone Cash to someone the account cannot take it from.
 */
export function paymentConfig(raw: string | null | undefined): { methods: Array<number | string>; kinds: PaymentKind[] } {
  const methods: Array<number | string> = [];
  const kinds = new Set<PaymentKind>();
  for (const entry of (raw ?? "").split(",").map((s) => s.trim()).filter(Boolean)) {
    const at = entry.indexOf(":");
    const label = at > 0 ? entry.slice(0, at).trim().toLowerCase() : "";
    const id = (at > 0 ? entry.slice(at + 1) : entry).trim();
    if (!id) continue;
    const value = /^\d+$/.test(id) ? Number(id) : id;
    if (!methods.includes(value)) methods.push(value);
    if ((PAYMENT_KINDS as readonly string[]).includes(label)) kinds.add(label as PaymentKind);
  }
  return { methods, kinds: PAYMENT_KINDS.filter((k) => kinds.has(k)) };
}

