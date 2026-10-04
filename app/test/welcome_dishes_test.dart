// The welcome's way in, made one tap (the qamar-design skill: no step that is
// not a real decision). "Chat with Qamar" used to open a sheet of three
// dishes and a second button before the first question (O5); it now goes
// straight to the first question, and the first moment of value is the
// reveal's dish, costed against the person's own target. What O5 asked of
// the welcome still holds: nothing on it promises a target, since the
// welcome comes before the safety question and not everyone is given one.

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

import 'package:qamar/l10n/strings.dart';
import 'package:qamar/main.dart';
import 'package:qamar/models/dishes.dart';
import 'package:qamar/models/messages.dart';
import 'package:qamar/models/onboarding.dart';
import 'package:qamar/screens/onboarding_screen.dart';
import 'package:qamar/screens/welcome_screen.dart';
import 'package:qamar/state/app_state.dart';
import 'package:qamar/widgets/common.dart';

import 'support/app_fonts.dart';

EgyptianDish _dish(String id) => kEgyptianDishes.firstWhere((d) => d.id == id);

void main() {
  setUpAll(() async {
    await loadAppFonts();
    for (final name in const ['com.qamar.app/quick_events', 'com.qamar.app/quick_invoke']) {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(MethodChannel(name), (call) async => null);
    }
  });

  group('the sentence under a dish', () {
    final ar = AppState()..setLang(AppLang.ar);
    final en = AppState()..setLang(AppLang.en);

    test('is read from the dish’s own numbers, so it is true of the card', () {
      final f = _dish('koshary').facts();
      final carbsPct = (f.carbs * 4 * 100 / (f.carbs * 4 + f.protein * 4 + f.fat * 9)).round();
      expect(dishSentence(f, ar: false, iso: en.iso), 'Most of its energy is carbs ($carbsPct%), with ${f.protein} g of protein.');
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
      for (final d in kEgyptianDishes) {
        expect(dishSentence(d.facts(), ar: false, iso: en.iso), isNot(contains('% of your')));
      }
    });
  });

  group('nothing on the welcome promises a target', () {
    // The welcome comes before the safety question, and whoever answers it is
    // given no target (the general-guidance route). So no line here may
    // promise one.
    final target = RegExp(r'target|goal|share of your day|of your day|your day|kcal a day|هدف|من يومك|يومك|قد إيه', caseSensitive: false);

    test('its every line, in both languages', () {
      for (final lang in AppLang.values) {
        final s = AppState()..setLang(lang);
        final ar = lang == AppLang.ar;
        final lines = [
          s.t.promise,
          s.t.chatDirect,
          s.t.next,
          s.t.scanInbody,
          s.t.guestNote,
          s.t.haveAccount,
          WelcomeScreen.invitationLabel(ar),
          s.t.boundary,
        ];
        for (final line in lines) {
          expect(target.hasMatch(line), isFalse, reason: line);
        }
      }
    });

    test('the guest line says how long, and that no sign-up is needed, in both languages alike', () {
      expect(QStrings.en.guestNote, allOf(contains('two minutes'), contains('no sign-up')));
      expect(QStrings.ar.guestNote, allOf(contains('دقيقتين'), contains('من غير تسجيل')));
    });
  });

  group('on the welcome', () {
    Future<AppState> pump(WidgetTester tester, AppState s) async {
      tester.view.physicalSize = const Size(1170, 2532);
      tester.view.devicePixelRatio = 3.0;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(ChangeNotifierProvider.value(value: s, child: const QamarApp()));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
      return s;
    }

    for (final lang in AppLang.values) {
      testWidgets('"Chat with Qamar" is the one round button, and one tap puts the first question on screen (${lang.name})', (tester) async {
        final s = await pump(tester, AppState()..setLang(lang));
        expect(find.descendant(of: find.byKey(WelcomeScreen.chatPillKey), matching: find.text(s.t.chatDirect)), findsOneWidget);
        expect(find.descendant(of: find.byType(WelcomeScreen), matching: find.byType(QPrimaryButton)), findsNothing,
            reason: 'one thing to do: the round button in its bump; the report is the white capsule above it');

        await tester.tap(find.byKey(WelcomeScreen.chatPillKey));
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 400));
        expect(s.screen, AppScreen.onboard, reason: 'no sheet, no second button: the consultation');
        expect(find.byType(BottomSheet), findsNothing);
        expect(find.byType(OnboardingScreen), findsOneWidget);
        final ar = lang == AppLang.ar;
        expect(find.text(kOnboardingSteps.first.ask(ar)), findsOneWidget, reason: 'the first question, with nothing before it');
        expect(find.widgetWithText(QPillChip, kOnboardingSteps.first.options.first.label(ar)), findsOneWidget, reason: 'and its answers');
      });
    }

    testWidgets('a consultation left part-way says so on the button, and carries on where it was', (tester) async {
      final s = AppState()..setLang(AppLang.en);
      await pump(tester, s);
      s.startOnboarding();
      s.pickOption(kOnboardingSteps.first.options.firstWhere((o) => o.value == 'yes'));
      // The answer's beat, then the safety question typed and on screen.
      for (var i = 0; i < 40 && !(s.currentStep!.id == 'safety' && s.questionShown); i++) {
        await tester.pump(const Duration(milliseconds: 100));
      }
      s.back();
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
      expect(s.screen, AppScreen.welcome);
      expect(s.consultationPaused, isTrue);
      expect(find.descendant(of: find.byKey(WelcomeScreen.chatPillKey), matching: find.text(s.t.next)), findsOneWidget, reason: '"Continue", not a new start');

      await tester.tap(find.byKey(WelcomeScreen.chatPillKey));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
      expect(s.screen, AppScreen.onboard);
      expect(s.currentStep!.id, 'safety', reason: 'where it was left');
      expect(s.msgs.where((m) => m.kind == ObKind.u).map((m) => m.text(false)), ['Agree'], reason: 'the answers kept');
    });
  });
}
