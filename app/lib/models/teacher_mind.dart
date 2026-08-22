/// Teacher AI Mind — offline Dart twin of the gateway learning OS.
///
/// Keeps Study Mode honest without a network call: mechanisms, mission cards,
/// BKT-lite mastery, and P50/P80 forecasts. Su still posts only on verified
/// completion (see [SuEconomy] study awards).
library;

import 'dart:math' as math;

enum LearningMechanism { encode, retrieve, discriminate, apply, transfer, reflect }

enum MasteryStatus { unknown, emerging, independent, durable, fragile }

class EvidenceCard {
  final String id;
  final String productRule;
  final List<String> sourceIds;
  const EvidenceCard({required this.id, required this.productRule, required this.sourceIds});
}

const kEvidenceCanon = <EvidenceCard>[
  EvidenceCard(
    id: 'EC-retrieve-01',
    productRule: 'Ask the learner to produce an answer before re-showing the source.',
    sourceIds: ['S1', 'S2', 'S5'],
  ),
  EvidenceCard(
    id: 'EC-space-01',
    productRule: 'Schedule the next review after effortful success; shorten after failure.',
    sourceIds: ['S1', 'S3'],
  ),
  EvidenceCard(
    id: 'EC-mastery-01',
    productRule: 'Do not mark a concept complete from a timer or page open alone.',
    sourceIds: ['S14'],
  ),
  EvidenceCard(
    id: 'EC-feedback-01',
    productRule: 'After an error, give the correct response and the next action.',
    sourceIds: ['S10', 'S11'],
  ),
  EvidenceCard(
    id: 'EC-sleep-01',
    productRule: 'Protect recovery; never reward all-night cramming.',
    sourceIds: ['S18'],
  ),
];

class MissionCard {
  final String outcome;
  final String whyNow;
  final LearningMechanism mechanism;
  final String evidenceCriterion;
  final int durationP50Min;
  final int durationP80Min;
  final String fallback;
  final int suPreview;
  final List<String> evidenceCardIds;

  const MissionCard({
    required this.outcome,
    required this.whyNow,
    required this.mechanism,
    required this.evidenceCriterion,
    required this.durationP50Min,
    required this.durationP80Min,
    required this.fallback,
    required this.suPreview,
    required this.evidenceCardIds,
  });
}

class CompletionForecast {
  final double remainingHoursP50;
  final double remainingHoursP80;
  final DateTime? finishDateP50;
  final DateTime? finishDateP80;
  final String confidence;
  final String dominantRisk;
  final double bufferRatio;

  const CompletionForecast({
    required this.remainingHoursP50,
    required this.remainingHoursP80,
    required this.finishDateP50,
    required this.finishDateP80,
    required this.confidence,
    required this.dominantRisk,
    required this.bufferRatio,
  });
}

class ConceptState {
  final String conceptId;
  final double masteryP;
  final double uncertainty;
  final double memoryStabilityDays;
  final int successes;
  final int failures;
  final MasteryStatus status;

  const ConceptState({
    required this.conceptId,
    required this.masteryP,
    required this.uncertainty,
    required this.memoryStabilityDays,
    required this.successes,
    required this.failures,
    required this.status,
  });

  factory ConceptState.fresh(String id) => ConceptState(
        conceptId: id,
        masteryP: 0.2,
        uncertainty: 0.5,
        memoryStabilityDays: 1,
        successes: 0,
        failures: 0,
        status: MasteryStatus.unknown,
      );
}

LearningMechanism mechanismForTask(String title, String finish) {
  final t = '$title $finish'.toLowerCase();
  if (RegExp(r'exam|امتحان|quiz|اختبار').hasMatch(t)) return LearningMechanism.discriminate;
  if (RegExp(r'solve|equation|math|معادلة|مسائل').hasMatch(t)) return LearningMechanism.apply;
  if (RegExp(r'read|pages|فصل|اقرا|قراءة').hasMatch(t)) return LearningMechanism.retrieve;
  if (RegExp(r'reflect|مراجعة|review').hasMatch(t)) return LearningMechanism.reflect;
  return LearningMechanism.retrieve;
}

