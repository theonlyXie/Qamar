// Su on screen (O9): one persistent display, Today's header chip, which
// opens the wallet; Level in the wallet only; and on the orb, never a
// balance — a wordless receipt for about two seconds when something is
// earned.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

import 'package:qamar/l10n/strings.dart';
import 'package:qamar/main.dart';
import 'package:qamar/models/activity.dart';
import 'package:qamar/models/meal.dart';
import 'package:qamar/models/su_economy.dart';
import 'package:qamar/screens/today_screen.dart';
import 'package:qamar/screens/wallet_screen.dart';
import 'package:qamar/state/app_state.dart';
import 'package:qamar/widgets/common.dart';
import 'package:qamar/widgets/explain.dart';
import 'package:qamar/widgets/tab_bar.dart';

import 'support/app_fonts.dart';

const _area = Size(390, 844);

Future<void> _pumpOrb(WidgetTester tester, AppState s) async {
  await tester.binding.setSurfaceSize(_area);
  addTearDown(() => tester.binding.setSurfaceSize(null));
  await tester.pumpWidget(ChangeNotifierProvider.value(
    value: s,
    child: MaterialApp(
      builder: (context, child) => Directionality(
        textDirection: context.watch<AppState>().isAr ? TextDirection.rtl : TextDirection.ltr,
        child: child!,
      ),
      home: const Scaffold(body: Stack(children: [QTabBar()])),
    ),
  ));
  await tester.pump();
}

Future<void> _pumpApp(WidgetTester tester, AppState s) async {
  await tester.binding.setSurfaceSize(_area);
  addTearDown(() => tester.binding.setSurfaceSize(null));
  await tester.pumpWidget(ChangeNotifierProvider.value(value: s, child: const QamarApp()));
  await tester.pump();
}

Future<void> _earn(AppState s) async {
  s.chooseActivity(ActivityKind.walk);
  await s.logActivity(20);
}

/// Every string drawn inside [of].
List<String> _texts(WidgetTester t, Finder of) => t
    .widgetList<RichText>(find.descendant(of: of, matching: find.byType(RichText)))
    .map((r) => r.text.toPlainText())
    .toList();

