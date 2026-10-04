// Help after the tutorial (seat 2): the moon's three gestures stay in Me for
// good, one row away ("Gestures and shortcuts"), so once Today's tutorial
// card is put away they can still be looked up. The card is the same one
// Today shows, with the same ticks.

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

import 'package:qamar/l10n/strings.dart';
import 'package:qamar/main.dart';
import 'package:qamar/models/su_economy.dart';
import 'package:qamar/screens/you_screen.dart';
import 'package:qamar/services/device_prefs.dart';
import 'package:qamar/state/app_state.dart';
import 'package:qamar/widgets/hold_coach_mark.dart';
import 'package:qamar/theme/icons.dart';
import 'package:qamar/widgets/common.dart';
import 'package:qamar/widgets/orb_gesture_guide.dart';
import 'package:qamar/widgets/log_sheet.dart';

import 'support/app_fonts.dart';
import 'support/arabic_digits.dart';

Future<void> _pump(WidgetTester tester, AppState s) async {
  await tester.binding.setSurfaceSize(const Size(900, 3000)); // words, not layout
  addTearDown(() => tester.binding.setSurfaceSize(null));
  await tester.pumpWidget(ChangeNotifierProvider.value(value: s, child: const QamarApp()));
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 400));
}

/// Me's help: the row that opens it, and the sheet risen.
Future<void> _openHelp(WidgetTester tester) async {
  await tester.tap(find.byKey(YouScreen.helpRowKey));
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 700));
}

