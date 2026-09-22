// The consultation's order and its first screen (O7).
//
// Consent comes before any personal data, and safety comes next, so an answer
// that rules out a calorie target changes the rest of the conversation
// rather than ending it. The goal comes before the numbers. The 18+ gate is
// the date step, before any target, on either route. The rule for the screen:
// an input never appears before its question.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

import 'package:qamar/l10n/strings.dart';
import 'package:qamar/main.dart';
import 'package:qamar/models/dishes.dart';
import 'package:qamar/models/messages.dart';
import 'package:qamar/models/nudge.dart';
import 'package:qamar/models/onboarding.dart';
import 'package:qamar/models/profile.dart';
import 'package:qamar/state/app_state.dart';
import 'package:qamar/widgets/common.dart';

Future<void> _wait([int ms = 1000]) => Future<void>.delayed(Duration(milliseconds: ms));

StepOption _option(String stepId, String value) =>
    kOnboardingSteps.firstWhere((s) => s.id == stepId).options.firstWhere((o) => o.value == value);

/// Opens the consultation and answers consent (required only).
Future<AppState> _pastConsent({AppLang lang = AppLang.en}) async {
  final s = AppState()..setLang(lang);
  s.startOnboarding();
  s.pickOption(_option('consent', 'yes'));
  await _wait();
  return s;
}

