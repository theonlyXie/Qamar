// Sheets that leave the way they came, and follow the finger, seat 6's part
// (my own deferred item): whatever closes a sheet — its scrim, its own
// button, the phone's back — it goes down and out on the settle spring
// instead of vanishing on the frame its state closed; it can be dragged
// down, and on release goes where the release was heading (Apple's
// projection of the velocity), away or back up, carrying the finger's speed
// into the spring; opened again on its way out, it turns round. The
// conversation arrives on the same spring, where it had a curve. With
// reduce-motion on, arriving and leaving are a fade.

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

import 'package:qamar/l10n/strings.dart';
import 'package:qamar/main.dart';
import 'package:qamar/state/app_state.dart';
import 'package:qamar/widgets/ask_qamar_overlay.dart';
import 'package:qamar/widgets/common.dart';
import 'package:qamar/widgets/why_sheet.dart';

import 'support/app_fonts.dart';

const _phone = Size(390, 844);

Future<AppState> _open(WidgetTester tester, AppLang lang, {bool still = false}) async {
  tester.view.devicePixelRatio = 3;
  tester.view.physicalSize = _phone * 3;
  addTearDown(tester.view.reset);
  final s = AppState()..setLang(lang);
  s.dismissOrbTutorial();
  s.go(AppScreen.today);
  await tester.pumpWidget(ChangeNotifierProvider.value(
    value: s,
    child: MediaQuery(data: MediaQueryData(size: _phone, disableAnimations: still), child: const QamarApp()),
  ));
  await tester.pump();
  s.openWhy();
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 800));
  return s;
}

Rect _title(WidgetTester tester, AppState s) => tester.getRect(find.text(s.t.whyTitle));
Rect _panel(WidgetTester tester) => tester.getRect(find.byKey(QSheetScrim.panelKey));

/// A point on the sheet away from its controls: the grabber.
Offset _grip(WidgetTester tester) {
  final p = _panel(tester);
  return Offset(p.center.dx, p.top + 12);
}

