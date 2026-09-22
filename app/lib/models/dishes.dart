import 'nudge.dart';
import 'profile.dart';

/// Real Egyptian dishes, as the food graph composes them, shipped with the
/// app so the first moment of value works with no backend at all (O5).
///
/// Every part names its food-graph slug (0017_egyptian_food_seed.sql) and a
/// household portion the graph defines (food_portions in 0017), and carries
/// the graph's own per-100 g numbers. Those are what
/// `qamar_nutrients_per_100g` returns: USDA FoodData Central values for a
/// single food, whose FDC id is in [DishPart.source], or values derived from
/// the recipe's ingredients for a dish. They were read from the live graph
/// on 2026-09-22. When the account is backed, the live graph's numbers
/// replace them (see [EgyptianDish.facts]); these are the fallback, never
/// the preference.
///
/// Portions are household estimates, and the card says so. This is not a
/// plan: it is one real dish, picked against the person's own target, goal
/// and exclusions and labelled as an estimate. The fixed three-meal menu
/// that plan.dart deleted stays deleted.
typedef Per100 = ({double kcal, double protein, double carbs, double fat});

class DishPart {
  /// Food-graph slug (foods.slug).
  final String slug;
  final String portionAr;
  final String portionEn;

  /// The portion's weight, from food_portions.
  final int grams;

  /// The graph's per-100 g numbers, as shipped.
  final Per100 per100;

  /// Where [per100] comes from: `usda_fdc:<fdc id>` or `derived_recipe`.
  final String source;

  const DishPart({
    required this.slug,
    required this.portionAr,
    required this.portionEn,
    required this.grams,
    required this.per100,
    required this.source,
  });
}

/// A dish's totals for its portions.
typedef DishFacts = ({int kcal, int protein, int carbs, int fat, bool live});

class EgyptianDish {
  final String id;
  final String nameAr;
  final String nameEn;
  final List<DishPart> parts;

  /// The meals it is eaten at.
  final Set<MealSlot> slots;

  /// Consultation exclusions ('nuts', 'meat', 'lactose') that rule it out.
  /// Conservative: 'meat' rules out poultry as well as red meat ("مش باكل
  /// لحوم"), and 'lactose' rules out any dairy, ghee included.
  final Set<String> ruledOutBy;

  /// Cheap to make or buy — what "tight budget" prefers.
  final bool budget;

  const EgyptianDish({
    required this.id,
    required this.nameAr,
    required this.nameEn,
    required this.parts,
    required this.slots,
    this.ruledOutBy = const {},
    required this.budget,
  });

  /// Every slug this dish reads from the graph.
  Iterable<String> get slugs => parts.map((p) => p.slug);

  /// The totals for the portions: the live graph's per-100 g numbers when
  /// [live] has every part, otherwise the shipped ones. It never mixes the
  /// two, so the numbers on the card always come from one source.
  DishFacts facts({Map<String, Per100> live = const {}}) {
    final useLive = parts.every((p) => live.containsKey(p.slug));
    var kcal = 0.0, protein = 0.0, carbs = 0.0, fat = 0.0;
    for (final p in parts) {
      final v = useLive ? live[p.slug]! : p.per100;
      final k = p.grams / 100;
      kcal += v.kcal * k;
      protein += v.protein * k;
      carbs += v.carbs * k;
      fat += v.fat * k;
    }
    return (kcal: kcal.round(), protein: protein.round(), carbs: carbs.round(), fat: fat.round(), live: useLive);
  }

  /// "Koshary (small bowl)" / "كشري (علبة صغيرة)", parts joined.
  String portions(bool isAr) => parts.map((p) => isAr ? p.portionAr : p.portionEn).join(isAr ? ' + ' : ' + ');
}

