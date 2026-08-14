/// The day's suggested meals.
///
/// Lives here rather than inside the Plan screen because the Today screen and
/// the orb both need it — the orb has to be able to explain a meal, portions
/// and all, without the user opening the Plan page.

/// One component of a planned meal. The plan is only actionable if it says how
/// much of each thing to eat — a bare "620 kcal" tells you the answer without
/// telling you what to put on the plate.
typedef PlanPortion = ({String ar, String en, String amountAr, String amountEn, int kcal});

typedef PlanMeal = ({
  /// Identifies the slot so a swap toggles only this meal. A single shared
  /// flag used to drive all three buttons, so every swap changed lunch.
  String id,
  String slotAr,
  String slotEn,
  String nameAr,
  String nameEn,
  String noteAr,
  String noteEn,
  List<PlanPortion> portions,
});

/// Meal totals are summed from the portions rather than written down
/// separately, so the headline number can never drift from the breakdown —
/// including when the lunch swap drops the rice.
int mealKcal(PlanMeal m) => m.portions.fold(0, (sum, p) => sum + p.kcal);

const _breakfast = (
  id: 'breakfast',
  slotAr: 'فطار',
  slotEn: 'Breakfast',
  nameAr: 'فول + عيش بلدي + خضار',
  nameEn: 'Foul + baladi bread + vegetables',
  noteAr: 'بروتين ٢٤ جم',
  noteEn: '24 g protein',
  portions: <PlanPortion>[
    (ar: 'فول مدمس', en: 'Foul medames', amountAr: '١٥٠ جم', amountEn: '150 g', kcal: 180),
    (ar: 'عيش بلدي', en: 'Baladi bread', amountAr: 'رغيف ونص', amountEn: '1½ loaves', kcal: 220),
    (ar: 'طماطم وخيار', en: 'Tomato & cucumber', amountAr: '١٠٠ جم', amountEn: '100 g', kcal: 30),
    (ar: 'زيت زيتون', en: 'Olive oil', amountAr: 'معلقة صغيرة', amountEn: '1 tsp', kcal: 50),
  ],
);

const _breakfastAlt = (
  id: 'breakfast',
  slotAr: 'فطار',
  slotEn: 'Breakfast',
  nameAr: 'بيض + عيش سن + جبنة قريش',
  nameEn: 'Eggs + wholemeal bread + cottage cheese',
  noteAr: 'بديل بروتين أعلى',
  noteEn: 'Higher-protein alternative',
  portions: <PlanPortion>[
    (ar: 'بيض مسلوق', en: 'Boiled eggs', amountAr: '٣ بيضات', amountEn: '3 eggs', kcal: 210),
    (ar: 'عيش سن', en: 'Wholemeal bread', amountAr: 'رغيف', amountEn: '1 loaf', kcal: 150),
    (ar: 'جبنة قريش', en: 'Cottage cheese', amountAr: '١٠٠ جم', amountEn: '100 g', kcal: 90),
    (ar: 'خضار', en: 'Vegetables', amountAr: '١٠٠ جم', amountEn: '100 g', kcal: 30),
  ],
);

const _lunchWithRice = (
  id: 'lunch',
  slotAr: 'غدا',
  slotEn: 'Lunch',
  nameAr: 'فراخ مشوية + رز + سلطة',
  nameEn: 'Grilled chicken + rice + salad',
  noteAr: 'بديل متاح',
  noteEn: 'Swap available',
  portions: <PlanPortion>[
    (ar: 'صدور فراخ مشوية', en: 'Grilled chicken breast', amountAr: '١٥٠ جم', amountEn: '150 g', kcal: 250),
    (ar: 'رز أبيض مطبوخ', en: 'Cooked white rice', amountAr: '١٥٠ جم', amountEn: '150 g', kcal: 200),
    (ar: 'سلطة خضرا', en: 'Green salad', amountAr: '١٥٠ جم', amountEn: '150 g', kcal: 45),
    (ar: 'زيت زيتون', en: 'Olive oil', amountAr: 'معلقة كبيرة', amountEn: '1 tbsp', kcal: 125),
  ],
);

const _lunchNoRice = (
  id: 'lunch',
  slotAr: 'غدا',
  slotEn: 'Lunch',
  nameAr: 'فراخ مشوية + سلطة',
  nameEn: 'Grilled chicken + salad',
  noteAr: 'من غير نشويات — أخف ١٧٠ سعر',
  noteEn: 'No starch — 170 kcal lighter',
  portions: <PlanPortion>[
    (ar: 'صدور فراخ مشوية', en: 'Grilled chicken breast', amountAr: '١٨٠ جم', amountEn: '180 g', kcal: 300),
    (ar: 'سلطة خضرا', en: 'Green salad', amountAr: '٢٠٠ جم', amountEn: '200 g', kcal: 60),
    (ar: 'زيت زيتون', en: 'Olive oil', amountAr: 'معلقة صغيرة', amountEn: '1 tsp', kcal: 50),
    (ar: 'عيش سن', en: 'Wholemeal bread', amountAr: 'نص رغيف', amountEn: '½ loaf', kcal: 40),
  ],
);

const _dinner = (
  id: 'dinner',
  slotAr: 'عشا',
  slotEn: 'Dinner',
  nameAr: 'زبادي + فاكهة + شوفان',
  nameEn: 'Yogurt + fruit + oats',
  noteAr: 'خفيف قبل النوم',
  noteEn: 'Light before sleep',
  portions: <PlanPortion>[
    (ar: 'زبادي يوناني', en: 'Greek yogurt', amountAr: '٢٠٠ جم', amountEn: '200 g', kcal: 130),
    (ar: 'شوفان', en: 'Oats', amountAr: '٤٠ جم', amountEn: '40 g', kcal: 150),
    (ar: 'موزة', en: 'Banana', amountAr: 'واحدة متوسطة', amountEn: '1 medium', kcal: 100),
  ],
);

const _dinnerAlt = (
  id: 'dinner',
  slotAr: 'عشا',
  slotEn: 'Dinner',
  nameAr: 'تونة + سلطة + عيش سن',
  nameEn: 'Tuna + salad + wholemeal bread',
  noteAr: 'بديل من غير ألبان',
  noteEn: 'Dairy-free alternative',
  portions: <PlanPortion>[
    (ar: 'تونة في الماء', en: 'Tuna in water', amountAr: 'علبة ١٢٠ جم', amountEn: '120 g tin', kcal: 130),
    (ar: 'سلطة خضرا', en: 'Green salad', amountAr: '١٥٠ جم', amountEn: '150 g', kcal: 45),
    (ar: 'عيش سن', en: 'Wholemeal bread', amountAr: 'نص رغيف', amountEn: '½ loaf', kcal: 75),
    (ar: 'زيت زيتون', en: 'Olive oil', amountAr: 'معلقة صغيرة', amountEn: '1 tsp', kcal: 50),
  ],
);

/// Each slot's default and its alternative, so a swap is a per-slot choice.
const kPlanSlots = <(PlanMeal, PlanMeal)>[
  (_breakfast, _breakfastAlt),
  (_lunchWithRice, _lunchNoRice),
  (_dinner, _dinnerAlt),
];

/// The slot the Today screen surfaces as "next".
const kNextMealSlot = 1;
