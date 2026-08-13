import 'dart:convert';
import 'package:http/http.dart' as http;

import '../models/meal.dart';
import 'config.dart';

/// A meal analysis result — candidate items with confidence, before the
/// user confirms (MealDraft in spec_mvp.txt Part 28). Never auto-written.
class MealAnalysis {
  final List<ConfirmItemDef> items;
  const MealAnalysis(this.items);
}

/// Server-gateway boundary for anything model-backed: meal photo/voice/text
/// analysis, and the Ask-Qamar chat reply. Per spec_mvp.txt §29.1 the app
/// never holds a model API key — every call here is a plain HTTPS request to
/// your own backend (Edge Function, Cloud Run, etc.), which then calls
/// OpenAI/etc. with server-side credentials and schema validation.
abstract class AiGateway {
  Future<MealAnalysis> analyzeMeal({required String inputType, String? text, String? mediaPath});
  Future<String> chatReply({required String message, required String lang});
}

/// Default implementation — mirrors the prototype's canned responses so the
/// app is fully demoable with zero backend. Swap for [HttpAiGateway] once
/// [QamarConfig.useAiGateway] is true.
class MockAiGateway implements AiGateway {
  const MockAiGateway();

  @override
  Future<MealAnalysis> analyzeMeal({required String inputType, String? text, String? mediaPath}) async {
    await Future.delayed(const Duration(milliseconds: 400));
    return const MealAnalysis(kMockConfirmItems);
  }

  @override
  Future<String> chatReply({required String message, required String lang}) async {
    await Future.delayed(const Duration(milliseconds: 400));
    return lang == 'ar' ? 'تمام، هظبط باقي يومك.' : 'Got it, I’ll adjust the rest of your day.';
  }
}

/// Talks to your own server gateway. The gateway owns the actual OpenAI
/// Responses API / Structured Outputs calls (spec_mvp.txt §29.1) — this
/// class only ever sees your backend's URL, never a model provider key.
class HttpAiGateway implements AiGateway {
  final String baseUrl;
  final String Function() authTokenProvider;
  const HttpAiGateway({required this.baseUrl, required this.authTokenProvider});

  Map<String, String> get _headers => {
        'Content-Type': 'application/json',
        'Authorization': 'Bearer ${authTokenProvider()}',
      };

  @override
  Future<MealAnalysis> analyzeMeal({required String inputType, String? text, String? mediaPath}) async {
    final res = await http.post(
      Uri.parse('$baseUrl/meal/analyze'),
      headers: _headers,
      body: jsonEncode({'inputType': inputType, 'text': text, 'mediaPath': mediaPath}),
    );
    if (res.statusCode != 200) {
      throw AiGatewayException('analyzeMeal failed: ${res.statusCode} ${res.body}');
    }
    final json = jsonDecode(res.body) as Map<String, dynamic>;
    final items = (json['items'] as List).map((e) => _itemFromJson(e as Map<String, dynamic>)).toList();
    return MealAnalysis(items);
  }

  @override
  Future<String> chatReply({required String message, required String lang}) async {
    final res = await http.post(
      Uri.parse('$baseUrl/chat/reply'),
      headers: _headers,
      body: jsonEncode({'message': message, 'lang': lang}),
    );
    if (res.statusCode != 200) {
      throw AiGatewayException('chatReply failed: ${res.statusCode} ${res.body}');
    }
    final json = jsonDecode(res.body) as Map<String, dynamic>;
    return json['reply'] as String;
  }

  ConfirmItemDef _itemFromJson(Map<String, dynamic> j) => ConfirmItemDef(
        ar: j['ar'] as String,
        en: j['en'] as String,
        portionAr: j['portionAr'] as String,
        portionEn: j['portionEn'] as String,
        conf: Confidence.values.byName(j['confidence'] as String),
        kcal: j['kcal'] as int,
        p: j['proteinG'] as int,
        c: j['carbsG'] as int,
        f: j['fatG'] as int,
      );
}

class AiGatewayException implements Exception {
  final String message;
  AiGatewayException(this.message);
  @override
  String toString() => 'AiGatewayException: $message';
}
