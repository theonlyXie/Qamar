// One way to each thing on You, seat 6's part (the scorecard's 09: "two
// affordances for the same act"). Pinned down on the tall renders: the
// wallet had a card with its Spend button and, further down, a "Su Points
// wallet" row with the same balance, a second entry to the same place, and
// a row that did not even respond. The row is gone. The one way in is the
// card's top row, named for the wallet and led on by the Qamar+ card's
// chevron, where it was a small "Spend" that named one of the wallet's
// tabs (seat 2). The rows left (target, what to avoid, memory, consents)
// are a read-out, one card with a line each, not four bordered rows
// dressed as controls that do nothing when touched. What to avoid reads
// out what is avoided, by the consultation's own names for its choices, on
// one line, where it said a bare "2" (seat 2).

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

import 'package:qamar/l10n/strings.dart';
import 'package:qamar/main.dart';
import 'package:qamar/screens/you_screen.dart';
import 'package:qamar/state/app_state.dart';
import 'package:qamar/widgets/common.dart';

import 'support/app_fonts.dart';
import 'support/arabic_digits.dart';

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
      final card = find.byKey(YouScreen.walletCardKey);
      expect(find.descendant(of: card, matching: find.byType(QOutlineButton)), findsNothing, reason: 'no button beside the name');
      expect(find.text(s.t.spendTab), findsNothing, reason: 'the way in is not named for one of the wallet’s tabs');

      // The card's top row is the way in: the whole width of the card, a
      // whole touch, the title in it, and the Qamar+ card's chevron.
      final row = find.byKey(YouScreen.walletRowKey);
      expect(find.descendant(of: card, matching: row), findsOneWidget);
      expect(find.descendant(of: row, matching: find.text(s.t.walletTitle)), findsOneWidget);
      final rowRect = tester.getRect(row);
      expect(rowRect.height, greaterThanOrEqualTo(48));
      expect(rowRect.width, moreOrLessEquals(tester.getRect(card).width, epsilon: 2.5), reason: 'the whole row, not a part of it');
      final chevrons = tester.widgetList<Icon>(find.byIcon(Icons.chevron_right)).toList();
      final walletChevron = tester.widget<Icon>(find.descendant(of: row, matching: find.byIcon(Icons.chevron_right)));
      expect(chevrons.length, 2, reason: 'the Qamar+ card’s and the wallet’s');
      expect(walletChevron.size, chevrons.first.size, reason: 'the same chevron');
      expect(walletChevron.color, chevrons.first.color);
      final data = tester.getSemantics(row).getSemanticsData();
      expect(data.hasAction(SemanticsAction.tap), isTrue);
      expect(data.flagsCollection.isButton, isTrue);
      expect(data.label, startsWith(s.t.walletTitle), reason: 'heard by the wallet’s name');
      expect(data.label, contains(lang == AppLang.ar ? 'متاح' : 'available'), reason: 'and its balance');

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

      await tester.tap(find.text(s.t.walletTitle));
      await tester.pump();
      expect(s.screen, AppScreen.wallet, reason: 'and that one way in goes to the wallet');
      handle.dispose();
    });
  }

  for (final lang in AppLang.values) {
    testWidgets('What to avoid names what is avoided, on one line, and the way to change it stays under it (${lang.name})', (tester) async {
      final ar = lang == AppLang.ar;
      tester.view.devicePixelRatio = 3;
      tester.view.physicalSize = const Size(390, 2600) * 3;
      addTearDown(tester.view.reset);
      final s = AppState()..setLang(lang);
      s.dismissOrbTutorial();
      s.go(AppScreen.today);
      s.go(AppScreen.you);
      String name(String value) {
        final o = AppState.avoidStep.options.firstWhere((o) => o.value == value);
        return ar ? o.ar : o.en;
      }

      final readOut = find.byKey(YouScreen.readOutKey);
      Finder line() => find.descendant(
            of: find.ancestor(of: find.text(ar ? 'ما يجب تجنبه' : 'What to avoid'), matching: find.byType(Row)).first,
            matching: find.byType(Text),
          ).last;

      // Nothing avoided: the consultation's own "Nothing".
      await tester.pumpWidget(ChangeNotifierProvider.value(value: s, child: const QamarApp()));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
      expect(tester.widget<Text>(line()).data, ar ? 'مفيش' : 'Nothing');
      expect(name('none'), ar ? 'مفيش' : 'Nothing', reason: 'the choice of that name');

      // Two things, named, in the choices' own order, not counted.
      s.profile = s.profile.copyWith(prefs: ['lactose', 'meat']);
      s.setLang(lang);
      await tester.pump();
      expect(tester.widget<Text>(line()).data, '${name('meat')} · ${name('lactose')}');
      expect(find.descendant(of: readOut, matching: find.text(s.iso('2'))), findsNothing, reason: 'not a bare count');
      if (ar) expectNoLatinDigits(tester, within: readOut);

      // All four: still one line, cut with an ellipsis, inside the card.
      s.profile = s.profile.copyWith(prefs: ['nuts', 'meat', 'lactose', 'budget']);
      s.setLang(lang);
      await tester.pump();
      final text = tester.widget<Text>(line());
      expect(text.data, [for (final v in const ['nuts', 'meat', 'lactose', 'budget']) name(v)].join(' · '));
      expect(text.maxLines, 1);
      expect(text.overflow, TextOverflow.ellipsis);
      final paragraph = tester.renderObject<RenderParagraph>(find.descendant(of: line(), matching: find.byType(RichText)));
      expect(paragraph.didExceedMaxLines, isTrue, reason: 'four names do not fit beside the label at 390');
      final card = tester.getRect(readOut);
      final r = tester.getRect(line());
      expect(r.left, greaterThanOrEqualTo(card.left));
      expect(r.right, lessThanOrEqualTo(card.right));
      final label = tester.getRect(find.text(ar ? 'ما يجب تجنبه' : 'What to avoid'));
      expect(ar ? r.right <= label.left : r.left >= label.right, isTrue, reason: 'beside its label, never over it');

      // Seat 1's way to change it is still right under the read-out.
      final entry = tester.getRect(find.byKey(YouScreen.avoidEntryKey));
      expect(entry.top, greaterThanOrEqualTo(card.bottom));
      expect(entry.top - card.bottom, lessThan(16));
    });
  }
}
