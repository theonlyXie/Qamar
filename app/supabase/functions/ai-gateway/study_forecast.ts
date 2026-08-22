// Completion-time estimation — work equation + P50/P80 ranges.
//
// Consumption is not completion. Forecasts are ranges with assumptions,
// never fake exact minutes.

export type TaskClass = "read" | "practice" | "retrieve" | "review" | "project";

export interface UnitEstimateInput {
  title: string;
  /** Base study minutes suggested by structure (not wall-clock video alone). */
  consumeMin: number;
  taskClass: TaskClass;
  complexity?: number; // 0.8–1.6
}

export interface PacePrior {
  taskClass: TaskClass;
  /** Effective minutes of work per planned minute (1 = on estimate). */
  rate: number;
  kappa: number;
  observations: number;
}

export interface ForecastAssumptions {
  bufferRatio: number;
  setupMin: number;
  populationPriorNote: string;
  dominantRisk: string;
  confidence: "low" | "medium" | "high";
  sampleSessions: number;
}

export interface CompletionForecast {
  remainingHoursP50: number;
  remainingHoursP80: number;
  finishDateP50: string | null;
  finishDateP80: string | null;
  assumptions: ForecastAssumptions;
  byClass: Record<string, { p50Min: number; p80Min: number }>;
}

const DEFAULT_RATES: Record<TaskClass, number> = {
  read: 1.15,
  practice: 1.35,
  retrieve: 1.1,
  review: 1.05,
  project: 1.45,
};

export function classifyUnit(title: string): TaskClass {
  const t = title.toLowerCase();
  if (/practice|question|exercise|تمرين|سؤال|مسائل/.test(t)) return "practice";
  if (/review|recall|مراجعة|استرجاع/.test(t)) return "review";
  if (/quiz|retrieve|اختبار/.test(t)) return "retrieve";
  if (/project|مشروع|essay|مقال/.test(t)) return "project";
  return "read";
}

/** T_u = C + E + P + R + V approximated from consume + class multipliers. */
export function unitWorkMinutes(u: UnitEstimateInput, pace?: PacePrior): { p50: number; p80: number } {
  const complexity = u.complexity ?? 1;
  const rate = pace?.rate ?? DEFAULT_RATES[u.taskClass];
  let encode = 0;
  let practice = 0;
  let retrieval = 0;
  let review = 0;
  switch (u.taskClass) {
    case "read":
      encode = u.consumeMin * 0.35;
      retrieval = u.consumeMin * 0.2;
      review = u.consumeMin * 0.1;
      break;
    case "practice":
      practice = u.consumeMin * 0.5;
      retrieval = u.consumeMin * 0.15;
      break;
    case "retrieve":
      retrieval = u.consumeMin * 0.7;
      review = u.consumeMin * 0.15;
      break;
    case "review":
      review = u.consumeMin * 0.8;
      break;
    case "project":
      practice = u.consumeMin * 0.6;
      encode = u.consumeMin * 0.25;
      break;
  }
  const raw = (u.consumeMin + encode + practice + retrieval + review) * complexity * rate;
  const p50 = Math.round(raw);
  const p80 = Math.round(raw * 1.22);
  return { p50, p80 };
}

/** Bayesian shrinkage for pace: r_new = (κ r_prior + n r_obs) / (κ + n). */
export function updatePace(prior: PacePrior, observedRate: number): PacePrior {
  const n = prior.observations + 1;
  const rate = (prior.kappa * prior.rate + prior.observations * observedRate + observedRate) /
    (prior.kappa + n);
  return {
    taskClass: prior.taskClass,
    rate: Number(rate.toFixed(3)),
    kappa: prior.kappa,
    observations: n,
  };
}

export function forecastCompletion(input: {
  units: UnitEstimateInput[];
  paces?: PacePrior[];
  maxDailyMin: number;
  bufferRatio?: number;
  deadline?: string | null;
  sampleSessions?: number;
  now?: Date;
}): CompletionForecast {
  const bufferRatio = input.bufferRatio ?? 0.18;
  const setupMin = Math.max(5, Math.round(input.units.length * 2));
  const paces = new Map((input.paces ?? []).map((p) => [p.taskClass, p]));
  const byClass: Record<string, { p50Min: number; p80Min: number }> = {};

  let p50 = setupMin;
  let p80 = setupMin;
  for (const u of input.units) {
    const est = unitWorkMinutes(u, paces.get(u.taskClass));
    p50 += est.p50;
    p80 += est.p80;
    const slot = byClass[u.taskClass] ?? { p50Min: 0, p80Min: 0 };
    slot.p50Min += est.p50;
    slot.p80Min += est.p80;
    byClass[u.taskClass] = slot;
  }

  p50 = Math.round(p50 * (1 + bufferRatio));
  p80 = Math.round(p80 * (1 + bufferRatio * 1.15));

  const usable = Math.max(25, Math.round(input.maxDailyMin * (1 - bufferRatio)));
  const now = input.now ?? new Date();
  const daysP50 = Math.ceil(p50 / usable);
  const daysP80 = Math.ceil(p80 / usable);
  const finish = (days: number) => {
    const d = new Date(now);
    d.setDate(d.getDate() + days);
    return d.toISOString().slice(0, 10);
  };

  const samples = input.sampleSessions ?? 0;
  const confidence = samples >= 5 ? "high" : samples >= 1 ? "medium" : "low";
  const dominant = Object.entries(byClass).sort((a, b) => b[1].p80Min - a[1].p80Min)[0]?.[0] ??
    "practice";

  return {
    remainingHoursP50: Number((p50 / 60).toFixed(1)),
    remainingHoursP80: Number((p80 / 60).toFixed(1)),
    finishDateP50: finish(daysP50),
    finishDateP80: finish(daysP80),
    assumptions: {
      bufferRatio,
      setupMin,
      populationPriorNote: "Cold-start uses conservative population priors until personal samples arrive.",
      dominantRisk: `Uncertainty highest in ${dominant} work.`,
      confidence,
      sampleSessions: samples,
    },
    byClass,
  };
}

/** Transparent MVP task ranking score (hard constraints applied by caller). */
export function scoreTask(input: {
  goalImportance: number;
  prerequisiteCentrality: number;
  forgettingRisk: number;
  uncertaintyReduction: number;
  deadlineRisk: number;
  masteryGainPerMin: number;
  switchCost: number;
  overloadRisk: number;
}): number {
  return (
    1.2 * input.goalImportance +
    1.0 * input.prerequisiteCentrality +
    1.1 * input.forgettingRisk +
    0.9 * input.uncertaintyReduction +
    1.3 * input.deadlineRisk +
    1.4 * input.masteryGainPerMin -
    0.8 * input.switchCost -
    1.0 * input.overloadRisk
  );
}
