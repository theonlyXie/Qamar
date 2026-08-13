// Smoke tests for the Qamar app shell.
//
// These exercise the offline path only — AppState is self-contained and needs
// no credentials (see app/README.md), so the whole shell is testable as-is.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

import 'package:qamar/l10n/strings.dart';
import 'package:qamar/main.dart';
import 'package:qamar/screens/welcome_screen.dart';
import 'package:qamar/state/app_state.dart';

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
}
