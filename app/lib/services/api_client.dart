import 'dart:convert';

import 'package:http/http.dart' as http;

/// Typed client for the Supabase Edge Function `api` (spec_mvp.txt §29.6).
///
/// All AI model calls still go through [AiGateway] / `ai-gateway`. This client
/// covers bootstrap, identity helpers, consents, profile/targets, meals/media,
/// foods/barcodes, plans, progress, chat lifecycle, memory, journey/wallet,
/// billing, notifications, privacy, analytics, and (for founder builds) admin.
class QamarApiClient {
  final String baseUrl;
  final String Function() authTokenProvider;
  final http.Client _client;

  QamarApiClient({
    required this.baseUrl,
    required this.authTokenProvider,
    http.Client? client,
  }) : _client = client ?? http.Client();

  Uri _uri(String path, [Map<String, String>? query]) {
    final normalized = baseUrl.endsWith('/') ? baseUrl.substring(0, baseUrl.length - 1) : baseUrl;
    final p = path.startsWith('/') ? path : '/$path';
    return Uri.parse('$normalized$p').replace(queryParameters: query);
  }

  Map<String, String> _headers({String? idempotencyKey}) => {
        'Content-Type': 'application/json',
        'Authorization': 'Bearer ${authTokenProvider()}',
        if (idempotencyKey != null) 'Idempotency-Key': idempotencyKey,
      };

  Future<Map<String, dynamic>> _send(
    String method,
    String path, {
    Map<String, dynamic>? body,
    Map<String, String>? query,
    String? idempotencyKey,
  }) async {
    final uri = _uri(path, query);
    final headers = _headers(idempotencyKey: idempotencyKey);
    late http.Response res;
    switch (method) {
      case 'GET':
        res = await _client.get(uri, headers: headers);
        break;
      case 'POST':
        res = await _client.post(uri, headers: headers, body: jsonEncode(body ?? {}));
        break;
      case 'PATCH':
        res = await _client.patch(uri, headers: headers, body: jsonEncode(body ?? {}));
        break;
      case 'DELETE':
        res = await _client.delete(uri, headers: headers, body: body == null ? null : jsonEncode(body));
        break;
      default:
        throw QamarApiException('unsupported method $method', status: 0);
    }
    final decoded = res.body.isEmpty ? <String, dynamic>{} : jsonDecode(res.body) as Map<String, dynamic>;
    if (res.statusCode >= 400) {
      final error = decoded['error'] as Map<String, dynamic>?;
      throw QamarApiException(
        error?['message_key'] as String? ?? 'request failed',
        status: res.statusCode,
        code: error?['code'] as String?,
        requestId: decoded['request_id'] as String?,
        retryable: error?['retryable'] as bool? ?? false,
        fieldErrors: (error?['field_errors'] as Map?)?.cast<String, String>(),
      );
    }
    return (decoded['data'] as Map<String, dynamic>?) ?? decoded;
  }

  // ---- Bootstrap --------------------------------------------------------

  Future<Map<String, dynamic>> bootstrap() => _send('GET', '/bootstrap');
  Future<Map<String, dynamic>> config() => _send('GET', '/config');

  // ---- Auth helpers (Supabase Auth remains the primary SDK path) --------

  Future<Map<String, dynamic>> authAnonymous() => _send('POST', '/auth/anonymous');
  Future<Map<String, dynamic>> authOtpStart(String email) =>
      _send('POST', '/auth/otp/start', body: {'email': email});
  Future<Map<String, dynamic>> authOtpVerify({required String email, required String token}) =>
      _send('POST', '/auth/otp/verify', body: {'email': email, 'token': token});
  Future<Map<String, dynamic>> authSessions() => _send('GET', '/auth/sessions');
  Future<Map<String, dynamic>> authSignOut() => _send('DELETE', '/auth/sessions');

  // ---- Consents / profile / targets ------------------------------------

  Future<Map<String, dynamic>> consentsCurrent() => _send('GET', '/consents/current');
  Future<Map<String, dynamic>> postConsent({
    required String type,
    required String version,
    bool granted = true,
  }) =>
      _send('POST', '/consents', body: {'type': type, 'version': version, 'granted': granted});

