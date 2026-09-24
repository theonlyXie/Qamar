// The Log sheet, the orb's tap, where the tree used to bloom. Seat 2 found
// the tree's hint — "hold Qamar to talk" — pointing at a gesture the moon in
// view did not answer. The sheet says the hold once, under its last row, and
// rises under the tab bar, so the moon it names is in view and answers it: a
// hold talks, a tap puts the sheet away. Its ask row opens the conversation
// to type; on a short phone the sheet scrolls, and never runs under the bar.

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

import 'package:qamar/l10n/strings.dart';
import 'package:qamar/main.dart';
import 'package:qamar/state/app_state.dart';
import 'package:qamar/widgets/common.dart';
import 'package:qamar/widgets/log_sheet.dart';
import 'package:qamar/widgets/tab_bar.dart';

import 'support/app_fonts.dart';

Future<void> _pumpApp(WidgetTester tester, AppState s, {Size size = const Size(390, 844)}) async {
  tester.view.devicePixelRatio = 3;
  tester.view.physicalSize = size * 3;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(ChangeNotifierProvider.value(value: s, child: const QamarApp()));
  await tester.pump(const Duration(milliseconds: 400));
}

/// Today, with the Log sheet risen.
Future<AppState> _logUp(WidgetTester tester, AppLang lang, {Size size = const Size(390, 844)}) async {
  final s = AppState()..setLang(lang);
  s.dismissOrbTutorial();
  s.go(AppScreen.today);
  await _pumpApp(tester, s, size: size);
  s.orbTap();
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 700));
  expect(s.logOpen, isTrue);
  return s;
}

