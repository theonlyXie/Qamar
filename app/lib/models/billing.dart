/// Qamar+ as sold in Egypt: Egyptian pounds, collected by Paymob.
///
/// Amounts are in piastres (cents of a pound) because that is what Paymob
/// charges. The paywall shows the pound figure. The server, not the phone,
/// is the price list — the client only names the plan.
class PlusCatalog {
  PlusCatalog._();

  static const currency = 'EGP';
  static const provider = 'paymob';

  static const monthly = PlusProduct(
    id: 'monthly',
    amountCents: 19900,
    periodDays: 30,
    nameAr: 'قمر+ شهري',
    nameEn: 'Qamar+ monthly',
  );

  static const annual = PlusProduct(
    id: 'annual',
    amountCents: 159000,
    periodDays: 365,
    nameAr: 'قمر+ سنوي',
    nameEn: 'Qamar+ annual',
  );

  static PlusProduct byId(String id) => id == annual.id ? annual : monthly;
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

/// Server-authoritative Qamar+ status. The phone never flips this itself.
class PlusEntitlement {
  final String status;
  final String? plan;
  final DateTime? periodEnd;
  final String provider;

  const PlusEntitlement({
    required this.status,
    this.plan,
    this.periodEnd,
    this.provider = PlusCatalog.provider,
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
    );
  }
}

class CheckoutSession {
  final String checkoutUrl;
  final String orderId;
  const CheckoutSession({required this.checkoutUrl, required this.orderId});
}
