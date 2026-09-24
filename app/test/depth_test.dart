// Depth on a near-black ground is lightness, never a cast shadow.
//
// A dark shadow offset under a surface has nothing to darken here, and
// under a Material it is clipped to the surface's square bounds, which drew
// dark slabs at the corners of every rounded button (the welcome pills,
// "Log a meal", "Try again", the scan shutter). What lifts a surface is a
// lighter fill and a lighter edge. Glows stay: they are the moon's light,
// centred on what gives it off, and cast nothing.

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

import 'package:qamar/l10n/strings.dart';
import 'package:qamar/main.dart';
import 'package:qamar/models/meal.dart';
import 'package:qamar/state/app_state.dart';

import 'support/app_fonts.dart';

/// Every shadow drawn by a box or an ink decoration that is offset from the
/// thing it belongs to, named by the widget that draws it.
List<String> castShadows(WidgetTester tester) {
  final out = <String>[];
  void check(String where, Decoration? d) {
    if (d is! BoxDecoration) return;
    for (final s in d.boxShadow ?? const <BoxShadow>[]) {
      if (s.offset != Offset.zero) out.add('$where: ${s.color} offset ${s.offset}');
    }
  }

  for (final e in find.byType(DecoratedBox).evaluate()) {
    check('DecoratedBox under ${e.debugGetCreatorChain(3)}', (e.widget as DecoratedBox).decoration);
  }
  for (final e in find.byType(Ink).evaluate()) {
    check('Ink under ${e.debugGetCreatorChain(3)}', (e.widget as Ink).decoration);
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

  for (final lang in AppLang.values) {
    testWidgets('no surface casts a shadow, on any screen, with the tree, the chat and the hold mark open (${lang.name})', (tester) async {
      await tester.binding.setSurfaceSize(const Size(390, 4000));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      final s = AppState()..setLang(lang);
      s.profile = s.profile.copyWith(name: 'Basel');
      s.meals.add(LoggedMeal(name: 'Koshary', sub: '', kcal: 640, p: 20, c: 100, f: 18, at: DateTime.now()));
      await tester.pumpWidget(ChangeNotifierProvider.value(value: s, child: const QamarApp()));

      final found = <String>[];
      Future<void> look(String where) async {
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 400));
        found.addAll(castShadows(tester).map((x) => '$where — $x'));
      }

      for (final screen in AppScreen.values) {
        s.go(screen);
        await look('$screen');
      }
      s.go(AppScreen.today);
      // The tree closed twice with no hold brings the hold's mark (O1).
      for (var i = 0; i < 2; i++) {
        s.orbTap();
        s.orbTap();
      }
      expect(s.holdCoachDue, isTrue);
      await look('the hold mark');
      s.orbTap();
      await look('the tree');
      s.closeLog();
      s.openChat();
      await look('the conversation');

      expect(found, isEmpty, reason: 'depth here is a lighter fill and edge, not a shadow:\n${found.join('\n')}');
    });
  }
}