void main() {
  setUpAll(loadAppFonts);

  group('the orb', () {
    testWidgets('carries no balance at rest: no number, no name', (tester) async {
      final s = AppState()..setLang(AppLang.ar);
      s.go(AppScreen.today);
      await _pumpOrb(tester, s);
      expect(find.byType(SuReceiptChip), findsNothing);
      for (final text in _texts(tester, find.byType(QTabBar))) {
        expect(text, isNot(matches(RegExp(r'[0-9٠-٩]|Su|نقط'))), reason: 'the orb drew "$text"');
      }
    });

    for (final lang in AppLang.values) {
      testWidgets('a credit shows as a coin and the signed amount, for about two seconds (${lang.name})', (tester) async {
        final s = AppState()..setLang(lang);
        s.go(AppScreen.today);
        await _pumpOrb(tester, s);

        await _earn(s);
        await tester.pump();
        final receipt = find.byType(SuReceiptChip);
        expect(receipt, findsOneWidget);
        expect(find.descendant(of: receipt, matching: find.byType(SuCoinIcon)), findsOneWidget);

        final texts = _texts(tester, receipt);
        final amount = lang == AppLang.ar ? '+٥٠' : '+${SuEconomy.activityLogged}';
        expect(texts.single, contains(amount));
        expect(texts.single, isNot(matches(RegExp('Su|نقط'))), reason: 'wordless: the coin says what it is');
        final size = tester.widget<Text>(find.descendant(of: receipt, matching: find.byType(Text))).style!.fontSize!;
        expect(size, greaterThanOrEqualTo(12));

        await tester.pump(const Duration(milliseconds: 1000));
        expect(_texts(tester, receipt), isNotEmpty, reason: 'still there at one second');
        await tester.pump(const Duration(milliseconds: 1100));
        expect(_texts(tester, receipt), isEmpty, reason: 'gone after two');
      });
    }

    testWidgets('the balance arriving from the server is not a receipt', (tester) async {
      final s = AppState()..setLang(AppLang.en);
      s.go(AppScreen.today);
      await _pumpOrb(tester, s);
      s.suAvailable = 12000; // what a hydrate does
      s.setLang(AppLang.en); // any rebuild
      await tester.pump();
      expect(s.suReceipt, isNull);
      expect(find.byType(SuReceiptChip), findsNothing);
    });

    testWidgets('a receipt already shown is not shown again when the orb is rebuilt', (tester) async {
      var now = DateTime(2026, 9, 22, 12);
      final s = AppState(clock: () => now)..setLang(AppLang.en);
      s.go(AppScreen.today);
      await _pumpOrb(tester, s);
      await _earn(s);
      await tester.pump();
      await tester.pump(SuReceipt.showFor);
      now = now.add(const Duration(seconds: 3));
      // Leaving for a screen without the orb and coming back rebuilds it.
      await tester.pumpWidget(const SizedBox());
      await _pumpOrb(tester, s);
      await tester.pump(const Duration(milliseconds: 100));
      expect(_texts(tester, find.byType(SuReceiptChip)), isEmpty);
    });
  });

  group('Today and the wallet', () {
    for (final lang in AppLang.values) {
      testWidgets('Today carries one Su chip, which opens the wallet, and no Level (${lang.name})', (tester) async {
        final s = AppState()..setLang(lang);
        s.go(AppScreen.today);
        await _pumpApp(tester, s);

        expect(find.byType(SuChip), findsOneWidget);
        expect(find.textContaining(lang == AppLang.ar ? 'المستوى' : 'Level'), findsNothing);
        final chip = tester.getSize(find.byType(SuChip));
        expect(chip.height, greaterThanOrEqualTo(48));
        expect(chip.width, greaterThanOrEqualTo(48));

        await tester.tap(find.byType(SuChip));
        await tester.pump();
        expect(s.screen, AppScreen.wallet);
      });
    }

    for (final lang in AppLang.values) {
      final ar = lang == AppLang.ar;
      testWidgets('at a zero balance the chip is the coin alone, and still the wallet’s door (${lang.name})', (tester) async {
        final semantics = tester.ensureSemantics();
        final s = AppState()..setLang(lang);
        expect(s.suAvailable, 0);
        s.go(AppScreen.today);
        await _pumpApp(tester, s);

        final chip = find.byType(SuChip);
        expect(chip, findsOneWidget);
        expect(find.descendant(of: chip, matching: find.byType(SuCoinIcon)), findsOneWidget);
        expect(find.byKey(SuChip.amountKey), findsNothing, reason: 'no numeral at zero: the Arabic ٠ over the dotted mark read as ":"');
        // Still explainable, so still marked (every explainable value is):
        // the dots sit under the coin, where there is no ٠ for them to join.
        final coinMark = find.byKey(SuChip.coinMarkKey);
        expect(coinMark, findsOneWidget);
        expect(find.descendant(of: coinMark, matching: find.byType(SuCoinIcon)), findsOneWidget);
        expect(find.descendant(of: chip, matching: find.byType(ExplainMark)), findsOneWidget);
        final coin = tester.getRect(find.descendant(of: coinMark, matching: find.byType(SuCoinIcon)));
        expect(tester.getRect(coinMark).bottom - coin.bottom, greaterThanOrEqualTo(3), reason: 'the dots under the coin, not through it');
        expect(_texts(tester, chip).where((t) => t.trim().isNotEmpty), isEmpty, reason: 'nothing written in the chip at all');
        expect(find.descendant(of: chip, matching: find.byWidgetPredicate((w) => w is Explainable && w.id == 'su_points')), findsOneWidget,
            reason: 'still explainable');
        // A screen reader still hears the balance, in the app's digits.
        expect(tester.getSemantics(chip), matchesSemantics(label: ar ? 'نقاط Su: ٠' : 'Su Points: 0', isButton: true, hasTapAction: true));

        await tester.tap(chip);
        await tester.pump();
        expect(s.screen, AppScreen.wallet, reason: 'still opens the wallet');

        // The first credit brings the number back.
        s.go(AppScreen.today);
        await _earn(s);
        await tester.pump();
        final amount = find.byKey(SuChip.amountKey);
        expect(amount, findsOneWidget);
        expect(tester.widget<Text>(amount).data, ar ? '٥٠' : '${SuEconomy.activityLogged}');
        expect(find.byKey(SuChip.coinMarkKey), findsNothing, reason: 'with a number, the mark is under the number');
        expect(find.descendant(of: chip, matching: find.byType(ExplainMark)), findsOneWidget);
        expect(tester.getSemantics(chip), matchesSemantics(label: ar ? 'نقاط Su: ٥٠' : 'Su Points: 50', isButton: true, hasTapAction: true));
        semantics.dispose();
      });

      testWidgets('with "Points and streaks" off there is no chip, at zero or not (${lang.name})', (tester) async {
        final s = AppState()..setLang(lang);
        s.setShowScore(false);
        s.go(AppScreen.today);
        await _pumpApp(tester, s);
        expect(find.byType(SuChip), findsNothing);
        await _earn(s);
        await tester.pump();
        expect(find.byType(SuChip), findsNothing);
        expect(find.byKey(SuChip.amountKey), findsNothing);
      });
    }

    testWidgets('Level lives in the wallet, in Eastern digits in Arabic', (tester) async {
      final s = AppState()..setLang(AppLang.ar);
      s.go(AppScreen.wallet);
      await _pumpApp(tester, s);
      // Numbers are wrapped in bidi isolates (state.iso), so read the text
      // without them.
      final shown = _texts(tester, find.byType(MaterialApp)).map((t) => t.replaceAll(RegExp('[\u2066-\u2069]'), ''));
      expect(shown, contains('المستوى ١'));
    });
  });

  // The one cue a price in Su needs beside it: Su cannot be bought. It was
  // in a line nothing drew (walletSub) and in the chip's explainer, which
  // "Points and streaks" hides with the chip; so with the switch off,
  // nothing in the app said it. The wallet's terms, at the foot of both
  // tabs whatever the switch, say it now, in the explainer's own words.
  // "Never sold" and not "cannot be bought with money": a friend who pays a
  // first month is paid Su for the invitation, and that is not a sale.
  group('Su are earned, never sold', () {
    const sentence = {AppLang.en: 'Su Points are only earned, never sold.', AppLang.ar: 'نقاط Su بتتكسب بس ومش بتتباع.'};
    for (final lang in AppLang.values) {
      for (final shown in const [true, false]) {
        testWidgets('the wallet says so on both tabs, with "Points and streaks" ${shown ? 'on' : 'off'} (${lang.name})', (tester) async {
          final s = AppState()..setLang(lang);
          s.setShowScore(shown);
          s.go(AppScreen.wallet);
          await _pumpApp(tester, s);
          await tester.pump(const Duration(milliseconds: 400));
          for (final tab in [s.showSpend, s.showHistory]) {
            tab();
            await tester.pump();
            await tester.dragUntilVisible(find.byKey(WalletScreen.termsKey), find.byType(Scrollable).first, const Offset(0, -200));
            final terms = tester.widget<Text>(find.byKey(WalletScreen.termsKey)).data!;
            expect(terms, startsWith(sentence[lang]!), reason: s.walletTab.name);
          }
        });
      }
      test('the Su explainer says it in the same words (${lang.name})', () {
        final e = kExplanations['su_points']!;
        expect(lang == AppLang.ar ? e.soWhatAr : e.soWhatEn, startsWith(sentence[lang]!));
        expect(QStrings.of(lang).walletTerms, startsWith(sentence[lang]!));
      });
    }
  });

  // The extra photo's cap counts per Cairo day (0067: the purchases whose
  // Cairo date is today), so both languages name the same reset: English
  // said "refreshes at Cairo midnight", Arabic "بكرة الصبح" (tomorrow
  // morning), hours after the photos are back.
  test('the extra photo\'s limit names the same reset in both languages: Cairo midnight', () {
    final photo = kSpendCatalog.singleWhere((i) => i.id == 'ai_extra');
    expect(photo.limitEn, contains('Cairo midnight'));
    expect(photo.limitAr, contains('نص الليل بتوقيت القاهرة'));
    expect(photo.limitAr, isNot(contains('الصبح')));
  });

  group('the naming rule', () {
    test('English: the number and "Su"', () {
      final s = AppState()..setLang(AppLang.en);
      expect(s.suAmount(100), '100 Su');
      expect(s.suAmount(100, signed: true), '+100 Su');
      expect(s.suAmount(1000), '1,000 Su');
    });

    test('Arabic: the name, with the number agreement Arabic needs', () {
      final s = AppState()..setLang(AppLang.ar);
      String plain(String x) => x.replaceAll(RegExp('[\u2066-\u2069]'), '');
      expect(plain(s.suAmount(5)), '٥ نقاط Su');
      expect(plain(s.suAmount(10)), '١٠ نقاط Su');
      expect(plain(s.suAmount(100)), '١٠٠ نقطة Su');
      expect(plain(s.suAmount(1000)), '١٬٠٠٠ نقطة Su');
      expect(plain(s.suAmount(250, signed: true)), '+٢٥٠ نقطة Su');
      expect(s.suAmount(100), isNot(contains(RegExp('[0-9]'))));
    });

    // The wallet's History: the number alone, signed, through the same
    // formatter as the balance above it. It drew the raw int: "+1000" under
    // "1,000", and in Arabic "+1000" and "-800" in Latin digits under a
    // balance in Eastern ones.
    test('History\'s signed numbers: separated, and Eastern in Arabic with the sign before the number', () {
      final en = AppState()..setLang(AppLang.en);
      expect(en.suSigned(1000), '+1,000');
      expect(en.suSigned(-800), '-800');
      expect(en.suSigned(100), '+100');
      final ar = AppState()..setLang(AppLang.ar);
      expect(ar.suSigned(1000), '\u2066+١٬٠٠٠\u2069');
      expect(ar.suSigned(-800), '\u2066-٨٠٠\u2069');
    });

    for (final lang in AppLang.values) {
      testWidgets('the wallet\'s History draws them (${lang.name})', (tester) async {
        final s = AppState()..setLang(lang);
        s.ledgerExtra.addAll(const [
          LedgerEntry(label: 'Onboarding', amount: 1000, when: 'Yesterday'),
          LedgerEntry(label: 'Extra question', amount: -800, when: 'Just now'),
        ]);
        s.go(AppScreen.wallet);
        s.showHistory();
        await _pumpApp(tester, s);
        await tester.pump(const Duration(milliseconds: 400));
        final shown = _texts(tester, find.byType(MaterialApp));
        expect(shown, containsAll([s.suSigned(1000), s.suSigned(-800)]));
        expect(shown, isNot(contains('+1000')));
      });
    }
  });
}
