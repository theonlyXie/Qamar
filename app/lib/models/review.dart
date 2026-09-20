import 'dart:math' as math;

import '../services/repositories.dart';
import 'streak.dart';

/// One line of the card, in both languages.
typedef ReviewLine = ({String ar, String en});

/// The week, read back as the blueprint's review card: a moon per day, one
/// thing the person did not expect, one change for next week.
///
/// Everything here is arithmetic over the days that were actually logged.
/// Under three logged days there is no pattern to claim, and the card says
/// so instead of asserting one. No weight is ever on the card; calories only
/// when the person turns numbers on.
class WeekReview {
  /// Seven days, oldest first.
  final List<DayTotals> days;
  final int targetKcal;
  final int loggedDays;
  final int inRange;
  final int meals;

  /// Average intake on a logged day; null until three days are logged.
  final int? avgKcal;
  final Streak streak;
  final ReviewLine insight;
  final ReviewLine change;

  const WeekReview({
    required this.days,
    required this.targetKcal,
    required this.loggedDays,
    required this.inRange,
    required this.meals,
    required this.avgKcal,
    required this.streak,
    required this.insight,
    required this.change,
  });

  /// Three logged days is the least a claim about "your week" can rest on.
  static const minDays = 3;

  bool get enough => loggedDays >= minDays;

  /// How lit each day's moon is: intake against target, clamped. An unlogged
  /// day is null — drawn dark, not as a day that happened to be tiny.
  List<double?> get fills => [
        for (final d in days) d.meals == 0 ? null : (d.kcal / math.max(targetKcal, 1)).clamp(0.0, 1.0),
      ];

  static const _dayAr = ['الاتنين', 'التلات', 'الأربع', 'الخميس', 'الجمعة', 'السبت', 'الحد'];
  static const _dayEn = ['Monday', 'Tuesday', 'Wednesday', 'Thursday', 'Friday', 'Saturday', 'Sunday'];

  /// [iso] wraps a number the way the app draws it (Eastern or Western
  /// digits, bidi-isolated) — the card follows the same preference.
  static WeekReview build({
    required List<DayTotals> week,
    required List<DayTotals> lastWeek,
    required int targetKcal,
    required Streak streak,
    required String Function(String) iso,
  }) {
    final logged = week.where((d) => d.meals > 0).toList();
    final loggedDays = logged.length;
    final meals = week.fold(0, (s, d) => s + d.meals);
    final target = math.max(targetKcal, 1);
    final inRange = logged.where((d) => (d.kcal - target).abs() <= target * 0.1).length;
    final avg = loggedDays >= minDays ? (logged.fold(0, (s, d) => s + d.kcal) / loggedDays).round() : null;

    // 1. A weekday pattern: one logged day well above the others.
    ({DayTotals day, int pct})? spike;
    if (loggedDays >= minDays) {
      final top = logged.reduce((a, b) => a.kcal >= b.kcal ? a : b);
      final others = logged.where((d) => d != top).toList();
      final othersAvg = others.fold(0, (s, d) => s + d.kcal) / others.length;
      if (othersAvg > 0 && top.kcal >= othersAvg * 1.25) {
        spike = (day: top, pct: ((top.kcal / othersAvg - 1) * 100).round());
      }
    }

    // 2. A comparison with last week.
    int? weekDiffPct;
    final lastLogged = lastWeek.where((d) => d.meals > 0).toList();
    if (avg != null && lastLogged.length >= minDays) {
      final lastAvg = lastLogged.fold(0, (s, d) => s + d.kcal) / lastLogged.length;
      if (lastAvg > 0) weekDiffPct = ((avg / lastAvg - 1) * 100).round();
    }

    final ReviewLine insight;
    if (loggedDays < minDays) {
      final left = minDays - loggedDays;
      insight = (
        ar: 'سجّل ${iso('$minDays')} أيام على الأقل وأقدر أقولك حاجة متتوقعها. لسه ${iso('$left')} ${left == 1 ? 'يوم' : 'أيام'}.',
        en: 'Log at least $minDays days and I can tell you something you did not expect — $left to go.',
      );
    } else if (spike != null) {
      final w = spike.day.day.weekday - 1;
      insight = (
        ar: 'أكلت ${iso('${spike.pct}')}٪ أكتر يوم ${_dayAr[w]} من باقي الأسبوع.',
        en: 'You ate ${spike.pct}% more on ${_dayEn[w]} than the rest of the week.',
      );
    } else if (weekDiffPct != null && weekDiffPct.abs() >= 5) {
      final more = weekDiffPct > 0;
      final n = iso('${weekDiffPct.abs()}');
      insight = (
        ar: more ? 'متوسطك اليومي أعلى من الأسبوع اللي فات بـ $n٪.' : 'متوسطك اليومي أقل من الأسبوع اللي فات بـ $n٪.',
        en: more ? 'Your daily average is ${weekDiffPct.abs()}% above last week.' : 'Your daily average is ${weekDiffPct.abs()}% below last week.',
      );
    } else if (weekDiffPct != null) {
      insight = (
        ar: 'نفس الإيقاع زي الأسبوع اللي فات — الفرق أقل من ${iso('5')}٪.',
        en: 'The same rhythm as last week — the difference is under 5%.',
      );
    } else if (inRange * 2 >= loggedDays) {
      insight = (
        ar: '${iso('$inRange')} من ${iso('$loggedDays')} أيام مسجلة داخل النطاق. ده مش حظ.',
        en: '$inRange of $loggedDays logged days inside your range. That is not luck.',
      );
    } else {
      insight = (
        ar: '${iso('$loggedDays')} أيام مسجلة من ${iso('7')} — ده اللي بيخلّي الأرقام تتكلم.',
        en: '$loggedDays days logged out of 7 — that is what lets the numbers speak.',
      );
    }

    final ReviewLine change;
    if (spike != null) {
      final w = spike.day.day.weekday - 1;
      change = (
        ar: 'الأسبوع الجاي: عشا خفيف يوم ${_dayAr[w]}.',
        en: 'Next week: a light dinner on ${_dayEn[w]}.',
      );
    } else if (loggedDays < 4) {
      change = (
        ar: 'الأسبوع الجاي: سجّل الغدا بس، ${iso('5')} أيام. الباقي أنا أحسبه.',
        en: 'Next week: log just lunch, five days. I’ll do the rest.',
      );
    } else if (inRange * 2 < loggedDays) {
      change = (
        ar: 'الأسبوع الجاي: التزم بغدا الخطة ${iso('3')} أيام.',
        en: 'Next week: stick to the lunch on the plan three days.',
      );
    } else {
      change = (
        ar: 'الأسبوع الجاي: نفس الإيقاع، وكوباية مياه بعد كل وجبة.',
        en: 'Next week: the same rhythm, and a glass of water after each meal.',
      );
    }

    return WeekReview(
      days: week,
      targetKcal: targetKcal,
      loggedDays: loggedDays,
      inRange: inRange,
      meals: meals,
      avgKcal: avg,
      streak: streak,
      insight: insight,
      change: change,
    );
  }
}
