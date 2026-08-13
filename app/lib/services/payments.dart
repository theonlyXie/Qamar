import 'dart:async';
import 'package:in_app_purchase/in_app_purchase.dart';

/// Qamar+ is the only real-money product — Su Points are explicitly
/// "never purchased, never cash" per the wallet's own terms copy
/// (l10n/strings.dart: walletTerms). Configure these IDs to match what you
/// create in App Store Connect / Google Play Console.
class QamarProductIds {
  QamarProductIds._();
  static const monthly = 'qamar_plus_monthly';
  static const annual = 'qamar_plus_annual';
  static const all = {monthly, annual};
}

/// Thin wrapper over `in_app_purchase`. Per spec_mvp.txt §29.1, this client
/// never decides entitlement on its own — every completed purchase must be
/// verified server-side (App Store Server API / Google Play Developer API,
/// or a RevenueCat webhook) before the app is told Qamar+ is active. Not
/// wired into the You/paywall screens yet.
class PaymentsService {
  final InAppPurchase _iap = InAppPurchase.instance;
  StreamSubscription<List<PurchaseDetails>>? _sub;

  /// Called once you have a backend endpoint to verify a completed purchase
  /// and flip the user's Entitlement row (spec_mvp.txt Part 28).
  final Future<void> Function(PurchaseDetails purchase) onVerifyPurchase;

  PaymentsService({required this.onVerifyPurchase});

  Future<bool> isAvailable() => _iap.isAvailable();

  Future<List<ProductDetails>> loadProducts() async {
    final res = await _iap.queryProductDetails(QamarProductIds.all);
    if (res.error != null) {
      throw StateError('queryProductDetails failed: ${res.error}');
    }
    return res.productDetails;
  }

  void startListening() {
    _sub = _iap.purchaseStream.listen(_onPurchaseUpdate, onError: (Object e) {});
  }

  void stopListening() => _sub?.cancel();

  Future<void> buy(ProductDetails product) async {
    final param = PurchaseParam(productDetails: product);
    await _iap.buyNonConsumable(purchaseParam: param);
  }

  Future<void> restorePurchases() => _iap.restorePurchases();

  Future<void> _onPurchaseUpdate(List<PurchaseDetails> purchases) async {
    for (final p in purchases) {
      switch (p.status) {
        case PurchaseStatus.purchased:
        case PurchaseStatus.restored:
          await onVerifyPurchase(p);
          if (p.pendingCompletePurchase) await _iap.completePurchase(p);
          break;
        case PurchaseStatus.error:
        case PurchaseStatus.canceled:
        case PurchaseStatus.pending:
          break;
      }
    }
  }
}
