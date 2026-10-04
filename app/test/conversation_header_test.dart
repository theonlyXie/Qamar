// The conversation's header line (O8): one thing at a time, and the quota
// only near the limit — never a countdown on open, never a number. The full
// count is in Me. Every Arabic number is drawn in Eastern digits.

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

import 'package:qamar/l10n/strings.dart';
import 'package:qamar/main.dart';
import 'package:qamar/models/plan.dart';
import 'package:qamar/models/su_economy.dart';
import 'package:qamar/services/ai_gateway.dart';
import 'package:qamar/screens/you_screen.dart';
import 'package:qamar/state/app_state.dart';
import 'package:qamar/widgets/ask_qamar_overlay.dart';
import 'package:qamar/widgets/explain.dart';

import 'support/app_fonts.dart';
import 'support/arabic_digits.dart';

/// Enough of a gateway for the assistant to exist; nothing here calls it.
class _Ai implements AiGateway {
  @override
  dynamic noSuchMethod(Invocation i) => throw UnimplementedError('${i.memberName}');
}

AiQuota _chat(int remaining, {int limit = 3}) =>
    AiQuota(bucket: 'chat', used: limit - remaining, limit: limit, extra: 0, remaining: remaining);

AppState _state(AppLang lang, {int left = 3}) => AppState(ai: _Ai())
  ..setLang(lang)
  ..aiQuota = _chat(left);

Future<void> _pumpChat(WidgetTester tester, AppState s) async {
  await tester.pumpWidget(ChangeNotifierProvider.value(
    value: s,
    child: MaterialApp(
      builder: (context, child) => Directionality(
        textDirection: s.isAr ? TextDirection.rtl : TextDirection.ltr,
        child: child!,
      ),
      home: const Scaffold(body: AskQamarOverlay()),
    ),
  ));
  await tester.pump(const Duration(milliseconds: 400));
}

