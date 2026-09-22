// The way back (seat 2): one rule, everywhere. Every screen but the two
// roots — the welcome screen and Today — has one back control at the top
// start corner, with the same arrow, and it returns to the screen the person
// came from. The phone's back does the same, after closing whatever sheet is
// open. The orb is the way home, and it shows on every in-app screen,
// Ramadan included: that screen used to have neither.

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

import 'package:qamar/l10n/strings.dart';
import 'package:qamar/main.dart';
import 'package:qamar/models/messages.dart';
import 'package:qamar/state/app_state.dart';
import 'package:qamar/widgets/common.dart';
import 'package:qamar/widgets/orb_nav.dart';

import 'support/app_fonts.dart';

const _phone = Size(390, 844);

/// How the person reaches each screen, and so where its back goes. The
/// wallet and the paywall are reached from the place their old buttons did
/// *not* go to (the wallet's went to Today, the paywall's to Me), so a
/// button wired to a fixed place fails here.
final _reach = <AppScreen, (AppScreen from, void Function(AppState s) open)>{
  AppScreen.plan: (AppScreen.today, (s) => s.go(AppScreen.plan)),
  AppScreen.progress: (AppScreen.today, (s) => s.go(AppScreen.progress)),
  AppScreen.you: (AppScreen.today, (s) => s.go(AppScreen.you)),
  AppScreen.wallet: (AppScreen.you, (s) => s.openWallet()),
  AppScreen.subscription: (AppScreen.today, (s) => s.openSubscription()),
  AppScreen.ramadan: (AppScreen.today, (s) => s.go(AppScreen.ramadan)),
  AppScreen.scan: (AppScreen.welcome, (s) => s.openScan()),
  AppScreen.onboard: (AppScreen.welcome, (s) => s.startOnboarding()),
};

Future<void> _pump(WidgetTester tester, AppState s) async {
  await tester.binding.setSurfaceSize(_phone);
  addTearDown(() => tester.binding.setSurfaceSize(null));
  await tester.pumpWidget(ChangeNotifierProvider.value(value: s, child: const QamarApp()));
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 400));
}

void main() {
  setUpAll(() async {
    await loadAppFonts();
    for (final name in const ['com.qamar.app/quick_events', 'com.qamar.app/quick_invoke']) {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(MethodChannel(name), (call) async => null);
    }
  });

  test('every screen is either a root or has a way back, and the list above covers them all', () {
    for (final screen in AppScreen.values) {
      final root = AppState.rootScreens.contains(screen);
      expect(root || _reach.containsKey(screen), isTrue, reason: '$screen has no way back and is not a root');
    }
    expect(AppState.rootScreens, {AppScreen.welcome, AppScreen.today});
  });

  for (final lang in AppLang.values) {
    for (final entry in _reach.entries) {
      final screen = entry.key;
      final (from, open) = entry.value;
      testWidgets('$screen has one back control at the top start, and it goes back to $from (${lang.name})', (tester) async {
        final s = AppState()..setLang(lang);
        s.go(from);
        open(s);
        expect(s.screen, screen);
        await _pump(tester, s);
        expect(tester.takeException(), isNull, reason: 'the header must still fit on a phone');

        final back = find.byType(QBackButton);
        expect(back, findsOneWidget);
        final r = tester.getRect(back);
        expect(r.height, greaterThanOrEqualTo(48));
        expect(r.width, greaterThanOrEqualTo(48));
        expect(r.top, lessThan(160), reason: 'at the top');
        if (lang == AppLang.ar) {
          expect(r.center.dx, greaterThan(_phone.width * 2 / 3), reason: 'the start corner is the right in Arabic');
        } else {
          expect(r.center.dx, lessThan(_phone.width / 3), reason: 'the start corner is the left in English');
        }
        // In-app screens also show the orb, the way home.
        if (from == AppScreen.today || from == AppScreen.you) expect(find.byType(OrbNav), findsOneWidget, reason: '$screen shows the orb');

        await tester.tap(back);
        await tester.pump();
        expect(s.screen, from);
      });
    }
  }

  test('back returns to where the person came from, not to a fixed place', () {
    final s = AppState()..setLang(AppLang.en);
    s.go(AppScreen.today);
    s.go(AppScreen.you);
    s.openSubscription();
    s.back();
    expect(s.screen, AppScreen.you);
    s.back();
    expect(s.screen, AppScreen.today);

    // The same paywall opened from Today's billing card goes back to Today.
    s.openSubscription();
    s.back();
    expect(s.screen, AppScreen.today, reason: 'it used to close to Me whatever opened it');

    // Going back to a screen already on the way cuts it there: no loops.
    s.go(AppScreen.you);
    s.openWallet();
    s.go(AppScreen.you);
    s.back();
    expect(s.screen, AppScreen.today);
  });

  testWidgets('the phone’s back closes the sheet on top first, then goes back, and at Today it is the system’s', (tester) async {
    final s = AppState()..setLang(AppLang.en);
    s.go(AppScreen.today);
    s.go(AppScreen.plan);
    await _pump(tester, s);

    s.openChat();
    await tester.pump();
    await tester.binding.handlePopRoute();
    await tester.pump();
    expect(s.chatOpen, isFalse);
    expect(s.screen, AppScreen.plan, reason: 'the conversation closed; the screen stayed');

    await tester.binding.handlePopRoute();
    await tester.pump();
    expect(s.screen, AppScreen.today);
    expect(s.handlesSystemBack, isFalse, reason: 'at Today with nothing open, back is the system’s');
  });

  test('the consultation left part-way keeps its answers and carries on', () {
    final s = AppState()..setLang(AppLang.en);
    s.startOnboarding();
    final firstStep = s.step;
    s.msgs.add(const ObMessage.u(ar: 'موافق', en: 'Agreed'));
    final said = s.msgs.length;
    s.back();
    expect(s.screen, AppScreen.welcome);
    s.startOnboarding();
    expect(s.screen, AppScreen.onboard);
    expect(s.msgs.length, said, reason: 'nothing was lost');
    expect(s.step, firstStep);
  });

  test('left before any answer, it simply starts again', () {
    final s = AppState()..setLang(AppLang.en);
    s.startOnboarding();
    s.back();
    expect(s.consultationPaused, isFalse);
  });

  test('the arrow turns with the language', () {
    expect(Icons.arrow_back.matchTextDirection, isTrue);
  });
}
