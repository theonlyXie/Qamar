// Qamar Teacher AI mind — learning-science operating system.
//
// One Qamar voice; specialist logic is invisible. This module encodes the
// executable principles from the Teacher AI Mind blueprint: retrieval before
// review, spacing, interleaving, worked examples, mastery evidence, and
// academic-integrity refusals. No clinical/IQ/character inference.

export type LearningMechanism =
  | "encode"
  | "retrieve"
  | "discriminate"
  | "apply"
  | "transfer"
  | "reflect";

export type LearningObject =
  | "facts"
  | "concepts"
  | "procedures"
  | "problem_solving"
  | "reading"
  | "writing"
  | "language"
  | "exam"
  | "project";

export type TutorMode =
  | "orient"
  | "explain"
  | "socratic"
  | "worked_example"
  | "coach"
  | "examiner"
  | "reflect";

export type StudyIntegrity =
  | { allowed: true; mode: TutorMode }
  | { allowed: false; reason: StudyRefuseReason; messageAr: string; messageEn: string };

export type StudyRefuseReason =
  | "self_harm"
  | "academic_cheating"
  | "clinical_inference"
  | "learning_styles"
  | "prompt_injection"
  | "off_topic";

/** Approved evidence cards — product rules with source IDs from the register. */
export interface EvidenceCard {
  id: string;
  claim: string;
  productRule: string;
  sourceIds: string[];
  strength: "A" | "B" | "C" | "D";
}

export const EVIDENCE_CANON: EvidenceCard[] = [
  {
    id: "EC-retrieve-01",
    claim: "Retrieval practice improves later retention relative to restudy.",
    productRule: "Ask the learner to produce an answer before re-showing the source.",
    sourceIds: ["S1", "S2", "S5"],
    strength: "A",
  },
  {
    id: "EC-space-01",
    claim: "Distributed practice is high utility; gaps depend on retention interval.",
    productRule: "Schedule the next review after effortful success; shorten after failure.",
    sourceIds: ["S1", "S3"],
    strength: "A",
  },
  {
    id: "EC-interleave-01",
    claim: "Interleaving can improve discrimination despite lower fluency.",
    productRule: "Mix related problem types after basic competence.",
    sourceIds: ["S4", "S12"],
    strength: "A",
  },
  {
    id: "EC-explain-01",
    claim: "Self-explanation supports integration of mental models.",
    productRule: "Prompt causal links and comparison between examples.",
    sourceIds: ["S8"],
    strength: "B",
  },
  {
    id: "EC-worked-01",
    claim: "Worked examples reduce load for early skill acquisition.",
    productRule: "Demonstrate complete reasoning for novices, then fade steps.",
    sourceIds: ["S6", "S7"],
    strength: "A",
  },
  {
    id: "EC-feedback-01",
    claim: "Useful feedback states the gap, cause, and next action; correct after error.",
    productRule: "Never leave a wrong retrieval uncorrected.",
    sourceIds: ["S10", "S11"],
    strength: "A",
  },
  {
    id: "EC-mastery-01",
    claim: "Mastery requires achievement criteria, not exposure time.",
    productRule: "Do not mark a concept complete from a timer or page open alone.",
    sourceIds: ["S14"],
    strength: "A",
  },
  {
    id: "EC-styles-01",
    claim: "Matching instruction to VAK learning styles lacks supporting evidence.",
    productRule: "Choose interaction from the learning task, never a style label.",
    sourceIds: ["S15"],
    strength: "A",
  },
  {
    id: "EC-sleep-01",
    claim: "Sleep participates in memory consolidation.",
    productRule: "Protect recovery; never reward all-night cramming with Su or praise.",
    sourceIds: ["S18"],
    strength: "A",
  },
];

const SELF_HARM = [
  "kill myself", "want to die", "suicidal", "suicide", "hurt myself", "self harm",
  "عايز أموت", "أنتحر", "انتحار", "أأذي نفسي",
];

const CHEATING = [
  "do my homework for me", "write my essay", "write my assignment",
  "complete my exam", "take the test for me", "give me the answers to the exam",
  "bypass proctor", "cheat on", "ghostwrite",
  "اعمل الواجب عني", "اكتب المقال عني", "حل الامتحان عني", "جاوب الامتحان",
  "الغش", "اكتب التسليم",
];

