// O11 in the shared controls themselves: what is drawn and what takes the
// touch are separate. A control is drawn at its own size — a compact row
// keeps its look — and takes at least 48 points each way; one with nothing
// to do says so, to the eye and to a screen reader.

import 'dart:ui' show SemanticsAction, Tristate;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

import 'package:qamar/l10n/strings.dart';
import 'package:qamar/main.dart';
import 'package:qamar/models/activity.dart';
import 'package:qamar/screens/you_screen.dart';
import 'package:qamar/state/app_state.dart';
import 'package:qamar/theme/app_theme.dart';
import 'package:qamar/theme/colors.dart';
import 'package:qamar/theme/icons.dart';
import 'package:qamar/theme/layout.dart';
import 'package:qamar/widgets/common.dart';
import 'package:qamar/widgets/surface.dart';

import 'support/app_fonts.dart';

Future<void> _pump(WidgetTester tester, Widget child) async {
  await tester.pumpWidget(MaterialApp(home: Scaffold(body: Center(child: child))));
}

/// Where a control is drawn: its surface (the control grey, or burgundy), or
/// the edged box of a control drawn by its edge.
Rect _drawn(WidgetTester tester, Finder control) {
  final boxes = find.descendant(
    of: control,
    matching: find.byWidgetPredicate((w) =>
        w is DecoratedBox && (w.key == QSurface.fillKey || (w.decoration is BoxDecoration && (w.decoration as BoxDecoration).border != null))),
  );
  return tester.getRect(boxes.first);
}

/// A control's surface: the fill it is drawn with.
ShapeDecoration _surface(WidgetTester tester, Finder control) =>
    tester.widget<DecoratedBox>(find.descendant(of: control, matching: find.byKey(QSurface.fillKey)).first).decoration as ShapeDecoration;

