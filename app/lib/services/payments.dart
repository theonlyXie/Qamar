import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:url_launcher/url_launcher.dart';

import '../models/billing.dart';

/// Server-gateway for Qamar+. Paymob is the Egyptian collector — EGP, cards,
/// Meeza, Vodafone Cash / Orange Cash. The app never holds a Paymob secret
/// and never marks someone Plus from a browser redirect.
abstract class BillingGateway {
  Future<PlusQuote> quote({required String plan, String? promoCode});
  Future<CheckoutSession> checkout({
    required String plan,
    String? promoCode,
    String? email,
    String? phone,
    String? firstName,
  });
  Future<PlusEntitlement> entitlement();

  /// Starts the free week. The server refuses a second one; the message
  /// in the [BillingException] says why.
  Future<PlusEntitlement> startTrial();

  /// Where the earned month stands: logged days in the first 30 of membership.
  Future<EarnedMonth> earnedMonth();

  /// Grants the earned month once 28 days are logged. The server re-checks;
  /// the [BillingException] says why when it refuses.
  Future<EarnedMonthClaim> claimEarnedMonth();
  Future<AffiliateWallet> affiliate();
  Future<AffiliateWallet> requestAffiliatePayout({int? amountCents});

  /// The professional's clients who said yes to sharing, with this week's
  /// adherence. Empty for anyone who is not a professional.
  Future<List<ProClient>> affiliateClients();
}

class HttpBillingGateway implements BillingGateway {
  final String baseUrl;
  final String Function() authTokenProvider;
  final http.Client _client;

  HttpBillingGateway({
    required this.baseUrl,
    required this.authTokenProvider,
    http.Client? client,
  }) : _client = client ?? http.Client();

  Map<String, String> get _headers => {
        'Content-Type': 'application/json',
        'Authorization': 'Bearer ${authTokenProvider()}',
      };

  @override
  Future<PlusQuote> quote({required String plan, String? promoCode}) async {
    final res = await _client.post(
      Uri.parse('$baseUrl/quote'),
      headers: _headers,
      body: jsonEncode({
        'plan': plan,
        if (promoCode != null && promoCode.isNotEmpty) 'promo_code': promoCode,
      }),
    );
    if (res.statusCode != 200) {
      throw BillingException('quote failed: ${res.statusCode} ${res.body}');
    }
    return PlusQuote.fromJson(jsonDecode(utf8.decode(res.bodyBytes)) as Map<String, dynamic>);
  }

  @override
  Future<CheckoutSession> checkout({
    required String plan,
    String? promoCode,
    String? email,
    String? phone,
    String? firstName,
  }) async {
    final res = await _client.post(
      Uri.parse('$baseUrl/checkout'),
      headers: _headers,
      body: jsonEncode({
        'plan': plan,
        if (promoCode != null && promoCode.isNotEmpty) 'promo_code': promoCode,
        if (email != null && email.isNotEmpty) 'email': email,
        if (phone != null && phone.isNotEmpty) 'phone': phone,
        if (firstName != null && firstName.isNotEmpty) 'first_name': firstName,
      }),
    );
    if (res.statusCode != 200) {
      throw BillingException('checkout failed: ${res.statusCode} ${res.body}');
    }
    final json = jsonDecode(utf8.decode(res.bodyBytes)) as Map<String, dynamic>;
    final url = json['checkout_url'] as String?;
    final orderId = json['order_id'] as String?;
    if (url == null || orderId == null) {
      throw BillingException('checkout returned no Paymob session');
    }
    return CheckoutSession(
      checkoutUrl: url,
      orderId: orderId,
      amountCents: (json['amount_cents'] as num?)?.toInt(),
    );
  }

  @override
  Future<PlusEntitlement> entitlement() async {
    final res = await _client.post(
      Uri.parse('$baseUrl/entitlement'),
      headers: _headers,
      body: jsonEncode({}),
    );
    if (res.statusCode != 200) {
      throw BillingException('entitlement failed: ${res.statusCode} ${res.body}');
    }
    return PlusEntitlement.fromJson(jsonDecode(utf8.decode(res.bodyBytes)) as Map<String, dynamic>);
  }