  Future<Map<String, dynamic>> getProfile() => _send('GET', '/profile');
  Future<Map<String, dynamic>> patchProfile(Map<String, dynamic> patch) =>
      _send('PATCH', '/profile', body: patch);

  Future<Map<String, dynamic>> calculateTarget(Map<String, dynamic> inputs) =>
      _send('POST', '/targets/calculate', body: inputs);
  Future<Map<String, dynamic>> confirmTarget(Map<String, dynamic> draft, {required String idempotencyKey}) =>
      _send('POST', '/targets/new/confirm', body: {'draft': draft}, idempotencyKey: idempotencyKey);

  // ---- Guidance ---------------------------------------------------------

  Future<Map<String, dynamic>> guidanceSource(String id) => _send('GET', '/guidance/sources/$id');
  Future<Map<String, dynamic>> guidanceWhy(String decisionId) => _send('GET', '/guidance/why/$decisionId');

  // ---- Media / meals ----------------------------------------------------

  Future<Map<String, dynamic>> mediaUploadUrl({
    required String mimeType,
    required int byteSize,
    String purpose = 'meal_photo',
  }) =>
      _send('POST', '/media/upload-url', body: {
        'mime_type': mimeType,
        'byte_size': byteSize,
        'purpose': purpose,
      });

  Future<Map<String, dynamic>> createMealDraft(Map<String, dynamic> draft) =>
      _send('POST', '/meal-drafts', body: draft);
  Future<Map<String, dynamic>> parseMealDraft(String id) => _send('POST', '/meal-drafts/$id/parse');
  Future<Map<String, dynamic>> clarifyMealDraft(String id, {Object? answer}) =>
      _send('POST', '/meal-drafts/$id/clarify', body: answer == null ? {} : {'answer': answer});
  Future<Map<String, dynamic>> confirmMealDraft(
    String id, {
    Map<String, dynamic>? body,
    required String idempotencyKey,
  }) =>
      _send('POST', '/meal-drafts/$id/confirm', body: body ?? {}, idempotencyKey: idempotencyKey);

  Future<Map<String, dynamic>> getMeal(String id) => _send('GET', '/meals/$id');
  Future<Map<String, dynamic>> patchMeal(String id, Map<String, dynamic> patch) =>
      _send('PATCH', '/meals/$id', body: patch);
  Future<Map<String, dynamic>> deleteMeal(String id) => _send('DELETE', '/meals/$id');

  // ---- Foods ------------------------------------------------------------

  Future<Map<String, dynamic>> searchFoods(String query) =>
      _send('GET', '/foods/search', query: {'q': query});
  Future<Map<String, dynamic>> getFood(String id) => _send('GET', '/foods/$id');
  Future<Map<String, dynamic>> recentFoods() => _send('GET', '/foods/recent');
  Future<Map<String, dynamic>> barcode(String gtin) => _send('GET', '/barcodes/$gtin');
  Future<Map<String, dynamic>> postFoodCorrection(Map<String, dynamic> proposed) =>
      _send('POST', '/food-corrections', body: proposed);

  // ---- Plans / progress -------------------------------------------------

  Future<Map<String, dynamic>> listPlans({String? date}) =>
      _send('GET', '/plans', query: date == null ? null : {'date': date});
  Future<Map<String, dynamic>> savePlan(Map<String, dynamic> plan, {String? idempotencyKey}) =>
      _send('POST', '/plans', body: plan, idempotencyKey: idempotencyKey);
  Future<Map<String, dynamic>> markPlanEaten(String id, {int? slot, required String idempotencyKey}) =>
      _send('POST', '/plans/$id/mark-eaten',
          body: {if (slot != null) 'slot': slot}, idempotencyKey: idempotencyKey);

  Future<Map<String, dynamic>> progress({int days = 7}) =>
      _send('GET', '/progress', query: {'days': '$days'});
  Future<Map<String, dynamic>> recordWeight(double kg) =>
      _send('POST', '/progress/weight', body: {'value_kg': kg});

