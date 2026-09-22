// The orb is placed from the start edge (O1), so it mirrors with the
// language: the same resting place is near the right edge in English and near
// the left edge in Arabic, and a drag moves it under the finger either way.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

import 'package:qamar/l10n/strings.dart';
import 'package:qamar/state/app_state.dart';
import 'package:qamar/widgets/living_orb.dart';
import 'package:qamar/widgets/orb_nav.dart';

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
      home: const Scaffold(body: Stack(children: [OrbNav()])),
    ),
  ));
  await tester.pump();
}

Rect _moon(WidgetTester t) => t.getRect(find.byType(LivingOrb));
Rect _orb(WidgetTester t) => t.getRect(find.byKey(OrbNav.orbKey));

void main() {
  testWidgets('the resting orb mirrors between English and Arabic', (tester) async {
    final s = AppState()..setLang(AppLang.en);
    s.go(AppScreen.today);
    await _pump(tester, s);
    final en = _orb(tester);
    expect(en.center.dx, greaterThan(_area.width / 2), reason: 'in English it rests towards the right, the end edge');

    s.setLang(AppLang.ar);
    await tester.pump();
    final ar = _orb(tester);
    // The orb's own box is the mirror image: it keeps the same gap from the
    // start edge — from the left in English, from the right in Arabic.
    expect(ar.left, moreOrLessEquals(_area.width - en.left - ar.width, epsilon: 0.01),
        reason: 'in Arabic the same resting place is the mirror image');
    expect(ar.top, en.top, reason: 'mirroring never moves it up or down');
    expect(ar.center.dx, lessThan(_area.width / 2), reason: 'towards the left, the end edge in Arabic');
  });

  testWidgets('with no balance pill under it, the moon itself is the exact mirror', (tester) async {
    final s = AppState()..setLang(AppLang.en);
    s.go(AppScreen.today);
    await _pump(tester, s);
    final en = _moon(tester).center.dx;
    s.setLang(AppLang.ar);
    await tester.pump();
    expect(_moon(tester).center.dx, moreOrLessEquals(_area.width - en, epsilon: 0.01));
  });

  for (final lang in AppLang.values) {
    testWidgets('a drag moves the orb under the finger (${lang.name})', (tester) async {
      final s = AppState()..setLang(lang);
      s.go(AppScreen.today);
      s.setOrbPosition(150, 500, maxX: _area.width - 96, maxY: _area.height - 118);
      await _pump(tester, s);
      final before = _moon(tester);
      final startBefore = s.orbStart;

      await tester.drag(find.byType(LivingOrb), const Offset(-60, 0));
      await tester.pump();
      final after = _moon(tester);

      expect(after.left, lessThan(before.left), reason: 'dragged left, it went left');
      // Drag gestures give up the touch slop before they move anything.
      expect(before.left - after.left, closeTo(60, 20));
      if (lang == AppLang.ar) {
        expect(s.orbStart, greaterThan(startBefore), reason: 'in Arabic, left is away from the start edge');
      } else {
        expect(s.orbStart, lessThan(startBefore), reason: 'in English, left is towards the start edge');
      }
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
