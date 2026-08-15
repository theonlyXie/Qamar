import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart' show visibleForTesting;
import 'package:http/http.dart' as http;

import '../models/meal.dart';
import '../models/plan.dart';

/// A meal analysis result — candidate items with confidence, before the
/// user confirms (MealDraft in spec_mvp.txt Part 28). Never auto-written.
///
/// [note] is what the assistant wants to say about the reading itself ("the
/// rice is hidden behind the chicken, so that portion is a guess"), already in
/// the user's language. An empty [items] with a note is a legitimate answer:
/// it means the photo could not be read, not that the call failed.
class MealAnalysis {
  final List<ConfirmItemDef> items;
  final String? note;
  const MealAnalysis(this.items, {this.note});
}

/// What could be read off a body-composition report. Every field is nullable
/// on purpose: the reader returns null for anything it cannot plainly see, and
/// the app then asks the question rather than filling the gap itself.
class BodyScan {
  final int? heightCm;
  final int? weightKg;
  final int? bodyFatPct;
  final int? age;
  final String? note;
  const BodyScan({this.heightCm, this.weightKg, this.bodyFatPct, this.age, this.note});

  bool get isEmpty => heightCm == null && weightKg == null && bodyFatPct == null && age == null;
}

/// A generated day of eating, plus why it was built that way.
class DayPlan {
  /// Each slot's meal and the alternative offered for it, in slot order.
  final List<(PlanMeal, PlanMeal)> slots;
  final String? rationale;
  final String date;
  const DayPlan({required this.slots, required this.date, this.rationale});
}

/// Server-gateway boundary for anything model-backed: meal photo/voice/text
/// analysis, and the Ask-Qamar chat reply. Per spec_mvp.txt §29.1 the app
/// never holds a model API key — every call here is a plain HTTPS request to
/// your own backend, which then calls the model with server-side credentials
/// and schema validation.
///
/// There is deliberately no mock implementation. An assistant that answers
/// from a script is indistinguishable from a working one until someone trusts
/// it with a real meal, so when the gateway is not configured the app is
/// handed `null` and says out loud that it is not connected.
abstract class AiGateway {
  /// [imagePath] is a local file; it is read and sent inline, so the gateway
  /// needs no access to the phone's storage.
  Future<MealAnalysis> analyzeMeal({
    required String inputType,
    String? text,
    String? imagePath,
    String lang = 'ar',
  });

  Future<String> chatReply({required String message, required String lang});

  /// Reads an InBody or similar body-composition printout.
  Future<BodyScan> readBodyScan({required String imagePath, required String lang});

  /// Builds the day's meals around the person's target and exclusions.
  /// [date] is ISO yyyy-MM-dd; the gateway stores the result against it.
  Future<DayPlan> generatePlan({required String date, required String lang});
}

/// Talks to your own server gateway (supabase/functions/ai-gateway). The
/// gateway owns the model credentials, the retrieval and the scope guard —
/// this class only ever sees your backend's URL and the user's own token.
class HttpAiGateway implements AiGateway {
  final String baseUrl;
  final String Function() authTokenProvider;
  final http.Client _client;

  HttpAiGateway({
    required this.baseUrl,
    required this.authTokenProvider,
    http.Client? client,
  }) : _client = client ?? http.Client();

  Map<String, String> get _headers => {
        'Content-Type': 'application/json',
        'Authorization': 'Bearer ${authTokenProvider()}',
      };

  static const _mediaTypes = {
    'jpg': 'image/jpeg',
    'jpeg': 'image/jpeg',
    'png': 'image/png',
    'webp': 'image/webp',
    'gif': 'image/gif',
  };

  static String _mediaTypeFor(String path) {
    final dot = path.lastIndexOf('.');
    if (dot == -1) return 'image/jpeg';
    return _mediaTypes[path.substring(dot + 1).toLowerCase()] ?? 'image/jpeg';
  }

  /// Reads a local image into the form the gateway takes. Returns nulls when
  /// there is no path.
  Future<({String? data, String? mediaType})> _encode(String? imagePath) async {
    if (imagePath == null || imagePath.isEmpty) return (data: null, mediaType: null);
    final file = File(imagePath);
    if (!await file.exists()) {
      throw AiGatewayException('the photo is no longer on disk: $imagePath');
    }
    return (data: base64Encode(await file.readAsBytes()), mediaType: _mediaTypeFor(imagePath));
  }

  @override
  Future<MealAnalysis> analyzeMeal({
    required String inputType,
    String? text,
    String? imagePath,
    String lang = 'ar',
  }) async {
    final (data: imageBase64, mediaType: imageMediaType) = await _encode(imagePath);

    final res = await _client.post(
      Uri.parse('$baseUrl/meal/analyze'),
      headers: _headers,
      body: jsonEncode({
        'inputType': inputType,
        'lang': lang,
        if (text != null && text.isNotEmpty) 'text': text,
        if (imageBase64 != null) 'imageBase64': imageBase64,
        if (imageMediaType != null) 'imageMediaType': imageMediaType,
      }),
    );
    if (res.statusCode != 200) {
      throw AiGatewayException('analyzeMeal failed: ${res.statusCode} ${res.body}');
    }
    // The body carries Arabic, so decode as UTF-8 rather than trusting the
    // latin-1 default http falls back to when a charset is missing.
    final json = jsonDecode(utf8.decode(res.bodyBytes)) as Map<String, dynamic>;
    final items = ((json['items'] as List?) ?? const [])
        .map((e) => _itemFromJson(e as Map<String, dynamic>))
        .toList();
    return MealAnalysis(items, note: json['note'] as String?);
  }

