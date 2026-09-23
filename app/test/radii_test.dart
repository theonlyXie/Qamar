// Corners (the liquid-glass skill): four radii and the pill, each shape taking
// the corner of what it is: an inset (12), a control or field (18), a card or
// a message bubble (24), a sheet's top (32), and the pill for anything a
// finger presses. No corner is written as a number outside the theme, and a
// sweep of every screen, the tree and the conversation, in both languages,
// finds no other corner drawn.

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

import 'package:qamar/l10n/strings.dart';
import 'package:qamar/main.dart';
import 'package:qamar/models/meal.dart';
import 'package:qamar/state/app_state.dart';
import 'package:qamar/theme/app_theme.dart';
import 'package:qamar/widgets/explain.dart';

import 'support/app_fonts.dart';

final _scale = {QRadii.inset, QRadii.control, QRadii.card, QRadii.sheet, QRadii.pill};

/// Every corner radius a decoration on screen draws with.
Set<double> _corners(WidgetTester tester) {
  final out = <double>{};
  void add(BorderRadiusGeometry? g) {
    if (g is BorderRadius) {
      for (final r in [g.topLeft, g.topRight, g.bottomLeft, g.bottomRight]) {
        if (r.x > 0) out.add(r.x);
      }
    }
  }

  for (final d in tester.widgetList<DecoratedBox>(find.byType(DecoratedBox))) {
    final dec = d.decoration;
    if (dec is BoxDecoration && dec.shape == BoxShape.rectangle) add(dec.borderRadius);
  }
  for (final c in tester.widgetList<ClipRRect>(find.byType(ClipRRect))) {
    add(c.borderRadius);
  }
  for (final i in tester.widgetList<InputDecorator>(find.byType(InputDecorator))) {
    final b = i.decoration.enabledBorder ?? i.decoration.border;
    if (b is OutlineInputBorder) add(b.borderRadius);
  }
  return out;
}

void main() {
  setUpAll(() async {
    await loadAppFonts();
    for (final name in const ['com.qamar.app/quick_events', 'com.qamar.app/quick_invoke']) {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(MethodChannel(name), (call) async => null);
    }
  });

  test('four corners and the pill', () {
    expect([QRadii.inset, QRadii.control, QRadii.card, QRadii.sheet, QRadii.pill], [12, 18, 24, 32, 999]);
  });

  test('no corner is written as a number outside the theme', () {
    final raw = RegExp(r'(BorderRadius\.circular|Radius\.circular)\(\s*[0-9.]+\s*\)|QDecor\.card\([^)]*radius:\s*[0-9.]');
    final found = <String>[];
    for (final f in Directory('lib').listSync(recursive: true).whereType<File>().where((f) => f.path.endsWith('.dart'))) {
      if (f.path.replaceAll(r'\', '/').startsWith('lib/theme/')) continue;
      final lines = f.readAsLinesSync();
      for (var i = 0; i < lines.length; i++) {
        if (raw.hasMatch(lines[i])) found.add('${f.path}:${i + 1}: ${lines[i].trim()}');
      }
    }
    expect(found, isEmpty, reason: found.join('\n'));
  });

  for (final lang in AppLang.values) {
    testWidgets('every corner drawn is on the scale: every screen, the tree, the conversation, a sheet (${lang.name})', (tester) async {
      tester.view.devicePixelRatio = 3;
      tester.view.physicalSize = const Size(390, 2400) * 3;
      addTearDown(tester.view.reset);
      final s = AppState()..setLang(lang);
      s.meals.add(LoggedMeal(name: lang == AppLang.ar ? 'كشري' : 'Koshary', sub: '', kcal: 640, p: 20, c: 100, f: 18, at: DateTime.now()));
      await tester.pumpWidget(ChangeNotifierProvider.value(value: s, child: const QamarApp()));
      final seen = <double>{};
      Future<void> check(String where) async {
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 400));
        final corners = _corners(tester);
        expect(corners.difference(_scale), isEmpty, reason: 'off-scale corners on $where: ${corners.difference(_scale)}');
        seen.addAll(corners);
      }

      for (final screen in AppScreen.values) {
        s.go(screen);
        await check('$screen');
      }
      s.go(AppScreen.today);
      s.orbTap();
      await check('the tree');
      s.closeTree();
      s.openChat();
      await check('the conversation');
      s.closeChat();
      s.openWhy();
      await check('the Why sheet');
      s.closeWhy();
      // The explain sheet's tip is a notice, on the control corner: with the
      // fields moved into their sheets, the one place the sweep meets it.
      s.openExplain(kExplanations['kcal_remaining']!);
      await check('the explain sheet');
      expect(seen, containsAll([QRadii.control, QRadii.card, QRadii.sheet, QRadii.pill]), reason: 'the sweep saw the scale in use');
    });
  }
}
