import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart' show visibleForTesting;
import 'package:http/http.dart' as http;

import '../models/meal.dart';
import '../models/plan.dart';
import '../models/su_economy.dart';

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

/// What Ask Qamar returned, including a menu change that is already saved.
class ChatResult {
  final String reply;
  final String? action;
  final DayPlan? plan;
  final String? rebuildInstruction;

  const ChatResult({
    required this.reply,
    this.action,
    this.plan,
    this.rebuildInstruction,
  });

  bool get changedPlan => plan != null || (rebuildInstruction != null && rebuildInstruction!.trim().isNotEmpty);
}

/// A generated day of eating, plus why it was built that way.
class DayPlan {
  /// Each slot's meal and the alternative offered for it, in slot order.
  final List<(PlanMeal, PlanMeal)> slots;
  final String? rationale;
  final String date;
  const DayPlan({required this.slots, required this.date, this.rationale});
}

/// Server-gateway boundary for anything that talks to the backend about food
/// or Qamar: photographing a meal (model-backed), typing or speaking a meal
/// (food graph, no daily AI use), and the Ask-Qamar chat reply. Per
/// spec_mvp.txt §29.1 the app never holds a model API key — every call here
/// is a plain HTTPS request to your own backend.
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

  Future<ChatResult> chatReply({
    required String message,
    required String lang,
    String? date,
    Map<String, dynamic>? currentPlan,
    List<String>? swappedSlots,
  });

  /// Reads an InBody or similar body-composition printout.
  Future<BodyScan> readBodyScan({required String imagePath, required String lang});

  /// Builds the day's meals around the person's target and exclusions.
  /// [date] is ISO yyyy-MM-dd; the gateway stores the result against it.
  /// [force] writes a new day even when one is already saved. [instruction]
  /// is Qamar's nutritionist note for a rebuild ("too tired to cook").
  Future<DayPlan> generatePlan({
    required String date,
    required String lang,
    bool force = false,
    String? instruction,
  });

  /// Remaining shared uses for chat, photographing a meal, and the plan today.
  Future<AiQuota> quotaStatus();

  /// Packaged barcode via Open Food Facts. No model, no daily AI use.
  Future<MealAnalysis> lookupBarcode({required String code, String lang = 'ar'});
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
    if (res.statusCode == 429) {
      throw AiQuotaException.fromBody(res.bodyBytes);
    }
    if (res.statusCode == 403) {
      throw AiPlusException.fromBody(res.bodyBytes, fallback: 'analyzeMeal failed: ${res.statusCode} ${res.body}');
    }
    if (res.statusCode != 200) {
      throw AiGatewayException('analyzeMeal failed: ${res.statusCode} ${res.body}');
    }
    // The body carries Arabic, so decode as UTF-8 rather than trusting the
    // latin-1 default http falls back to when a charset is missing.
    final json = jsonDecode(utf8.decode(res.bodyBytes)) as Map<String, dynamic>;
    _absorbQuota(json);
    final items = ((json['items'] as List?) ?? const [])
        .map((e) => _itemFromJson(e as Map<String, dynamic>))
        .toList();
    return MealAnalysis(items, note: json['note'] as String?);
  }

  @override
  Future<ChatResult> chatReply({
    required String message,
    required String lang,
    String? date,
    Map<String, dynamic>? currentPlan,
    List<String>? swappedSlots,
  }) async {
    final day = date ?? DateTime.now().toIso8601String().substring(0, 10);
    final res = await _client.post(
      Uri.parse('$baseUrl/chat/reply'),
      headers: _headers,
      body: jsonEncode({
        'message': message,
        'lang': lang,
        'date': day,
        if (currentPlan != null) 'current_plan': currentPlan,
        if (swappedSlots != null && swappedSlots.isNotEmpty) 'swapped_slots': swappedSlots,
      }),
    );
    if (res.statusCode == 429) {
      throw AiQuotaException.fromBody(res.bodyBytes);
    }
    if (res.statusCode != 200) {
      throw AiGatewayException('chatReply failed: ${res.statusCode} ${res.body}');
    }
    final json = jsonDecode(utf8.decode(res.bodyBytes)) as Map<String, dynamic>;
    _absorbQuota(json);
    return chatResultFromJson(json, lang: lang, date: day);
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
  Future<DayPlan> generatePlan({
    required String date,
    required String lang,
    bool force = false,
    String? instruction,
  }) async {
    final res = await _client.post(
      Uri.parse('$baseUrl/plan/generate'),
      headers: _headers,
      body: jsonEncode({
        'date': date,
        'lang': lang,
        if (force) 'force': true,
        if (instruction != null && instruction.trim().isNotEmpty) 'instruction': instruction.trim(),
      }),
    );
    if (res.statusCode == 429) {
      throw AiQuotaException.fromBody(res.bodyBytes);
    }
    if (res.statusCode == 403) {
      throw AiPlusException.fromBody(res.bodyBytes, fallback: 'generatePlan failed: ${res.statusCode} ${res.body}');
    }
    if (res.statusCode != 200) {
      throw AiGatewayException('generatePlan failed: ${res.statusCode} ${res.body}');
    }
    final decoded = utf8.decode(res.bodyBytes);
    final json = jsonDecode(decoded) as Map<String, dynamic>;
    _absorbQuota(json);
    return planFromBody(decoded, lang, date);
  }

  /// Parses a `plan/generate` response. Separate from the request so the
  /// shape the gateway promises can be tested without a network.
  @visibleForTesting
  DayPlan planFromBody(String body, String lang, String fallbackDate) {
    return dayPlanFromJson(jsonDecode(body) as Map<String, dynamic>, lang, fallbackDate);
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
        // Snake case because these come straight from the gateway, which named
        // them after the database columns they end up in.
        qamarFoodId: j['qamar_food_id'] as String?,
        grams: _double(j['grams']),
        portionMatched: j['portion_matched'] == true,
      );

  static int _int(Object? v) => v is num ? v.round() : 0;
  static double? _double(Object? v) => v is num ? v.toDouble() : null;

  AiQuota? lastQuota;

  void _absorbQuota(Map<String, dynamic> json) {
    final raw = json['quota'];
    if (raw is Map) {
      lastQuota = AiQuota.fromJson(Map<String, dynamic>.from(raw));
    }
  }

  @override
  Future<AiQuota> quotaStatus() async {
    final res = await _client.post(
      Uri.parse('$baseUrl/quota'),
      headers: _headers,
      body: jsonEncode({}),
    );
    if (res.statusCode != 200) {
      throw AiGatewayException('quotaStatus failed: ${res.statusCode} ${res.body}');
    }
    final json = jsonDecode(utf8.decode(res.bodyBytes)) as Map<String, dynamic>;
    lastQuota = AiQuota.fromJson(json);
    return lastQuota!;
  }

  @override
  Future<MealAnalysis> lookupBarcode({required String code, String lang = 'ar'}) async {
    final res = await _client.post(
      Uri.parse('$baseUrl/meal/barcode'),
      headers: _headers,
      body: jsonEncode({'code': code, 'lang': lang}),
    );
    if (res.statusCode != 200) {
      throw AiGatewayException('lookupBarcode failed: ${res.statusCode} ${res.body}');
    }
    final json = jsonDecode(utf8.decode(res.bodyBytes)) as Map<String, dynamic>;
    final items = ((json['items'] as List?) ?? const [])
        .map((e) => _itemFromJson(e as Map<String, dynamic>))
        .toList();
    return MealAnalysis(items, note: json['note'] as String?);
  }
}

