import 'package:flutter_test/flutter_test.dart';
import 'package:qamar/models/study.dart';
import 'package:qamar/models/su_economy.dart';
import 'package:qamar/state/app_state.dart';

void main() {
  test('Study Mode opens from Today entry and shares the Su wallet', () async {
    final state = AppState()..suAvailable = 100..suLifetime = 100;
    state.openStudyMode();
    expect(state.screen, AppScreen.study);
    expect(state.studyView, StudyView.add);

    state.studyPickType(StudySourceType.subject);
    state.studyUpdateDraft(
      title: 'Organic Chemistry',
      outcome: 'Finish the syllabus',
      topicsRaw: 'Reactions\nMechanisms\nPractice',
      noDeadline: false,
      deadline: DateTime.now().add(const Duration(days: 21)),
      maxDailyMin: 120,
      blockMin: 50,
    );
    await state.studyGeneratePlan();
    expect(state.studyView, StudyView.planReview);
    expect(state.activeStudyWorkspace, isNotNull);
    expect(state.activeStudyWorkspace!.tasks, isNotEmpty);

    state.studyApprovePlan();
    expect(state.studyView, StudyView.hub);
    expect(state.activeStudyWorkspace!.planApproved, isTrue);

    final task = state.activeStudyWorkspace!.nextTask!;
    final before = state.suAvailable;
    state.studyCompleteTaskQuick(task.id);
    expect(state.suAvailable, before + SuEconomy.studyTaskComplete);
    expect(state.ledger().first.amount, SuEconomy.studyTaskComplete);

    // Same wallet from nutrition spends.
    state.openWallet();
    expect(state.screen, AppScreen.wallet);
    expect(state.suAvailable, before + SuEconomy.studyTaskComplete);
  });

  test('timer alone does not award Su; confirm does once', () async {
    final state = AppState();
    state.openStudyMode();
    state.studyPickType(StudySourceType.book);
    state.studyUpdateDraft(
      title: 'Physics',
      topicsRaw: 'Kinematics, Forces',
      noDeadline: true,
      maxDailyMin: 90,
      blockMin: 25,
    );
    await state.studyGeneratePlan();
    state.studyApprovePlan();

    final task = state.activeStudyWorkspace!.nextTask!;
    state.studyStartSession(taskId: task.id);
    state.studySessionFocusSec = 50 * 60;
    expect(state.suAvailable, 0);

    state.studyOpenFinish();
    state.studySetFinish(progress: 100, confidence: 4);
    state.studyConfirmSession();
    expect(state.suAvailable, SuEconomy.studyTaskComplete);

    // Idempotent — completing again does not double-pay.
    final mid = state.suAvailable;
    state.studyCompleteTaskQuick(task.id);
    expect(state.suAvailable, mid);
  });

  test('moving a missed task never deducts Su and can earn catch-up', () async {
    final state = AppState()..suAvailable = 50..suLifetime = 50;
    state.openStudyMode();
    state.studyPickType(StudySourceType.custom);
    state.studyUpdateDraft(
      title: 'Exam prep',
      topicsRaw: 'A, B, C',
      noDeadline: true,
      maxDailyMin: 120,
      blockMin: 50,
    );
    await state.studyGeneratePlan();
    state.studyApprovePlan();
    final task = state.activeStudyWorkspace!.tasks.first;
    state.studyCarryTask(task.id);
    expect(state.suAvailable, greaterThanOrEqualTo(50));
    expect(state.suAvailable, 50 + SuEconomy.studyCatchUp);
  });

  test('plan review carries a P50/P80 teacher forecast', () async {
    final state = AppState();
    state.openStudyMode();
    state.studyPickType(StudySourceType.subject);
    state.studyUpdateDraft(
      title: 'Calculus',
      topicsRaw: 'Limits\nDerivatives\nApplications',
      noDeadline: true,
      maxDailyMin: 90,
      blockMin: 50,
    );
    await state.studyGeneratePlan();
    expect(state.studyForecast, isNotNull);
    expect(state.studyForecast!.remainingHoursP80,
        greaterThan(state.studyForecast!.remainingHoursP50));
    final task = state.activeStudyWorkspace!.tasks.first;
    final mission = state.missionForTask(task);
    expect(mission, isNotNull);
    expect(mission!.evidenceCriterion.toLowerCase(), contains('timer'));
  });
}
