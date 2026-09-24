// One way to each thing on Me, seat 6's part (the scorecard's 09: "two
// affordances for the same act"), in Me's settings layout: a row to a thing,
// one card to a group. The wallet had a card with its Spend button and,
// further down, a "Su Points wallet" row with the same balance, a second
// entry to the same place. The one way in is the wallet's row, named for the
// wallet, and led on by the same chevron as every row that goes somewhere,
// where it was a small "Spend" that named one of the wallet's tabs (seat 2).
// The food group is one card with a line each under hairlines; the lines
// that only read out (the target, what Qamar remembers) are drawn with no
// chevron and take no touch, so nothing pretends to be a control, and the
// one that changes something, what to avoid, is a whole row with the
// chevron. What to avoid reads out what is avoided, by the consultation's
// own names for its choices, on one line, where it said a bare "2" (seat 2).

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

import 'package:qamar/l10n/strings.dart';
import 'package:qamar/main.dart';
import 'package:qamar/screens/you_screen.dart';
import 'package:qamar/state/app_state.dart';
import 'package:qamar/theme/icons.dart';
import 'package:qamar/widgets/avoid_editor.dart';
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
    testWidgets('the wallet has one way in, and the read-outs are not dressed as controls (${lang.name})', (tester) async {
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

      expect(find.text(s.t.walletTitle), findsOneWidget, reason: 'the wallet is named once on Me');
      final card = find.byKey(YouScreen.walletCardKey);
      expect(find.descendant(of: card, matching: find.byType(QOutlineButton)), findsNothing, reason: 'no button beside the name');
      expect(find.text(s.t.spendTab), findsNothing, reason: 'the way in is not named for one of the wallet’s tabs');

      // The wallet's row is the way in: the whole width of its card, a whole
      // touch, the title in it, and the chevron every row that goes
      // somewhere carries, the same as the Qamar+ row's.
      final row = find.byKey(YouScreen.walletRowKey);
      expect(find.descendant(of: card, matching: row), findsOneWidget);
      expect(find.descendant(of: row, matching: find.text(s.t.walletTitle)), findsOneWidget);
      final rowRect = tester.getRect(row);
      expect(rowRect.height, greaterThanOrEqualTo(56), reason: 'a settings row, 56 at least');
      expect(rowRect.width, moreOrLessEquals(tester.getRect(card).width, epsilon: 2.5), reason: 'the whole row, not a part of it');
      final walletChevron = tester.widget<Icon>(find.descendant(of: row, matching: find.byIcon(QIcons.forward)));
      final plusChevron = tester.widget<Icon>(find.descendant(of: find.byKey(YouScreen.plusRowKey), matching: find.byIcon(QIcons.forward)));
      expect(walletChevron.size, plusChevron.size, reason: 'the same chevron');
      expect(walletChevron.color, plusChevron.color);
      final data = tester.getSemantics(row).getSemanticsData();
      expect(data.hasAction(SemanticsAction.tap), isTrue);
      expect(data.flagsCollection.isButton, isTrue);
      expect(data.label, startsWith(s.t.walletTitle), reason: 'heard by the wallet’s name');
      expect(data.label, contains(lang == AppLang.ar ? 'متاح' : 'available'), reason: 'and its balance');

      // The food: one card, three rows, with no lines between them (the
      // kit's settings list keeps its rows apart by their height alone).
      final readOut = find.byKey(YouScreen.readOutKey);
      expect(readOut, findsOneWidget);
      expect(find.descendant(of: readOut, matching: find.byType(Divider)), findsNothing, reason: 'no hairlines between the rows');
      for (final label in [lang == AppLang.ar ? 'هدفك اليومي' : 'Daily target', lang == AppLang.ar ? 'قمر فاكر' : 'Qamar remembers']) {
        expect(find.descendant(of: readOut, matching: find.text(label)), findsOneWidget, reason: 'three rows of one card');
      }
      expect(find.descendant(of: readOut, matching: find.byKey(YouScreen.avoidEntryKey)), findsOneWidget);
      // One of them changes something, and says so with the chevron; the
      // read-outs carry neither a chevron nor a touch.
      expect(find.descendant(of: readOut, matching: find.byIcon(QIcons.forward)), findsOneWidget);
      final avoid = find.byKey(YouScreen.avoidEntryKey);
      expect(find.descendant(of: avoid, matching: find.byIcon(QIcons.forward)), findsOneWidget, reason: 'what to avoid goes somewhere');
      var buttons = 0;
      tester.getSemantics(readOut).visitChildren((n) {
        if (n.getSemanticsData().hasAction(SemanticsAction.tap)) buttons++;
        return true;
      });
      expect(buttons, 1, reason: 'the target and the memory are read-outs; only what to avoid is a button');
      expect(tester.getSemantics(avoid).getSemanticsData().hasAction(SemanticsAction.tap), isTrue);

      await tester.tap(find.text(s.t.walletTitle));
      await tester.pump();
      expect(s.screen, AppScreen.wallet, reason: 'and that one way in goes to the wallet');
      handle.dispose();
    });
  }

  for (final lang in AppLang.values) {
    testWidgets('What to avoid names what is avoided, on one line, and its row is the way to change it (${lang.name})', (tester) async {
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
      final label = AvoidEditor.title(isAr: ar);
      Finder line() => find.descendant(
            of: find.ancestor(of: find.text(label), matching: find.byType(Row)).first,
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
      final labelRect = tester.getRect(find.text(label));
      expect(ar ? r.right <= labelRect.left : r.left >= labelRect.right, isTrue, reason: 'beside its label, never over it');

      // Seat 1's way to change it is the row itself: the words, the value
      // and the chevron are one touch, inside the card.
      final entry = find.byKey(YouScreen.avoidEntryKey);
      expect(find.descendant(of: readOut, matching: entry), findsOneWidget);
      expect(find.descendant(of: entry, matching: find.text(label)), findsOneWidget);
      expect(find.descendant(of: entry, matching: line()), findsOneWidget);
      expect(tester.getRect(entry).height, greaterThanOrEqualTo(56));
    });
  }
}