const CLINICAL = [
  "am i adhd", "do i have autism", "diagnose my learning", "iq test",
  "my intelligence", "learning disability diagnose",
  "عندي فرط حركة", "شخصني", "ذكاؤه", "إعاقة تعلم",
];

const LEARNING_STYLES = [
  "visual learner", "auditory learner", "kinesthetic learner", "learning style",
  "متعلم بصري", "أسلوب التعلم",
];

const INJECTION = [
  "ignore previous", "ignore all previous", "jailbreak", "you are now",
  "system prompt", "تجاهل التعليمات",
];

export function classifyStudyRequest(message: string): StudyIntegrity {
  const q = message.toLowerCase();
  if (SELF_HARM.some((p) => q.includes(p))) {
    return {
      allowed: false,
      reason: "self_harm",
      messageAr: "لو بتمر بلحظة صعبة، كلم حد ثقة أو خط المساعدة المحلي. أنا دليل مذاكرة، مش بديل للدعم الطبي.",
      messageEn: "If you are in a hard moment, talk to someone you trust or a local help line. I am a study guide, not a substitute for care.",
    };
  }
  if (INJECTION.some((p) => q.includes(p))) {
    return {
      allowed: false,
      reason: "prompt_injection",
      messageAr: "مش هقدر أغيّر تعليماتي. اسأل عن مادتك أو خطتك.",
      messageEn: "I cannot change my instructions. Ask about your subject or plan.",
    };
  }
  if (CHEATING.some((p) => q.includes(p))) {
    return {
      allowed: false,
      reason: "academic_cheating",
      messageAr: "أقدر أشرح، أدرّب، وأراجع معاك — من غير ما أكتب التسليم أو أجاوب امتحان مكانك.",
      messageEn: "I can explain, practice, and review with you — not write a submission or sit an exam for you.",
    };
  }
  if (CLINICAL.some((p) => q.includes(p))) {
    return {
      allowed: false,
      reason: "clinical_inference",
      messageAr: "مش بهحلل شخصية أو تشخيص من طريقة مذاكرتك. قولي إيه اللي عايز تتعلمه.",
      messageEn: "I do not diagnose or label you from study behaviour. Tell me what you want to learn.",
    };
  }
  if (LEARNING_STYLES.some((p) => q.includes(p))) {
    return {
      allowed: false,
      reason: "learning_styles",
      messageAr: "مفيش دليل إن أسلوب تعلم ثابت (بصري/سمعي) هو اللي يحدد الطريقة. بنختار الطريقة حسب نوع المعرفة.",
      messageEn: "There is no good evidence for fixed VAK learning styles. I choose the method from the knowledge being learned.",
    };
  }
  return { allowed: true, mode: pickTutorMode(message) };
}

export function pickTutorMode(message: string): TutorMode {
  const q = message.toLowerCase();
  // Arabic has no \b word boundaries — use substring matches for AR cues.
  if (/why|explain|ليه|لماذا|اشرح/.test(q)) return "explain";
  if (/quiz|test me|اسألني|اختبرني|retrieve/.test(q)) return "examiner";
  if (/stuck|lost|مش فاهم|تايه|confused/.test(q)) return "orient";
  if (/example|مثال|how do i|ازاي|step by step/.test(q)) return "worked_example";
  if (/plan|جدول|deadline|ميعاد|replan/.test(q)) return "coach";
  if (/wrong|غلط|mistake|خطأ|reflect/.test(q)) return "reflect";
  if (/\?|؟/.test(q)) return "socratic";
  return "coach";
}

