/// Qamar+ as sold in Egypt: Egyptian pounds, collected by Paymob.
///
/// Amounts are in piastres (cents of a pound) because that is what Paymob
/// charges. The paywall shows the pound figure. The server, not the phone,
/// is the price list — the client only names the plan and, optionally, a code.
///
/// One plan, 500 EGP a month. Annual and family tiers wait on month-2
/// retention; discount marketing is out. A professional's code does not
/// change what the client pays — it sends 20% of each payment (EGP 100) to
/// the nutritionist or coach for twelve months. Su Points are never part of
/// this wallet.
class PlusCatalog {
  PlusCatalog._();

  static const currency = 'EGP';
  static const provider = 'paymob';

  static const listMonthlyCents = 50000;

  /// The professional's share of every payment their referral makes.
  static const proSharePercent = 20;
  static const proShareMonths = 12;
  static const proShareCents = listMonthlyCents * proSharePercent ~/ 100;
  static const minPayoutCents = 5000;

  static const monthly = PlusProduct(
    id: 'monthly',
    amountCents: listMonthlyCents,
    periodDays: 30,
    nameAr: 'قمر+ شهري',
    nameEn: 'Qamar+ monthly',
  );

  /// Only the monthly plan is sold; any other id falls back to it so an old
  /// server answer cannot crash the paywall.
  static PlusProduct byId(String id) => monthly;
}

class PlusProduct {
  final String id;
  final int amountCents;
  final int periodDays;
  final String nameAr;
  final String nameEn;
  const PlusProduct({
    required this.id,
    required this.amountCents,
    required this.periodDays,
    required this.nameAr,
    required this.nameEn,
  });

  int get amountPounds => amountCents ~/ 100;
}

/// A promo the server has already resolved. The phone does not invent prices
/// from a typed string — it sends the code and displays the quote.
class PlusPromo {
  final String code;
  final String kind;
  final String? ownerUserId;
  final int? percentOff;
  final int? amountCents;
  final List<String>? appliesToPlans;
  const PlusPromo({
    required this.code,
    required this.kind,
    this.ownerUserId,
    this.percentOff,
    this.amountCents,
    this.appliesToPlans,
  });

  bool get isAffiliate => kind == 'affiliate';
}

class PlusQuote {
  final String plan;
  final int days;
  final int listCents;
  final int amountCents;
  final String pricingReason;
  final bool firstPurchase;
  final String? promoCode;
  final String? promoKind;
  final int affiliateCommissionCents;
  final String? promoNote;
  final String? promoError;

  const PlusQuote({
    required this.plan,
    required this.days,
    required this.listCents,
    required this.amountCents,
    required this.pricingReason,
    required this.firstPurchase,
    this.promoCode,
    this.promoKind,
    this.affiliateCommissionCents = 0,
    this.promoNote,
    this.promoError,
  });

  int get amountPounds => amountCents ~/ 100;
  int get listPounds => listCents ~/ 100;
  bool get discounted => amountCents < listCents;

  factory PlusQuote.fromJson(Map<String, dynamic> json) {
    return PlusQuote(
      plan: (json['plan'] as String?) ?? 'monthly',
      days: (json['days'] as num?)?.toInt() ?? 30,
      listCents: (json['list_cents'] as num?)?.toInt() ?? PlusCatalog.listMonthlyCents,
      amountCents: (json['amount_cents'] as num?)?.toInt() ?? PlusCatalog.listMonthlyCents,
      pricingReason: (json['pricing_reason'] as String?) ?? 'list',
      firstPurchase: json['first_purchase'] == true,
      promoCode: json['promo_code'] as String?,
      promoKind: json['promo_kind'] as String?,
      affiliateCommissionCents: (json['affiliate_commission_cents'] as num?)?.toInt() ?? 0,
      promoNote: json['promo_note'] as String?,
      promoError: json['promo_error'] as String?,
    );
  }
}

/// Local mirror of the server catalog so the paywall is honest offline.
/// Checkout still re-quotes on the server; this never charges anyone.
class PlusPricing {
  PlusPricing._();

  static String normalizeCode(String? raw) =>
      (raw ?? '').trim().toUpperCase().replaceAll(RegExp(r'\s+'), '');