void main() {
  setUpAll(() async {
    await loadAppFonts();
    for (final name in const ['com.qamar.app/quick_events', 'com.qamar.app/quick_invoke']) {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(MethodChannel(name), (call) async => null);
    }
  });

  testWidgets('"Why this number?" is drawn 30 points tall and takes the touch across 48', (tester) async {
    var taps = 0;
    await _pump(tester, QOutlineButton(label: 'Why this number?', onTap: () => taps++, height: 30));
    final control = find.byType(QOutlineButton);
    final touch = tester.getRect(control);
    final drawn = _drawn(tester, control);
    expect(drawn.height, 30, reason: 'a compact row keeps its look');
    expect(touch.height, greaterThanOrEqualTo(QLayout.minTap));
    expect(touch.width, greaterThanOrEqualTo(QLayout.minTap));
    // A finger just above the outline, inside the touch, still presses it.
    await tester.tapAt(Offset(drawn.center.dx, drawn.top - 7));
    expect(taps, 1, reason: 'the band around the outline is part of the control');
  });

  testWidgets('a button asked to fill a column still fills it', (tester) async {
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: SizedBox(
          width: 300,
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            QPrimaryButton(label: 'Log a meal', onTap: () {}),
            QOutlineButton(label: 'Try again', onTap: () {}),
          ]),
        ),
      ),
    ));
    expect(_drawn(tester, find.byType(QOutlineButton)).width, 300);
    final primary = tester.getRect(find.descendant(of: find.byType(QPrimaryButton), matching: find.byType(DecoratedBox)).first);
    expect(primary.width, 300);
  });

  testWidgets('a round icon button is drawn at its size, touched at 48, and named', (tester) async {
    await _pump(tester, QRoundIconButton(icon: QIcons.add, onTap: () {}, size: 28, label: 'More'));
    final control = find.byType(QRoundIconButton);
    expect(_drawn(tester, control).size, const Size(28, 28));
    expect(tester.getSize(control), const Size(48, 48));
    expect(find.bySemanticsLabel('More'), findsOneWidget);
  });

  testWidgets('the language switch: each side is a whole touch, drawn inside the kit’s white track as tall as before', (tester) async {
    for (final large in [false, true]) {
      await _pump(tester, QLangToggle(lang: AppLang.ar, onChanged: (_) {}, large: large));
      final pill = tester.getRect(find.descendant(
        of: find.byType(QLangToggle),
        matching: find.byWidgetPredicate((w) => w is DecoratedBox && w.decoration == QDecor.segmentTrack),
      ));
      expect(pill.height, large ? 34 : 28);
      for (final side in [find.bySemanticsLabel('العربية'), find.bySemanticsLabel('English')]) {
        final r = tester.getRect(side);
        expect(r.height, greaterThanOrEqualTo(48));
        expect(r.width, greaterThanOrEqualTo(48));
      }
    }
  });

  group('a control with nothing to do says so', () {
    testWidgets('a secondary button: no touch, the control grey, a muted label, not enabled', (tester) async {
      final handle = tester.ensureSemantics();
      await _pump(tester, const QOutlineButton(label: 'Redeem', onTap: null));
      final control = find.byType(QOutlineButton);
      expect(_surface(tester, control).color, QDisabled.fill);
      expect(tester.widget<Text>(find.text('Redeem')).style!.color, QDisabled.label);
      final data = tester.getSemantics(find.descendant(of: control, matching: find.byType(Semantics)).first).getSemanticsData();
      expect(data.flagsCollection.isEnabled, Tristate.isFalse, reason: 'a screen reader hears it as not enabled');
      expect(data.hasAction(SemanticsAction.tap), isFalse);
      handle.dispose();
    });

    testWidgets('the primary: not burgundy, no gradient and no glow, a muted label', (tester) async {
      await _pump(tester, const QPrimaryButton(label: 'One moment…', onTap: null));
      final d = _surface(tester, find.byType(QPrimaryButton));
      expect(d.color, QDisabled.fill, reason: 'nothing to act on, so no burgundy');
      expect(d.gradient, isNull);
      expect(d.shadows, isNull);
      expect(tester.widget<Text>(find.text('One moment…')).style!.color, QDisabled.label);
      expect(QDisabled.label, QColors.inkDisabled);
    });

    testWidgets('enabled, the same controls draw their own surface and label', (tester) async {
      await _pump(tester, QOutlineButton(label: 'Redeem', onTap: () {}));
      final surface = tester.widget<QSurface>(find.descendant(of: find.byType(QOutlineButton), matching: find.byType(QSurface)));
      expect(surface.tint, isNull, reason: 'the control grey: a secondary action is not burgundy');
      expect(tester.widget<Text>(find.text('Redeem')).style!.color, isNot(QDisabled.label));
      await _pump(tester, QPrimaryButton(label: 'Log a meal', onTap: () {}));
      expect(tester.widget<QSurface>(find.descendant(of: find.byType(QPrimaryButton), matching: find.byType(QSurface))).tint, QColors.accent, reason: 'the one thing to do is burgundy');
      expect(tester.widget<Text>(find.text('Log a meal')).style!.color, QColors.onAccent);
    });
  });

  testWidgets('on the Log sheet a name is part of its circle: tapping "Walk" chooses the walk', (tester) async {
    tester.view.devicePixelRatio = 3;
    tester.view.physicalSize = const Size(390, 844) * 3;
    addTearDown(tester.view.reset);
    final s = AppState()..setLang(AppLang.en);
    s.dismissOrbTutorial();
    s.go(AppScreen.today);
    await tester.pumpWidget(ChangeNotifierProvider.value(value: s, child: const QamarApp()));
    s.orbTap();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 600));
    await tester.tap(find.text('Walk'));
    await tester.pump();
    expect(s.pendingActivity, ActivityKind.walk, reason: 'the word under the circle does what the circle does');
  });

  for (final lang in AppLang.values) {
    testWidgets('on Me, each count of Qamar’s questions is a whole touch, named for what it sets (${lang.name})', (tester) async {
      tester.view.devicePixelRatio = 3;
      tester.view.physicalSize = const Size(390, 844) * 3;
      addTearDown(tester.view.reset);
      final handle = tester.ensureSemantics();
      final s = AppState()..setLang(lang);
      s.dismissOrbTutorial();
      s.go(AppScreen.today);
      s.go(AppScreen.you);
      await tester.pumpWidget(ChangeNotifierProvider.value(value: s, child: const QamarApp()));
      await tester.pump();
      await tester.dragUntilVisible(find.byKey(YouScreen.nudgeKey(2)), find.byType(ListView).first, const Offset(0, -200));
      await tester.pump(const Duration(milliseconds: 400));
      for (final n in [0, 1, 2]) {
        final seg = find.byKey(YouScreen.nudgeKey(n));
        final touch = find.descendant(of: seg, matching: find.byType(QTapArea));
        expect(tester.getSize(touch).width, greaterThanOrEqualTo(QLayout.minTap), reason: '$n: 48 across');
        expect(tester.getSize(touch).height, greaterThanOrEqualTo(QLayout.minTap), reason: '$n: 48 tall');
        // Words, on Me's row "How many a day": off, once, twice.
        final label = tester.getSemantics(touch).label;
        const named = {AppLang.en: ['Off', 'Once', 'Twice'], AppLang.ar: ['مقفولة', 'مرة', 'مرتين']};
        expect(label, named[lang]![n], reason: 'named for what it sets, not a bare digit');
      }
      await tester.tap(find.byKey(YouScreen.nudgeKey(1)));
      await tester.pump();
      expect(s.nudgesPerDay, 1);
      final selected = tester.getSemantics(find.byKey(YouScreen.nudgeKey(1)));
      expect(selected.flagsCollection.isSelected, Tristate.isTrue, reason: 'the chosen count says so');
      handle.dispose();
    });
  }
}
