// The tab bar (O1): a floating pill at the foot of the four tab pages,
// Today and Progress, the orb, Plan and Me, and nowhere else. The page on
// show is its burgundy circle; the orb rests in the middle. A drag takes the
// moon out of the bar (explain reads the moon's centre mid-drag); letting go
// springs it back into its circle, from where the finger left it and at the
// finger's speed. A tap on the orb opens the Log sheet. The tab pages have
// no back control and end their lists above the band.

import 'dart:ui' show Tristate;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

import 'package:qamar/l10n/strings.dart';
import 'package:qamar/main.dart';
import 'package:qamar/models/meal.dart';
import 'package:qamar/state/app_state.dart';
import 'package:qamar/theme/colors.dart';
import 'package:qamar/theme/layout.dart';
import 'package:qamar/widgets/common.dart';
import 'package:qamar/widgets/explain.dart';
import 'package:qamar/widgets/living_orb.dart';
import 'package:qamar/widgets/log_sheet.dart';
import 'package:qamar/widgets/moon.dart';
import 'package:qamar/widgets/tab_bar.dart';

import 'support/app_fonts.dart';

const _area = Size(390, 844);
const _bandTop = 844 - QLayout.tabBand;

Future<void> _pumpBar(WidgetTester tester, AppState s, {bool still = false}) async {
  await tester.binding.setSurfaceSize(_area);
  addTearDown(() => tester.binding.setSurfaceSize(null));
  await tester.pumpWidget(ChangeNotifierProvider.value(
    value: s,
    child: MaterialApp(
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(context).copyWith(disableAnimations: still),
        child: Directionality(
          textDirection: context.watch<AppState>().isAr ? TextDirection.rtl : TextDirection.ltr,
          child: child!,
        ),
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

Rect _orb(WidgetTester t) => t.getRect(find.byKey(QTabBar.orbKey));

void _expectInBand(Rect r, String why) {
  expect(r.top, greaterThanOrEqualTo(_bandTop), reason: '$why: inside the band, not on the page');
  expect(r.bottom, lessThanOrEqualTo(_area.height), reason: why);
}

void _expectHome(WidgetTester tester, String why) {
  final r = _orb(tester);
  expect(r.center.dx, moreOrLessEquals(_area.width / 2, epsilon: 0.5), reason: '$why: in the middle of the bar');
  _expectInBand(r, why);
}

AppState _today(AppLang lang) {
  final s = AppState()..setLang(lang);
  s.profile = s.profile.copyWith(name: 'Basel');
  s.dismissOrbTutorial();
  s.go(AppScreen.today);
  return s;
}

void main() {
  setUpAll(() async {
    await loadAppFonts();
    for (final name in const ['com.qamar.app/quick_events', 'com.qamar.app/quick_invoke']) {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(MethodChannel(name), (call) async => null);
    }
  });

  group('at rest', () {
    for (final lang in AppLang.values) {
      testWidgets('the orb rests in the middle of the bar, and the tabs sit either side of it in the reading order (${lang.name})', (tester) async {
        final s = _today(lang);
        await _pumpBar(tester, s);
        _expectHome(tester, 'at rest');
        expect(s.orbHeld, isFalse);
        final xs = [for (final t in kTabs) tester.getCenter(find.byKey(QTabBar.tabKey(t.screen))).dx];
        final orb = _orb(tester).center.dx;
        final rtl = lang == AppLang.ar;
        // Today, Progress | orb | Plan, Me — from the start edge.
        final ordered = rtl ? (List.of(xs)..sort((a, b) => b.compareTo(a))) : (List.of(xs)..sort());
        expect(xs, ordered, reason: 'the tabs run the way the page reads');
        expect(rtl ? xs[1] > orb && xs[2] < orb : xs[1] < orb && xs[2] > orb, isTrue, reason: 'Progress before the orb, Plan after it');
        final bar = tester.getRect(find.byKey(QTabBar.barKey));
        expect(bar.height, QLayout.tabBar);
        expect(bar.bottom, moreOrLessEquals(_area.height - QLayout.tabBarGap, epsilon: 0.5));
        expect(bar.center.dx, moreOrLessEquals(_area.width / 2, epsilon: 0.5));
      });
    }

    testWidgets('the page on show is its burgundy circle, and says it is chosen', (tester) async {
      final s = _today(AppLang.en);
      final semantics = tester.ensureSemantics();
      await _pumpBar(tester, s);
      Color fill(AppScreen screen) {
        final box = tester.widget<AnimatedContainer>(find.descendant(of: find.byKey(QTabBar.tabKey(screen)), matching: find.byType(AnimatedContainer)));
        return (box.decoration! as BoxDecoration).color!;
      }

      expect(fill(AppScreen.today), QColors.accent);
      for (final other in [AppScreen.progress, AppScreen.plan, AppScreen.you]) {
        expect(fill(other), QColors.surfaceHigh, reason: '$other at rest');
      }
      final today = tester.getSemantics(find.byKey(QTabBar.tabKey(AppScreen.today)));
      expect(today.label, 'Today');
      expect(today.flagsCollection.isSelected, Tristate.isTrue);
      final plan = tester.getSemantics(find.byKey(QTabBar.tabKey(AppScreen.plan)));
      expect(plan.label, 'Plan');
      expect(plan.flagsCollection.isSelected, isNot(Tristate.isTrue));
      semantics.dispose();
    });

    testWidgets('the orb is calm in its circle: the moon breathes where it is, and nothing orbits it', (tester) async {
      final s = _today(AppLang.en);
      await _pumpBar(tester, s);
      final home = tester.getCenter(find.byType(QamarMoon));
      // The breath and the halo share a five-second cycle; sample it.
      for (var i = 0; i < 20; i++) {
        await tester.pump(const Duration(milliseconds: 250));
        expect(tester.getCenter(find.byType(QamarMoon)), home, reason: 'no drift at ${i * 250}ms');
      }
      expect(find.byType(QamarMoon), findsOneWidget, reason: 'one moon, and nothing drawn round it but its light');
    });

    testWidgets('the band takes no touches beside the bar: only the bar does', (tester) async {
      final s = _today(AppLang.en);
      await _pumpApp(tester, s);
      final bar = tester.getRect(find.byKey(QTabBar.barKey));
      final fade = tester.renderObject(find.byType(TabBarFade));
      final barBox = tester.renderObject(find.byKey(QTabBar.barKey));
      final point = Offset(bar.left / 2, bar.center.dy); // in the band, beside the pill
      final result = HitTestResult();
      tester.binding.hitTestInView(result, point, tester.view.viewId);
      final targets = result.path.map((e) => e.target).toList();
      expect(targets, isNot(contains(fade)), reason: 'the fade draws and takes nothing');
      bool inBar(Object t) => t is RenderObject && (identical(t, barBox) || _isDescendant(t, barBox));
      expect(targets.any(inBar), isFalse, reason: 'a touch beside the bar is not the bar’s');
    });
  });

  group('the tabs', () {
    testWidgets('a tab goes to its page, which has no back control: the bar is the way between them', (tester) async {
      final s = _today(AppLang.en);
      await _pumpApp(tester, s);
      for (final t in [AppScreen.progress, AppScreen.plan, AppScreen.you, AppScreen.today]) {
        await tester.tap(find.byKey(QTabBar.tabKey(t)));
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 400));
        expect(s.screen, t);
        expect(find.byType(QBackButton), findsNothing, reason: '$t is a tab: no back control');
      }
    });

    test('the phone\'s back from a tab goes to Today, and from Today leaves the app', () {
      final s = _today(AppLang.en);
      s.go(AppScreen.plan);
      s.go(AppScreen.you);
      expect(s.handlesSystemBack, isTrue);
      s.systemBack();
      expect(s.screen, AppScreen.today, reason: 'tabs are peers: back goes home, not through the tabs visited');
      expect(s.handlesSystemBack, isFalse);
    });

    test('the pages under a tab keep their way back to it', () {
      final s = _today(AppLang.en);
      s.go(AppScreen.you);
      s.openWallet();
      expect(s.orbVisible, isFalse, reason: 'no bar over the wallet');
      s.back();
      expect(s.screen, AppScreen.you);
    });
  });

  group('the orb', () {
    testWidgets('a tap opens the Log sheet, and a second tap puts it away', (tester) async {
      final s = _today(AppLang.en);
      await _pumpApp(tester, s);
      await tester.tap(find.byKey(QTabBar.orbKey));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 500));
      expect(s.logOpen, isTrue);
      expect(find.byType(LogSheet), findsOneWidget);
      s.orbTap();
      await tester.pump(const Duration(milliseconds: 600));
      expect(s.logOpen, isFalse);
    });

    testWidgets('a hold opens the conversation, listening', (tester) async {
      final s = _today(AppLang.en);
      await _pumpApp(tester, s);
      await tester.longPress(find.byKey(QTabBar.orbKey));
      await tester.pump();
      expect(s.chatOpen, isTrue);
      expect(s.gesturesLearned, contains(OrbGesture.hold));
    });

    testWidgets('dragged out and let go, it springs back into the middle from where the finger left it', (tester) async {
      final s = _today(AppLang.en);
      await _pumpBar(tester, s);
      final from = tester.getCenter(find.byType(LivingOrb));
      await tester.timedDragFrom(from, const Offset(-120, -300), const Duration(milliseconds: 600));
      await tester.pump();
      final released = _orb(tester);
      expect(released.center.dy, lessThan(_bandTop), reason: 'the spring starts where the finger left it, not in the bar');
      expect(s.orbHeld, isFalse);
      await tester.pump(const Duration(seconds: 2));
      _expectHome(tester, 'after the spring');
    });

    testWidgets('the spring can be grabbed mid-flight, from where it is on screen', (tester) async {
      final s = _today(AppLang.en);
      await _pumpBar(tester, s);
      await tester.timedDragFrom(tester.getCenter(find.byType(LivingOrb)), const Offset(-100, -260), const Duration(milliseconds: 400));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 60));
      final midFlight = _orb(tester);
      final gesture = await tester.startGesture(midFlight.center);
      // Past the touch slop, so the drag takes it.
      await gesture.moveBy(const Offset(0, -30));
      await gesture.moveBy(const Offset(0, -10));
      await tester.pump();
      final grabbed = _orb(tester);
      expect(grabbed.left, moreOrLessEquals(midFlight.left, epsilon: 1), reason: 'no jump sideways when caught');
      expect(s.orbHeld, isTrue);
      await gesture.up();
      await tester.pump(); // the spring's first frame starts its clock
      await tester.pump(const Duration(seconds: 2));
      _expectHome(tester, 'let go again');
    });

    testWidgets('with reduced motion there is no spring: it is home on the next frame, fading in', (tester) async {
      final s = _today(AppLang.en);
      await _pumpBar(tester, s, still: true);
      await tester.timedDragFrom(tester.getCenter(find.byType(LivingOrb)), const Offset(-80, -240), const Duration(milliseconds: 400));
      await tester.pump();
      _expectHome(tester, 'no spring');
      final fade = tester.widget<FadeTransition>(find.ancestor(of: find.byKey(QTabBar.orbKey), matching: find.byType(FadeTransition)).first);
      expect(fade.opacity.value, lessThan(1), reason: 'a cross-fade, not a slide');
      await tester.pump(const Duration(seconds: 2));
      expect(fade.opacity.value, 1);
    });

    testWidgets('dropped on a value it explains the value, and goes back into the bar', (tester) async {
      final s = _today(AppLang.en);
      s.meals.add(LoggedMeal(name: 'Koshary', sub: '', kcal: 640, p: 20, c: 100, f: 18, at: DateTime.now()));
      await _pumpApp(tester, s);
      final target = tester.getCenter(find.byWidgetPredicate((w) => w is Explainable && w.id == 'protein'));
      final moon = tester.getCenter(find.byType(LivingOrb).last);
      await tester.timedDragFrom(moon, target - moon, const Duration(milliseconds: 900));
      await tester.pump();
      expect(s.explainOpen, isNotNull, reason: 'drag-to-explain works as before');
      expect(s.orbHeld, isFalse);
      await tester.pump(const Duration(seconds: 2));
      _expectHome(tester, 'after explaining');
    });
  });

  group('the pages', () {
    for (final lang in AppLang.values) {
      testWidgets('on the paywall there is no bar: its own back control is the way home (${lang.name})', (tester) async {
        final s = _today(lang);
        s.openSubscription();
        expect(s.orbVisible, isFalse);
        await _pumpApp(tester, s);
        expect(find.byType(QTabBar), findsNothing);
        expect(find.byKey(QTabBar.orbKey), findsNothing);
        expect(find.byType(QBackButton), findsOneWidget, reason: 'the way home is its own');
      });
    }

    test('the bar is on the four tab pages and nowhere else', () {
      final s = AppState();
      final shown = [
        for (final x in AppScreen.values)
          if ((s..go(x)).orbVisible) x,
      ];
      expect(shown.toSet(), AppState.tabScreens.toSet());
      expect(AppState.tabScreens, [AppScreen.today, AppScreen.progress, AppScreen.plan, AppScreen.you]);
    });

    for (final lang in AppLang.values) {
      testWidgets('on every tab page, the page scrolled to its end rests above the band (${lang.name})', (tester) async {
        tester.view.devicePixelRatio = 3;
        tester.view.physicalSize = _area * 3;
        tester.view.padding = const FakeViewPadding(top: 47 * 3, bottom: 34 * 3);
        addTearDown(tester.view.reset);
        final s = AppState()..setLang(lang);
        s.profile = s.profile.copyWith(name: 'Basel');
        s.meals.add(LoggedMeal(name: 'Koshary', sub: '', kcal: 640, p: 20, c: 100, f: 18, at: DateTime.now()));
        await tester.pumpWidget(ChangeNotifierProvider.value(value: s, child: const QamarApp()));
        // The band's top inside the safe area, on screen.
        const bandTop = 844 - 34 - QLayout.tabBand;
        for (final screen in AppState.tabScreens) {
          s.go(screen);
          await tester.pump();
          await tester.pump(const Duration(milliseconds: 400));
          final list = find.byType(Scrollable).first;
          final position = tester.state<ScrollableState>(list).position;
          // A lazily built list only knows its full length once its last
          // children are laid out: jump to the end until the end holds.
          for (var i = 0; i < 10; i++) {
            position.jumpTo(position.maxScrollExtent);
            await tester.pump();
            if (position.pixels >= position.maxScrollExtent) break;
          }
          final barLayer = find.byType(QTabBar);
          final words = find.byType(RichText).evaluate().where((e) => find.descendant(of: barLayer, matching: find.byWidget(e.widget)).evaluate().isEmpty);
          var lowest = 0.0;
          for (final e in words) {
            final box = e.renderObject! as RenderBox;
            if (!box.hasSize || !box.attached) continue;
            final bottom = box.localToGlobal(Offset(0, box.size.height)).dy;
            if (bottom > lowest) lowest = bottom;
          }
          expect(lowest, lessThanOrEqualTo(bandTop), reason: 'the end of $screen comes to rest above the band');
        }
      });
    }
  });
}

bool _isDescendant(RenderObject t, RenderObject ancestor) {
  RenderObject? p = t.parent;
  while (p != null) {
    if (identical(p, ancestor)) return true;
    p = p.parent;
  }
  return false;
}
