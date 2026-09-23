// The orb's band (O1): the orb rests at one of three stops in a band at the
// bottom of the screen — start, centre, end — and never on the page. A drag
// is free over the whole screen (explain reads the moon's centre mid-drag);
// letting go springs it to the stop nearest where the throw would carry it,
// from where the finger left it and at the finger's speed. The stop is kept
// on the phone. Screens that show the orb end their lists above the band.

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

import 'package:qamar/l10n/strings.dart';
import 'package:qamar/main.dart';
import 'package:qamar/models/meal.dart';
import 'package:qamar/services/device_prefs.dart';
import 'package:qamar/state/app_state.dart';
import 'package:qamar/theme/layout.dart';
import 'package:qamar/widgets/explain.dart';
import 'package:qamar/widgets/living_orb.dart';
import 'package:qamar/widgets/orb_nav.dart';

import 'support/app_fonts.dart';

const _area = Size(390, 844);
const _bandTop = 844 - QLayout.orbBand;

Future<void> _pumpOrb(WidgetTester tester, AppState s, {bool still = false}) async {
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
      home: const Scaffold(body: Stack(children: [OrbNav()])),
    ),
  ));
  await tester.pump();
}

Rect _orb(WidgetTester t) => t.getRect(find.byKey(OrbNav.orbKey));

/// Where each stop puts the orb's left edge on this screen.
double _left(OrbStop stop, {bool rtl = false}) {
  final start = OrbNav.stopStart(stop, _area.width);
  return rtl ? _area.width - OrbNav.moon - start : start;
}

