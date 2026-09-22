// The welcome's first moment of value (O5): "Chat with Qamar" shows a real
// Egyptian dish before any question, by chips alone, then starts the
// consultation.

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

import 'package:qamar/l10n/strings.dart';
import 'package:qamar/main.dart';
import 'package:qamar/models/dishes.dart';
import 'package:qamar/state/app_state.dart';
import 'package:qamar/widgets/dish_card.dart';
import 'package:qamar/widgets/welcome_dishes.dart';

import 'support/app_fonts.dart';

EgyptianDish _dish(String id) => kEgyptianDishes.firstWhere((d) => d.id == id);

void main() {
  setUpAll(() async {
    await loadAppFonts();
    for (final name in const ['com.qamar.app/quick_events', 'com.qamar.app/quick_invoke']) {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(MethodChannel(name), (call) async => null);
    }
  });

  group('the sentence under the dish', () {
    final ar = AppState()..setLang(AppLang.ar);
    final en = AppState()..setLang(AppLang.en);

    test('is read from the dish’s own numbers, so it is true of the card', () {
      final f = _dish('koshary').facts();
      final carbsPct = (f.carbs * 4 * 100 / (f.carbs * 4 + f.protein * 4 + f.fat * 9)).round();
      expect(dishSentence(f, ar: false, iso: en.iso), 'Most of its energy is carbs ($carbsPct%), with ${f.protein} g of protein — once I know you, I’ll say what share of your day that is.');
      final eggs = _dish('eggs_areesh_bread').facts();
      expect(dishSentence(eggs, ar: false, iso: en.iso), anyOf(contains('is fat'), contains('is protein'), contains('is carbs')));
    });

    test('in Arabic, every number in Eastern digits', () {
      for (final id in kWelcomeDishIds) {
        final line = dishSentence(_dish(id).facts(), ar: true, iso: ar.iso);
        expect(RegExp(r'[0-9]').hasMatch(line), isFalse, reason: line);
        expect(line, contains('جم بروتين'));
      }
    });

    test('never names a share of a day before there is a target', () {
      for (final id in kWelcomeDishIds) {
        expect(dishSentence(_dish(id).facts(), ar: false, iso: en.iso), isNot(contains('% of your')));
      }
    });
  });

  group('on the welcome', () {
    Future<AppState> pump(WidgetTester tester, AppLang lang) async {
      final s = AppState()..setLang(lang);
      // The phone itself, so MediaQuery says 390 wide too (the pill sizes
      // itself from it); a surface size alone leaves the test's 800.
      tester.view.physicalSize = const Size(1170, 2532);
      tester.view.devicePixelRatio = 3.0;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(ChangeNotifierProvider.value(value: s, child: const QamarApp()));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
      return s;
    }

    Future<void> open(WidgetTester tester, AppState s) async {
      await tester.tap(find.text(s.t.chatDirect));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
    }

    for (final lang in AppLang.values) {
      testWidgets('the pill promises what it opens, drawn whole (${lang.name})', (tester) async {
        final s = await pump(tester, lang);
        expect(s.screen, AppScreen.welcome);
        final sub = find.text(s.t.chatDirectSub);
        expect(sub, findsOneWidget);
        expect(s.t.chatDirectSub, contains(lang == AppLang.ar ? 'أكلة' : 'dish'), reason: 'it names what opens');
        expect(s.t.chatDirectSub, isNot(contains(lang == AppLang.ar ? 'دقيق' : 'minute')),
            reason: 'both languages promise the same; the button says how long');
        final paragraph = tester.renderObject<RenderParagraph>(find.descendant(of: sub, matching: find.byType(RichText)));
        expect(paragraph.didExceedMaxLines, isFalse, reason: 'a promise cut short is not a promise');
      });
    }

    testWidgets('"Chat with Qamar" offers three dishes as chips, with nothing to type', (tester) async {
      final s = await pump(tester, AppLang.en);
      await open(tester, s);
      expect(find.byType(WelcomeDishes), findsOneWidget);
      for (final id in kWelcomeDishIds) {
        expect(find.byKey(WelcomeDishes.chipKey(id)), findsOneWidget);
      }
      expect(find.descendant(of: find.byType(WelcomeDishes), matching: find.byType(TextField)), findsNothing, reason: 'consent comes before anything personal');
      expect(s.screen, AppScreen.welcome, reason: 'no question has been asked yet');
    });

    testWidgets('a chip shows the dish with its numbers and one plain sentence, and no share of a day', (tester) async {
      final s = await pump(tester, AppLang.ar);
      await open(tester, s);
      await tester.tap(find.byKey(WelcomeDishes.chipKey('koshary')));
      await tester.pump();
      final card = tester.widget<DishCard>(find.byType(DishCard));
      expect(card.dish.id, 'koshary');
      expect(card.targetKcal, isNull, reason: 'there is no target yet');
      expect(card.facts, s.dishFactsFor(_dish('koshary')));
      expect(find.text(dishSentence(card.facts, ar: true, iso: s.iso)), findsOneWidget);
      expect(find.textContaining('من هدفك'), findsNothing);
    });

    testWidgets('"Get my target" starts the consultation, with or without a dish', (tester) async {
      final s = await pump(tester, AppLang.en);
      await open(tester, s);
      await tester.tap(find.byKey(WelcomeDishes.startKey));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
      expect(s.screen, AppScreen.onboard);
      expect(find.byType(WelcomeDishes), findsNothing);
    });

    testWidgets('a consultation left part-way carries on, without the dishes again', (tester) async {
      final s = await pump(tester, AppLang.en);
      s.consultationPaused = true;
      await tester.tap(find.text(s.t.chatDirect));
      await tester.pump();
      expect(find.byType(WelcomeDishes), findsNothing);
      expect(s.screen, AppScreen.onboard);
    });
  });
}