/// Today's five uses are gone. The wallet is how they buy another, not a paywall.
class AiQuotaException implements Exception {
  final String message;
  final AiQuota quota;
  AiQuotaException(this.message, this.quota);

  factory AiQuotaException.fromBody(List<int> bytes) {
    try {
      final json = jsonDecode(utf8.decode(bytes)) as Map<String, dynamic>;
      final raw = json['quota'];
      final quota = raw is Map
          ? AiQuota.fromJson(Map<String, dynamic>.from(raw))
          : AiQuota.empty;
      return AiQuotaException(
        (json['error'] as String?) ?? (json['reply'] as String?) ?? 'quota',
        quota,
      );
    } catch (_) {
      return AiQuotaException('quota', AiQuota.empty);
    }
  }

  @override
  String toString() => 'AiQuotaException: $message';
}

const _slotLabels = {
  'breakfast': ('فطار', 'Breakfast'),
  'lunch': ('غدا', 'Lunch'),
  'dinner': ('عشا', 'Dinner'),
  'snack': ('سناك', 'Snack'),
};

int _jsonInt(Object? v) => v is num ? v.round() : 0;

/// [source] carries the slot, which an `alt` object does not repeat.
PlanMeal mealFromJson(Map<String, dynamic> m, Map<String, dynamic> source) {
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
          kcal: _jsonInt(p['kcal']),
        ),
    ],
  );
}

