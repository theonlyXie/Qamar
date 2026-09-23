// One way to each thing on You, seat 6's part (the scorecard's 09: "two
// affordances for the same act"). Pinned down on the tall renders: the
// wallet had a card with its Spend button and, further down, a "Su Points
// wallet" row with the same balance, a second entry to the same place, and
// a row that did not even respond. The row is gone; the card's Spend is the
// one way in. The rows left (target, what to avoid, memory, consents) are a
// read-out, one card with a line each, not four bordered rows dressed as
// controls that do nothing when touched.

import 'dart:ui' show SemanticsAction;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

import 'package:qamar/l10n/strings.dart';
import 'package:qamar/main.dart';
import 'package:qamar/screens/you_screen.dart';
import 'package:qamar/state/app_state.dart';
import 'package:qamar/widgets/common.dart';

import 'support/app_fonts.dart';

void main() {
  setUpAll(() async {
    await loadAppFonts();
    for (final name in const ['com.qamar.app/quick_events', 'com.qamar.app/quick_invoke']) {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(MethodChannel(name), (call) async => null);
    }
  });

  for (final lang in AppLang.values) {
    testWidgets('the wallet has one way in, and the read-out is not dressed as controls (${lang.name})', (tester) async {
      tester.view.devicePixelRatio = 3;
      tester.view.physicalSize = const Size(390, 2600) * 3;
      addTearDown(tester.view.reset);
      final handle = tester.ensureSemantics();
      final s = AppState()..setLang(lang);
      s.dismissOrbTutorial();
      s.go(AppScreen.today);
      s.go(AppScreen.you);
      await tester.pumpWidget(ChangeNotifierProvider.value(value: s, child: const QamarApp()));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));

      expect(find.text(s.t.walletTitle), findsOneWidget, reason: 'the wallet is named once on You');
      final spend = find.descendant(of: find.byKey(YouScreen.walletCardKey), matching: find.byType(QOutlineButton));
      expect(spend, findsOneWidget, reason: 'its card carries the one way in');

      final readOut = find.byKey(YouScreen.readOutKey);
      expect(readOut, findsOneWidget);
      final lines = find.descendant(of: readOut, matching: find.byType(Divider));
      expect(lines, findsNWidgets(3), reason: 'four lines of one card, under hairlines');
      final node = tester.getSemantics(readOut);
      var tappable = false;
      node.visitChildren((n) {
        if (n.getSemanticsData().hasAction(SemanticsAction.tap)) tappable = true;
        return true;
      });
      expect(tappable || node.getSemanticsData().hasAction(SemanticsAction.tap), isFalse, reason: 'a read-out, nothing in it pretends to be a button');

      await tester.tap(spend);
      await tester.pump();
      expect(s.screen, AppScreen.wallet, reason: 'and that one way in goes to the wallet');
      handle.dispose();
    });
  }
}
