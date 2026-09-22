import 'dart:math' as math;

import 'meal.dart';
import 'nudge.dart';

/// Qamar's words after a log, and Today's sentence once something is logged
/// (O3): one sentence about this meal against this day.
///
/// "Fixed points keep the economy honest; variable words keep the reward
/// alive." The words vary because the day varies, never because of dice:
/// no random phrasing, no model call, no delay, and no question spent. The
/// same day always reads the same way. No sentence here mentions Su, points
/// or earning; the wallet counts, the companion talks.
///
/// The gateway's meal `note` is not used here. It is the reading's caveat
/// ("adjust the amounts before you confirm", "I assumed a medium plate"), shown
/// with the proposal before the confirm, which is where it is true.

/// The day as it stands, with the meal just logged included.
class DayNumbers {
  /// Eaten today, kcal.
  final int kcal;
  final int targetKcal;

  /// Eaten today, grams of protein.
  final int protein;
  final int targetProtein;

  /// The clock's hour now, 0 to 23.
  final int hour;

  /// The next planned meal later today that has not been eaten, when a plan
  /// exists: its name in both languages and its kcal.
  final ({String nameAr, String nameEn, int kcal})? next;

  /// The meals still ahead today by the clock, not yet eaten, in order.
  final List<MealSlot> ahead;

  const DayNumbers({
    required this.kcal,
    required this.targetKcal,
    required this.protein,
    required this.targetProtein,
    required this.hour,
    this.next,
    this.ahead = const [],
  });

  /// Room left today. Negative past the target.
  int get left => targetKcal - kcal;

  /// How close counts as "at the target": 5% of it, and never under 100 kcal.
  int get tolerance => math.max(100, (targetKcal * 0.05).round());
}

/// Which way the day reads. The first that applies, in this order.
enum DayShape {
  /// Past the target by more than the tolerance. Said without blame.
  over,

  /// Within the tolerance of the target.
  atTarget,

  /// The day's protein is reached (for a reply: reached by this meal).
  proteinDone,

  /// Afternoon or later, under half the protein, and room left.
  proteinShort,

  /// A planned meal is still ahead today and fits what is left.
  nextFits,

  /// A planned meal is still ahead today and is more than what is left.
  nextLarge,

  /// Anything else: the room left, and what it is for.
  room,
}

DayShape shapeOf(DayNumbers d, {LoggedMeal? meal}) {
  final t = d.tolerance;
  if (d.left < -t) return DayShape.over;
  if (d.left.abs() <= t) return DayShape.atTarget;
  final reached = d.targetProtein > 0 && d.protein >= d.targetProtein;
  final reachedNow = meal == null ? reached : reached && d.protein - meal.p < d.targetProtein;
  if (reachedNow) return DayShape.proteinDone;
  if (d.hour >= 15 && d.targetProtein > 0 && d.protein * 2 < d.targetProtein) return DayShape.proteinShort;
  final next = d.next;
  if (next != null) return next.kcal <= d.left + t ? DayShape.nextFits : DayShape.nextLarge;
  return DayShape.room;
}

/// Qamar's reply to a meal just logged: its kcal, then what it does to the day.
String replyFor(LoggedMeal meal, DayNumbers day, {required bool ar, required String Function(String) iso}) {
  // Arabic draws numbers the app's way (Eastern digits, bidi-isolated).
  String n(int v) => ar ? iso('$v') : '$v';
  final m = n(meal.kcal);
  final left = n(day.left);
  final over = n(-day.left);
  final gap = n(math.max(0, day.targetProtein - day.protein));
  final next = day.next;
  final name = next == null ? '' : (ar ? next.nameAr : next.nameEn);
  final nextK = next == null ? '' : n(next.kcal);
  return switch (shapeOf(day, meal: meal)) {
    DayShape.over => ar
        ? '$m سعرة، وكده النهارده عدّى هدفك بحوالي $over — مفيش حاجة تتعوّض، وبكرة يوم جديد.'
        : '$m kcal, which takes today about $over past your target — nothing to make up, tomorrow starts fresh.',
    DayShape.atTarget => ar ? '$m سعرة، وكده النهارده وصل لهدفك بالظبط.' : '$m kcal, and that brings today right to your target.',
    DayShape.proteinDone => ar
        ? '$m سعرة، وكده بروتين النهارده كمل، وفاضل $left سعرة.'
        : '$m kcal, and with it today’s protein is done, with $left kcal left.',
    DayShape.proteinShort => ar
        ? '$m سعرة؛ فاضل $left سعرة، والنهارده لسه محتاج حوالي $gap جم بروتين.'
        : '$m kcal; $left kcal left, and today still wants about $gap g of protein.',
    DayShape.nextFits => ar
        ? '$m سعرة؛ فاضل $left، يعني $name اللي في الخطة ($nextK سعرة) لسه مناسب.'
        : '$m kcal; $left left, so the plan’s $name ($nextK kcal) still fits.',
    DayShape.nextLarge => ar
        ? '$m سعرة؛ فاضل $left، يعني $name اللي في الخطة محتاج طبق أصغر.'
        : '$m kcal; $left left, so the plan’s $name would want a smaller plate.',
    DayShape.room => '$m ${ar ? 'سعرة؛' : 'kcal;'} ${_room(day, left, ar: ar, lower: true)}',
  };
}

