// What Qamar is allowed to talk about, and what it must refuse.
//
// A general model will cheerfully answer anything. This product is a nutrition
// and training assistant for adults, and everything outside that — medicine,
// mental health, and the whole rest of the world — has to be handed back
// rather than guessed at. The guard runs *before* the model is called, so an
// out-of-scope question costs nothing and cannot be talked around by the
// question itself.

export type Domain = "nutrition" | "training";

export type ScopeVerdict =
  | { allowed: true; domain: Domain }
  | { allowed: false; reason: RefusalReason };

export type RefusalReason =
  | "self_harm"
  | "severe_symptom"
  | "medical"
  | "eating_disorder"
  | "pregnancy"
  | "minor"
  | "off_topic"
  | "prompt_injection";

/**
 * Someone describing a crisis. Checked before everything else, including the
 * injection guard: if a message contains both an override attempt and this,
 * the person matters more than the prompt hygiene, and the outcome here is a
 * refusal plus an escalation either way so there is nothing to exploit.
 *
 * Kept separate from severe_symptom because one message needs an ambulance and
 * the other needs a human, and a single blended sentence serves neither.
 */
const SELF_HARM = [
  "kill myself", "want to die", "end my life", "suicidal", "suicide",
  "hurt myself", "self harm", "self-harm", "no reason to live",
  "عايز أموت", "عايزة أموت", "أنتحر", "انتحار", "أأذي نفسي", "مش عايز أعيش",
];

/** Symptoms that need care now, not a nutrition answer. */
const SEVERE_SYMPTOM = [
  "chest pain", "pain in my chest", "chest tightness",
  "can't breathe", "cannot breathe", "cant breathe", "trouble breathing",
  "shortness of breath", "passed out", "fainted", "fainting", "blacked out",
  "vomiting blood", "coughing blood", "blood in my stool", "blood in stool",
  "blood in my urine", "severe pain", "unbearable pain", "slurred speech",
  "seizure", "numbness on one side", "cannot stop vomiting",
  "ألم في الصدر", "وجع في صدري", "مش قادر أتنفس", "مش قادرة أتنفس",
  "ضيق في التنفس", "أغمى عليا", "إغماء", "بتقيأ دم", "دم في البراز",
  "دم في البول", "ألم شديد", "وجع فظيع", "تشنج", "تنميل في نص جسمي",
];

/** Matched case-insensitively against the question, Arabic and English. */
const MEDICAL = [
  // English
  "diagnose", "diagnosis", "prescribe", "prescription", "dosage", "mg of",
  "insulin", "chemotherapy", "blood pressure medication", "antibiotic",
  "is it cancer", "tumour", "tumor", "symptom of", "should i stop taking",
  "thyroid medication", "statin", "metformin", "ozempic", "semaglutide",
  // Arabic
  "تشخيص", "وصفة طبية", "جرعة", "أنسولين", "علاج كيماوي", "مضاد حيوي",
  "ورم", "سرطان", "أوقف الدواء", "دواء الضغط", "دواء السكر",
];

const EATING_DISORDER = [
  "anorexia", "bulimia", "purge", "purging", "laxative", "make myself sick",
  "starve myself", "not eating for days", "how little can i eat",
  "فقدان الشهية", "الشره العصبي", "استفرغ", "ملين", "أجوع نفسي", "بطلت أكل",
];

const PREGNANCY = [
  "pregnant", "pregnancy", "breastfeeding", "nursing mother", "trimester",
  "حامل", "الحمل", "رضاعة", "مرضعة",
];

const MINOR = [
  "my son is", "my daughter is", "for my child", "i am 15", "i am 16",
  "i am 17", "year old son", "year old daughter",
  "ابني", "بنتي", "طفلي", "عندي ١٥", "عندي ١٦", "عندي ١٧",
];

/** Attempts to talk the assistant out of its job. */
const INJECTION = [
  "ignore previous", "ignore all previous", "disregard your instructions",
  "you are now", "system prompt", "pretend you are", "jailbreak",
  "developer mode", "act as an unrestricted",
  "تجاهل التعليمات", "انت دلوقتي", "تظاهر انك",
];

/** Signals the question really is about food or training. */
const NUTRITION = [
  "eat", "food", "meal", "calorie", "kcal", "protein", "carb", "fat", "sugar",
  "diet", "breakfast", "lunch", "dinner", "snack", "portion", "recipe",
  "fibre", "fiber", "vitamin", "hydration", "water", "weight", "fasting",
  "أكل", "اكل", "وجبة", "سعرات", "سعرة", "سعر حراري", "بروتين", "كربوهيدرات",
  "دهون", "سكر", "رجيم", "دايت", "فطار", "غدا", "عشا", "وزن", "صيام", "مية",
  "ألياف", "فيتامين", "طبق", "فول", "عيش", "رز", "أكلة",
];

const TRAINING = [
  "workout", "exercise", "training", "gym", "cardio", "run", "running",
  "walk", "steps", "lift", "weights", "reps", "sets", "rest day", "recovery",
  "muscle", "strength", "stretch",
  "تمرين", "تمارين", "أتمرن", "اتمرن", "تمرن", "رياضة", "جيم", "كارديو",
  "جري", "مشي", "خطوات", "عضلات", "أوزان", "تكرارات", "راحة", "استشفاء",
  "إطالة",
];

