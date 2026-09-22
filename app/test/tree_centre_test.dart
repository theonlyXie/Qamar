// The tree's centre moon (seat 2): its tap opened the conversation, but
// nothing said so, and the hint under the ring — "hold Qamar to talk" —
// pointed at a gesture the moon in view did not answer. Now it is labelled
// like every circle on the ring, and it answers the hold exactly as the
// floating orb does, so the label and the hint agree with what it does.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

import 'package:qamar/l10n/strings.dart';
import 'package:qamar/state/app_state.dart';
import 'package:qamar/widgets/living_orb.dart';
import 'package:qamar/widgets/tree_overlay.dart';

Future<void> _pump(WidgetTester tester, AppState s) async {
  await tester.binding.setSurfaceSize(const Size(390, 844));
  addTearDown(() => tester.binding.setSurfaceSize(null));
  await tester.pumpWidget(ChangeNotifierProvider.value(
    value: s,
    child: MaterialApp(
      builder: (context, child) => Directionality(textDirection: s.isAr ? TextDirection.rtl : TextDirection.ltr, child: child!),
      home: const Scaffold(body: Stack(children: [TreeOverlay()])),
    ),
  ));
  await tester.pump();
}

AppState _tree(AppLang lang) {
  final s = AppState()..setLang(lang);
  s.go(AppScreen.today);
  s.toggleTree();
  return s;
}

void main() {
  for (final lang in AppLang.values) {
    testWidgets('the centre moon is labelled, under the moon, and the hint names the same Qamar (${lang.name})', (tester) async {
      final s = _tree(lang);
      await _pump(tester, s);
      final label = find.byKey(TreeOverlay.centreLabelKey);
      expect(tester.widget<Text>(label).data, s.t.ask);
      final moon = tester.getRect(find.byType(LivingOrb));
      final l = tester.getRect(label);
      expect(l.top, greaterThanOrEqualTo(moon.center.dy), reason: 'under the moon');
      expect(l.center.dx, moreOrLessEquals(moon.center.dx, epsilon: 1), reason: 'centred on it');
      expect(find.text(s.t.treeHint), findsOneWidget);
      expect(s.t.treeHint, contains(lang == AppLang.ar ? 'قمر' : 'Qamar'));
    });
  }

  testWidgets('a tap on the centre moon opens the conversation to type', (tester) async {
    final s = _tree(AppLang.en);
    await _pump(tester, s);
    await tester.tap(find.byType(LivingOrb));
    await tester.pump();
    expect(s.chatOpen, isTrue);
    expect(s.gesturesLearned, isNot(contains(OrbGesture.hold)));
  });

  testWidgets('holding the centre moon does what holding the orb does: talk, and the hold is learned', (tester) async {
    final s = _tree(AppLang.en);
    await _pump(tester, s);
    final at = tester.getCenter(find.byType(LivingOrb));
    final gesture = await tester.startGesture(at);
    await tester.pump(const Duration(milliseconds: 400));
    await gesture.up();
    await tester.pump();
    expect(s.gesturesLearned, contains(OrbGesture.hold), reason: 'the hint said hold, and holding now works');
    expect(s.chatOpen, isTrue);
    expect(s.treeOpen, isFalse, reason: 'the tree gives way to the conversation');
    expect(s.dictationError, isNotNull, reason: 'it tried to listen: this test phone has no recogniser');
  });
}