// The graph's per-100 g numbers, read 2026-09-22.
const Per100 _koshary = (kcal: 144.785, protein: 4.452, carbs: 21.752, fat: 4.422);
const Per100 _foul = (kcal: 110, protein: 7.6, carbs: 19.6, fat: 0.4);
const Per100 _baladi = (kcal: 262, protein: 9.8, carbs: 55.89, fat: 1.71);
const Per100 _taameya = (kcal: 193.954, protein: 6.346, carbs: 17.353, fat: 11.388);
const Per100 _molokhia = (kcal: 160.205, protein: 12.745, carbs: 3.948, fat: 10.497);
const Per100 _rice = (kcal: 130, protein: 2.69, carbs: 28.17, fat: 0.28);
const Per100 _tilapia = (kcal: 96, protein: 20.1, carbs: 0, fat: 1.7);
const Per100 _salad = (kcal: 49.582, protein: 0.878, carbs: 5.067, fat: 3.38);
const Per100 _chicken = (kcal: 151, protein: 30.5, carbs: 0, fat: 3.17);
const Per100 _eggs = (kcal: 155, protein: 12.6, carbs: 1.12, fat: 10.6);
const Per100 _areesh = (kcal: 72, protein: 12.39, carbs: 2.72, fat: 1.02);
const Per100 _mahshi = (kcal: 90.986, protein: 1.596, carbs: 11.887, fat: 4.317);

const _halfLoaf = DishPart(slug: 'baladi_bread', portionAr: 'نص رغيف بلدي', portionEn: 'half a baladi loaf', grams: 45, per100: _baladi, source: 'usda_fdc:174916');
const _ricePlate = DishPart(slug: 'white_rice', portionAr: 'طبق رز', portionEn: 'a plate of rice', grams: 180, per100: _rice, source: 'usda_fdc:168878');
const _saladPlate = DishPart(slug: 'salata_baladi', portionAr: 'طبق سلطة بلدي', portionEn: 'a plate of baladi salad', grams: 150, per100: _salad, source: 'derived_recipe');

const List<EgyptianDish> kEgyptianDishes = [
  EgyptianDish(
    id: 'koshary',
    nameAr: 'كشري',
    nameEn: 'Koshary',
    parts: [DishPart(slug: 'koshary', portionAr: 'علبة صغيرة', portionEn: 'a small bowl', grams: 350, per100: _koshary, source: 'derived_recipe')],
    slots: {MealSlot.lunch, MealSlot.dinner, MealSlot.iftar},
    budget: true,
  ),
  EgyptianDish(
    id: 'ful_bread',
    nameAr: 'فول بالعيش البلدي',
    nameEn: 'Ful with baladi bread',
    parts: [DishPart(slug: 'foul_beans', portionAr: 'طبق فول', portionEn: 'a plate of ful', grams: 200, per100: _foul, source: 'usda_fdc:173798'), _halfLoaf],
    slots: {MealSlot.breakfast, MealSlot.dinner, MealSlot.suhoor},
    budget: true,
  ),
  EgyptianDish(
    id: 'taameya_sandwich',
    nameAr: 'سندوتش طعمية',
    nameEn: 'A taameya sandwich',
    parts: [DishPart(slug: 'taameya', portionAr: 'تلات أقراص طعمية', portionEn: 'three taameya', grams: 75, per100: _taameya, source: 'derived_recipe'), _halfLoaf],
    slots: {MealSlot.breakfast, MealSlot.dinner},
    budget: true,
  ),
  EgyptianDish(
    id: 'molokhia_rice',
    nameAr: 'ملوخية بالفراخ ورز',
    nameEn: 'Molokhia with chicken, and rice',
    parts: [DishPart(slug: 'molokhia_dish', portionAr: 'سلطانية ملوخية بالفراخ', portionEn: 'a bowl of molokhia with chicken', grams: 250, per100: _molokhia, source: 'derived_recipe'), _ricePlate],
    slots: {MealSlot.lunch, MealSlot.iftar},
    ruledOutBy: {'meat', 'lactose'},
    budget: false,
  ),
  EgyptianDish(
    id: 'tilapia_rice_salad',
    nameAr: 'بلطي مشوي بالرز والسلطة',
    nameEn: 'Grilled tilapia with rice and salad',
    parts: [DishPart(slug: 'tilapia', portionAr: 'سمكة بلطي', portionEn: 'one tilapia', grams: 200, per100: _tilapia, source: 'usda_fdc:175176'), _ricePlate, _saladPlate],
    slots: {MealSlot.lunch, MealSlot.dinner, MealSlot.iftar},
    budget: false,
  ),
  EgyptianDish(
    id: 'chicken_salad_bread',
    nameAr: 'صدر فراخ مشوي بالسلطة البلدي',
    nameEn: 'Grilled chicken breast with baladi salad',
    parts: [DishPart(slug: 'chicken_breast', portionAr: 'صدر فراخ', portionEn: 'a chicken breast', grams: 150, per100: _chicken, source: 'usda_fdc:171534'), _saladPlate, _halfLoaf],
    slots: {MealSlot.lunch, MealSlot.dinner, MealSlot.iftar},
    ruledOutBy: {'meat'},
    budget: false,
  ),
  EgyptianDish(
    id: 'eggs_areesh_bread',
    nameAr: 'بيض وجبنة قريش بالعيش',
    nameEn: 'Eggs and areesh cheese with bread',
    parts: [
      DishPart(slug: 'eggs', portionAr: 'بيضتين', portionEn: 'two eggs', grams: 100, per100: _eggs, source: 'usda_fdc:173424'),
      DishPart(slug: 'areesh_cheese', portionAr: 'طبق قريش صغير', portionEn: 'a small plate of areesh', grams: 100, per100: _areesh, source: 'usda_fdc:173417'),
      _halfLoaf,
    ],
    slots: {MealSlot.breakfast, MealSlot.dinner, MealSlot.suhoor},
    ruledOutBy: {'lactose'},
    budget: true,
  ),
  EgyptianDish(
    id: 'mahshi_cabbage',
    nameAr: 'محشي كرنب',
    nameEn: 'Stuffed cabbage',
    parts: [DishPart(slug: 'mahshi_cabbage', portionAr: 'تمن صوابع محشي', portionEn: 'eight pieces', grams: 320, per100: _mahshi, source: 'derived_recipe')],
    slots: {MealSlot.lunch, MealSlot.iftar},
    budget: true,
  ),
];