/** Latin needles match whole words; Arabic matches as a stem. */
function matches(text: string, needle: string): boolean {
  const t = text.toLowerCase();
  const n = needle.toLowerCase();
  // Arabic is heavily prefixed and suffixed ("أتمرن" from "تمرن"), so a
  // substring is the right test there.
  if (!/^[a-z][a-z ]*$/.test(n)) return t.includes(n);
  // Whole word, allowing a plural: "workouts" must match "workout", while a
  // bare substring test would let "weight" match "weights" and read a lifting
  // question as a body-weight one. Where a word genuinely belongs to both
  // lists, the scoring in classify() decides — not the order of the check.
  const re = new RegExp(`(^|[^a-z])${n.replace(/ /g, "\\s+")}(s|es)?($|[^a-z])`, "i");
  return re.test(t);
}

function hits(text: string, needles: string[]): boolean {
  return needles.some((n) => matches(text, n));
}

function score(text: string, needles: string[]): number {
  return needles.reduce((n, needle) => n + (matches(text, needle) ? 1 : 0), 0);
}

/**
 * Decides whether a question may be answered at all, and in which domain.
 *
 * Order matters: the refusals are checked before the topic match, so
 * "what should I eat while I'm pregnant" refuses on pregnancy rather than
 * passing as a nutrition question.
 */
export function classify(question: string): ScopeVerdict {
  const q = question.trim();
  if (q.length === 0) return { allowed: false, reason: "off_topic" };

  // Urgency first. Someone in crisis or describing an emergency gets that
  // handled before any question about scope or prompt hygiene.
  if (hits(q, SELF_HARM)) return { allowed: false, reason: "self_harm" };
  if (hits(q, SEVERE_SYMPTOM)) return { allowed: false, reason: "severe_symptom" };

  if (hits(q, INJECTION)) return { allowed: false, reason: "prompt_injection" };
  if (hits(q, EATING_DISORDER)) return { allowed: false, reason: "eating_disorder" };
  if (hits(q, MEDICAL)) return { allowed: false, reason: "medical" };
  if (hits(q, PREGNANCY)) return { allowed: false, reason: "pregnancy" };
  if (hits(q, MINOR)) return { allowed: false, reason: "minor" };

  // Scored rather than first-match: "cardio before or after weights" mentions
  // both, and the domain with more evidence should win. Nutrition takes ties,
  // being the product's centre and the deeper half of the knowledge base.
  const nutrition = score(q, NUTRITION);
  const training = score(q, TRAINING);
  if (nutrition === 0 && training === 0) return { allowed: false, reason: "off_topic" };

  return { allowed: true, domain: training > nutrition ? "training" : "nutrition" };
}

/** What the user is told, in their own language. Never a bare "I can't". */
export function refusalText(reason: RefusalReason, lang: string): string {
  const ar: Record<RefusalReason, string> = {
    self_harm:
      "أنا مش المكان الصح للكلام ده، ومش هتظاهر بالعكس. لو حاسس بكده دلوقتي، اتكلم مع حد بتثق فيه أو دكتور. ولو في خطر فوري، كلّم الطوارئ أو روح أقرب مستشفى. أنا هنا لو حبيت نتكلم عن الأكل أو التمرين وقت تاني.",
    severe_symptom:
      "الأعراض دي محتاجة دكتور دلوقتي، مش تطبيق تغذية. من فضلك دوّر على مساعدة طبية النهاردة، وفورًا لو الوضع بيسوء. أنا موجود لموضوع الأكل بعد ما تطمن.",
    medical:
      "ده سؤال طبي، وأنا مش دكتور ومينفعش أجاوب عليه. الأنسب تكلم دكتور أو صيدلي. لو عايز تسألني عن الأكل أو التمرين، أنا معاك.",
    eating_disorder:
      "أنا قلقان من السؤال ده ومش هساعد فيه. لو علاقتك بالأكل بتتعبك، ده شيء يستاهل دعم حقيقي من متخصص. أنا هنا لو حبيت نتكلم عن أكل متوازن.",
    pregnancy:
      "الحمل والرضاعة ليهم احتياجات غذائية خاصة لازم تتظبط مع دكتور أو أخصائي تغذية. مش هحسبلك أرقام في الحالة دي.",
    minor:
      "قمر للبالغين ١٨ سنة أو أكتر. تغذية الأطفال والمراهقين محتاجة متخصص، مش تطبيق.",
    off_topic:
      "أنا متخصص في الأكل والتمرين بس. اسألني عن وجبة، سعرات، أو تمرين وأنا أساعدك.",
    prompt_injection:
      "أنا قمر، ومهمتي الأكل والتمرين. تعالَ نرجع للموضوع — عايز تسأل عن إيه؟",
  };
  const en: Record<RefusalReason, string> = {
    self_harm:
      "I am not the right kind of help for this, and I am not going to pretend otherwise. Please talk to someone you trust or a doctor now. If you are in immediate danger, contact your local emergency services or go to the nearest hospital. I am here for food and training another time.",
    severe_symptom:
      "That needs a doctor now, not a nutrition app. Please get medical help today, and immediately if it is getting worse. I will be here for the food side once you are seen.",
    medical:
      "That is a medical question and I am not a doctor, so I will not answer it. A doctor or pharmacist is the right person. If you want to ask about food or training, I am here.",
    eating_disorder:
      "That question worries me and I am not going to help with it. If your relationship with food is hurting you, that deserves real support from a professional. I am here if you want to talk about eating well.",
    pregnancy:
      "Pregnancy and breastfeeding have specific nutritional needs that should be set with a doctor or dietitian. I will not calculate numbers for that.",
    minor:
      "Qamar is for adults 18 and over. Nutrition for children and teenagers needs a professional, not an app.",
    off_topic:
      "I only cover food and training. Ask me about a meal, calories, or a workout and I will help.",
    prompt_injection:
      "I am Qamar, and my job is food and training. Let us get back to it — what would you like to ask?",
  };
  return (lang === "ar" ? ar : en)[reason];
}
