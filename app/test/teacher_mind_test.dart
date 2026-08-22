import 'package:flutter_test/flutter_test.dart';
import 'package:qamar/models/teacher_mind.dart';

void main() {
  test('mission cards expose a learning mechanism and P50/P80 range', () {
    final card = buildMissionCard(
      title: 'Read pages 44–62',
      finishCondition: 'Write five recall prompts',
      estimateMin: 50,
    );
    expect(card.mechanism, LearningMechanism.retrieve);
    expect(card.durationP80Min, greaterThan(card.durationP50Min));
    expect(card.evidenceCardIds, isNotEmpty);
  });

  test('forecast is a range with cold-start low confidence', () {
    final f = forecastFromUnits(
      units: [
        (title: 'Chapter 1', minutes: 40),
        (title: 'Practice set', minutes: 50),
      ],
      maxDailyMin: 120,
      sampleSessions: 0,
      now: DateTime.utc(2026, 8, 22),
    );
    expect(f.remainingHoursP80, greaterThan(f.remainingHoursP50));
    expect(f.confidence, 'low');
    expect(f.finishDateP50, isNotNull);
  });

  test('BKT mastery rises with successful delayed retrieval', () {
    var s = ConceptState.fresh('chain-rule');
    s = updateMastery(s, correct: true);
    s = updateMastery(s, correct: true, delayedHours: 24);
    expect(s.masteryP, greaterThan(0.2));
    expect(s.successes, 2);
  });

  test('timer-irrelevant: mastery does not flip from progress alone without updateMastery', () {
    final s = ConceptState.fresh('limits');
    expect(s.status, MasteryStatus.unknown);
    expect(s.masteryP, 0.2);
  });
}
