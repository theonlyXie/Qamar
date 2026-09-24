// Out of the tab bar under a finger, the orb is placed from the start edge
// (O1), so it mirrors with the language: the same place is near the left in
// English and near the right in Arabic, and a drag moves it under the finger
// either way. At rest it is the middle of the bar, the same in both
// (tab_bar_test.dart).

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

import 'package:qamar/l10n/strings.dart';
import 'package:qamar/state/app_state.dart';
import 'package:qamar/widgets/living_orb.dart';
import 'package:qamar/widgets/tab_bar.dart';

const _area = Size(390, 844);

Future<void> _pump(WidgetTester tester, AppState s) async {
  await tester.binding.setSurfaceSize(_area);
  addTearDown(() => tester.binding.setSurfaceSize(null));
  await tester.pumpWidget(ChangeNotifierProvider.value(
    value: s,
    child: MaterialApp(
      // The app sets the direction from the language, and follows a switch;
      // so does this harness.
      builder: (context, child) => Directionality(
        textDirection: context.watch<AppState>().isAr ? TextDirection.rtl : TextDirection.ltr,
        child: child!,
      ),
      home: const Scaffold(body: Stack(children: [QTabBar()])),
    ),
  ));
  await tester.pump();
}

Rect _moon(WidgetTester t) => t.getRect(find.byType(LivingOrb));
Rect _orb(WidgetTester t) => t.getRect(find.byKey(QTabBar.orbKey));

void main() {
  testWidgets('a held orb mirrors between English and Arabic', (tester) async {
    final s = AppState()..setLang(AppLang.en);
    s.go(AppScreen.today);
    s.setOrbPosition(60, 500, maxX: _area.width - 96, maxY: _area.height - 118);
    await _pump(tester, s);
    final en = _orb(tester);
    expect(en.center.dx, lessThan(_area.width / 2), reason: 'in English the start edge is the left');

    s.setLang(AppLang.ar);
    await tester.pump();
    final ar = _orb(tester);
    // The orb's box is the mirror image: it keeps the same gap from the start
    // edge — from the left in English, from the right in Arabic.
    expect(ar.left, moreOrLessEquals(_area.width - en.left - ar.width, epsilon: 0.01),
        reason: 'in Arabic the same place is the mirror image');
    expect(ar.top, en.top, reason: 'mirroring never moves it up or down');
    expect(ar.center.dx, greaterThan(_area.width / 2), reason: 'towards the right, the start edge in Arabic');
  });

  for (final lang in AppLang.values) {
    testWidgets('a drag takes the orb out of the bar and moves it under the finger (${lang.name})', (tester) async {
      final s = AppState()..setLang(lang);
      s.go(AppScreen.today);
      await _pump(tester, s);
      final before = _moon(tester);

      final finger = await tester.startGesture(before.center);
      await finger.moveBy(const Offset(0, -20)); // past the touch slop: the drag has it
      await tester.pump();
      await finger.moveBy(const Offset(-60, -200));
      await tester.pump();
      expect(s.orbHeld, isTrue, reason: 'out of the bar while the finger has it');
      final after = _moon(tester);
      // Drag gestures give up the touch slop before they move anything.
      expect(before.center.dx - after.center.dx, closeTo(60, 20), reason: 'dragged left, it went left');
      expect(before.center.dy - after.center.dy, closeTo(220, 30), reason: 'and up, with the finger');

      await finger.up();
      // The spring home (the moon keeps breathing, so nothing "settles").
      for (var i = 0; i < 20; i++) {
        await tester.pump(const Duration(milliseconds: 100));
      }
      expect(s.orbHeld, isFalse);
      expect(_moon(tester).center.dx, moreOrLessEquals(before.center.dx, epsilon: 0.5), reason: 'let go, it is home in the bar');
      expect(_moon(tester).center.dy, moreOrLessEquals(before.center.dy, epsilon: 0.5));
    });
  }

  testWidgets('the start edge is the right in Arabic: at the smallest start it sits by the right edge', (tester) async {
    final s = AppState()..setLang(AppLang.ar);
    s.go(AppScreen.today);
    s.setOrbPosition(4, 500, maxX: _area.width - 96, maxY: _area.height - 118);
    await _pump(tester, s);
    expect(_moon(tester).center.dx, greaterThan(_area.width - 60));

    s.setLang(AppLang.en);
    await tester.pump();
    expect(_moon(tester).center.dx, lessThan(60), reason: 'and by the left edge in English');
  });
}