void main() {
  setUpAll(() async {
    await loadAppFonts();
    for (final name in const ['com.qamar.app/quick_events', 'com.qamar.app/quick_invoke']) {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(MethodChannel(name), (call) async => null);
    }
  });

  test('a release goes where it was heading', () {
    const h = 400.0;
    expect(QSheetScrim.releaseDismisses(1, 0, h), isFalse, reason: 'at rest, let go: stays');
    expect(QSheetScrim.releaseDismisses(0.4, 0, h), isTrue, reason: 'dragged past half-way: goes');
    expect(QSheetScrim.releaseDismisses(0.95, 900, h), isTrue, reason: 'a flick down: goes, however little it moved');
    expect(QSheetScrim.releaseDismisses(0.8, 300, h), isTrue, reason: 'slower, but its projected rest is past half-way');
    expect(QSheetScrim.releaseDismisses(0.8, 60, h), isFalse, reason: 'drifting: back up');
    expect(QSheetScrim.releaseDismisses(0.45, -900, h), isFalse, reason: 'thrown back up: stays');
  });

  for (final lang in AppLang.values) {
    testWidgets('closed by its own button or the back, it goes down the way it came (${lang.name})', (tester) async {
      final s = await _open(tester, lang);
      final rest = _title(tester, s);
      s.closeWhy(); // the sheet's Close, or the phone's back
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 30));
      expect(find.byType(WhySheet), findsOneWidget, reason: 'still there, leaving');
      final leaving = _title(tester, s);
      expect(leaving.top, greaterThan(rest.top), reason: 'going down');
      expect(leaving.left, moreOrLessEquals(rest.left, epsilon: 0.5), reason: 'straight down, the way it came');
      await tester.pump(const Duration(milliseconds: 30));
      expect(_title(tester, s).top, greaterThan(leaving.top), reason: 'still going');
      await tester.pump(const Duration(milliseconds: 800));
      expect(find.byType(WhySheet), findsNothing, reason: 'gone once it has left');
    });

    testWidgets('dragged down and let go past its mark, it leaves, carrying the finger’s speed (${lang.name})', (tester) async {
      final s = await _open(tester, lang);
      final h = _panel(tester).height;
      await tester.timedDragFrom(_grip(tester), Offset(0, h * 0.6), const Duration(milliseconds: 600));
      expect(s.whyOpen, isFalse, reason: 'past half-way: closed');
      await tester.pump(const Duration(milliseconds: 800));
      expect(find.byType(WhySheet), findsNothing);
    });

    testWidgets('a flick down closes it from where it is; a small drag springs back (${lang.name})', (tester) async {
      final s = await _open(tester, lang);
      final rest = _title(tester, s);
      await tester.timedDragFrom(_grip(tester), const Offset(0, 40), const Duration(milliseconds: 800));
      expect(s.whyOpen, isTrue, reason: 'a small, slow drag: back up');
      await tester.pump(const Duration(milliseconds: 800));
      expect(_title(tester, s).top, moreOrLessEquals(rest.top, epsilon: 0.5), reason: 'at rest again');

      await tester.flingFrom(_grip(tester), const Offset(0, 60), 1500);
      expect(s.whyOpen, isFalse, reason: 'a flick: closed');
      final released = _title(tester, s).top;
      await tester.pump(const Duration(milliseconds: 16));
      expect(_title(tester, s).top, greaterThan(released), reason: 'the throw carries on down');
    });

    testWidgets('opened again on its way out, it turns round (${lang.name})', (tester) async {
      final s = await _open(tester, lang);
      final rest = _title(tester, s);
      s.closeWhy();
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 40));
      final low = _title(tester, s).top;
      expect(low, greaterThan(rest.top));
      s.openWhy();
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 16));
      expect(_title(tester, s).top, lessThanOrEqualTo(low + 0.5), reason: 'coming back up from where it was');
      await tester.pump(const Duration(milliseconds: 800));
      expect(find.byType(WhySheet), findsOneWidget);
      expect(_title(tester, s).top, moreOrLessEquals(rest.top, epsilon: 0.5));
    });
  }

  testWidgets('with reduce-motion on, it leaves in place, fading', (tester) async {
    final s = await _open(tester, AppLang.en, still: true);
    final rest = _title(tester, s);
    s.closeWhy();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));
    expect(_title(tester, s), rest, reason: 'nothing moves');
    final fading = tester.widget<Opacity>(find.ancestor(of: find.byKey(QSheetScrim.panelKey), matching: find.byType(Opacity)).first);
    expect(fading.opacity, lessThan(1));
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.byType(WhySheet), findsNothing);
  });

  testWidgets('the conversation arrives on the settle spring: quick, and never past its place', (tester) async {
    tester.view.devicePixelRatio = 3;
    tester.view.physicalSize = _phone * 3;
    addTearDown(tester.view.reset);
    final s = AppState()..setLang(AppLang.en);
    s.dismissOrbTutorial();
    s.go(AppScreen.today);
    await tester.pumpWidget(ChangeNotifierProvider.value(value: s, child: const QamarApp()));
    await tester.pump();
    s.openChat();
    await tester.pump();
    final name = find.descendant(of: find.byType(AskQamarOverlay), matching: find.text(s.t.brand));
    final samples = <double>[];
    for (var i = 0; i < 40; i++) {
      await tester.pump(const Duration(milliseconds: 16));
      samples.add(tester.getRect(name).top);
    }
    final rest = samples.last;
    expect(samples.first, greaterThan(rest + 1), reason: 'it rose into place');
    expect(samples[6] - rest, lessThan((samples.first - rest) * 0.5), reason: 'past half-way by about 100ms');
    expect(samples[25] - rest, lessThan(0.05), reason: 'at rest by about 400ms');
    for (final y in samples) {
      expect(y, greaterThanOrEqualTo(rest - 0.01), reason: 'never above its place: no bounce');
    }
  });
}