export function methodForObject(object: LearningObject): {
  recipe: string;
  avoid: string;
  mechanism: LearningMechanism;
} {
  switch (object) {
    case "facts":
      return {
        recipe: "Short retrieval prompts; spaced production; varied cues.",
        avoid: "Rereading until familiar; recognition-only quizzes.",
        mechanism: "retrieve",
      };
    case "concepts":
      return {
        recipe: "Self-explanation; compare/contrast; examples and non-examples.",
        avoid: "Memorizing definitions without application.",
        mechanism: "encode",
      };
    case "procedures":
      return {
        recipe: "Worked example → completion problem → independent mixed practice.",
        avoid: "Random hard problems before prerequisite diagnosis.",
        mechanism: "apply",
      };
    case "problem_solving":
      return {
        recipe: "Prerequisite check; scaffold; strategy reflection; delayed novel problems.",
        avoid: "Hinting every step until mechanical following.",
        mechanism: "transfer",
      };
    case "reading":
      return {
        recipe: "Preview questions; section retrieval; memory summary; synthesis.",
        avoid: "Highlighting as proof of mastery.",
        mechanism: "retrieve",
      };
    case "writing":
      return {
        recipe: "Exemplar analysis; outline; draft; targeted feedback; revision.",
        avoid: "Ghostwriting the submission.",
        mechanism: "apply",
      };
    case "language":
      return {
        recipe: "Spaced vocabulary; sentence production; corrective feedback.",
        avoid: "Only translating word lists.",
        mechanism: "retrieve",
      };
    case "exam":
      return {
        recipe: "Blueprint map; timed mixed sets; error ledger; spaced repair.",
        avoid: "Studying only comfortable chapters.",
        mechanism: "discriminate",
      };
    case "project":
      return {
        recipe: "Milestones; subskill practice; critique; reflection.",
        avoid: "Reducing progress to time spent.",
        mechanism: "reflect",
      };
  }
}

export function inferLearningObject(title: string, finishCondition: string): LearningObject {
  const t = `${title} ${finishCondition}`.toLowerCase();
  if (/exam|امتحان|mock|اختبار/.test(t)) return "exam";
  // Reading + recall prompts are retrieval practice, not essay writing.
  if (/read|chapter|pages|فصل|اقرا|قراءة|recall|from memory/.test(t)) return "reading";
  if (/essay|مقال|كتابة|write an essay|ghostwrit/.test(t)) return "writing";
  if (/equation|solve|math|حساب|معادلة|procedure/.test(t)) return "procedures";
  if (/vocab|language|لغه|لغة/.test(t)) return "language";
  if (/project|مشروع|artifact/.test(t)) return "project";
  if (/concept|نظرية|theory|explain/.test(t)) return "concepts";
  return "concepts";
}

/** Session sequence from the blueprint — mechanism must be explicit. */
export function sessionSequence(mechanism: LearningMechanism): string[] {
  return [
    "orient",
    mechanism === "encode" ? "learn" : "retrieve",
    "learn",
    "practice",
    "check",
    "close",
  ];
}

export function evidenceForMechanism(mechanism: LearningMechanism): EvidenceCard[] {
  switch (mechanism) {
    case "retrieve":
      return EVIDENCE_CANON.filter((c) => c.id.startsWith("EC-retrieve") || c.id.startsWith("EC-space"));
    case "discriminate":
      return EVIDENCE_CANON.filter((c) => c.id.startsWith("EC-interleave"));
    case "encode":
      return EVIDENCE_CANON.filter((c) => c.id.startsWith("EC-explain") || c.id.startsWith("EC-worked"));
    case "apply":
      return EVIDENCE_CANON.filter((c) => c.id.startsWith("EC-worked") || c.id.startsWith("EC-feedback"));
    case "transfer":
      return EVIDENCE_CANON.filter((c) => c.id.startsWith("EC-feedback") || c.id.startsWith("EC-mastery"));
    case "reflect":
      return EVIDENCE_CANON.filter((c) => c.id.startsWith("EC-feedback") || c.id === "EC-sleep-01");
  }
}

export interface MissionCard {
  outcome: string;
  whyNow: string;
  mechanism: LearningMechanism;
  evidenceCriterion: string;
  durationP50Min: number;
  durationP80Min: number;
  fallback: string;
  suPreview: number;
  evidenceCardIds: string[];
}

export function buildMissionCard(input: {
  title: string;
  finishCondition: string;
  estimateMin: number;
  whyNow?: string;
  suPreview?: number;
}): MissionCard {
  const object = inferLearningObject(input.title, input.finishCondition);
  const method = methodForObject(object);
  const cards = evidenceForMechanism(method.mechanism);
  const p50 = Math.max(10, input.estimateMin);
  const p80 = Math.round(p50 * 1.25);
  return {
    outcome: input.finishCondition,
    whyNow: input.whyNow ?? "Next on the mastery path for your goal.",
    mechanism: method.mechanism,
    evidenceCriterion: "Show retrieval, explanation, or solution quality — not timer elapsed.",
    durationP50Min: p50,
    durationP80Min: p80,
    fallback: "If time collapses: one retrieval prompt + one sentence summary from memory.",
    suPreview: input.suPreview ?? 10,
    evidenceCardIds: cards.map((c) => c.id),
  };
}
