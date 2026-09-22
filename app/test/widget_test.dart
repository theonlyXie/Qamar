// Smoke tests for the Qamar app shell.
//
// These exercise the offline path only — AppState is self-contained and needs
// no credentials (see app/README.md), so the whole shell is testable as-is.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

import 'package:qamar/l10n/strings.dart';
import 'package:qamar/main.dart';
import 'package:qamar/models/meal.dart';
import 'package:qamar/screens/welcome_screen.dart';
import 'package:qamar/state/app_state.dart';
import 'package:qamar/widgets/explain.dart';

import 'support/arabic_digits.dart';

Widget _app(AppState state) => ChangeNotifierProvider.value(
      value: state,
      child: const QamarApp(),
    );

void main() {
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
      expectNoLatinDigits(tester, where: '$screen');
    }
  });
}