void main() {
  test('the agreed order: consent, safety, name, goal, date of birth, sex, body, activity, food', () {
    expect(kOnboardingSteps.map((s) => s.id).toList(), ['consent', 'safety', 'name', 'goal', 'dob', 'gender', 'body', 'activity', 'food']);
    expect(kGeneralGuidanceSkips, {'goal', 'gender', 'body', 'activity'}, reason: 'the date of birth is never skipped');
  });

  test('the first question is on screen the moment the consultation opens — no typing beat on step 0', () {
    final s = AppState()..setLang(AppLang.en);
    s.startOnboarding();
    expect(s.typing, isFalse);
    expect(s.msgs, hasLength(1));
    expect(s.msgs.single.text(false), startsWith('Hi, I’m Qamar.'));
    expect(s.msgs.single.text(true), startsWith('أهلاً'));
    expect(s.currentStep!.id, 'consent');
    expect(s.questionShown, isTrue, reason: 'its chips may show at once');
  });

  test('every later step waits for its own question: nothing is answerable while Qamar types', () async {
    final s = AppState();
    s.startOnboarding();
    s.pickOption(_option('consent', 'yes'));
    await _wait(350);
    expect(s.currentStep!.id, 'safety');
    expect(s.questionShown, isFalse, reason: 'the safety question is still being typed');
    await _wait(700);
    expect(s.questionShown, isTrue);
    expect(s.msgs.last.text(false), 'One safety question before we start: does any of these apply?');
  });

  test('"None of these" goes on to the target’s questions, in order', () async {
    final s = await _pastConsent();
    s.pickOption(_option('safety', 'none'));
    await _wait();
    expect(s.generalGuidance, isFalse);
    expect(s.currentStep!.id, 'name');
    s.skipStep();
    await _wait();
    expect(s.currentStep!.id, 'goal', reason: 'the goal before the numbers');
    s.pickOption(_option('goal', 'maintain'));
    await _wait();
    expect(s.currentStep!.id, 'dob');
    expect(s.msgs.last.text(false), contains('feeds the calorie maths'));
  });

  for (final answer in ['pregnant', 'breastfeeding', 'chronic']) {
    test('safety "$answer" continues into the app on general guidance — not a dead end, and no target', () async {
      final s = await _pastConsent();
      s.pickOption(_option('safety', answer));
      await _wait();

      expect(s.generalGuidance, isTrue);
      expect(s.blocked, isFalse, reason: 'the conversation goes on');
      expect(s.msgs.any((m) => m.text(false).contains('I won’t calculate a calorie target or a plan')), isTrue);
      expect(s.currentStep!.id, 'name');

      s.skipStep();
      await _wait();
      expect(s.currentStep!.id, 'dob', reason: 'the goal feeds only the target, so it is not asked');
      expect(s.msgs.last.text(false), 'Qamar is for adults, so I need to know: what’s your date of birth?');

      s.profile = s.profile.copyWith(age: 30);
      s.primarySubmit();
      await _wait();
      expect(s.currentStep!.id, 'food', reason: 'sex, body and activity feed only the target');

      s.primarySubmit(); // nothing to avoid
      await _wait();
      expect(s.currentStep, isNull);
      expect(s.msgs.any((m) => m.kind == ObKind.target), isFalse, reason: 'no target card on this route');
      expect(s.msgs.any((m) => m.text(false).contains('There’s no calorie target in your case')), isTrue);

      s.primarySubmit(); // "Let's start"
      expect(s.screen, AppScreen.today, reason: 'a way into the app');
    });
  }

  test('the 18+ gate still holds on the general-guidance route', () async {
    final s = await _pastConsent();
    s.pickOption(_option('safety', 'pregnant'));
    await _wait();
    s.skipStep();
    await _wait();
    expect(s.currentStep!.id, 'dob');
    s.profile = s.profile.copyWith(age: 16);
    s.primarySubmit();
    await _wait();
    expect(s.blocked, isTrue);
    expect(s.minor, isTrue);
    expect(s.currentStep!.id, 'dob', reason: 'it stops at the gate');
  });

  test('pregnancy and breastfeeding reach the account as the life stage the gateway enforces; a condition cannot', () {
    expect(SafetyAnswer.pregnant.lifeStage, 'pregnant');
    expect(SafetyAnswer.breastfeeding.lifeStage, 'lactating');
    expect(SafetyAnswer.chronic.lifeStage, 'none', reason: 'no column holds it; without a target row the gateway refuses plans anyway');
    expect(SafetyAnswer.none.lifeStage, 'none');
    expect(SafetyAnswer.fromLifeStage('lactating'), SafetyAnswer.breastfeeding);
    expect(SafetyAnswer.fromLifeStage('pregnant'), SafetyAnswer.pregnant);
    expect(SafetyAnswer.fromLifeStage(null), SafetyAnswer.none);
  });

  test('free text at the safety step takes the same routes', () async {
    for (final (typed, want) in [('I’m pregnant', SafetyAnswer.pregnant), ('breastfeeding now', SafetyAnswer.breastfeeding), ('عندي سكر', SafetyAnswer.chronic), ('no', SafetyAnswer.none)]) {
      final s = await _pastConsent();
      await _wait(); // the safety question has arrived
      s.onDraftChanged(typed);
      s.sendDraft();
      await _wait();
      expect(s.profile.safety, want, reason: typed);
      expect(s.blocked, isFalse, reason: typed);
      expect(s.currentStep!.id, 'name', reason: typed);
    }
  });

  test('on general guidance no plan is asked for, and the Plan screen says why in both languages', () async {
    final s = AppState()..profile = const Profile(safety: SafetyAnswer.chronic);
    await s.ensurePlan();
    expect(s.planLoading, isFalse);
    expect(s.planError, isNull, reason: 'nothing was asked, so nothing failed');
    s.setLang(AppLang.en);
    expect(s.generalGuidancePlanNote, contains('Qamar doesn’t set one in your case'));
    s.setLang(AppLang.ar);
    expect(s.generalGuidancePlanNote, contains('قمر مش بيحط هدف في حالتك'));
  });

  test('the reveal opens with one real dish, before the calorie card — filtered by the exclusions, costed against the target', () async {
    final s = AppState(clock: () => DateTime(2026, 9, 21, 20, 0))..setLang(AppLang.en); // dinner
    s.profile = s.profile.copyWith(prefs: ['lactose', 'meat']);
    s.step = kOnboardingSteps.indexWhere((x) => x.id == 'food');
    s.primarySubmit();
    await _wait(2600);

    final kinds = s.msgs.map((m) => m.kind).toList();
    final dishAt = kinds.indexOf(ObKind.dish);
    final targetAt = kinds.indexOf(ObKind.target);
    expect(dishAt, greaterThanOrEqualTo(0), reason: 'a dish is shown');
    expect(dishAt, lessThan(targetAt), reason: 'before the calorie card');
    expect(s.msgs[dishAt - 1].text(false), startsWith('Before the numbers, something to eat'));

    final dish = s.revealDish!;
    expect(dish.ruledOutBy.intersection({'lactose', 'meat'}), isEmpty);
    expect(s.revealSlot, MealSlot.dinner);
    expect(dish.id, pickDish(targetKcal: s.target().kcal, goal: s.profile.goal, exclusions: const ['lactose', 'meat'], slot: MealSlot.dinner)!.id);
    expect(s.revealDishFacts!.live, isFalse, reason: 'no backend: the numbers that ship with the app');
  });

  test('on the general-guidance route there is no dish either: it would be costed against a target that is not set', () async {
    final s = await _pastConsent();
    s.pickOption(_option('safety', 'chronic'));
    await _wait();
    s.skipStep();
    await _wait();
    s.profile = s.profile.copyWith(age: 30);
    s.primarySubmit();
    await _wait();
    s.primarySubmit();
    await _wait(2000);
    expect(s.msgs.any((m) => m.kind == ObKind.dish), isFalse);
    expect(s.revealDish, isNull);
  });

  group('on screen', () {
    Future<void> pump(WidgetTester tester, AppState s) async {
      await tester.binding.setSurfaceSize(const Size(900, 2000)); // words, not layout
      addTearDown(() => tester.binding.setSurfaceSize(null));
      await tester.pumpWidget(ChangeNotifierProvider.value(value: s, child: const QamarApp()));
    }

    testWidgets('step 0 opens with its question and its chips together; later chips wait for their question', (tester) async {
      final s = AppState()..setLang(AppLang.en);
      await pump(tester, s);
      s.startOnboarding();
      await tester.pump();
      expect(find.textContaining('Hi, I’m Qamar.'), findsOneWidget);
      expect(find.widgetWithText(QPillChip, 'Agree to the required only'), findsOneWidget, reason: 'the first frame has both');

      s.pickOption(_option('consent', 'yes'));
      await tester.pump(const Duration(milliseconds: 400));
      expect(find.byType(QPillChip), findsNothing, reason: 'the safety question is still being typed');
      await tester.pump(const Duration(milliseconds: 700));
      expect(find.widgetWithText(QPillChip, 'None of these'), findsOneWidget);
    });

    testWidgets('the reveal — the dish, then the calorie card — carries no Latin digits in Arabic', (tester) async {
      final s = AppState(clock: () => DateTime(2026, 9, 21, 13, 0));
      s.profile = s.profile.copyWith(prefs: ['budget']);
      await pump(tester, s);
      s.go(AppScreen.onboard);
      s.step = kOnboardingSteps.indexWhere((x) => x.id == 'food');
      s.primarySubmit();
      for (var i = 0; i < 6; i++) {
        await tester.pump(const Duration(milliseconds: 500)); // the answer, the dish, then the numbers
      }
      final transcript = tester.widgetList<Text>(find.descendant(of: find.byType(ListView), matching: find.byType(Text))).map((t) => t.data ?? '').join(' | ');
      expect(transcript, contains('٪ من هدفك'), reason: 'the dish is costed against the target');
      expect(RegExp('[0-9]').hasMatch(transcript), isFalse, reason: transcript);
    });

    testWidgets('a free week left at "Not now" is waiting on the Me tile, in both languages', (tester) async {
      final s = AppState()..plusTrialEligible = true;
      s.setLang(AppLang.en);
      await pump(tester, s);
      s.go(AppScreen.you);
      await tester.pump();
      expect(find.text('Your free week is waiting: 7 days, no card, nothing renews.'), findsOneWidget);
      s.setLang(AppLang.ar);
      await tester.pump();
      expect(find.text('أسبوعك المجاني مستنيك: \u2066٧\u2069 أيام، من غير بطاقة، ومفيش تجديد.'), findsOneWidget);
    });

    testWidgets('while an invitation code waits, the Me tile does not offer the free week, in either language', (tester) async {
      final s = AppState()
        ..plusTrialEligible = true
        ..pendingInvitationCode = 'QMR-LATER';
      s.setLang(AppLang.en);
      await pump(tester, s);
      s.go(AppScreen.you);
      await tester.pump();
      expect(find.textContaining('Your free week is waiting'), findsNothing);
      expect(find.text('Tomorrow’s plan, more photos and questions'), findsOneWidget);
      s.setLang(AppLang.ar);
      await tester.pump();
      expect(find.textContaining('أسبوعك المجاني مستنيك'), findsNothing);
      expect(find.text('خطة بكرة، وصور وأسئلة أكتر'), findsOneWidget);
    });

    testWidgets('Today names no target on general guidance, and says what is still here', (tester) async {
      final s = AppState()
        ..profile = const Profile(safety: SafetyAnswer.pregnant)
        ..setLang(AppLang.en);
      await pump(tester, s);
      s.go(AppScreen.today);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
      expect(find.textContaining('General guidance', findRichText: true), findsOneWidget);
      expect(find.textContaining('kcal remaining'), findsNothing);
      expect(find.text('Why this number?'), findsNothing);

      s.go(AppScreen.plan);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
      expect(find.textContaining('Qamar doesn’t set one in your case'), findsOneWidget);
      expect(find.text('Build today’s plan'), findsNothing, reason: 'no button that could only be refused');
    });
  });
}