  static PlusQuote quote({
    required String plan,
    required bool firstPurchase,
    PlusPromo? promo,
    String buyerUserId = 'local',
  }) {
    final product = PlusCatalog.byId(plan);
    var amount = product.amountCents;
    var reason = 'list';

    String? promoCode;
    String? promoKind;
    var commission = 0;
    String? note;
    String? error;

    final code = promo;
    if (code != null) {
      promoCode = normalizeCode(code.code);
      promoKind = code.kind;
      if (code.isAffiliate) {
        if (code.ownerUserId != null && code.ownerUserId == buyerUserId) {
          error = 'You cannot use your own code';
        } else {
          // The price does not move; the professional's share comes out of it.
          reason = 'affiliate';
          commission = amount * PlusCatalog.proSharePercent ~/ 100;
          note = 'Your nutritionist follows your plan and earns a share of this subscription. The price is the same.';
        }
      } else {
        final applies = code.appliesToPlans;
        if (applies != null && applies.isNotEmpty && !applies.contains(plan)) {
          error = 'This code does not apply to this plan';
        } else {
          int? next;
          if (code.amountCents != null && code.amountCents! > 0) {
            next = code.amountCents;
          } else if (code.percentOff != null && code.percentOff! > 0) {
            next = (product.amountCents * (100 - code.percentOff!) / 100).round();
          }
          if (next != null && next < amount) {
            amount = next;
            reason = 'campaign';
          } else {
            note = 'Your current price is already lower than this code';
          }
        }
      }
    }

    return PlusQuote(
      plan: plan,
      days: product.periodDays,
      listCents: product.amountCents,
      amountCents: amount,
      pricingReason: reason,
      firstPurchase: firstPurchase,
      promoCode: promoCode,
      promoKind: promoKind,
      affiliateCommissionCents: commission,
      promoNote: note,
      promoError: error,
    );
  }
}

/// Server-authoritative Qamar+ status. The phone never flips this itself.
class PlusEntitlement {
  final String status;
  final String? plan;
  final DateTime? periodEnd;
  final String provider;
  final bool firstPurchase;

  const PlusEntitlement({
    required this.status,
    this.plan,
    this.periodEnd,
    this.provider = PlusCatalog.provider,
    this.firstPurchase = true,
  });

  static const free = PlusEntitlement(status: 'free');

  bool get active {
    if (status != 'active') return false;
    final end = periodEnd;
    if (end == null) return true;
    return !end.isBefore(DateTime.now().toUtc());
  }

  factory PlusEntitlement.fromJson(Map<String, dynamic> json) {
    final endRaw = json['period_end'] ?? json['periodEnd'];
    return PlusEntitlement(
      status: (json['status'] as String?) ?? 'free',
      plan: json['plan'] as String?,
      periodEnd: endRaw is String ? DateTime.tryParse(endRaw)?.toUtc() : null,
      provider: (json['provider'] as String?) ?? PlusCatalog.provider,
      firstPurchase: json['first_purchase'] != false,
    );
  }
}

class CheckoutSession {
  final String checkoutUrl;
  final String orderId;
  final int? amountCents;
  const CheckoutSession({
    required this.checkoutUrl,
    required this.orderId,
    this.amountCents,
  });
}

/// EGP cash owed to an affiliate. Separate from the Su Points wallet.
class AffiliateWallet {
  final String? code;
  final int balanceCents;
  final int lifetimeEarnedCents;
  final int pendingPayoutCents;
  final String currency;
  final int minPayoutCents;

  const AffiliateWallet({
    this.code,
    this.balanceCents = 0,
    this.lifetimeEarnedCents = 0,
    this.pendingPayoutCents = 0,
    this.currency = PlusCatalog.currency,
    this.minPayoutCents = PlusCatalog.minPayoutCents,
  });

  static const empty = AffiliateWallet();

  int get balancePounds => balanceCents ~/ 100;
  bool get canRedeem => balanceCents >= minPayoutCents;

  factory AffiliateWallet.fromJson(Map<String, dynamic> json) {
    return AffiliateWallet(
      code: json['code'] as String?,
      balanceCents: (json['balance_cents'] as num?)?.toInt() ?? 0,
      lifetimeEarnedCents: (json['lifetime_earned_cents'] as num?)?.toInt() ?? 0,
      pendingPayoutCents: (json['pending_payout_cents'] as num?)?.toInt() ?? 0,
      currency: (json['currency'] as String?) ?? PlusCatalog.currency,
      minPayoutCents: (json['min_payout_cents'] as num?)?.toInt() ?? PlusCatalog.minPayoutCents,
    );
  }
}

String formatEgp(int pounds, {required bool ar}) {
  if (!ar) return 'EGP $pounds';
  const western = '0123456789';
  const eastern = '٠١٢٣٤٥٦٧٨٩';
  final mapped = pounds.toString().split('').map((c) {
    final i = western.indexOf(c);
    return i >= 0 ? eastern[i] : c;
  }).join();
  return '$mapped ج.م';
}
