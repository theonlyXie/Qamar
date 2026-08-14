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
  | "medical"
  | "eating_disorder"
  | "pregnancy"
  | "minor"
  | "off_topic"
  | "prompt_injection";

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
