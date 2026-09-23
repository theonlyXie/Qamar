// Controls that say what they will do, seat 6's part (the scorecard's 08,
// 09, 11 and 12): switches drawn in the palette, not stock grey; a spend or
// a payout the balance does not reach is off, not a live-looking button
// that quietly does nothing; the wallet's chosen tab is a cool surface, not
// gold washed to warm grey; a placeholder for a code is an instruction, not
// a title; and the scan offers typing once, not three times.

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

import 'package:qamar/l10n/strings.dart';
import 'package:qamar/main.dart';
import 'package:qamar/models/billing.dart';
import 'package:qamar/screens/you_screen.dart';
import 'package:qamar/state/app_state.dart';
import 'package:qamar/theme/app_theme.dart';
import 'package:qamar/theme/colors.dart';
import 'package:qamar/widgets/common.dart';

import 'support/app_fonts.dart';

Future<void> _pumpApp(WidgetTester tester, AppState s) async {
  tester.view.devicePixelRatio = 3;
  tester.view.physicalSize = const Size(390, 2400) * 3;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(ChangeNotifierProvider.value(value: s, child: const QamarApp()));
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 400));
}

QOutlineButton _outline(WidgetTester tester, String label) =>
    tester.widget<QOutlineButton>(find.ancestor(of: find.text(label), matching: find.byType(QOutlineButton)).first);

void main() {
  setUpAll(() async {
    await loadAppFonts();
    for (final name in const ['com.qamar.app/quick_events', 'com.qamar.app/quick_invoke']) {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(MethodChannel(name), (call) async => null);
    }
  });

  test('switches are the palette’s: white on the deep violet, a muted thumb on an edged card', () {
    final theme = buildQamarTheme().switchTheme;
    expect(theme.thumbColor!.resolve({WidgetState.selected}), QColors.onAccent);
    expect(theme.trackColor!.resolve({WidgetState.selected}), QColors.violetDeep);
    expect(theme.thumbColor!.resolve({}), QColors.textMuted);
    expect(theme.trackColor!.resolve({}), QColors.cardMid);
    expect(theme.trackOutlineColor!.resolve({}), QColors.borderStrong);
  });

  for (final lang in AppLang.values) {
    testWidgets('no screen paints its own switch colours over the theme (${lang.name})', (tester) async {
      final s = AppState()..setLang(lang);
      s.plusPromoCode = 'QMR-TEST1';
      await _pumpApp(tester, s);
      var seen = 0;
      for (final screen in AppScreen.values) {
        s.go(screen);
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 400));
        for (final sw in tester.widgetList<Switch>(find.byType(Switch))) {
          seen++;
          expect(sw.activeThumbColor, isNull, reason: 'on $screen');
          expect(sw.activeTrackColor, isNull, reason: 'on $screen');
          expect(sw.thumbColor, isNull, reason: 'on $screen');
        }
      }
      expect(seen, greaterThan(3), reason: 'the sweep met the switches');
    });

    testWidgets('a spend the balance does not reach is off, and says no "after" (${lang.name})', (tester) async {
      final s = AppState()..setLang(lang);
      s.go(AppScreen.today);
      s.go(AppScreen.wallet);
      await _pumpApp(tester, s);
      expect(s.suAvailable, 0);
      final redeem = s.t.spendCta;
      expect(find.text(redeem), findsWidgets);
      for (final b in tester.widgetList<QOutlineButton>(find.ancestor(of: find.text(redeem), matching: find.byType(QOutlineButton)))) {
        expect(b.onTap, isNull, reason: 'nothing to spend: the button is off');
      }
      expect(find.textContaining(s.t.balanceAfter), findsNothing, reason: 'no "after" under a price out of reach');

      s.suAvailable = 5000;
      s.showSpend();
      await tester.pump();
      expect(_outline(tester, redeem).onTap, isNotNull, reason: 'in reach: on');
      expect(find.textContaining(s.t.balanceAfter), findsWidgets);
    });

    testWidgets('the wallet’s chosen tab is a cool surface with a gold edge (${lang.name})', (tester) async {
      final s = AppState()..setLang(lang);
      s.go(AppScreen.today);
      s.go(AppScreen.wallet);
      await _pumpApp(tester, s);
      final spend = find.text(s.t.spendTab);
      final boxes = tester
          .widgetList<Container>(find.ancestor(of: spend.first, matching: find.byType(Container)))
          .map((c) => c.decoration)
          .whereType<BoxDecoration>()
          .where((d) => d.color != null);
      final fill = boxes.first.color!;
      expect(fill, QColors.glassHigh);
      expect(fill.b, greaterThan(fill.r), reason: 'cool, not warm grey');
    });

    testWidgets('below the smallest payout, the payout is off; with no code, the way to one is an instruction (${lang.name})', (tester) async {
      final s = AppState()..setLang(lang);
      s.go(AppScreen.today);
      s.go(AppScreen.you);
      await _pumpApp(tester, s);
      final payout = s.isAr ? 'حوّل العمولة' : 'Redeem EGP';
      expect(_outline(tester, payout).onTap, isNull, reason: 'EGP 0: nothing to send');
      final link = tester.getSize(find.ancestor(of: find.text(s.t.linkAccount), matching: find.byType(QPillButton)));
      expect(link.width, lessThan(390 * 0.6), reason: 'a compact pill, as wide as its label');
      expect(link.height, greaterThanOrEqualTo(48), reason: 'touched across 48');
      final placeholder = tester.widget<Text>(find.byKey(YouScreen.proCodeKey));
      expect(placeholder.style!.color, QColors.textMuted);
      expect(placeholder.style!.fontSize, lessThan(17), reason: 'not set like the code it stands in for');

      s.affiliateWallet = const AffiliateWallet(code: 'QMR-AB12', balanceCents: 5000);
      s.setLang(lang); // rebuild
      await tester.pump();
      expect(_outline(tester, payout).onTap, isNotNull, reason: 'EGP 50: it can be sent');
      expect(tester.widget<Text>(find.byKey(YouScreen.proCodeKey)).style!.fontSize, 17, reason: 'a code is set as a code');
    });

    testWidgets('the scan offers typing once beside the shutter, not again under it (${lang.name})', (tester) async {
      final s = AppState()..setLang(lang);
      s.openScan();
      await _pumpApp(tester, s);
      expect(find.byIcon(Icons.keyboard_outlined), findsOneWidget);
      expect(find.text(lang == AppLang.ar ? 'أو اكتب بدل الكلام' : 'or type instead'), findsNothing);
      expect(find.byType(TextButton), findsNothing);
    });
  }
}
