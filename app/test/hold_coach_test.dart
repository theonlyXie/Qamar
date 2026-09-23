// The hold, named where it is done (O1). Hold is the one gesture people have
// to learn, and it is the logging path. After the tree has opened and closed
// twice with no hold, a one-time mark above the orb names it in the tutorial
// card's words. It goes on the first hold or a tap, and never comes back.
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
import 'package:qamar/widgets/orb_nav.dart';

/// Opens and closes the tree [n] times from the orb.
void _useTree(AppState s, int n) {
  for (var i = 0; i < n; i++) {
    s.orbTap(); // open
    s.orbTap(); // close
  }
}

void main() {
  test('the tree closing twice with no hold brings the mark; once is not enough', () {
    final s = AppState()..go(AppScreen.today);
    expect(s.holdTutorialDue, isTrue, reason: 'the tutorial keeps its place until the first hold');
    _useTree(s, 1);
    expect(s.holdCoachDue, isFalse);
    _useTree(s, 1);
    expect(s.treeClosesWithoutHold, 2);
    expect(s.holdCoachDue, isTrue);
  });

  test('a close by going somewhere from the tree counts too, once', () {
    final s = AppState()..go(AppScreen.today);
    s.orbTap(); // open
    s.go(AppScreen.plan); // closed by using it
    expect(s.treeClosesWithoutHold, 1);
    s.go(AppScreen.today); // the tree was not open: nothing to count
    expect(s.treeClosesWithoutHold, 1);
  });

  test('the first hold makes it unnecessary for good, and ends the tutorial’s claim to the slot', () async {
    final prefs = MemoryDevicePrefs();
    final s = AppState(prefs: prefs)..go(AppScreen.today);
    _useTree(s, 2);
    expect(s.holdCoachDue, isTrue);
    await s.holdOrb();
    expect(s.holdCoachDue, isFalse);
    expect(s.holdTutorialDue, isFalse);
    expect(await prefs.getBool('hold_coach_seen'), isTrue);
  });

  test('only the hold ends the tutorial’s claim; dismissing the card ends it too', () {
    final s = AppState()..go(AppScreen.today);
    s.orbTap(); // tap learned (the tree opens)
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
    _useTree(s, 2);
    s.dismissHoldCoach();
    expect(s.holdCoachDue, isFalse);

    final again = AppState(prefs: prefs);
    await Future<void>.delayed(const Duration(milliseconds: 60));
    again.go(AppScreen.today);
    _useTree(again, 3);
    expect(again.holdCoachDue, isFalse, reason: 'remembered on the phone');
  });

  test('someone who has already held the moon never sees it', () async {
    final s = AppState()..go(AppScreen.today);
    await s.holdOrb();
    s.closeChat();
    _useTree(s, 3);
    expect(s.holdCoachDue, isFalse);
  });

  test('it names the hold in the tutorial card’s own words', () {
    expect(HoldCopy.line(false), 'Hold it\u00A0— talk to Qamar with your voice');
    expect(HoldCopy.line(true), 'استمر ضاغط عليه\u00A0— تتكلم\u00A0مع\u00A0قمر\u00A0بصوتك');
  });

  group('on screen', () {
    const area = Size(390, 844);

    // The orb layer alone, on a phone-sized screen.
    Future<void> pump(WidgetTester tester, AppState s) async {
      await tester.binding.setSurfaceSize(area);
      addTearDown(() => tester.binding.setSurfaceSize(null));
      await tester.pumpWidget(ChangeNotifierProvider.value(
        value: s,
        child: MaterialApp(
          // As the app does (main.dart): the direction follows the language,
          // so the orb's start edge is the right in Arabic.
          builder: (context, child) => Directionality(
            textDirection: s.isAr ? TextDirection.rtl : TextDirection.ltr,
            child: child!,
          ),
          home: const Scaffold(body: Stack(children: [OrbNav()])),
        ),
      ));
      await tester.pump();
    }

    Rect mark(WidgetTester t) => t.getRect(find.byType(HoldCoachMark));
    Rect moon(WidgetTester t) => t.getRect(find.byType(LivingOrb));
    Rect caret(WidgetTester t) => t.getRect(find.byKey(HoldCoachMark.caretKey));
    // The orb's whole box: the moon (its balance pill is gone, O9).
    Rect pill(WidgetTester t) => t.getRect(find.byKey(OrbNav.orbKey));

    Future<void> moveOrb(WidgetTester t, AppState s, double x, double y) async {
      s.setOrbPosition(x, y, maxX: area.width - 96, maxY: area.height - 118);
      await t.pump();
    }

    void expectOnMoon(WidgetTester t, {required bool above, required String where}) {
      final m = mark(t), o = moon(t), c = caret(t);
      expect(c.center.dx, moreOrLessEquals(o.center.dx, epsilon: 0.5), reason: '$where: the caret points at the moon');
      expect(c.left, greaterThanOrEqualTo(m.left), reason: where);
      expect(c.right, lessThanOrEqualTo(m.right), reason: '$where: the caret is under the bubble');
      expect(m.left, greaterThanOrEqualTo(8), reason: '$where: kept on screen');
      expect(m.right, lessThanOrEqualTo(area.width - 8), reason: '$where: kept on screen');
      if (above) {
        expect(c.bottom, lessThanOrEqualTo(o.top), reason: '$where: above the moon, never on it');
        expect(m.bottom, lessThanOrEqualTo(c.bottom), reason: where);
      } else {
        expect(c.top, greaterThanOrEqualTo(pill(t).bottom), reason: '$where: below the whole orb');
        expect(m.top, greaterThanOrEqualTo(c.top), reason: where);
      }
    }

    for (final lang in AppLang.values) {
      testWidgets('it points at the moon wherever the orb rests (${lang.name})', (tester) async {
        final s = AppState()..setLang(lang);
        s.go(AppScreen.today);
        _useTree(s, 2);
        await pump(tester, s);

        expect(find.byType(HoldCoachMark), findsOneWidget);
        expect(find.text(HoldCopy.line(lang == AppLang.ar)), findsOneWidget);
        expectOnMoon(tester, above: true, where: 'where the orb starts, near the edge');

        await moveOrb(tester, s, 147, 500);
        expectOnMoon(tester, above: true, where: 'mid-screen');
        expect(mark(tester).center.dx, moreOrLessEquals(moon(tester).center.dx, epsilon: 0.5), reason: 'centred over the moon when there is room');

        // The orb is placed from the start edge (O1): the left in English,
        // the right in Arabic. At that edge the mark is held 8 points in.
        await moveOrb(tester, s, 4, 500);
        expectOnMoon(tester, above: true, where: 'at the start edge');
        if (lang == AppLang.ar) {
          expect(mark(tester).right, area.width - 8);
        } else {
          expect(mark(tester).left, 8);
        }

        await moveOrb(tester, s, 147, 60);
        expectOnMoon(tester, above: false, where: 'with the orb at the top, it goes below');

        await tester.tap(find.byType(HoldCoachMark));
        await tester.pump();
        expect(find.byType(HoldCoachMark), findsNothing);
        expect(s.holdCoachSeen, isTrue);
      });
    }

    testWidgets('in Arabic it reads right to left: the microphone first, the close last', (tester) async {
      final s = AppState()..setLang(AppLang.ar);
      s.go(AppScreen.today);
      _useTree(s, 2);
      await pump(tester, s);
      final mic = tester.getCenter(find.descendant(of: find.byType(HoldCoachMark), matching: find.byIcon(QIcons.mic)));
      final close = tester.getCenter(find.descendant(of: find.byType(HoldCoachMark), matching: find.byIcon(QIcons.close)));
      expect(mic.dx, greaterThan(close.dx));
    });

    testWidgets('holding the moon is what makes it go, and the mark never takes the hold', (tester) async {
      final s = AppState()..setLang(AppLang.en);
      s.go(AppScreen.today);
      _useTree(s, 2);
      await pump(tester, s);
      expect(find.byType(HoldCoachMark), findsOneWidget);
      await tester.longPress(find.byType(LivingOrb));
      await tester.pump();
      expect(s.gesturesLearned, contains(OrbGesture.hold));
      expect(s.chatOpen, isTrue, reason: 'the hold did what it always does');
      expect(find.byType(HoldCoachMark), findsNothing);
      expect(s.holdCoachSeen, isTrue);
    });

    testWidgets('not while the tree or the conversation is open, and not off Today', (tester) async {
      final s = AppState()..setLang(AppLang.en);
      s.go(AppScreen.today);
      _useTree(s, 2);
      await pump(tester, s);
      expect(find.byType(HoldCoachMark), findsOneWidget);

      await tester.tap(find.byType(LivingOrb)); // the tree opens
      await tester.pump();
      expect(s.treeOpen, isTrue);
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
        _useTree(s, 2);
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
