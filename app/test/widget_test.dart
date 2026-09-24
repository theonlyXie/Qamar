// Smoke tests for the Qamar app shell.
//
// These exercise the offline path only — AppState is self-contained and needs
// no credentials (see app/README.md), so the whole shell is testable as-is.

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

import 'package:qamar/l10n/strings.dart';
import 'package:qamar/main.dart';
import 'package:qamar/models/activity.dart';
import 'package:qamar/models/meal.dart';
import 'package:qamar/screens/welcome_screen.dart';
import 'package:qamar/screens/you_screen.dart';
import 'package:qamar/state/app_state.dart';
import 'package:qamar/widgets/explain.dart';

import 'support/app_fonts.dart';
import 'support/arabic_digits.dart';

Widget _app(AppState state) => ChangeNotifierProvider.value(
      value: state,
      child: const QamarApp(),
    );

void main() {
  // The app's own fonts: the guideline sweep below lays screens out at a
  // phone's width, where the test font's full-em glyphs would overflow.
  setUpAll(() async {
    await loadAppFonts();
    for (final name in const ['com.qamar.app/quick_events', 'com.qamar.app/quick_invoke']) {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(MethodChannel(name), (call) async => null);
    }
  });

  testWidgets('boots to the welcome screen in Arabic/RTL', (tester) async {
    final state = AppState();
    await tester.pumpWidget(_app(state));
    await tester.pump();

    expect(find.byType(WelcomeScreen), findsOneWidget);
    expect(state.lang, AppLang.ar);
    expect(Directionality.of(tester.element(find.byType(WelcomeScreen))),
        TextDirection.rtl);
  });

  testWidgets('switching language flips text direction to LTR',
      (tester) async {
    final state = AppState();
    await tester.pumpWidget(_app(state));
    await tester.pump();

    state.setLang(AppLang.en);
    await tester.pump();

    expect(state.lang, AppLang.en);
    expect(Directionality.of(tester.element(find.byType(WelcomeScreen))),
        TextDirection.ltr);
  });

  testWidgets('every screen in AppScreen builds without throwing',
      (tester) async {
    final state = AppState();
    await tester.pumpWidget(_app(state));

    for (final screen in AppScreen.values) {
      state.go(screen);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
      expect(tester.takeException(), isNull, reason: 'while building $screen');
    }
  });

  // O8: every Arabic number is drawn in Eastern digits. The sweep is the
  // reusable helper in support/arabic_digits.dart.
  testWidgets('no Latin digit on any screen in Arabic: a meal logged, the conversation and an explanation open',
      (tester) async {
    final state = AppState()..setLang(AppLang.ar);
    state.profile = state.profile.copyWith(name: 'Basel', prefs: ['no_meat', 'lactose']);
    // Tall enough that every list builds to its end: lists build lazily, and
    // the sweep can only read what was built. This checks words, not layout.
    await tester.binding.setSurfaceSize(const Size(900, 9000));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(_app(state));

    // A meal on the day, repeated once so the conversation carries Qamar's
    // reply to it, with its numbers ("٥٢٠ سعرة، وفاضل …").
    final meal = LoggedMeal(name: 'فول بالعيش', sub: 'بالصوت · تقدير', kcal: 520, p: 22, c: 64, f: 18, at: DateTime.now());
    state.meals.add(meal);
    state.repeatMeal(meal);
    state.openExplain(kExplanations['kcal_remaining']!);

    for (final screen in AppScreen.values) {
      state.go(screen);
      state.openChat();
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
      expect(tester.takeException(), isNull, reason: 'while building $screen');
      // Me's digits choice shows the Western option in its own digits.
      expectNoLatinDigits(tester, where: '$screen', allow: [if (screen == AppScreen.you) RegExp('^${YouScreen.westernDigits}\$')]);
    }

    // The wallet opens on Spend; its History is a column of numbers, one
    // per row. An earning and a spend in the thousands, so the separator is
    // checked with the digits.
    state.ledgerExtra.addAll(const [
      LedgerEntry(label: 'خلصت الإعداد', amount: 1000, when: 'امبارح'),
      LedgerEntry(label: 'سؤال زيادة', amount: -800, when: 'دلوقتي'),
    ]);
    state.go(AppScreen.wallet);
    state.showHistory();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    expect(find.text('خلصت الإعداد'), findsOneWidget, reason: 'the History rows are drawn');
    expectNoLatinDigits(tester, where: 'the wallet’s History');
  });

  // O11: every control is a whole touch — 48 points each way on Android, 44
  // on iOS — and says what it is, on every screen in both languages, then
  // with the tree, the conversation and each sheet open. The rule lives in the shared
  // controls (QTapArea), so a screen that uses them keeps it.
  for (final lang in AppLang.values) {
    testWidgets('every control is a whole touch with a name, on every screen, the tree, the conversation and each sheet (${lang.name})', (tester) async {
      // A phone's width, tall enough that each screen's lists build to
      // their end: controls that are not built cannot be checked.
      tester.view.devicePixelRatio = 3;
      tester.view.physicalSize = const Size(390, 2400) * 3;
      tester.view.padding = const FakeViewPadding(top: 47 * 3, bottom: 34 * 3);
      addTearDown(tester.view.reset);
      final state = AppState()..setLang(lang);
      state.profile = state.profile.copyWith(name: 'Basel');
      state.meals.add(LoggedMeal(name: 'Koshary', sub: '', kcal: 640, p: 20, c: 100, f: 18, at: DateTime.now()));
      final semantics = tester.ensureSemantics();
      await tester.pumpWidget(_app(state));

      Future<void> check(String where) async {
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 400));
        expect(tester.takeException(), isNull, reason: where);
        await expectLater(tester, meetsGuideline(androidTapTargetGuideline), reason: '48dp on $where');
        await expectLater(tester, meetsGuideline(iOSTapTargetGuideline), reason: '44pt on $where');
        await expectLater(tester, meetsGuideline(labeledTapTargetGuideline), reason: 'every control named on $where');
      }

      for (final screen in AppScreen.values) {
        state.go(screen);
        await check('$screen');
      }
      state.go(AppScreen.today);
      state.orbTap();
      await check('the tree');
      state.closeLog();
      state.openChat();
      await check('the conversation');
      state.closeChat();
      // Each sheet open: its controls, and the scrim that closes it, which
      // a screen reader hears as a button named Close (seat 2's review).
      state.openWhy();
      await check('the Why sheet');
      state.closeWhy();
      state.openExplain(kExplanations['kcal_remaining']!);
      await check('an explanation');
      state.closeExplain();
      state.openLinkAccount();
      await check('the account sheet');
      state.closeAuth();
      state.chooseActivity(ActivityKind.walk);
      await check('the activity sheet');
      state.cancelActivity();
      semantics.dispose();
    });
  }
}