  // ---- Chat / memory ----------------------------------------------------

  Future<Map<String, dynamic>> chatResponse({
    required String message,
    String lang = 'ar',
    String? conversationId,
  }) =>
      _send('POST', '/chat/responses', body: {
        'message': message,
        'lang': lang,
        if (conversationId != null) 'conversation_id': conversationId,
      });

  Future<Map<String, dynamic>> stopChat(String conversationId) =>
      _send('POST', '/chat/$conversationId/stop');
  Future<Map<String, dynamic>> reportMessage(String messageId) =>
      _send('POST', '/messages/$messageId/report');

  Future<Map<String, dynamic>> listMemory() => _send('GET', '/memory');
  Future<Map<String, dynamic>> deleteMemory(String id) => _send('DELETE', '/memory/$id');

  // ---- Journey / wallet -------------------------------------------------

  Future<Map<String, dynamic>> journey() => _send('GET', '/journey');
  Future<Map<String, dynamic>> quests() => _send('GET', '/quests');
  Future<Map<String, dynamic>> wallet() => _send('GET', '/wallet');
  Future<Map<String, dynamic>> walletCatalog() => _send('GET', '/wallet/catalog');
  Future<Map<String, dynamic>> walletRedeem({
    required String catalogItemId,
    required String idempotencyKey,
  }) =>
      _send('POST', '/wallet/redeem',
          body: {'catalog_item_id': catalogItemId}, idempotencyKey: idempotencyKey);

  // ---- Billing ----------------------------------------------------------

  Future<Map<String, dynamic>> billingOffering() => _send('GET', '/billing/offering');
  Future<Map<String, dynamic>> billingEntitlement() => _send('GET', '/billing/entitlement');
  Future<Map<String, dynamic>> billingSync(Map<String, dynamic> purchase, {required String idempotencyKey}) =>
      _send('POST', '/billing/sync', body: purchase, idempotencyKey: idempotencyKey);
  Future<Map<String, dynamic>> billingRestore() => _send('POST', '/billing/restore');
  Future<Map<String, dynamic>> validatePromo(String code) =>
      _send('POST', '/promo/validate', body: {'code': code});

  // ---- Devices / reminders ----------------------------------------------

  Future<Map<String, dynamic>> registerDevice({
    required String platform,
    required String pushToken,
    String locale = 'ar',
    String? timezone,
  }) =>
      _send('POST', '/devices', body: {
        'platform': platform,
        'push_token': pushToken,
        'locale': locale,
        if (timezone != null) 'timezone': timezone,
      });

  Future<Map<String, dynamic>> listReminders() => _send('GET', '/reminders');

  // ---- Privacy / analytics ----------------------------------------------

  Future<Map<String, dynamic>> requestExport({required String idempotencyKey}) =>
      _send('POST', '/exports', idempotencyKey: idempotencyKey);
  Future<Map<String, dynamic>> getExport(String id) => _send('GET', '/exports/$id');
  Future<Map<String, dynamic>> requestAccountDeletion({required String idempotencyKey}) =>
      _send('POST', '/account-deletion', idempotencyKey: idempotencyKey);

  Future<Map<String, dynamic>> eventsBatch(List<Map<String, dynamic>> events) =>
      _send('POST', '/events/batch', body: {'events': events});
  Future<Map<String, dynamic>> feedback(String body, {String category = 'general'}) =>
      _send('POST', '/feedback', body: {'body': body, 'category': category});
  Future<Map<String, dynamic>> supportCode() => _send('GET', '/support-code');
}

class QamarApiException implements Exception {
  final String message;
  final int status;
  final String? code;
  final String? requestId;
  final bool retryable;
  final Map<String, String>? fieldErrors;

  QamarApiException(
    this.message, {
    required this.status,
    this.code,
    this.requestId,
    this.retryable = false,
    this.fieldErrors,
  });

  @override
  String toString() => 'QamarApiException($status $code: $message)';
}