  @override
  Future<PlusEntitlement> startTrial() async {
    final res = await _client.post(
      Uri.parse('$baseUrl/trial/start'),
      headers: _headers,
      body: jsonEncode({}),
    );
    if (res.statusCode != 200) {
      String reason = 'trial failed: ${res.statusCode}';
      try {
        final body = jsonDecode(utf8.decode(res.bodyBytes));
        if (body is Map && body['error'] is String) reason = body['error'] as String;
      } catch (_) {}
      throw BillingException(reason);
    }
    return PlusEntitlement.fromJson(jsonDecode(utf8.decode(res.bodyBytes)) as Map<String, dynamic>);
  }

  @override
  Future<EarnedMonth> earnedMonth() async {
    final res = await _client.post(Uri.parse('$baseUrl/earned'), headers: _headers, body: jsonEncode({}));
    if (res.statusCode != 200) {
      throw BillingException('earned month failed: ${res.statusCode} ${res.body}');
    }
    return EarnedMonth.fromJson(jsonDecode(utf8.decode(res.bodyBytes)) as Map<String, dynamic>);
  }

  @override
  Future<EarnedMonthClaim> claimEarnedMonth() async {
    final res = await _client.post(Uri.parse('$baseUrl/earned/claim'), headers: _headers, body: jsonEncode({}));
    if (res.statusCode != 200) {
      String reason = 'earned month claim failed: ${res.statusCode}';
      try {
        final body = jsonDecode(utf8.decode(res.bodyBytes));
        if (body is Map && body['error'] is String) reason = body['error'] as String;
      } catch (_) {}
      throw BillingException(reason);
    }
    return EarnedMonthClaim.fromJson(jsonDecode(utf8.decode(res.bodyBytes)) as Map<String, dynamic>);
  }

  @override
  Future<List<ProClient>> affiliateClients() async {
    final res = await _client.post(Uri.parse('$baseUrl/affiliate/clients'), headers: _headers, body: jsonEncode({}));
    if (res.statusCode != 200) {
      throw BillingException('clients failed: ${res.statusCode} ${res.body}');
    }
    return ProClient.listFromJson(jsonDecode(utf8.decode(res.bodyBytes)) as Map<String, dynamic>);
  }

  @override
  Future<AffiliateWallet> affiliate() async {
    final res = await _client.post(
      Uri.parse('$baseUrl/affiliate'),
      headers: _headers,
      body: jsonEncode({}),
    );
    if (res.statusCode != 200) {
      throw BillingException('affiliate failed: ${res.statusCode} ${res.body}');
    }
    return AffiliateWallet.fromJson(jsonDecode(utf8.decode(res.bodyBytes)) as Map<String, dynamic>);
  }

  @override
  Future<AffiliateWallet> requestAffiliatePayout({int? amountCents}) async {
    final res = await _client.post(
      Uri.parse('$baseUrl/affiliate/payout'),
      headers: _headers,
      body: jsonEncode({
        if (amountCents != null) 'amount_cents': amountCents,
      }),
    );
    if (res.statusCode != 200) {
      throw BillingException('payout failed: ${res.statusCode} ${res.body}');
    }
    return AffiliateWallet.fromJson(jsonDecode(utf8.decode(res.bodyBytes)) as Map<String, dynamic>);
  }
}

/// Opens Paymob's hosted checkout in the system browser.
Future<bool> openPaymobCheckout(String url) {
  return launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication);
}

/// Opens a partner's page in the system browser or their app — the grocery
/// basket, for one. Same posture as checkout: the person sees the address.
Future<bool> openExternalUrl(String url) {
  return launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication);
}

class BillingException implements Exception {
  final String message;
  BillingException(this.message);
  @override
  String toString() => 'BillingException: $message';
}
