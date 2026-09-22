// Help after the tutorial (seat 2): the moon's three gestures stay in Me for
// good, so once Today's tutorial card is put away they can still be looked
// up. The card is the same one Today shows, with the same ticks.

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

import 'package:qamar/l10n/strings.dart';
import 'package:qamar/main.dart';
import 'package:qamar/models/su_economy.dart';
import 'package:qamar/state/app_state.dart';
import 'package:qamar/widgets/orb_gesture_guide.dart';

import 'support/arabic_digits.dart';

Future<void> _pump(WidgetTester tester, AppState s) async {
  await tester.binding.setSurfaceSize(const Size(900, 3000)); // words, not layout
  addTearDown(() => tester.binding.setSurfaceSize(null));
  await tester.pumpWidget(ChangeNotifierProvider.value(value: s, child: const QamarApp()));
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 400));
}

void main() {
  setUpAll(() {
    for (final name in const ['com.qamar.app/quick_events', 'com.qamar.app/quick_invoke']) {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(MethodChannel(name), (call) async => null);
    }
  });

  testWidgets('once "Got it" puts Today’s tutorial away, the gestures are still in Me', (tester) async {
    final s = AppState()..setLang(AppLang.en);
    s.go(AppScreen.today);
    await _pump(tester, s);
    expect(find.byType(OrbGestureGuide), findsOneWidget, reason: 'the tutorial, on Today');

    final gotIt = find.text('Got it');
    final hit = tester.getSize(find.ancestor(of: gotIt, matching: find.byType(ConstrainedBox)).first);
    expect(hit.height, greaterThanOrEqualTo(48), reason: 'small words, a full touch');
    await tester.tap(gotIt);
    await tester.pump();
    expect(s.orbTutorialDone, isTrue);
    expect(find.byType(OrbGestureGuide), findsNothing, reason: 'put away on Today');

    s.go(AppScreen.you);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    expect(find.byType(OrbGestureGuide), findsOneWidget, reason: 'and there for good in Me');
    expect(find.text('Got it'), findsNothing, reason: 'nothing to put away in Me');
    for (final (_, _, _, doEn, _, _) in OrbGestureGuide.rows()) {
      expect(find.textContaining(doEn), findsOneWidget);
    }
  });

  testWidgets('Me ticks the gestures already done', (tester) async {
    final s = AppState()..setLang(AppLang.en);
    s.go(AppScreen.today);
    s.orbTap(); // the tree opens: the tap is learned
    s.closeTree();
    s.go(AppScreen.you);
    await _pump(tester, s);
    final guide = find.byType(OrbGestureGuide);
    expect(find.descendant(of: guide, matching: find.byIcon(Icons.check_circle)), findsOneWidget);
    expect(find.descendant(of: guide, matching: find.byIcon(Icons.mic_none)), findsOneWidget, reason: 'the hold, not yet');
  });

  testWidgets('its photo line says the person’s own daily photos, in Eastern digits in Arabic', (tester) async {
    final s = AppState()..setLang(AppLang.ar);
    s.photoQuota = const AiQuota(bucket: 'photo', used: 0, limit: 30, extra: 0, remaining: 30);
    s.go(AppScreen.you);
    await _pump(tester, s);
    final texts = drawnTexts(tester, within: find.byType(OrbGestureGuide));
    expect(texts.any((t) => t.contains('الصور ٣٠ في اليوم')), isTrue, reason: '$texts');
    expectNoLatinDigits(tester, within: find.byType(OrbGestureGuide));

    s.setLang(AppLang.en);
    await tester.pump();
    expect(find.textContaining('Photos, 30 a day'), findsOneWidget, reason: 'it used to say three, whatever the plan');
  });
}
