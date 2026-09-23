// Grounds and alignments, seat 6's part (the scorecard's 08, 11, 12 and the
// renders of 13/14): what covers the screen reaches its edges, the status
// bar and the home indicator included, instead of stopping under a strip of
// the page's sky; the wallet's two labels share a baseline; and Progress's
// cards share one edge, the state said by the eyebrow's colour.

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

import 'package:qamar/l10n/strings.dart';
import 'package:qamar/main.dart';
import 'package:qamar/models/meal.dart';
import 'package:qamar/screens/home_shell.dart';
import 'package:qamar/screens/wallet_screen.dart';
import 'package:qamar/state/app_state.dart';
import 'package:qamar/theme/colors.dart';
import 'package:qamar/widgets/ask_qamar_overlay.dart';

import 'support/app_fonts.dart';

Future<void> _pumpPhone(WidgetTester tester, AppState s) async {
  tester.view.devicePixelRatio = 3;
  tester.view.physicalSize = const Size(390, 844) * 3;
  tester.view.padding = const FakeViewPadding(top: 47 * 3, bottom: 34 * 3);
  addTearDown(tester.view.reset);
  await tester.pumpWidget(ChangeNotifierProvider.value(value: s, child: const QamarApp()));
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 400));
}

Color _strip(WidgetTester tester, Key key) {
  final box = tester.widget<AnimatedContainer>(find.byKey(key));
  return (box.decoration as BoxDecoration?)?.color ?? Colors.transparent;
}

void main() {
  setUpAll(() async {
    await loadAppFonts();
    for (final name in const ['com.qamar.app/quick_events', 'com.qamar.app/quick_invoke']) {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(MethodChannel(name), (call) async => null);
    }
  });

  testWidgets('what covers the screen reaches the status bar and the home indicator', (tester) async {
    final s = AppState()..setLang(AppLang.en);
    s.dismissOrbTutorial();
    s.go(AppScreen.today);
    await _pumpPhone(tester, s);
    expect(tester.getSize(find.byKey(HomeShell.topStripKey)).height, 47);
    expect(tester.getSize(find.byKey(HomeShell.bottomStripKey)).height, 34);
    expect(_strip(tester, HomeShell.topStripKey), Colors.transparent, reason: 'the page’s own sky');

    s.openChat();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    expect(_strip(tester, HomeShell.topStripKey), AskQamarOverlay.groundTop, reason: 'the conversation’s ground, to the top edge');
    expect(_strip(tester, HomeShell.bottomStripKey), AskQamarOverlay.groundBottom);
    s.closeChat();

    s.openWhy();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    expect(_strip(tester, HomeShell.topStripKey), QColors.scrim, reason: 'a sheet dims the status bar too');
    expect(_strip(tester, HomeShell.bottomStripKey), QColors.surface, reason: 'the sheet itself, at the bottom');
    s.closeWhy();

    s.openScan();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    expect(_strip(tester, HomeShell.topStripKey), QColors.canvas, reason: 'the scan is black edge to edge');
    expect(_strip(tester, HomeShell.bottomStripKey), QColors.canvas);
  });

  test('covers stack in the order they are drawn', () {
    final s = AppState()..setLang(AppLang.en);
    s.go(AppScreen.today);
    s.openChat();
    s.openWhy();
    expect(HomeShell.coverAt(s, top: true), Color.alphaBlend(QColors.scrim, AskQamarOverlay.groundTop));
  });

  for (final lang in AppLang.values) {
    testWidgets('the wallet’s two labels share a baseline (${lang.name})', (tester) async {
      final s = AppState()..setLang(lang);
      s.go(AppScreen.today);
      s.go(AppScreen.wallet);
      await _pumpPhone(tester, s);
      final available = tester.getRect(find.byKey(WalletScreen.availableLabelKey));
      final lifetime = tester.getRect(find.byKey(WalletScreen.lifetimeLabelKey));
      expect(lifetime.bottom, moreOrLessEquals(available.bottom, epsilon: 0.5), reason: 'one line of labels, not a 35px stagger');
    });

    testWidgets('Progress’s cards share one edge (${lang.name})', (tester) async {
      final s = AppState()..setLang(lang);
      s.meals.add(LoggedMeal(name: 'Koshary', sub: '', kcal: 640, p: 20, c: 100, f: 18, at: DateTime.now()));
      s.go(AppScreen.today);
      s.go(AppScreen.progress);
      await _pumpPhone(tester, s);
      for (final eyebrow in [lang == AppLang.ar ? 'السلسلة' : 'Streak', s.t.thisWeek]) {
        final edges = tester
            .widgetList<Container>(find.ancestor(of: find.text(eyebrow).first, matching: find.byType(Container)))
            .map((c) => c.decoration)
            .whereType<BoxDecoration>()
            .map((d) => d.border)
            .whereType<Border>()
            .map((b) => b.top.color)
            .toList();
        expect(edges, isNotEmpty, reason: eyebrow);
        expect(edges.first, QColors.hairline, reason: '$eyebrow’s card: the one edge, the hairline');
      }
    });
  }
}