void main() {
  setUpAll(() async {
    await loadAppFonts();
    for (final name in const ['com.qamar.app/quick_events', 'com.qamar.app/quick_invoke']) {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(MethodChannel(name), (call) async => null);
    }
  });

  for (final lang in AppLang.values) {
    testWidgets('its last row asks, and names the hold of the moon in view, above the bar (${lang.name})', (tester) async {
      final isAr = lang == AppLang.ar;
      await _logUp(tester, lang);
      final ask = find.byKey(LogSheet.askKey);
      expect(find.descendant(of: ask, matching: find.text(isAr ? 'اسأل قمر أي حاجة' : 'Ask Qamar anything')), findsOneWidget);
      expect(find.descendant(of: ask, matching: find.text(isAr ? 'أو استمر ضاغط على القمر وكلّمه' : 'or hold the moon to talk')), findsOneWidget);
      final bar = tester.getRect(find.byKey(QTabBar.barKey));
      expect(tester.getRect(ask).bottom, lessThanOrEqualTo(bar.top), reason: 'the sheet runs on under the bar; its rows end above it');
      final orb = tester.getCenter(find.byKey(QTabBar.orbKey));
      expect(tester.hitTestOnBinding(orb).path.any((e) => e.target == tester.renderObject(find.byKey(QTabBar.orbKey))), isTrue,
          reason: 'the moon is over the sheet’s scrim, where a finger can reach it');
    });
  }

  testWidgets('holding the moon while the sheet is up talks, and the hold is learned', (tester) async {
    final s = await _logUp(tester, AppLang.en);
    final gesture = await tester.startGesture(tester.getCenter(find.byKey(QTabBar.orbKey)));
    await tester.pump(const Duration(milliseconds: 400));
    await gesture.up();
    await tester.pump();
    expect(s.gesturesLearned, contains(OrbGesture.hold), reason: 'the sheet said hold, and holding works');
    expect(s.chatOpen, isTrue);
    expect(s.logOpen, isFalse, reason: 'the sheet gives way to the conversation');
    expect(s.dictationError, isNotNull, reason: 'it tried to listen: this test phone has no recogniser');
  });

  testWidgets('a tap on the moon puts the sheet away, where it came from', (tester) async {
    final s = await _logUp(tester, AppLang.en);
    await tester.tap(find.byKey(QTabBar.orbKey));
    await tester.pump();
    expect(s.logOpen, isFalse);
    expect(s.chatOpen, isFalse);
  });

  testWidgets('a tap on the page’s own tab puts it away too; another tab goes there', (tester) async {
    final s = await _logUp(tester, AppLang.en);
    await tester.tap(find.byKey(QTabBar.tabKey(AppScreen.today)));
    await tester.pump();
    expect(s.logOpen, isFalse);
    expect(s.screen, AppScreen.today);

    s.orbTap();
    await tester.pump(const Duration(milliseconds: 700));
    await tester.tap(find.byKey(QTabBar.tabKey(AppScreen.plan)));
    await tester.pump();
    expect(s.logOpen, isFalse);
    expect(s.screen, AppScreen.plan);
  });

  testWidgets('taking the moon out to explain a number puts the sheet away first', (tester) async {
    final s = await _logUp(tester, AppLang.en);
    final finger = await tester.startGesture(tester.getCenter(find.byKey(QTabBar.orbKey)));
    await finger.moveBy(const Offset(0, -30));
    await tester.pump();
    await finger.moveBy(const Offset(0, -150));
    await tester.pump();
    expect(s.orbHeld, isTrue);
    expect(s.logOpen, isFalse, reason: 'the page is what the moon is taken over');
    await finger.up();
    for (var i = 0; i < 10; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
    expect(s.orbHeld, isFalse);
  });

  testWidgets('a tap on the ask row opens the conversation to type', (tester) async {
    final s = await _logUp(tester, AppLang.en);
    await tester.tap(find.byKey(LogSheet.askKey));
    await tester.pump();
    expect(s.chatOpen, isTrue);
    expect(s.logOpen, isFalse);
    expect(s.gesturesLearned, isNot(contains(OrbGesture.hold)));
  });

  for (final lang in AppLang.values) {
    testWidgets('on a short phone it scrolls, stops under the top, and every row can be reached above the bar (${lang.name})', (tester) async {
      const small = Size(375, 667);
      await _logUp(tester, lang, size: small);
      expect(tester.takeException(), isNull, reason: 'no overflow');
      final panel = tester.getRect(find.descendant(of: find.byType(LogSheet), matching: find.byKey(QSheetScrim.panelKey)));
      expect(panel.top, greaterThanOrEqualTo(24 - 0.5), reason: 'the sheet stops under the top');
      final ask = find.byKey(LogSheet.askKey);
      await tester.ensureVisible(ask);
      await tester.pump();
      expect(tester.getRect(ask).bottom, lessThanOrEqualTo(tester.getRect(find.byKey(QTabBar.barKey)).top));
    });
  }

  testWidgets('with nothing drunk yet the water line names the goal alone, never a lone Arabic zero', (tester) async {
    final s = await _logUp(tester, AppLang.ar);
    final sheet = find.byType(LogSheet);
    expect(find.descendant(of: sheet, matching: find.textContaining('هدفك')), findsOneWidget);
    expect(find.descendant(of: sheet, matching: find.textContaining('٠ من')), findsNothing);
    s.quickWater(kWaterChoices.first.unit);
    s.orbTap(); // the glass put the sheet away; up again
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 700));
    expect(find.descendant(of: find.byType(LogSheet), matching: find.textContaining('من')), findsWidgets, reason: 'then how much of it');
  });

  testWidgets('under reduce motion nothing on the sheet runs', (tester) async {
    final s = AppState()..setLang(AppLang.en);
    s.go(AppScreen.today);
    s.toggleLog();
    await tester.binding.setSurfaceSize(const Size(390, 844));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(ChangeNotifierProvider.value(
      value: s,
      child: MaterialApp(
        builder: (context, child) => MediaQuery(data: MediaQuery.of(context).copyWith(disableAnimations: true), child: child!),
        home: const Scaffold(body: Stack(children: [LogSheet()])),
      ),
    ));
    await tester.pumpAndSettle();
    expect(tester.binding.hasScheduledFrame, isFalse, reason: 'the sheet comes to rest, and stays');
  });
}
