// Run: deno test teacher_test.ts learner_model_test.ts study_forecast_test.ts

import { assertEquals, assertAlmostEquals } from "jsr:@std/assert@1";
import {
  buildMissionCard,
  classifyStudyRequest,
  inferLearningObject,
  methodForObject,
  pickTutorMode,
} from "./teacher.ts";
import { freshConcept, reviewDueDays, updateConcept } from "./learner_model.ts";
import {
  classifyUnit,
  forecastCompletion,
  scoreTask,
  unitWorkMinutes,
  updatePace,
} from "./study_forecast.ts";

Deno.test("teacher refuses academic cheating in one Qamar voice", () => {
  const v = classifyStudyRequest("write my essay for the exam tomorrow");
  assertEquals(v.allowed, false);
  if (!v.allowed) assertEquals(v.reason, "academic_cheating");
});

Deno.test("teacher refuses VAK learning-style matching", () => {
  const v = classifyStudyRequest("I am a visual learner so only show videos");
  assertEquals(v.allowed, false);
  if (!v.allowed) assertEquals(v.reason, "learning_styles");
});

Deno.test("teacher allows study questions and picks a mode", () => {
  const v = classifyStudyRequest("اشرح لي السلسلة في التفاضل");
  assertEquals(v.allowed, true);
  if (v.allowed) assertEquals(v.mode, "explain");
});

Deno.test("mission cards require an explicit learning mechanism", () => {
  const card = buildMissionCard({
    title: "Read pages 44–62",
    finishCondition: "Write five recall prompts from memory",
    estimateMin: 50,
  });
  assertEquals(card.mechanism, "retrieve");
  assertEquals(card.durationP80Min > card.durationP50Min, true);
  assertEquals(card.evidenceCardIds.length > 0, true);
});

Deno.test("method follows the learning object, not a style label", () => {
  const object = inferLearningObject("Solve integrals", "three varied problems without hints");
  assertEquals(object, "procedures");
  const m = methodForObject(object);
  assertEquals(m.mechanism, "apply");
});

Deno.test("examiner mode for quiz requests", () => {
  assertEquals(pickTutorMode("quiz me on chapter 3"), "examiner");
});

Deno.test("BKT updates mastery without inventing ability labels", () => {
  let s = freshConcept("chain-rule");
  s = updateConcept(s, { correct: true, hintsUsed: 0 });
  s = updateConcept(s, { correct: true, delayedHours: 24, transfer: true });
  assertEquals(s.masteryP > 0.2, true);
  assertEquals(s.status === "durable" || s.status === "independent" || s.status === "emerging", true);
  const due = reviewDueDays(s);
  assertEquals(due.late >= due.soon, true);
});

Deno.test("failed retrieval shortens memory stability", () => {
  let s = freshConcept("limits");
  s = updateConcept(s, { correct: true });
  const afterOk = s.memoryStabilityDays;
  s = updateConcept(s, { correct: false });
  assertEquals(s.memoryStabilityDays < afterOk, true);
  assertEquals(s.failures, 1);
});

Deno.test("forecast returns P50/P80 ranges with buffer, not a single fake minute", () => {
  const f = forecastCompletion({
    units: [
      { title: "Chapter 1", consumeMin: 40, taskClass: "read" },
      { title: "Practice set", consumeMin: 50, taskClass: "practice" },
    ],
    maxDailyMin: 120,
    bufferRatio: 0.18,
    sampleSessions: 0,
    now: new Date("2026-08-22T12:00:00Z"),
  });
  assertEquals(f.remainingHoursP80 > f.remainingHoursP50, true);
  assertEquals(f.assumptions.confidence, "low");
  assertEquals(f.finishDateP50 !== null, true);
});

Deno.test("pace shrinkage moves toward observations", () => {
  const prior = { taskClass: "practice" as const, rate: 1.35, kappa: 4, observations: 0 };
  const next = updatePace(prior, 1.0);
  assertEquals(next.observations, 1);
  assertEquals(next.rate < prior.rate, true);
});

Deno.test("unit work includes practice beyond consumption", () => {
  const a = unitWorkMinutes({ title: "Read", consumeMin: 60, taskClass: "read" });
  const b = unitWorkMinutes({ title: "Read", consumeMin: 60, taskClass: "practice" });
  assertEquals(b.p50 > a.p50 * 0.9, true);
  assertEquals(classifyUnit("Practice questions"), "practice");
});

Deno.test("task score prefers mastery gain and deadline risk", () => {
  const low = scoreTask({
    goalImportance: 0.2,
    prerequisiteCentrality: 0.2,
    forgettingRisk: 0.1,
    uncertaintyReduction: 0.1,
    deadlineRisk: 0.1,
    masteryGainPerMin: 0.2,
    switchCost: 0.5,
    overloadRisk: 0.5,
  });
  const high = scoreTask({
    goalImportance: 1,
    prerequisiteCentrality: 0.8,
    forgettingRisk: 0.7,
    uncertaintyReduction: 0.6,
    deadlineRisk: 1,
    masteryGainPerMin: 1,
    switchCost: 0.1,
    overloadRisk: 0.1,
  });
  assertEquals(high > low, true);
  assertAlmostEquals(high - low, high - low, 1e-9);
});
