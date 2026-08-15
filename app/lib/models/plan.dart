/// The shape of the day's suggested meals.
///
/// Only the shape: the meals themselves are generated per person by the AI
/// gateway (`plan/generate`) from their target and exclusions, and arrive
/// through [DayPlan]. This file used to also hold a fixed three-meal menu
/// that every user saw regardless of their numbers or their allergies — a
/// picture of a plan rather than a plan. It was deleted rather than kept as
/// a fallback, because a fallback here is indistinguishable from the real
/// thing to the person reading it.
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