/// How much of the day's target each meal usually carries in Egypt: lunch is
/// the main meal, and on a fasting day iftar is.
const Map<MealSlot, double> kSlotShare = {
  MealSlot.breakfast: 0.25,
  MealSlot.lunch: 0.40,
  MealSlot.dinner: 0.30,
  MealSlot.iftar: 0.45,
  MealSlot.suhoor: 0.25,
};

/// One dish for [slot], never one the person's exclusions rule out, sized to
/// their target: the dish closest to the slot's share of it, a little under
/// for "lose" and a little over for "build". "Tight budget" narrows to cheap
/// dishes when any fit. Deterministic, so the same answers give the same
/// dish. Null only when nothing is left.
EgyptianDish? pickDish({
  required int targetKcal,
  required Goal goal,
  required List<String> exclusions,
  required MealSlot slot,
  Map<String, Per100> live = const {},
  List<EgyptianDish> dishes = kEgyptianDishes,
}) {
  var candidates = dishes.where((d) => d.slots.contains(slot) && !d.ruledOutBy.any(exclusions.contains)).toList();
  if (exclusions.contains('budget')) {
    final cheap = candidates.where((d) => d.budget).toList();
    if (cheap.isNotEmpty) candidates = cheap;
  }
  if (candidates.isEmpty) return null;
  final lean = switch (goal) {
    Goal.lose => 0.85,
    Goal.gain => 1.15,
    Goal.maintain => 1.0,
  };
  final ideal = targetKcal * (kSlotShare[slot] ?? 0.3) * lean;
  EgyptianDish? best;
  var bestGap = double.infinity;
  for (final d in candidates) {
    final gap = (d.facts(live: live).kcal - ideal).abs();
    if (gap < bestGap) {
      best = d;
      bestGap = gap;
    }
  }
  return best;
}