Map<String, dynamic> mealToWire(PlanMeal m) => {
      'slot': m.id,
      'name_ar': m.nameAr,
      'name_en': m.nameEn,
      'note_ar': m.noteAr,
      'note_en': m.noteEn,
      'portions': [
        for (final p in m.portions)
          {
            'ar': p.ar,
            'en': p.en,
            'amount_ar': p.amountAr,
            'amount_en': p.amountEn,
            'kcal': p.kcal,
          },
      ],
    };

/// The menu Qamar currently has on Plan/Today, in the shape the gateway edits.
Map<String, dynamic> planToWire(DayPlan plan) => {
      'date': plan.date,
      'meals': [
        for (final (base, alt) in plan.slots)
          {
            ...mealToWire(base),
            'alt': mealToWire(alt)..remove('slot'),
          },
      ],
    };

DayPlan dayPlanFromJson(Map<String, dynamic> json, String lang, String fallbackDate) {
  final plan = json['plan'] as Map<String, dynamic>;
  final meals = (plan['meals'] as List).cast<Map<String, dynamic>>();

  return DayPlan(
    date: json['date'] as String? ?? fallbackDate,
    rationale: (lang == 'ar' ? plan['rationale_ar'] : plan['rationale_en']) as String?,
    slots: [
      for (final m in meals)
        (
          mealFromJson(m, m),
          // A meal without an alternative falls back to itself. The UI then
          // hides that slot's swap button rather than offering a swap to
          // the same dish.
          mealFromJson((m['alt'] as Map<String, dynamic>?) ?? m, m),
        ),
    ],
  );
}

ChatResult chatResultFromJson(
  Map<String, dynamic> json, {
  required String lang,
  required String date,
}) {
  DayPlan? plan;
  final planRaw = json['plan'];
  if (planRaw is Map && ((planRaw['meals'] as List?)?.isNotEmpty ?? false)) {
    plan = dayPlanFromJson(
      {'plan': Map<String, dynamic>.from(planRaw), 'date': json['date'] ?? date},
      lang,
      date,
    );
  }

  String? rebuild;
  final update = json['plan_update'];
  if (update is Map) {
    final kind = '${update['kind'] ?? update['type'] ?? ''}'.toLowerCase();
    if (kind == 'rebuild' || kind == 'regenerate' || kind == 'rebalance') {
      final inst = '${update['instruction'] ?? update['reason'] ?? ''}'.trim();
      if (inst.isNotEmpty) rebuild = inst;
    }
  }

  final action = json['action'] as String?;
  return ChatResult(
    reply: (json['reply'] as String?) ?? '',
    action: (action != null && action.trim().isNotEmpty) ? action.trim() : null,
    plan: plan,
    rebuildInstruction: rebuild,
  );
}

class AiGatewayException implements Exception {
  final String message;
  AiGatewayException(this.message);
  @override
  String toString() => 'AiGatewayException: $message';
}

/// Photographing a plate, or a plan for a day that is not today, needs Qamar+.
class AiPlusException implements Exception {
  final String message;
  final String feature;
  AiPlusException(this.message, {this.feature = 'plus'});

  factory AiPlusException.fromBody(List<int> bytes, {required String fallback}) {
    try {
      final json = jsonDecode(utf8.decode(bytes)) as Map<String, dynamic>;
      final reason = json['reason'] as String?;
      if (reason == 'plus_required') {
        return AiPlusException(
          (json['error'] as String?) ?? fallback,
          feature: (json['feature'] as String?) ?? 'plus',
        );
      }
    } catch (_) {}
    throw AiGatewayException(fallback);
  }

  @override
  String toString() => 'AiPlusException: $message';
}
