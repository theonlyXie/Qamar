// Entrances on springs, seat 6's part (the scorecard's "zero
// SpringDescription"; the orb's own springs are tab_bar_test's): the sheets,
// the Log sheet among them, rise from below their own height on the settle
// spring (damping 1.0), quick and without a bounce, where they used to be
// simply there; with reduce-motion on, nothing moves, it fades.

import 'package:flutter/material.dart';
import 'package:flutter/physics.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

import 'package:qamar/l10n/strings.dart';
import 'package:qamar/main.dart';
import 'package:qamar/state/app_state.dart';
import 'package:qamar/theme/motion.dart';
import 'package:qamar/widgets/common.dart';
import 'package:qamar/widgets/log_sheet.dart';
import 'package:qamar/widgets/why_sheet.dart';

import 'support/app_fonts.dart';

const _phone = Size(390, 844);

Future<void> _pump(WidgetTester tester, AppState s, {bool still = false}) async {
  tester.view.devicePixelRatio = 3;
  tester.view.physicalSize = _phone * 3;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(ChangeNotifierProvider.value(
    value: s,
    child: MediaQuery(data: MediaQueryData(size: _phone, disableAnimations: still), child: const QamarApp()),
  ));
  await tester.pump(const Duration(milliseconds: 400));
}

/// The sheet's panel, in the Why sheet's scrim.
Finder _panel() => find.descendant(of: find.byType(WhySheet), matching: find.byKey(QSheetScrim.panelKey));

/// Where the sheet's title is drawn (a translation moves what is inside it,
/// not the box that does the moving).
Rect _title(WidgetTester tester, AppState s) => tester.getRect(find.text(s.t.whyTitle));

void main() {
  setUpAll(() async {
    await loadAppFonts();
    for (final name in const ['com.qamar.app/quick_events', 'com.qamar.app/quick_invoke']) {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(MethodChannel(name), (call) async => null);
    }
  });

  test('the settle spring arrives quickly and never passes its mark', () {
    final sim = SpringSimulation(QSpring.settle, 0, 1, 0);
    var t = 0.0;
    while (t <= 1.5) {
      expect(sim.x(t), lessThanOrEqualTo(1.0 + 1e-9), reason: 'no bounce at $t s');
      t += 0.01;
    }
    expect(sim.x(0.1), greaterThan(0.5), reason: 'most of the way in the first 100ms');
    expect(sim.x(0.6), greaterThan(0.99));
  });

  test('each way in, and reduce-motion only fades', () {
    expect(QSpringIn.at(QArrive.rise, 0, still: false).dy, 1, reason: 'from below its own height');
    expect(QSpringIn.at(QArrive.rise, 1, still: false).dy, 0);
    expect(QSpringIn.at(QArrive.grow, 0, still: false).scale, lessThan(1));
    expect(QSpringIn.at(QArrive.grow, 1.2, still: false).scale, 1, reason: 'clamped');
    for (final a in QArrive.values) {
      final m = QSpringIn.at(a, 0.3, still: true);
      expect((m.dy, m.scale), (0.0, 1.0), reason: '${a.name}: nothing moves');
      expect(m.opacity, closeTo(0.3, 1e-9));
    }
  });

  for (final lang in AppLang.values) {
    testWidgets('a sheet rises from below its own height and comes to rest (${lang.name})', (tester) async {
      final s = AppState()..setLang(lang);
      s.dismissOrbTutorial();
      s.go(AppScreen.today);
      await _pump(tester, s);
      s.openWhy();
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 16));
      final early = _title(tester, s);
      await tester.pump(const Duration(milliseconds: 30));
      final soon = _title(tester, s);
      await tester.pump(const Duration(milliseconds: 700));
      final rest = _title(tester, s);
      expect(tester.getRect(_panel()).bottom, moreOrLessEquals(_phone.height, epsilon: 0.5), reason: 'at rest on the bottom edge');
      expect(early.top, greaterThan(rest.top + 40), reason: 'it came from below');
      expect(soon.top, lessThan(early.top), reason: 'rising');
      expect(soon.top, greaterThan(rest.top), reason: 'not yet there: it moves, it does not appear');
    });
  }

  testWidgets('the Log sheet rises the same way, from under the tab bar', (tester) async {
    final s = AppState()..setLang(AppLang.en);
    s.dismissOrbTutorial();
    s.go(AppScreen.today);
    await _pump(tester, s);
    s.orbTap();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 16));
    final panel = find.descendant(of: find.byType(LogSheet), matching: find.byKey(QSheetScrim.panelKey));
    final title = find.descendant(of: panel, matching: find.text('Log'));
    final early = tester.getRect(title);
    await tester.pump(const Duration(milliseconds: 30));
    final soon = tester.getRect(title);
    await tester.pump(const Duration(milliseconds: 700));
    final rest = tester.getRect(title);
    expect(tester.getRect(panel).bottom, moreOrLessEquals(_phone.height, epsilon: 0.5), reason: 'at rest on the bottom edge, under the bar');
    expect(early.top, greaterThan(rest.top + 40), reason: 'it came from below');
    expect(soon.top, lessThan(early.top), reason: 'rising');
    expect(soon.top, greaterThan(rest.top), reason: 'not yet there: it moves, it does not appear');
  });

  testWidgets('with reduce-motion on, the sheet is in place from the first frame and fades in', (tester) async {
    final s = AppState()..setLang(AppLang.en);
    s.dismissOrbTutorial();
    s.go(AppScreen.today);
    await _pump(tester, s, still: true);
    s.openWhy();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 16));
    final r = _title(tester, s);
    expect(tester.getRect(_panel()).bottom, moreOrLessEquals(_phone.height, epsilon: 0.5));
    final fading = tester.widget<Opacity>(find.ancestor(of: _panel(), matching: find.byType(Opacity)).first);
    expect(fading.opacity, lessThan(1), reason: 'it fades in');
    await tester.pump(const Duration(milliseconds: 200));
    expect(_title(tester, s), r, reason: 'nothing moved');
  });
}
