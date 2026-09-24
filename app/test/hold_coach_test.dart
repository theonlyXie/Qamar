// The hold, named where it is done (O1). Hold is the one gesture people have
// to learn, and it is the logging path. After the Log sheet has opened and
// closed twice with no hold, a one-time mark above the orb, in the middle of
// the tab bar, names it in the tutorial card's words. It goes on the first
// hold or a tap, and never comes back.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

import 'package:qamar/l10n/strings.dart';
import 'package:qamar/main.dart';
import 'package:qamar/services/device_prefs.dart';
import 'package:qamar/state/app_state.dart';
import 'package:qamar/widgets/explain.dart';
import 'package:qamar/theme/icons.dart';
import 'package:qamar/widgets/hold_coach_mark.dart';
import 'package:qamar/widgets/living_orb.dart';
import 'package:qamar/widgets/orb_gesture_guide.dart';
import 'package:qamar/widgets/tab_bar.dart';

/// Opens and closes the Log sheet [n] times from the orb.
void _useLog(AppState s, int n) {
  for (var i = 0; i < n; i++) {
    s.orbTap(); // open
    s.orbTap(); // close
  }
}

void main() {
  test('the Log sheet closing twice with no hold brings the mark; once is not enough', () {
    final s = AppState()..go(AppScreen.today);
    expect(s.holdTutorialDue, isTrue, reason: 'the tutorial keeps its place until the first hold');
    _useLog(s, 1);
    expect(s.holdCoachDue, isFalse);
    _useLog(s, 1);
    expect(s.logClosesWithoutHold, 2);
    expect(s.holdCoachDue, isTrue);
  });

  test('a close by going somewhere from the Log sheet counts too, once', () {
    final s = AppState()..go(AppScreen.today);
    s.orbTap(); // open
    s.go(AppScreen.plan); // closed by using it
    expect(s.logClosesWithoutHold, 1);
    s.go(AppScreen.today); // the sheet was not open: nothing to count
    expect(s.logClosesWithoutHold, 1);
  });

  test('the first hold makes it unnecessary for good, and ends the tutorial’s claim to the slot', () async {
    final prefs = MemoryDevicePrefs();
    final s = AppState(prefs: prefs)..go(AppScreen.today);
    _useLog(s, 2);
    expect(s.holdCoachDue, isTrue);
    await s.holdOrb();
    expect(s.holdCoachDue, isFalse);
    expect(s.holdTutorialDue, isFalse);
    expect(await prefs.getBool('hold_coach_seen'), isTrue);
  });

  test('only the hold ends the tutorial’s claim; dismissing the card ends it too', () {
    final s = AppState()..go(AppScreen.today);
    s.orbTap(); // tap learned (the Log sheet rises)
    s.openExplain(kExplanations.values.first);
    s.closeExplain(); // drag-to-explain learned
    expect(s.gesturesLearned, containsAll([OrbGesture.tap, OrbGesture.explain]));
    expect(s.holdTutorialDue, isTrue, reason: 'two of three is not the hold');
    s.dismissOrbTutorial();
    expect(s.holdTutorialDue, isFalse);
  });

  test('a tap dismisses it, and it is one-time: never again on this phone', () async {
    final prefs = MemoryDevicePrefs();
    final s = AppState(prefs: prefs)..go(AppScreen.today);
    _useLog(s, 2);
    s.dismissHoldCoach();
    expect(s.holdCoachDue, isFalse);

    final again = AppState(prefs: prefs);
    await Future<void>.delayed(const Duration(milliseconds: 60));
    again.go(AppScreen.today);
    _useLog(again, 3);
    expect(again.holdCoachDue, isFalse, reason: 'remembered on the phone');
  });

  test('someone who has already held the moon never sees it', () async {
    final s = AppState()..go(AppScreen.today);
    await s.holdOrb();
    s.closeChat();
    _useLog(s, 3);
    expect(s.holdCoachDue, isFalse);
  });

  test('it names the hold in the tutorial card’s own words', () {
    expect(HoldCopy.line(false), 'Hold it\u00A0— talk to Qamar with your voice');
    expect(HoldCopy.line(true), 'استمر ضاغط عليه\u00A0— تتكلم\u00A0مع\u00A0قمر\u00A0بصوتك');
  });

  group('on screen', () {
    const area = Size(390, 844);

    // The tab bar alone, on a phone-sized screen.
    Future<void> pump(WidgetTester tester, AppState s) async {
      await tester.binding.setSurfaceSize(area);
      addTearDown(() => tester.binding.setSurfaceSize(null));
      await tester.pumpWidget(ChangeNotifierProvider.value(
        value: s,
        child: MaterialApp(
          // As the app does (main.dart): the direction follows the language.
          builder: (context, child) => Directionality(
            textDirection: s.isAr ? TextDirection.rtl : TextDirection.ltr,
            child: child!,
          ),
          home: const Scaffold(body: Stack(children: [QTabBar()])),
        ),
      ));
      await tester.pump();
    }

    Rect mark(WidgetTester t) => t.getRect(find.byType(HoldCoachMark));
    Rect moon(WidgetTester t) => t.getRect(find.byType(LivingOrb));
    Rect caret(WidgetTester t) => t.getRect(find.byKey(HoldCoachMark.caretKey));
    // The orb's circle, in the middle of the bar.
    Rect orb(WidgetTester t) => t.getRect(find.byKey(QTabBar.orbKey));

    for (final lang in AppLang.values) {
      testWidgets('it stands over the middle of the bar, its caret on the moon (${lang.name})', (tester) async {
        final s = AppState()..setLang(lang);
        s.go(AppScreen.today);
        _useLog(s, 2);
        await pump(tester, s);

        expect(find.byType(HoldCoachMark), findsOneWidget);
        expect(find.text(HoldCopy.line(lang == AppLang.ar)), findsOneWidget);
        final m = mark(tester), o = moon(tester), c = caret(tester);
        expect(c.center.dx, moreOrLessEquals(o.center.dx, epsilon: 0.5), reason: 'the caret points at the moon');
        expect(o.center.dx, moreOrLessEquals(area.width / 2, epsilon: 0.5), reason: 'the moon rests in the middle of the bar');
        expect(c.left, greaterThanOrEqualTo(m.left));
        expect(c.right, lessThanOrEqualTo(m.right), reason: 'the caret is under the bubble');
        expect(c.bottom, lessThanOrEqualTo(orb(tester).top), reason: 'above the orb, never on it');
        expect(m.bottom, lessThanOrEqualTo(c.bottom));
        expect(m.center.dx, moreOrLessEquals(o.center.dx, epsilon: 0.5), reason: 'centred over the moon');
        expect(m.left, greaterThanOrEqualTo(8), reason: 'kept on screen');
        expect(m.right, lessThanOrEqualTo(area.width - 8), reason: 'kept on screen');

        await tester.tap(find.byType(HoldCoachMark));
        await tester.pump();
        expect(find.byType(HoldCoachMark), findsNothing);
        expect(s.holdCoachSeen, isTrue);
      });
    }

    testWidgets('in Arabic it reads right to left: the microphone first, the close last', (tester) async {
      final s = AppState()..setLang(AppLang.ar);
      s.go(AppScreen.today);
      _useLog(s, 2);
      await pump(tester, s);
      final mic = tester.getCenter(find.descendant(of: find.byType(HoldCoachMark), matching: find.byIcon(QIcons.mic)));
      final close = tester.getCenter(find.descendant(of: find.byType(HoldCoachMark), matching: find.byIcon(QIcons.close)));
      expect(mic.dx, greaterThan(close.dx));
    });

    testWidgets('holding the moon is what makes it go, and the mark never takes the hold', (tester) async {
      final s = AppState()..setLang(AppLang.en);
      s.go(AppScreen.today);
      _useLog(s, 2);
      await pump(tester, s);
      expect(find.byType(HoldCoachMark), findsOneWidget);
      await tester.longPress(find.byType(LivingOrb));
      await tester.pump();
      expect(s.gesturesLearned, contains(OrbGesture.hold));
      expect(s.chatOpen, isTrue, reason: 'the hold did what it always does');
      expect(find.byType(HoldCoachMark), findsNothing);
      expect(s.holdCoachSeen, isTrue);
    });

    testWidgets('not while the Log sheet or the conversation is open, and not off Today', (tester) async {
      final s = AppState()..setLang(AppLang.en);
      s.go(AppScreen.today);
      _useLog(s, 2);
      await pump(tester, s);
      expect(find.byType(HoldCoachMark), findsOneWidget);

      await tester.tap(find.byType(LivingOrb)); // the Log sheet rises
      await tester.pump();
      expect(s.logOpen, isTrue);
      expect(find.byType(HoldCoachMark), findsNothing);
      await tester.tap(find.byType(LivingOrb)); // and closes
      await tester.pump();
      expect(find.byType(HoldCoachMark), findsOneWidget, reason: 'not dismissed: it waits');

      s.openChat();
      await tester.pump();
      expect(find.byType(HoldCoachMark), findsNothing);
      s.closeChat();
      s.go(AppScreen.progress);
      await tester.pump();
      expect(find.byType(HoldCoachMark), findsNothing);
    });

    for (final lang in AppLang.values) {
      testWidgets('on Today the tutorial card and the mark say the same words (${lang.name})', (tester) async {
        final s = AppState()..setLang(lang);
        await tester.binding.setSurfaceSize(const Size(900, 2400)); // wide: this checks the words, not the layout
        addTearDown(() => tester.binding.setSurfaceSize(null));
        await tester.pumpWidget(ChangeNotifierProvider.value(value: s, child: const QamarApp()));
        s.go(AppScreen.today);
        _useLog(s, 2);
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 400));
        final line = HoldCopy.line(lang == AppLang.ar);
        expect(find.descendant(of: find.byType(HoldCoachMark), matching: find.text(line)), findsOneWidget);
        // The card's hold cell carries its tick before the words.
        final cell = find.descendant(of: find.byType(OrbGestureGuide), matching: find.textContaining(line));
        expect(cell, findsOneWidget, reason: 'the card’s hold cell is the mark’s line');
        expect(tester.widget<Text>(cell).textSpan!.toPlainText(includePlaceholders: false), line, reason: 'word for word, the tick aside');
      });
    }
  });
}