void main() {
  setUpAll(() async {
    await loadAppFonts(); // the height checks below measure real lines
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
    final hit = tester.getSize(find.ancestor(of: gotIt, matching: find.byType(QTapArea)).first);
    expect(hit.height, greaterThanOrEqualTo(48), reason: 'small words, a full touch');
    await tester.tap(gotIt);
    await tester.pump();
    expect(s.orbTutorialDone, isTrue);
    expect(find.byType(OrbGestureGuide), findsNothing, reason: 'put away on Today');

    s.go(AppScreen.you);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    await _openHelp(tester);
    expect(find.byType(OrbGestureGuide), findsOneWidget, reason: 'and there for good in Me');
    expect(find.text('Got it'), findsNothing, reason: 'nothing to put away in Me');
    for (final (_, _, _, doEn, _, _) in OrbGestureGuide.rows()) {
      expect(find.textContaining(doEn), findsOneWidget);
    }
  });

  // O15: the slot is 120 points, and on the phone the tutorial used to run
  // to 205 (English) and 169 (Arabic), its last row under the orb.
  for (final lang in AppLang.values) {
    testWidgets('on Today it keeps to the slot’s 120 points on a phone, three gestures in one row of cells (${lang.name})', (tester) async {
      tester.view.devicePixelRatio = 3;
      tester.view.physicalSize = const Size(390, 844) * 3;
      tester.view.padding = const FakeViewPadding(top: 47 * 3, bottom: 34 * 3);
      addTearDown(tester.view.reset);
      final s = AppState()..setLang(lang);
      s.go(AppScreen.today);
      await tester.pumpWidget(ChangeNotifierProvider.value(value: s, child: const QamarApp()));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
      expect(tester.takeException(), isNull, reason: 'nothing overflows');

      final card = tester.getRect(find.byType(OrbGestureGuide));
      expect(card.height, lessThanOrEqualTo(120), reason: 'the slot’s budget (${lang.name}: ${card.height})');
      final cells = find.byKey(OrbGestureGuide.cellKey);
      expect(cells, findsNWidgets(3));
      final rects = [for (var i = 0; i < 3; i++) tester.getRect(cells.at(i))];
      for (final r in rects) {
        expect(r.height, greaterThanOrEqualTo(48), reason: 'each gesture a full cell');
        expect(r.top, moreOrLessEquals(rects.first.top, epsilon: 0.5), reason: 'one row');
      }
      final isAr = lang == AppLang.ar;
      expect(OrbGestureGuide.cellText(OrbGesture.hold, isAr), HoldCopy.line(isAr), reason: 'the hold cell is the hold mark’s line');
      expect(find.descendant(of: find.byType(OrbGestureGuide), matching: find.textContaining(HoldCopy.line(isAr))), findsOneWidget);
    });
  }

  testWidgets('the cells tick the real gestures as they are done', (tester) async {
    final s = AppState()..setLang(AppLang.en);
    s.go(AppScreen.today);
    await _pump(tester, s);
    final guide = find.byType(OrbGestureGuide);
    expect(find.descendant(of: guide, matching: find.byIcon(QIcons.done)), findsNothing);
    s.orbTap(); // the Log sheet rises: the tap is learned
    s.closeLog();
    await tester.pump();
    expect(find.descendant(of: guide, matching: find.byIcon(QIcons.done)), findsOneWidget);
    expect(find.descendant(of: guide, matching: find.byIcon(QIcons.mic)), findsOneWidget, reason: 'the hold, not yet');
    expect(find.descendant(of: guide, matching: find.textContaining('Tap it\u00A0— opens Log')), findsOneWidget);
    expect(find.descendant(of: guide, matching: find.textContaining('Drag it onto a dotted number\u00A0— it explains itself')), findsOneWidget);
  });

  testWidgets('Me ticks the gestures already done', (tester) async {
    final s = AppState()..setLang(AppLang.en);
    s.go(AppScreen.today);
    s.orbTap(); // the Log sheet rises: the tap is learned
    s.closeLog();
    s.go(AppScreen.you);
    await _pump(tester, s);
    await _openHelp(tester);
    final guide = find.byType(OrbGestureGuide);
    expect(find.descendant(of: guide, matching: find.byIcon(QIcons.done)), findsOneWidget);
    expect(find.descendant(of: guide, matching: find.byIcon(QIcons.mic)), findsOneWidget, reason: 'the hold, not yet');
  });

  testWidgets('its photo line says the person’s own daily photos, in Eastern digits in Arabic', (tester) async {
    final s = AppState()..setLang(AppLang.ar);
    s.photoQuota = const AiQuota(bucket: 'photo', used: 0, limit: 30, extra: 0, remaining: 30);
    s.go(AppScreen.you);
    await _pump(tester, s);
    await _openHelp(tester);
    final texts = drawnTexts(tester, within: find.byType(OrbGestureGuide));
    expect(texts.any((t) => t.contains('الصور ٣٠ في اليوم')), isTrue, reason: '$texts');
    expectNoLatinDigits(tester, within: find.byType(OrbGestureGuide));

    s.setLang(AppLang.en);
    await tester.pump();
    expect(find.textContaining('Photos, 30 a day'), findsOneWidget, reason: 'it used to say three, whatever the plan');
  });

  test('a gesture made after the tutorial is put away is still recorded, and ticked in Me', () {
    final s = AppState()..setLang(AppLang.en);
    s.go(AppScreen.today);
    s.dismissOrbTutorial();
    s.orbTap();
    expect(s.gesturesLearned, contains(OrbGesture.tap), reason: 'it used to stop recording once the card was put away');
  });

  test('the gestures are remembered across launches', () async {
    final prefs = MemoryDevicePrefs();
    final s = AppState(prefs: prefs);
    await Future<void>.delayed(const Duration(milliseconds: 20));
    s.go(AppScreen.today);
    s.orbTap();
    s.closeLog();
    await s.holdOrb();

    final again = AppState(prefs: prefs);
    await Future<void>.delayed(const Duration(milliseconds: 60));
    expect(again.gesturesLearned, containsAll([OrbGesture.tap, OrbGesture.hold]));
    expect(again.gesturesLearned, isNot(contains(OrbGesture.explain)));
  });

  test('the tap row names the Log sheet’s own words: its three ways to say a meal, water and movement', () {
    final (_, _, _, _, whatAr, whatEn) = OrbGestureGuide.rows().first;
    for (final m in kLogMethods) {
      expect(whatAr, contains(m.labelAr), reason: 'the card and the sheet use the same words');
      expect(whatEn.toLowerCase(), contains(m.labelEn.toLowerCase()));
    }
    expect(whatAr, contains('الماء'));
    expect(whatEn, contains('water'));
    expect(whatAr, contains('حركة'));
    expect(whatEn, contains('movement'));
    expect(whatAr, isNot(contains('مياه')), reason: 'one word for water, the sheet’s');
    expect(whatEn, isNot(contains('tree')), reason: 'the tap opens the Log sheet on every tab; there is no tree');
  });
}
