// Onboarding's composition (O7), seat 6's part. Seat 1 set the order and
// seat 2 the gate (no input before its question, onboarding_gate_test.dart);
// here: the conversation is drawn from the bottom up, so each question sits
// right on its answer; the dock keeps its height between one question and
// the next, so the conversation does not drop and come back; the inputs'
// entrance starts on the frame their question paints; one radius across the
// answer stack, the composer a pill; wheel labels at 12pt.

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

import 'package:qamar/l10n/strings.dart';
import 'package:qamar/main.dart';
import 'package:qamar/models/onboarding.dart';
import 'package:qamar/screens/onboarding_screen.dart';
import 'package:qamar/state/app_state.dart';
import 'package:qamar/theme/app_theme.dart';
import 'package:qamar/widgets/common.dart';

import 'support/app_fonts.dart';

const _phone = Size(390, 844);

Future<void> _pump(WidgetTester tester, AppState s, {bool still = false}) async {
  tester.view.devicePixelRatio = 3;
  tester.view.physicalSize = _phone * 3;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(ChangeNotifierProvider.value(
    value: s,
    child: MediaQuery(
      data: MediaQueryData(size: _phone, disableAnimations: still),
      child: const QamarApp(),
    ),
  ));
  await tester.pump();
}

Rect _dock(WidgetTester t) => t.getRect(find.byKey(OnboardingScreen.dockKey));

/// The opacity the step's inputs are drawn at.
double _inputsOpacity(WidgetTester tester, Finder input) =>
    tester.widgetList<Opacity>(find.ancestor(of: input, matching: find.byType(Opacity))).fold(1.0, (a, o) => a * o.opacity);

/// Pumps until the step's question is on screen with its inputs.
Future<void> _untilAsked(WidgetTester tester, AppState s) async {
  for (var i = 0; i < 80 && !s.questionShown; i++) {
    await tester.pump(const Duration(milliseconds: 50));
  }
  expect(s.questionShown, isTrue);
}

void main() {
  setUpAll(() async {
    await loadAppFonts();
    for (final name in const ['com.qamar.app/quick_events', 'com.qamar.app/quick_invoke']) {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(MethodChannel(name), (call) async => null);
    }
  });

  for (final lang in AppLang.values) {
    testWidgets('step 0: the question sits right on its chips, the space above is sky (${lang.name})', (tester) async {
      final s = AppState()..setLang(lang);
      s.startOnboarding();
      await _pump(tester, s);
      await tester.pump(const Duration(milliseconds: 400));
      expect(s.currentStep!.kind, StepKind.chips, reason: 'step 0 is the consent chips');
      final list = tester.widget<ListView>(find.byKey(OnboardingScreen.transcriptKey));
      expect(list.reverse, isTrue, reason: 'drawn from the bottom up');
      final question = tester.getRect(find.text(s.msgs.last.text(lang == AppLang.ar)));
      final dock = _dock(tester);
      expect(dock.top - question.bottom, lessThan(48), reason: 'the question is on its answer, not 1000 points above it');
      expect(find.byType(QPillChip), findsWidgets);
    });
  }

  testWidgets('between one question and the next the dock keeps its height, then its entrance starts on the question’s frame', (tester) async {
    final s = AppState()..setLang(AppLang.en);
    s.startOnboarding();
    await _pump(tester, s);
    await tester.pump(const Duration(milliseconds: 400));
    final asked = _dock(tester).top;

    // Answer the consent: the chips go, Qamar types the safety question.
    s.pickOption(s.currentStep!.options.first);
    for (var i = 0; i < 60 && s.questionShown; i++) {
      await tester.pump(const Duration(milliseconds: 20));
    }
    expect(s.questionShown, isFalse, reason: 'the next question is being typed');
    var beatFrames = 0;
    while (!s.questionShown && beatFrames < 60) {
      await tester.pump(const Duration(milliseconds: 40));
      if (!s.questionShown) {
        expect(find.byType(QPillChip), findsNothing, reason: 'the gate holds (seat 2)');
        expect(_dock(tester).top, moreOrLessEquals(asked, epsilon: 0.5), reason: 'the dock holds its place through the beat');
        beatFrames++;
      }
    }
    expect(beatFrames, greaterThan(2), reason: 'there was a beat to hold through');

    // The frame the next question is on screen, its chips are there and
    // already on their way in.
    expect(find.byType(QPillChip), findsWidgets);
    final first = _inputsOpacity(tester, find.byType(QPillChip).first);
    expect(first, lessThan(1), reason: 'the entrance starts here');
    await tester.pump(const Duration(milliseconds: 120));
    expect(_inputsOpacity(tester, find.byType(QPillChip).first), greaterThan(0.6), reason: 'an ease-out: most of the way in early');
    await tester.pump(const Duration(milliseconds: 400));
    expect(_inputsOpacity(tester, find.byType(QPillChip).first), 1);
  });

  testWidgets('with reduced motion the inputs are simply there', (tester) async {
    final s = AppState()..setLang(AppLang.en);
    s.startOnboarding();
    await _pump(tester, s, still: true);
    expect(_inputsOpacity(tester, find.byType(QPillChip).first), 1);
  });

  testWidgets('one radius across the answer stack; the composer a pill; the wheels’ labels at 12pt', (tester) async {
    final s = AppState()..setLang(AppLang.en);
    s.startOnboarding();
    s.step = kOnboardingSteps.indexWhere((x) => x.id == 'dob');
    s.askStep(s.step);
    await _pump(tester, s);
    await _untilAsked(tester, s);
    await tester.pump(const Duration(milliseconds: 400));

    final wheels = find.byType(QWheelField);
    expect(wheels, findsNWidgets(3));
    for (final w in tester.widgetList<QWheelField>(wheels)) {
      final card = tester
          .widgetList<DecoratedBox>(find.descendant(of: find.byWidget(w), matching: find.byType(DecoratedBox)))
          .map((d) => d.decoration)
          .whereType<BoxDecoration>()
          .firstWhere((d) => d.border != null);
      expect(card.borderRadius, BorderRadius.circular(QRadii.control), reason: 'the wheel cards');
      final label = tester.widget<Text>(find.descendant(of: find.byWidget(w), matching: find.text(w.unit)));
      expect(label.style!.fontSize, 12);
    }
    final continueBox = tester
        .widgetList<DecoratedBox>(find.descendant(of: find.byType(QPrimaryButton), matching: find.byType(DecoratedBox)))
        .map((d) => d.decoration)
        .whereType<BoxDecoration>()
        .firstWhere((d) => d.gradient != null);
    expect(continueBox.borderRadius, BorderRadius.circular(QRadii.control), reason: 'Continue, the same radius');

    final field = tester.widget<TextField>(find.descendant(of: find.byKey(OnboardingScreen.dockKey), matching: find.byType(TextField)));
    final border = field.decoration!.enabledBorder! as OutlineInputBorder;
    expect(border.borderRadius, BorderRadius.circular(QRadii.pill), reason: 'the composer is a pill, beside its round send');
  });
}