void _expectInBand(Rect r, String why) {
  expect(r.top, greaterThanOrEqualTo(_bandTop), reason: '$why: inside the band, not on the page');
  expect(r.bottom, lessThanOrEqualTo(_area.height), reason: why);
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
      testWidgets('it rests in the band at the end stop by default, mirrored in Arabic (${lang.name})', (tester) async {
        final s = AppState()..setLang(lang);
        s.go(AppScreen.today);
        await _pumpOrb(tester, s);
        final r = _orb(tester);
        _expectInBand(r, 'the default');
        expect(r.left, moreOrLessEquals(_left(OrbStop.end, rtl: lang == AppLang.ar), epsilon: 0.01));
        expect(s.orbStop, OrbStop.end);
        expect(s.orbHeld, isFalse);
      });
    }

    testWidgets('its sparks and drift stay inside the band, all the way round', (tester) async {
      final s = AppState()..go(AppScreen.today);
      await _pumpOrb(tester, s);
      // The drift and the sparks share an 11-second cycle; sample it.
      for (var i = 0; i < 44; i++) {
        await tester.pump(const Duration(milliseconds: 250));
        for (var k = 0; k < 3; k++) {
          final dot = find.descendant(of: find.byKey(LivingOrb.sparkKey(k)), matching: find.byType(Container));
          _expectInBand(tester.getRect(dot.first), 'spark $k at ${i * 250}ms');
        }
      }
    });

    testWidgets('the band takes no touches: only the orb does', (tester) async {
      final s = AppState()..setLang(AppLang.en);
      s.dismissOrbTutorial();
      s.go(AppScreen.today);
      await tester.binding.setSurfaceSize(_area);
      addTearDown(() => tester.binding.setSurfaceSize(null));
      await tester.pumpWidget(ChangeNotifierProvider.value(value: s, child: const QamarApp()));
      await tester.pump();
      final orb = _orb(tester);
      final fade = tester.renderObject(find.byType(OrbBandFade));
      final orbBox = tester.renderObject(find.byKey(OrbNav.orbKey));
      final point = Offset(40, orb.center.dy); // in the band, away from the orb
      final result = HitTestResult();
      tester.binding.hitTestInView(result, point, tester.view.viewId);
      final targets = result.path.map((e) => e.target).toList();
      expect(targets, isNot(contains(fade)), reason: 'the fade draws and takes nothing');
      bool inOrb(Object t) => t is RenderObject && (identical(t, orbBox) || _isDescendant(t, orbBox));
      expect(targets.any(inOrb), isFalse, reason: 'a touch beside the orb is not the orb’s');
    });
  });

  group('letting go', () {
    testWidgets('a flick towards the start throws it to the start stop, from where the finger left it', (tester) async {
      final s = AppState()..setLang(AppLang.en);
      s.go(AppScreen.today);
      await _pumpOrb(tester, s);
      await tester.fling(find.byType(LivingOrb), const Offset(-60, -20), 1400);
      await tester.pump();
      final released = _orb(tester);
      expect(released.left, lessThan(_left(OrbStop.end)), reason: 'the spring starts where the finger left it, not at the stop');
      expect(s.orbStop, OrbStop.start, reason: 'a 60-point flick at speed carries past the centre: the projection, not the release point');
      expect(s.orbHeld, isFalse);
      await tester.pump(const Duration(seconds: 2));
      final rest = _orb(tester);
      expect(rest.left, moreOrLessEquals(_left(OrbStop.start), epsilon: 0.5));
      _expectInBand(rest, 'after the flick');
    });

    testWidgets('a slow drag let go near the middle rests at the centre stop', (tester) async {
      final s = AppState()..setLang(AppLang.en);
      s.go(AppScreen.today);
      await _pumpOrb(tester, s);
      final from = tester.getCenter(find.byType(LivingOrb));
      await tester.timedDragFrom(from, Offset(_area.width / 2 - from.dx, -300), const Duration(seconds: 2));
      await tester.pump(const Duration(seconds: 2));
      expect(s.orbStop, OrbStop.centre);
      expect(_orb(tester).center.dx, moreOrLessEquals(_area.width / 2, epsilon: 0.5));
      _expectInBand(_orb(tester), 'dropped mid-screen, it goes home to the band');
    });

    testWidgets('the spring can be grabbed mid-flight, from where it is on screen', (tester) async {
      final s = AppState()..setLang(AppLang.en);
      s.go(AppScreen.today);
      await _pumpOrb(tester, s);
      await tester.fling(find.byType(LivingOrb), const Offset(-80, 0), 1600);
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
      _expectInBand(_orb(tester), 'let go again');
    });

    testWidgets('with reduced motion there is no spring: it is at its stop on the next frame, fading in', (tester) async {
      final s = AppState()..setLang(AppLang.en);
      s.go(AppScreen.today);
      await _pumpOrb(tester, s, still: true);
      await tester.fling(find.byType(LivingOrb), const Offset(-80, -40), 1600);
      await tester.pump();
      expect(_orb(tester).left, moreOrLessEquals(_left(s.orbStop), epsilon: 0.01));
      final fade = tester.widget<FadeTransition>(find.ancestor(of: find.byKey(OrbNav.orbKey), matching: find.byType(FadeTransition)).first);
      expect(fade.opacity.value, lessThan(1), reason: 'a cross-fade, not a slide');
      await tester.pump(const Duration(seconds: 2));
      expect(fade.opacity.value, 1);
    });

    testWidgets('dropping it on a value explains the value, and it goes back to the stop it came from', (tester) async {
      final s = AppState()..setLang(AppLang.en);
      s.profile = s.profile.copyWith(name: 'Basel');
      s.dismissOrbTutorial();
      s.meals.add(LoggedMeal(name: 'Koshary', sub: '', kcal: 640, p: 20, c: 100, f: 18, at: DateTime.now()));
      s.go(AppScreen.today);
      await tester.binding.setSurfaceSize(_area);
      addTearDown(() => tester.binding.setSurfaceSize(null));
      await tester.pumpWidget(ChangeNotifierProvider.value(value: s, child: const QamarApp()));
      await tester.pump();
      final target = tester.getCenter(find.byWidgetPredicate((w) => w is Explainable && w.id == 'protein'));
      final moon = tester.getCenter(find.byType(LivingOrb).last);
      await tester.timedDragFrom(moon, target - moon, const Duration(milliseconds: 900));
      await tester.pump();
      expect(s.explainOpen, isNotNull, reason: 'drag-to-explain works as before');
      expect(s.orbStop, OrbStop.end, reason: 'the drag was to explain, not to move it');
      expect(s.orbHeld, isFalse);
      await tester.pump(const Duration(seconds: 2));
      final r = tester.getRect(find.byKey(OrbNav.orbKey));
      expect(r.top, greaterThanOrEqualTo(_bandTop));
    });
  });

  test('the stop is kept on the phone for the next launch', () async {
    final prefs = MemoryDevicePrefs();
    final first = AppState(prefs: prefs);
    await Future<void>.delayed(const Duration(milliseconds: 20));
    first.settleOrb(OrbStop.start);
    final again = AppState(prefs: prefs);
    await Future<void>.delayed(const Duration(milliseconds: 60));
    expect(again.orbStop, OrbStop.start);
    expect(AppState().orbStop, OrbStop.end, reason: 'the end stop by default');
  });

  test('the nearest stop is chosen from where the throw would come to rest', () {
    const w = 390.0;
    final end = OrbNav.stopStart(OrbStop.end, w);
    expect(OrbNav.nearestStop(end, 0, w), OrbStop.end, reason: 'let go where it is');
    expect(OrbNav.nearestStop(end - 40, 0, w), OrbStop.end, reason: 'a small move stays');
    expect(OrbNav.nearestStop(end - 40, -800, w), OrbStop.start, reason: 'the same place, thrown: it carries');
    expect(OrbNav.nearestStop(OrbNav.stopStart(OrbStop.start, w), 400, w), OrbStop.centre);
  });

  group('the pages', () {
    testWidgets('on the paywall the orb rests in the band, off the comparison table', (tester) async {
      // It stays, the way home from every in-app screen (way_back_test);
      // in the band it can no longer rest on the table, as it used to.
      final s = AppState()..setLang(AppLang.en);
      s.go(AppScreen.today);
      s.openSubscription();
      await tester.binding.setSurfaceSize(_area);
      addTearDown(() => tester.binding.setSurfaceSize(null));
      await tester.pumpWidget(ChangeNotifierProvider.value(value: s, child: const QamarApp()));
      await tester.pump();
      _expectInBand(_orb(tester), 'on the paywall');
    });

    for (final lang in AppLang.values) {
      testWidgets('on every screen with the orb, the page scrolled to its end rests above the band (${lang.name})', (tester) async {
        tester.view.devicePixelRatio = 3;
        tester.view.physicalSize = _area * 3;
        tester.view.padding = const FakeViewPadding(top: 47 * 3, bottom: 34 * 3);
        addTearDown(tester.view.reset);
        final s = AppState()..setLang(lang);
        s.profile = s.profile.copyWith(name: 'Basel');
        s.meals.add(LoggedMeal(name: 'Koshary', sub: '', kcal: 640, p: 20, c: 100, f: 18, at: DateTime.now()));
        await tester.pumpWidget(ChangeNotifierProvider.value(value: s, child: const QamarApp()));
        // The band's top inside the safe area, on screen.
        const bandTop = 844 - 34 - QLayout.orbBand;
        for (final screen in AppScreen.values.where((x) {
          s.go(x);
          return s.orbVisible;
        })) {
          s.go(screen);
          await tester.pump();
          await tester.pump(const Duration(milliseconds: 400));
          final list = find.byType(Scrollable).first;
          final position = tester.state<ScrollableState>(list).position;
          position.jumpTo(position.maxScrollExtent);
          await tester.pump();
          final orbLayer = find.byType(OrbNav);
          final words = find.byType(RichText).evaluate().where((e) => find.descendant(of: orbLayer, matching: find.byWidget(e.widget)).evaluate().isEmpty);
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
