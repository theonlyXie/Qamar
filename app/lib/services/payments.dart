import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:url_launcher/url_launcher.dart';

import '../models/billing.dart';

/// Server-gateway for Qamar+. Paymob is the Egyptian collector — EGP, cards,
/// Meeza, Vodafone Cash / Orange Cash. The app never holds a Paymob secret
/// and never marks someone Plus from a browser redirect.
abstract class BillingGateway {
  Future<CheckoutSession> checkout({required String plan, String? email, String? phone, String? firstName});
  Future<PlusEntitlement> entitlement();
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
  Future<CheckoutSession> checkout({
    required String plan,
    String? email,
    String? phone,
    String? firstName,
  }) async {
    final res = await _client.post(
      Uri.parse('$baseUrl/checkout'),
      headers: _headers,
      body: jsonEncode({
        'plan': plan,
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
    return CheckoutSession(checkoutUrl: url, orderId: orderId);
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
}

/// Opens Paymob's hosted checkout in the system browser.
Future<bool> openPaymobCheckout(String url) {
  return launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication);
}

class BillingException implements Exception {
  final String message;
  BillingException(this.message);
  @override
  String toString() => 'BillingException: $message';
}
