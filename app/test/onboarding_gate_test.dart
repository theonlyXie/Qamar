// O7: an input never appears before its question. Walked through the whole
// consultation, on every step: while Qamar is typing the next question no
// wheel, chip, number input, Continue or Skip is drawn, and the free-text
// box sends nothing — what is typed waits for the question. The walk is the
// consultation's eight questions: the name is no longer one of them (it is
// asked beside "Let's start", once the target is on screen).

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

import 'package:qamar/l10n/strings.dart';
import 'package:qamar/main.dart';
import 'package:qamar/models/onboarding.dart';
import 'package:qamar/screens/onboarding_screen.dart';
import 'package:qamar/state/app_state.dart';
import 'package:qamar/widgets/common.dart';

Future<void> _pump(WidgetTester tester, AppState s) async {
  await tester.binding.setSurfaceSize(const Size(900, 2000)); // words, not layout
  addTearDown(() => tester.binding.setSurfaceSize(null));
  await tester.pumpWidget(ChangeNotifierProvider.value(value: s, child: const QamarApp()));
  await tester.pump();
}

/// Nothing that answers a step is on screen.
void _noAnswerDrawn(WidgetTester tester, String where) {
  expect(find.byType(QWheelField), findsNothing, reason: 'a wheel before its question ($where)');
  expect(find.byType(QPillChip), findsNothing, reason: 'a chip before its question ($where)');
  expect(find.byType(QPrimaryButton), findsNothing, reason: 'Continue before its question ($where)');
  expect(find.text('Skip'), findsNothing, reason: 'Skip before its question ($where)');
  final send = tester.widget<QTapArea>(find.byKey(OnboardingScreen.sendKey));
  expect(send.onTap, isNull, reason: 'send before its question ($where)');
}

/// Answers the step on screen the way a person would: the first real chip
/// ("None" for safety, so the target's questions follow), a name, or the
/// wheels as they are.
void _answer(AppState s, OnboardingStep step) {
  switch (step.kind) {
    case StepKind.chips:
      final pick = step.id == 'safety' ? step.options.firstWhere((o) => o.value == 'none') : step.options.first;
      s.pickOption(pick);
    case StepKind.text:
      s.onDraftChanged('Basel');
      s.sendDraft();
    case StepKind.multi:
    case StepKind.number:
    case StepKind.date:
      s.primarySubmit();
  }
}

void main() {
  setUpAll(() {
    for (final name in const ['com.qamar.app/quick_events', 'com.qamar.app/quick_invoke']) {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(MethodChannel(name), (call) async => null);
    }
  });

  testWidgets('on every step, nothing answerable is drawn while its question is being typed', (tester) async {
    final s = AppState()..setLang(AppLang.en);
    await _pump(tester, s);
    s.startOnboarding();
    await tester.pump();

    final walked = <String>[];
    for (var guard = 0; guard < 30 && s.currentStep != null; guard++) {
      final step = s.currentStep!;
      var sawTyping = false;
      // Every frame until the question is on screen, check the dock.
      for (var f = 0; f < 40 && !s.questionShown; f++) {
        sawTyping = true;
        _noAnswerDrawn(tester, step.id);
        await tester.pump(const Duration(milliseconds: 50));
      }
      expect(s.questionShown, isTrue, reason: '${step.id}: its question arrives');
      await tester.pump();
      if (walked.isNotEmpty) expect(sawTyping, isTrue, reason: '${step.id} had its beat, and it was checked');
      walked.add(step.id);

      _answer(s, step);
      await tester.pump(const Duration(milliseconds: 300)); // the answer's own beat
    }
    expect(walked, ['consent', 'safety', 'goal', 'dob', 'gender', 'body', 'activity', 'food'],
        reason: 'every step of the consultation was walked');
    // The reveal that follows the last answer: the dish, the calorie card,
    // and "Let's start", which also waits for Qamar to stop typing.
    for (var i = 0; i < 12 && s.typing; i++) {
      expect(find.byType(QPrimaryButton), findsNothing, reason: '"Let’s start" before the last line');
      await tester.pump(const Duration(milliseconds: 250));
    }
    await tester.pump(const Duration(seconds: 3));
    expect(find.widgetWithText(QPrimaryButton, 'Let’s start'), findsOneWidget, reason: 'the way in, once the last line is there');
  });

  testWidgets('what is typed while Qamar types waits in the box, and is sent once the question is there', (tester) async {
    final s = AppState()..setLang(AppLang.en);
    await _pump(tester, s);
    s.startOnboarding();
    await tester.pump();
    s.pickOption(s.currentStep!.options.first); // consent: the safety question starts typing
    await tester.pump(const Duration(milliseconds: 300));
    expect(s.questionShown, isFalse);
    expect(find.text('Qamar is typing…'), findsOneWidget, reason: 'the box says why it waits');

    final before = s.msgs.length;
    s.onDraftChanged('none');
    s.sendDraft();
    expect(s.msgs.length, before, reason: 'not taken as the answer to a question not yet asked');
    expect(s.draft, 'none', reason: 'and not thrown away');

    await tester.pump(const Duration(milliseconds: 800));
    expect(s.questionShown, isTrue);
    s.sendDraft();
    expect(s.msgs.last.text(false), 'none', reason: 'sent, now that the question is on screen');
    await tester.pump(const Duration(seconds: 2)); // let the answer land
  });
}