MissionCard buildMissionCard({
  required String title,
  required String finishCondition,
  required int estimateMin,
  String? whyNow,
  int suPreview = 10,
}) {
  final mechanism = mechanismForTask(title, finishCondition);
  final cards = kEvidenceCanon
      .where((c) =>
          mechanism == LearningMechanism.retrieve
              ? c.id.contains('retrieve') || c.id.contains('space') || c.id.contains('mastery')
              : true)
      .take(3)
      .toList();
  final p50 = estimateMin < 10 ? 10 : estimateMin;
  return MissionCard(
    outcome: finishCondition,
    whyNow: whyNow ?? 'Next useful step on your mastery path.',
    mechanism: mechanism,
    evidenceCriterion: 'Show retrieval, explanation, or solution quality — not timer elapsed.',
    durationP50Min: p50,
    durationP80Min: (p50 * 1.25).round(),
    fallback: 'If time collapses: one retrieval prompt + one sentence from memory.',
    suPreview: suPreview,
    evidenceCardIds: cards.map((c) => c.id).toList(),
  );
}

CompletionForecast forecastFromUnits({
  required List<({String title, int minutes})> units,
  required int maxDailyMin,
  double bufferRatio = 0.18,
  int sampleSessions = 0,
  DateTime? now,
}) {
  final stamp = now ?? DateTime.now();
  var p50 = units.length * 2.0; // setup
  for (final u in units) {
    final cls = u.title.toLowerCase();
    final mult = RegExp(r'practice|تمرين|question').hasMatch(cls)
        ? 1.85
        : RegExp(r'review|مراجعة').hasMatch(cls)
            ? 1.2
            : 1.65;
    p50 += u.minutes * mult;
  }
  p50 = p50 * (1 + bufferRatio);
  final p80 = p50 * 1.22;
  final usable = (maxDailyMin * (1 - bufferRatio)).round().clamp(25, maxDailyMin);
  final days50 = (p50 / usable).ceil();
  final days80 = (p80 / usable).ceil();
  return CompletionForecast(
    remainingHoursP50: double.parse((p50 / 60).toStringAsFixed(1)),
    remainingHoursP80: double.parse((p80 / 60).toStringAsFixed(1)),
    finishDateP50: stamp.add(Duration(days: days50)),
    finishDateP80: stamp.add(Duration(days: days80)),
    confidence: sampleSessions >= 5 ? 'high' : sampleSessions >= 1 ? 'medium' : 'low',
    dominantRisk: 'Uncertainty highest in practice work until a sample session lands.',
    bufferRatio: bufferRatio,
  );
}

ConceptState updateMastery(ConceptState state, {required bool correct, int hintsUsed = 0, double? delayedHours}) {
  const pT = 0.15, pG = 0.2, pS = 0.1;
  final pL = state.masteryP;
  final pCorrect = pL * (1 - pS) + (1 - pL) * pG;
  double pLGiven;
  if (correct) {
    pLGiven = (pL * (1 - pS)) / (pCorrect == 0 ? 1e-9 : pCorrect);
  } else {
    final pWrong = 1 - pCorrect;
    pLGiven = (pL * pS) / (pWrong == 0 ? 1e-9 : pWrong);
  }
  var learn = pT;
  if (hintsUsed > 0) learn = pT * (1 - 0.25 * hintsUsed).clamp(0.2, 1.0);
  var nextP = (pLGiven + (1 - pLGiven) * learn).clamp(0.0, 1.0);

  var stability = state.memoryStabilityDays;
  if (correct) {
    final delayBoost = (delayedHours ?? 0) >= 12 ? 1.6 : 1.15;
    stability = (stability * delayBoost).clamp(0.5, 60.0);
  } else {
    stability = (stability * 0.55).clamp(0.5, 60.0);
  }

  final successes = state.successes + (correct ? 1 : 0);
  final failures = state.failures + (correct ? 0 : 1);
  final uncertainty = (0.55 / math.sqrt(successes + failures + 1)).clamp(0.0, 1.0);

  MasteryStatus status;
  if (successes + failures < 2) {
    status = MasteryStatus.unknown;
  } else if (!correct && state.status == MasteryStatus.durable) {
    status = MasteryStatus.fragile;
  } else if (correct && (delayedHours ?? 0) >= 12 && nextP >= 0.85) {
    status = MasteryStatus.durable;
  } else if (nextP >= 0.8 && hintsUsed == 0) {
    status = MasteryStatus.independent;
  } else if (nextP >= 0.45) {
    status = MasteryStatus.emerging;
  } else {
    status = MasteryStatus.unknown;
  }

  return ConceptState(
    conceptId: state.conceptId,
    masteryP: nextP,
    uncertainty: uncertainty.toDouble(),
    memoryStabilityDays: double.parse(stability.toStringAsFixed(2)),
    successes: successes,
    failures: failures,
    status: status,
  );
}
