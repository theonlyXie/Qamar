enum StepKind { chips, text, number, multi }

class StepOption {
  final String ar;
  final String en;
  final Object value; // String or double, mirrors the prototype's o.v
  const StepOption({required this.ar, required this.en, required this.value});

  String label(bool isAr) => isAr ? ar : en;
}

class OnboardingStep {
  final String id;
  final StepKind kind;
  final String askAr;
  final String askEn;
  final List<StepOption> options;
  const OnboardingStep({
    required this.id,
    required this.kind,
    required this.askAr,
    required this.askEn,
    this.options = const [],
  });
}

/// Ported 1:1 from the prototype's STEPS array (S06 age gate → S07 consent →
/// name → body numbers → goal → activity → food exclusions → S-safety gate).
final List<OnboardingStep> kOnboardingSteps = [
  OnboardingStep(
    id: 'age',
    kind: StepKind.chips,
    askAr: 'أهلاً 👋 أنا قمر. هساعدك تاكل أحسن من غير رجيم قاسي. سؤال أول للأهلية: عندك ١٨ سنة أو أكتر؟',
    askEn: 'Hi, I’m Qamar. I’ll help you eat better without a punishing diet. First, an eligibility question: are you 18 or older?',
    options: const [
      StepOption(ar: 'أيوه، ١٨ أو أكتر', en: 'Yes, 18 or older', value: 'adult'),
      StepOption(ar: 'أقل من ١٨', en: 'Under 18', value: 'minor'),
    ],
  ),
  OnboardingStep(
    id: 'consent',
    kind: StepKind.chips,
    askAr:
        'تمام. الخدمة دي إرشاد عام بالذكاء الاصطناعي ومش استشارة طبية. لازم أعالج بياناتك اللي بتدخلها عشان أحسب الهدف — ودي حاجة أساسية. وفي اختيار تاني منفصل: تسمح نستخدم محادثاتك لتحسين قمر؟',
    askEn:
        'Good. This is AI-powered general guidance, not medical advice. Processing the data you enter is required to calculate your target. Separately and optionally: may we use your conversations to improve Qamar?',
    options: const [
      StepOption(ar: 'موافق على الأساسي بس', en: 'Agree to the required only', value: 'yes'),
      StepOption(ar: 'موافق + ساعد في التحسين', en: 'Agree + help improve', value: 'yes_improve'),
      StepOption(ar: 'عايز أعرف أكتر', en: 'Tell me more', value: 'more'),
    ],
  ),
  OnboardingStep(
    id: 'name',
    kind: StepKind.text,
    askAr: 'تمام. أناديك بإيه؟ (تقدر تتخطى)',
    askEn: 'Great. What should I call you? (you can skip)',
  ),
  OnboardingStep(
    id: 'body',
    kind: StepKind.number,
    askAr: 'محتاج 3 أرقام بس عشان أحسب هدف واقعي: السن، الطول، والوزن الحالي.',
    askEn: 'I need just three numbers for a realistic target: age, height and current weight.',
  ),
  OnboardingStep(
    id: 'goal',
    kind: StepKind.chips,
    askAr: 'هدفك إيه دلوقتي؟',
    askEn: 'What’s your goal right now?',
    options: const [
      StepOption(ar: 'أخس بهدوء', en: 'Lose slowly', value: 'lose'),
      StepOption(ar: 'أثبّت وزني', en: 'Maintain', value: 'maintain'),
      StepOption(ar: 'أزيد عضل', en: 'Build muscle', value: 'gain'),
    ],
  ),
  OnboardingStep(
    id: 'activity',
    kind: StepKind.chips,
    askAr: 'يومك عامل إزاي؟ اختار الأقرب.',
    askEn: 'How does your day usually look? Pick the closest.',
    options: const [
      StepOption(ar: 'قاعد أغلب اليوم', en: 'Mostly sitting', value: 1.35),
      StepOption(ar: 'بتحرك شوية', en: 'Some walking', value: 1.5),
      StepOption(ar: 'شغل حركة أو تمرين', en: 'Active or training', value: 1.65),
    ],
  ),
  OnboardingStep(
    id: 'food',
    kind: StepKind.multi,
    askAr: 'في حاجة مينفعش أقترحها عليك؟ اختار اللي ينطبق.',
    askEn: 'Anything I should never suggest? Pick all that apply.',
    options: const [
      StepOption(ar: 'مفيش', en: 'Nothing', value: 'none'),
      StepOption(ar: 'حساسية مكسرات', en: 'Nut allergy', value: 'nuts'),
      StepOption(ar: 'مش باكل لحوم', en: 'No red meat', value: 'meat'),
      StepOption(ar: 'لاكتوز', en: 'Lactose', value: 'lactose'),
      StepOption(ar: 'ميزانية محدودة', en: 'Tight budget', value: 'budget'),
    ],
  ),
  OnboardingStep(
    id: 'safety',
    kind: StepKind.chips,
    askAr: 'آخر سؤال للأمان: في أي حالة من دول؟',
    askEn: 'One last safety check: does any of these apply?',
    options: const [
      StepOption(ar: 'ولا واحدة', en: 'None of these', value: 'none'),
      StepOption(ar: 'حمل أو رضاعة', en: 'Pregnant or breastfeeding', value: 'preg'),
      StepOption(ar: 'حالة مزمنة تحت علاج', en: 'Chronic condition under care', value: 'chronic'),
    ],
  ),
];
