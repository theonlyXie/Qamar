// Interpretable Bayesian Knowledge Tracing (BKT) — Phase 1 learner model.
//
// Mastery is local to a concept and evidence window. Never convert these
// posteriors into IQ, diligence, or clinical labels.

export type MasteryStatus = "unknown" | "emerging" | "independent" | "durable" | "fragile";

export interface ConceptState {
  conceptId: string;
  /** P(L) — probability the skill is learned. */
  masteryP: number;
  uncertainty: number;
  /** Half-life days for spaced review (interpretable HLR-style stability). */
  memoryStabilityDays: number;
  lastEvidenceAt: string | null;
  successes: number;
  failures: number;
  status: MasteryStatus;
}

export interface AssessmentEvidence {
  correct: boolean;
  /** 0–1 self-reported confidence before feedback. */
  confidence?: number;
  hintsUsed?: number;
  /** Hours since last successful retrieval; null if immediate. */
  delayedHours?: number | null;
  transfer?: boolean;
}

export interface BktParams {
  /** P(L0) prior. */
  pL0: number;
  /** P(T) learn from one opportunity. */
  pT: number;
  /** P(G) guess. */
  pG: number;
  /** P(S) slip. */
  pS: number;
}

export const DEFAULT_BKT: BktParams = {
  pL0: 0.2,
  pT: 0.15,
  pG: 0.2,
  pS: 0.1,
};

export function freshConcept(conceptId: string, params: BktParams = DEFAULT_BKT): ConceptState {
  return {
    conceptId,
    masteryP: params.pL0,
    uncertainty: 0.5,
    memoryStabilityDays: 1,
    lastEvidenceAt: null,
    successes: 0,
    failures: 0,
    status: "unknown",
  };
}

function clamp01(x: number): number {
  return Math.min(1, Math.max(0, x));
}

/**
 * One BKT update. Delayed/transfer evidence weighs more toward durable status.
 */
export function updateConcept(
  state: ConceptState,
  evidence: AssessmentEvidence,
  params: BktParams = DEFAULT_BKT,
  nowIso: string = new Date().toISOString(),
): ConceptState {
  const { pT, pG, pS } = params;
  const pL = state.masteryP;

  // P(correct | state)
  const pCorrect = pL * (1 - pS) + (1 - pL) * pG;
  let pLGivenObs: number;
  if (evidence.correct) {
    pLGivenObs = (pL * (1 - pS)) / Math.max(1e-9, pCorrect);
  } else {
    const pWrong = 1 - pCorrect;
    pLGivenObs = (pL * pS) / Math.max(1e-9, pWrong);
  }

  // Learn transition after the opportunity.
  let nextP = pLGivenObs + (1 - pLGivenObs) * pT;

  // Hints reduce learning credit.
  const hints = evidence.hintsUsed ?? 0;
  if (hints > 0) nextP = pLGivenObs + (1 - pLGivenObs) * (pT * Math.max(0.2, 1 - 0.25 * hints));

  nextP = clamp01(nextP);

  let stability = state.memoryStabilityDays;
  if (evidence.correct) {
    const delayBoost = evidence.delayedHours && evidence.delayedHours >= 12 ? 1.6 : 1.15;
    const transferBoost = evidence.transfer ? 1.25 : 1;
    stability = Math.min(60, stability * delayBoost * transferBoost);
  } else {
    stability = Math.max(0.5, stability * 0.55);
  }

  const successes = state.successes + (evidence.correct ? 1 : 0);
  const failures = state.failures + (evidence.correct ? 0 : 1);
  const uncertainty = clamp01(0.55 / Math.sqrt(successes + failures + 1));

  const delayedOk = evidence.correct && (evidence.delayedHours ?? 0) >= 12;
  let status: MasteryStatus;
  if (successes + failures < 2) status = "unknown";
  else if (!evidence.correct && state.status === "durable") status = "fragile";
  else if (delayedOk && nextP >= 0.85) status = "durable";
  else if (nextP >= 0.8 && hints === 0) status = "independent";
  else if (nextP >= 0.45) status = "emerging";
  else status = "unknown";

  return {
    conceptId: state.conceptId,
    masteryP: nextP,
    uncertainty,
    memoryStabilityDays: Number(stability.toFixed(2)),
    lastEvidenceAt: nowIso,
    successes,
    failures,
    status,
  };
}

/** Next review due window in days from now (productive forgetting band). */
export function reviewDueDays(state: ConceptState): { soon: number; late: number } {
  const half = Math.max(0.5, state.memoryStabilityDays);
  return { soon: Number((half * 0.7).toFixed(2)), late: Number((half * 1.2).toFixed(2)) };
}
