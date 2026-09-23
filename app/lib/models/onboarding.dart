enum StepKind { chips, text, number, multi, date }

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

  /// The same question asked on the general-guidance route, where its usual
  /// reason (the calorie maths) does not apply. Null: asked the same way.
  final String? generalAr;
  final String? generalEn;

  const OnboardingStep({
    required this.id,
    required this.kind,
    required this.askAr,
    required this.askEn,
    this.options = const [],
    this.generalAr,
    this.generalEn,
  });

  String ask(bool isAr, {bool general = false}) =>
      general && generalAr != null ? (isAr ? generalAr! : generalEn!) : (isAr ? askAr : askEn);
}

/// Consent → safety → goal → date of birth → sex → body numbers → activity
/// → food exclusions: only what a target needs, and nothing that could be
/// left for later.
///
/// Consent comes before any personal data. The safety question comes next, so
/// an answer that rules out a calorie target changes the rest of the
/// conversation instead of ending it (see [kGeneralGuidanceSkips]). The goal
/// comes before the numbers, so the questions after it have a reason. The 18+
/// gate is the date step, and it comes before any target on either route.
///
/// The name is not a step: it is optional, so it is asked once the target is
/// on screen (AppState's reveal), beside "Let's start", and costs nothing to
/// leave (the spec's S08: "ask after first value").
final List<OnboardingStep> kOnboardingSteps = [
  const OnboardingStep(
    id: 'consent',
    kind: StepKind.chips,
    askAr:
        'أهلاً، أنا قمر. هساعدك تاكل أحسن من غير رجيم قاسي.\n\nأنا إرشاد عام بالذكاء الاصطناعي، مش دكتور، وهستخدم إجاباتك عشان أحسب هدفك. وكمان ممكن تساعدنا نحسّن قمر: نشوف إزاي التطبيق بيتستخدم، من غير أكلك ولا وزنك ولا اسمك.',
    askEn:
        'Hi, I’m Qamar. I’ll help you eat better, without a harsh diet.\n\nI’m an AI guide, not a doctor, and I use your answers to set your target. You can also help improve Qamar: we’d see how the app is used, never your food, weight or name.',
    options: [
      StepOption(ar: 'موافق', en: 'Agree', value: 'yes'),
      StepOption(ar: 'موافق + ساعد في التحسين', en: 'Agree + help improve', value: 'yes_improve'),
      StepOption(ar: 'عايز أعرف أكتر', en: 'Tell me more', value: 'more'),
    ],
  ),
  const OnboardingStep(
    id: 'safety',
    kind: StepKind.chips,
    askAr: 'سؤال أمان واحد: في حاجة من دول بتنطبق عليك؟',
    askEn: 'One safety question: does any of these apply to you?',
    options: [
      StepOption(ar: 'ولا واحدة', en: 'None of these', value: 'none'),
      StepOption(ar: 'حامل', en: 'Pregnant', value: 'pregnant'),
      StepOption(ar: 'برضّع', en: 'Breastfeeding', value: 'breastfeeding'),
      StepOption(ar: 'مرض مزمن', en: 'Chronic illness', value: 'chronic'),
    ],
  ),
  const OnboardingStep(
    id: 'goal',
    kind: StepKind.chips,
    askAr: 'هدفك إيه؟',
    askEn: 'What’s your goal?',
    options: [
      StepOption(ar: 'أخس بهدوء', en: 'Lose slowly', value: 'lose'),
      StepOption(ar: 'أثبّت وزني', en: 'Maintain', value: 'maintain'),
      StepOption(ar: 'أزيد عضل', en: 'Build muscle', value: 'gain'),
    ],
  ),
  const OnboardingStep(
    id: 'dob',
    kind: StepKind.date,
    askAr: 'اتولدت إمتى؟ قمر للبالغين، والسن بيفرق في هدفك.',
    askEn: 'When were you born? Qamar is for adults, and age shapes your target.',
    generalAr: 'اتولدت إمتى؟ قمر للبالغين بس.',
    generalEn: 'When were you born? Qamar is for adults only.',
  ),
  const OnboardingStep(
    id: 'gender',
    kind: StepKind.chips,
    askAr: 'ذكر ولا أنثى؟ ده بيفرق في السعرات.',
    askEn: 'Male or female? It changes the calories.',
    options: [
      StepOption(ar: 'ذكر', en: 'Male', value: 'male'),
      StepOption(ar: 'أنثى', en: 'Female', value: 'female'),
    ],
  ),
  const OnboardingStep(
    id: 'body',
    kind: StepKind.number,
    askAr: 'طولك ووزنك كام؟',
    askEn: 'What’s your height and weight?',
  ),
  const OnboardingStep(
    id: 'activity',
    kind: StepKind.chips,
    askAr: 'يومك عامل إزاي؟',
    askEn: 'What’s a usual day like?',
    options: [
      StepOption(ar: 'قاعد أغلب اليوم', en: 'Mostly sitting', value: 1.35),
      StepOption(ar: 'بتحرك شوية', en: 'Some walking', value: 1.5),
      StepOption(ar: 'شغل حركة أو تمرين', en: 'Active or training', value: 1.65),
    ],
  ),
  const OnboardingStep(
    id: 'food',
    kind: StepKind.multi,
    askAr: 'في حاجة مينفعش أقترحها عليك؟ اختار اللي ينطبق.',
    askEn: 'Anything I should never suggest? Pick all that apply.',
    options: [
      StepOption(ar: 'مفيش', en: 'Nothing', value: 'none'),
      StepOption(ar: 'حساسية مكسرات', en: 'Nut allergy', value: 'nuts'),
      StepOption(ar: 'مش باكل لحوم', en: 'No red meat', value: 'meat'),
      StepOption(ar: 'لاكتوز', en: 'Lactose', value: 'lactose'),
      StepOption(ar: 'ميزانية محدودة', en: 'Tight budget', value: 'budget'),
    ],
  ),
];

/// The questions that exist only to calculate a calorie target. On the
/// general-guidance route (a safety answer that rules a target out) they are
/// not asked: the answers would feed a number Qamar will not give.
const Set<String> kGeneralGuidanceSkips = {'goal', 'gender', 'body', 'activity'};