  @override
  Future<String> chatReply({required String message, required String lang}) async {
    final res = await _client.post(
      Uri.parse('$baseUrl/chat/reply'),
      headers: _headers,
      body: jsonEncode({'message': message, 'lang': lang}),
    );
    if (res.statusCode != 200) {
      throw AiGatewayException('chatReply failed: ${res.statusCode} ${res.body}');
    }
    final json = jsonDecode(utf8.decode(res.bodyBytes)) as Map<String, dynamic>;
    return json['reply'] as String;
  }

  @override
  Future<BodyScan> readBodyScan({required String imagePath, required String lang}) async {
    final (data: imageBase64, mediaType: imageMediaType) = await _encode(imagePath);
    final res = await _client.post(
      Uri.parse('$baseUrl/scan/read'),
      headers: _headers,
      body: jsonEncode({'imageBase64': imageBase64, 'imageMediaType': imageMediaType, 'lang': lang}),
    );
    if (res.statusCode != 200) {
      throw AiGatewayException('readBodyScan failed: ${res.statusCode} ${res.body}');
    }
    final json = jsonDecode(utf8.decode(res.bodyBytes)) as Map<String, dynamic>;
    return BodyScan(
      heightCm: _nullableInt(json['heightCm']),
      weightKg: _nullableInt(json['weightKg']),
      bodyFatPct: _nullableInt(json['bodyFatPct']),
      age: _nullableInt(json['age']),
      note: json['note'] as String?,
    );
  }

  static int? _nullableInt(Object? v) => v is num ? v.round() : null;

  @override
  Future<DayPlan> generatePlan({required String date, required String lang}) async {
    final res = await _client.post(
      Uri.parse('$baseUrl/plan/generate'),
      headers: _headers,
      body: jsonEncode({'date': date, 'lang': lang}),
    );
    if (res.statusCode != 200) {
      throw AiGatewayException('generatePlan failed: ${res.statusCode} ${res.body}');
    }
    return planFromBody(utf8.decode(res.bodyBytes), lang, date);
  }

  /// Parses a `plan/generate` response. Separate from the request so the
  /// shape the gateway promises can be tested without a network.
  @visibleForTesting
  DayPlan planFromBody(String body, String lang, String fallbackDate) {
    final json = jsonDecode(body) as Map<String, dynamic>;
    final plan = json['plan'] as Map<String, dynamic>;
    final meals = (plan['meals'] as List).cast<Map<String, dynamic>>();

    return DayPlan(
      date: json['date'] as String? ?? fallbackDate,
      rationale: (lang == 'ar' ? plan['rationale_ar'] : plan['rationale_en']) as String?,
      slots: [
        for (final m in meals)
          (
            _mealFromJson(m, m),
            // A meal without an alternative falls back to itself. The UI then
            // hides that slot's swap button rather than offering a swap to
            // the same dish.
            _mealFromJson((m['alt'] as Map<String, dynamic>?) ?? m, m),
          ),
      ],
    );
  }

  static const _slotLabels = {
    'breakfast': ('فطار', 'Breakfast'),
    'lunch': ('غدا', 'Lunch'),
    'dinner': ('عشا', 'Dinner'),
    'snack': ('سناك', 'Snack'),
  };

  /// [source] carries the slot, which an `alt` object does not repeat.
  static PlanMeal _mealFromJson(Map<String, dynamic> m, Map<String, dynamic> source) {
    final slot = (source['slot'] as String? ?? 'meal').toLowerCase();
    final labels = _slotLabels[slot] ?? (slot, slot);
    return (
      id: slot,
      slotAr: labels.$1,
      slotEn: labels.$2,
      nameAr: (m['name_ar'] ?? m['name_en'] ?? '') as String,
      nameEn: (m['name_en'] ?? m['name_ar'] ?? '') as String,
      noteAr: (m['note_ar'] ?? '') as String,
      noteEn: (m['note_en'] ?? '') as String,
      portions: [
        for (final p in ((m['portions'] as List?) ?? const []).cast<Map<String, dynamic>>())
          (
            ar: (p['ar'] ?? p['en'] ?? '') as String,
            en: (p['en'] ?? p['ar'] ?? '') as String,
            amountAr: (p['amount_ar'] ?? '') as String,
            amountEn: (p['amount_en'] ?? '') as String,
            kcal: _int(p['kcal']),
          ),
      ],
    );
  }

  /// Tolerant on purpose: a missing macro is a zero, not a crash mid-meal.
  ConfirmItemDef _itemFromJson(Map<String, dynamic> j) => ConfirmItemDef(
        ar: (j['ar'] ?? j['en'] ?? '') as String,
        en: (j['en'] ?? j['ar'] ?? '') as String,
        portionAr: (j['portionAr'] ?? '') as String,
        portionEn: (j['portionEn'] ?? '') as String,
        conf: j['confidence'] == 'high' ? Confidence.high : Confidence.low,
        kcal: _int(j['kcal']),
        p: _int(j['proteinG']),
        c: _int(j['carbsG']),
        f: _int(j['fatG']),
      );

  static int _int(Object? v) => v is num ? v.round() : 0;
}

class AiGatewayException implements Exception {
  final String message;
  AiGatewayException(this.message);
  @override
  String toString() => 'AiGatewayException: $message';
}