void main() {
  setUpAll(loadAppFonts);

  group('the quota line', () {
    test('is empty while two or more questions are left, in both languages', () {
      for (final lang in AppLang.values) {
        for (final left in [50, 3, 2]) {
          expect(_state(lang, left: left).quotaLine, isEmpty, reason: '$left left (${lang.name})');
        }
      }
    });

    test('is a sentence at the last one, with no number', () {
      expect(_state(AppLang.en, left: 1).quotaLine, 'Last question today');
      expect(_state(AppLang.ar, left: 1).quotaLine, 'آخر سؤال النهارده');
    });

    test('at none, says what still works, with no number', () {
      expect(_state(AppLang.en, left: 0).quotaLine, 'No questions left today · you can still log meals');
      expect(_state(AppLang.ar, left: 0).quotaLine, 'خلصت أسئلة النهارده · لسه تقدر تسجّل أكلك');
      for (final lang in AppLang.values) {
        for (final left in [0, 1]) {
          expect(_state(lang, left: left).quotaLine, isNot(matches(RegExp('[0-9٠-٩]'))));
        }
      }
    });

    test('there is none without an assistant to ask', () {
      final s = AppState()..setLang(AppLang.en);
      s.aiQuota = _chat(1);
      expect(s.quotaLine, isEmpty);
    });
  });

  group('the header', () {
    for (final lang in AppLang.values) {
      testWidgets('opens with no counter, and names the last question (${lang.name})', (tester) async {
        final s = _state(lang, left: 3);
        await _pumpChat(tester, s);
        final ar = lang == AppLang.ar;
        final drawn = drawnTexts(tester);
        expect(drawn.where((t) => RegExp('[0-9٠-٩]').hasMatch(t)), isEmpty,
            reason: 'no count anywhere in a fresh conversation: $drawn');

        s.aiQuota = _chat(1);
        s.setLang(lang); // rebuild
        await tester.pump(const Duration(milliseconds: 400));
        expect(find.text(ar ? 'آخر سؤال النهارده' : 'Last question today'), findsOneWidget);
      });
    }

    for (final lang in AppLang.values) {
      testWidgets('the line at none fits the header whole on a 390pt phone (${lang.name})', (tester) async {
        await tester.binding.setSurfaceSize(const Size(390, 844));
        addTearDown(() => tester.binding.setSurfaceSize(null));
        final s = _state(lang, left: 0);
        await _pumpChat(tester, s);
        final line = find.text(s.quotaLine);
        expect(line, findsOneWidget);
        final paragraph = tester.renderObject<RenderParagraph>(line);
        expect(paragraph.didExceedMaxLines, isFalse, reason: 'cut short, the line loses what still works: "${s.quotaLine}"');
        // Seat 6 sets the line at 12pt: it has to fit there too.
        final at12 = TextPainter(
          text: TextSpan(text: s.quotaLine, style: paragraph.text.style!.copyWith(fontSize: 12)),
          textDirection: s.isAr ? TextDirection.rtl : TextDirection.ltr,
          maxLines: 1,
        )..layout(maxWidth: paragraph.constraints.maxWidth);
        expect(at12.didExceedMaxLines, isFalse, reason: 'at 12pt');
      });
    }

    testWidgets('a dictation error comes before the quota', (tester) async {
      final s = _state(AppLang.en, left: 0);
      s.dictationError = 'Dictation is not available on this device. Type instead and I will follow.';
      await _pumpChat(tester, s);
      expect(find.textContaining('Dictation is not available'), findsOneWidget);
      expect(find.textContaining('No questions left today'), findsNothing);
    });
  });

  // The field's hint says what it takes (O10, the unread mealPlaceholder):
  // while a meal is being logged, a meal, since a meal read spends no
  // question; otherwise a question for Qamar.
  group('the composer’s hint', () {
    String hint(WidgetTester tester) => tester.widget<TextField>(find.byType(TextField)).decoration!.hintText!;

    for (final lang in AppLang.values) {
      testWidgets('a meal while one is being logged, a question otherwise (${lang.name})', (tester) async {
        final ar = lang == AppLang.ar;
        final s = AppState()..setLang(lang);
        s.quickLog(QuickLog.text);
        await _pumpChat(tester, s);
        expect(hint(tester), ar ? 'مثال: كشري وسط + دقة' : 'e.g. medium koshary + daqqa');
        expect(hint(tester), isNot(s.t.chatPlaceholder), reason: 'a question’s words would suggest a question is spent');

        // The meal's words sent, the next thing typed is a question again.
        await s.sendChatMsg(ar ? 'كشري' : 'koshary');
        await tester.pump(const Duration(milliseconds: 400));
        expect(s.loggingMeal, isFalse);
        expect(hint(tester), ar ? 'اسأل قمر أي حاجة' : 'Ask Qamar anything');
      });
    }

    testWidgets('a conversation opened to ask: a question', (tester) async {
      final s = AppState()..setLang(AppLang.en);
      s.openChat();
      await _pumpChat(tester, s);
      expect(hint(tester), 'Ask Qamar anything');
    });
  });

  group('the full count, in Me', () {
    test('questions and photos left of the day, in Eastern digits in Arabic', () {
      final s = _state(AppLang.ar, left: 2)
        ..photoQuota = const AiQuota(bucket: 'photo', used: 1, limit: 3, extra: 0, remaining: 2);
      final plain = s.quotaSummary.replaceAll(RegExp('[\u2066-\u2069]'), '');
      expect(plain, 'فاضل النهارده — أسئلة: ٢ من ٣، صور: ٢ من ٣');
      final en = _state(AppLang.en, left: 2)
        ..photoQuota = const AiQuota(bucket: 'photo', used: 1, limit: 3, extra: 0, remaining: 2);
      expect(en.quotaSummary, 'Left today — questions: 2 of 3 · photos: 2 of 3');
    });

    testWidgets('Me shows it, with no Latin digit in Arabic', (tester) async {
      final s = _state(AppLang.ar, left: 2);
      s.go(AppScreen.you);
      await tester.binding.setSurfaceSize(const Size(900, 2400)); // this checks the words, not the layout
      addTearDown(() => tester.binding.setSurfaceSize(null));
      await tester.pumpWidget(ChangeNotifierProvider.value(value: s, child: const QamarApp()));
      await tester.pump();
      expect(drawnTexts(tester).where((t) => t.startsWith('فاضل النهارده')), hasLength(1));
      // Me's digits choice shows the Western option in its own digits.
      expectNoLatinDigits(tester, where: 'Me', allow: [RegExp('^${YouScreen.westernDigits}\$')]);
    });
  });

  test('a meal explanation draws its Arabic numbers in Eastern digits', () {
    final s = AppState()..setLang(AppLang.ar);
    const PlanMeal meal = (
      id: 'lunch',
      slotAr: 'الغدا',
      slotEn: 'Lunch',
      nameAr: 'فول بالعيش',
      nameEn: 'Foul with bread',
      noteAr: '',
      noteEn: '',
      portions: [(ar: 'فول', en: 'Foul', amountAr: '150 جم', amountEn: '150 g', kcal: 180)],
    );
    final ex = mealExplanation(meal, iso: s.iso, digits: s.digits);
    expect(ex.bodyAr, isNot(contains(RegExp('[0-9]'))));
    expect(ex.bodyAr.replaceAll(RegExp('[\u2066-\u2069]'), ''), contains('إجمالي ١٨٠ سعر'));
    expect(ex.bodyAr, contains('١٥٠ جم'));
  });
}