/// Today's sentence once something is logged: the same reading of the day,
/// without a particular meal.
String dayLineFor(DayNumbers day, {required bool ar, required String Function(String) iso}) {
  // Arabic draws numbers the app's way (Eastern digits, bidi-isolated).
  String n(int v) => ar ? iso('$v') : '$v';
  final left = n(day.left);
  final over = n(-day.left);
  final gap = n(math.max(0, day.targetProtein - day.protein));
  final next = day.next;
  final name = next == null ? '' : (ar ? next.nameAr : next.nameEn);
  final nextK = next == null ? '' : n(next.kcal);
  return switch (shapeOf(day)) {
    DayShape.over => ar
        ? 'النهارده عدّى هدفك بحوالي $over سعرة — مفيش حاجة تتعوّض، وبكرة يوم جديد.'
        : 'Today is about $over kcal past your target — nothing to make up, tomorrow starts fresh.',
    DayShape.atTarget => ar ? 'النهارده وصل لهدفك بالظبط.' : 'Today is right at your target.',
    DayShape.proteinDone => ar ? 'بروتين النهارده كمل، وفاضل $left سعرة.' : 'Today’s protein is done, with $left kcal left.',
    DayShape.proteinShort => ar
        ? 'فاضل $left سعرة، والنهارده لسه محتاج حوالي $gap جم بروتين.'
        : '$left kcal left, and today still wants about $gap g of protein.',
    DayShape.nextFits => ar
        ? 'فاضل $left سعرة، يعني $name اللي في الخطة ($nextK سعرة) لسه مناسب.'
        : '$left kcal left, so the plan’s $name ($nextK kcal) still fits.',
    DayShape.nextLarge => ar
        ? 'فاضل $left سعرة، يعني $name اللي في الخطة محتاج طبق أصغر.'
        : '$left kcal left, so the plan’s $name would want a smaller plate.',
    DayShape.room => _room(day, left, ar: ar),
  };
}

String _slot(MealSlot slot, bool ar) => switch (slot) {
      MealSlot.breakfast => ar ? 'فطار' : 'breakfast',
      MealSlot.lunch => ar ? 'غدا' : 'lunch',
      MealSlot.dinner => ar ? 'عشا' : 'dinner',
      MealSlot.iftar => ar ? 'إفطار' : 'iftar',
      MealSlot.suhoor => ar ? 'سحور' : 'suhoor',
    };

/// The room left, said as what it is for: the meals still ahead today, or
/// something light tonight if the day's meals are done. [lower] starts it
/// in lower case, after the meal's kcal.
String _room(DayNumbers d, String left, {required bool ar, bool lower = false}) {
  if (d.ahead.isEmpty) {
    if (ar) return 'فاضل حوالي $left سعرة الليلة — حاجة خفيفة تنفع لو حابب.';
    return '${lower ? 'about' : 'About'} $left kcal left tonight — something light fits, if you want it.';
  }
  if (d.ahead.length == 1) {
    final slot = _slot(d.ahead.single, ar);
    final full = d.left * 4 >= d.targetKcal;
    if (ar) return full ? 'فاضل $left سعرة — فيه مكان ل$slot كامل.' : 'فاضل $left سعرة — فيه مكان ل$slot خفيف.';
    return '$left kcal left — room for a ${full ? 'full' : 'light'} $slot.';
  }
  final first = _slot(d.ahead[0], ar), second = _slot(d.ahead[1], ar);
  if (ar) return 'فاضل $left سعرة، ولسه قدامك $first و$second.';
  return '$left kcal left, with $first and $second still ahead.';
}
