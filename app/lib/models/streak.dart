import 'dart:math' as math;

import 'days.dart';

/// Days in a row with at least one logged meal.
///
/// A streak is arithmetic over the days that were actually logged — the same
/// data the Progress chart draws. Today is special: an empty today does not
/// break the streak, it only means today has not been counted yet, so the
/// number the orb shows is stable through the morning and grows when the
/// first meal lands.
///
/// A streak freeze covers exactly one empty day. The server applies them (see
/// `qamar_streak_snapshot` in 0042_streaks.sql) and reports which days it
/// covered; offline the freeze is only ever a token in the wallet, never a
/// day filled in by the client.
class Streak {
  final int current;
  final int best;

  /// Today already has a meal, so [current] includes it.
  final bool todayCounted;

  /// Unused freeze tokens in the wallet.
  final int freezesAvailable;

  /// Days the server covered with a freeze instead of a meal.
  final List<DateTime> frozenDays;

  const Streak({
    required this.current,
    required this.best,
    required this.todayCounted,
    this.freezesAvailable = 0,
    this.frozenDays = const [],
  });

  static const none = Streak(current: 0, best: 0, todayCounted: false);

  /// Yesterday was the last counted day and today is still empty: the streak
  /// is alive but will end at midnight without a meal.
  bool get atRisk => current > 0 && !todayCounted;

  Streak copyWith({int? current, int? best, bool? todayCounted, int? freezesAvailable, List<DateTime>? frozenDays}) => Streak(
        current: current ?? this.current,
        best: best ?? this.best,
        todayCounted: todayCounted ?? this.todayCounted,
        freezesAvailable: freezesAvailable ?? this.freezesAvailable,
        frozenDays: frozenDays ?? this.frozenDays,
      );

  /// Counts back from [today] over [loggedDays] (any time of day; only the
  /// calendar date matters). [frozenDays] count as logged. It steps and
  /// counts by the calendar ([Days]): stepped by 24 hours, a run broke where
  /// Egypt's clocks change.
  factory Streak.fromDays(
    Iterable<DateTime> loggedDays, {
    required DateTime today,
    Iterable<DateTime> frozenDays = const [],
    int freezesAvailable = 0,
  }) {
    final days = <DateTime>{
      for (final d in loggedDays) Days.of(d),
      for (final d in frozenDays) Days.of(d),
    };
    final t = Days.of(today);
    final todayCounted = days.contains(t);

    var cursor = todayCounted ? t : Days.add(t, -1);
    var current = 0;
    while (days.contains(cursor)) {
      current++;
      cursor = Days.add(cursor, -1);
    }

    // Best run anywhere in the data — an old streak that ended still counts
    // as the one to beat.
    var best = current;
    final sorted = days.toList()..sort();
    var run = 0;
    DateTime? prev;
    for (final d in sorted) {
      run = (prev != null && Days.between(prev, d) == 1) ? run + 1 : 1;
      prev = d;
      best = math.max(best, run);
    }

    return Streak(
      current: current,
      best: best,
      todayCounted: todayCounted,
      freezesAvailable: freezesAvailable,
      frozenDays: frozenDays.map((d) => DateTime(d.year, d.month, d.day)).toList(),
    );
  }

  factory Streak.fromJson(Map<String, dynamic> json) {
    int n(Object? v) => v is num ? v.round() : 0;
    final frozen = json['frozen_days'];
    return Streak(
      current: n(json['current']),
      best: n(json['best']),
      todayCounted: json['today_counted'] == true,
      freezesAvailable: n(json['freezes_available']),
      frozenDays: frozen is List
          ? [for (final d in frozen) if (d is String && DateTime.tryParse(d) != null) DateTime.parse(d)]
          : const [],
    );
  }
}

/// The streak as Qamar says it under the name on Today (O4): one sentence,
/// from the second day of a run.
///
/// It appears only once today's meal has joined a run of two days or more,
/// so it is always news about something done, never a reminder of something
/// to keep: nothing here speaks of risk, deadlines or midnight (those stay
/// on Progress). When a run ends the line is simply not there. Null means
/// no line.
String? streakSentence(Streak s, {required bool ar, required String Function(String) iso}) {
  if (!s.todayCounted || s.current < 2) return null;
  final n = s.current;
  if (n <= 10) {
    const ordAr = ['تاني', 'تالت', 'رابع', 'خامس', 'سادس', 'سابع', 'تامن', 'تاسع', 'عاشر'];
    const ordEn = ['Second', 'Third', 'Fourth', 'Fifth', 'Sixth', 'Seventh', 'Eighth', 'Ninth', 'Tenth'];
    return ar ? '${ordAr[n - 2]} يوم ورا بعض.' : '${ordEn[n - 2]} day running.';
  }
  return ar ? '${iso('$n')} يوم ورا بعض.' : '$n days running.';
}

/// What the moon says about a day. Seat 4 owns what the states mean; seat 6
/// owns how they are drawn, and can restyle each by name.
///
/// Only [under], [at] and [over] are readings of a day. [unknown] is no
/// reading at all, and is never drawn as a dark moon: nothing logged is not a
/// bad day, and on the general-guidance route there is no target to read a
/// day against.
enum OrbDay {
  /// Nothing logged, or no target to read against: the moon at rest, as it
  /// is on every screen where it is not reading a day.
  unknown,

  /// Logged, and short of the target: the moon brightens toward full.
  under,

  /// Within reach of the target: a moon a day from full.
  at,

  /// Past the target by more than an estimate can tell apart from it
  /// ([OrbState.overMargin]): full, and the halo warms.
  over,
}

/// What the orb looks like right now, derived from the day rather than from
/// a clock: which [OrbDay] it is, how far the moon has brightened toward the
/// target, how much of the day's rhythm has happened (the glow), and the
/// streak (the ring).
class OrbState {
  final OrbDay day;

  /// 0..1: how far the day has come toward the target. 0 when [unknown], 1
  /// at or past the target.
  final double fill;

  /// 0..1: meals eaten today against the plan's slots (or three, unplanned).
  /// Drawn only on a day the moon reads: an [OrbDay.unknown] day's halo is the
  /// moon's at rest (LivingOrb.glowBaseFor).
  final double glow;

  final Streak streak;

  const OrbState({required this.day, required this.fill, required this.glow, required this.streak});

  static const rest = OrbState(day: OrbDay.unknown, fill: 0, glow: 0, streak: Streak.none);

  /// Past the target by more than an estimate can tell apart: the halo warms.
  bool get over => day == OrbDay.over;

  /// The moon painter's phase (0 fully lit, 1 fully dark), or null for an
  /// [OrbDay.unknown] day: the moon at rest, drifting as it does everywhere.
  double? get moonPhase => day == OrbDay.unknown ? null : phaseForFill(fill);

  /// The resting crescent, where a day's moon starts: the middle of the drift
  /// the moon has everywhere it is not reading a day (moon.dart, 0.58-0.67).
  /// A day's moon only ever brightens from here, so logging a small meal
  /// never draws it darker than logging nothing at all.
  static const restPhase = 0.62;

  /// A day at the target: a moon a day from full.
  static const fullPhase = 0.06;

  /// The same mapping for any day — the review card draws a week of them.
  static double phaseForFill(double fill) => restPhase - (restPhase - fullPhase) * fill.clamp(0.0, 1.0);

  /// How close counts as at the target: 5%, and never under 100 kcal. Qamar's
  /// words (reply.dart) classify the day through [dayFor], so they read it the
  /// same way: "right at your target" within this, and past it but under
  /// [overMargin] "within what an estimate can tell apart".
  static int atTolerance(int target) => math.max(100, (target * 0.05).round());

  /// How far past the target a day must go before the moon warms: further
  /// than an estimate can tell apart from the target. The target is itself an
  /// estimate that can be 10% or more off for a given person (knowledge base,
  /// 03-energy-and-protein), and what is logged is an estimate on top of it,
  /// so a day within a quarter of the target, or 400 kcal, whichever is more,
  /// reads as at the target. "One heavy day inside a good month changes very
  /// little" (06-egyptian-eating-culture). It used to be 110%.
  static int overMargin(int target) => math.max(400, (target * 0.25).round());

  /// Which state a day is in. [targetKcal] is null where there is no target
  /// (the general-guidance route); [logged] is whether anything was logged.
  static OrbDay dayFor({required int consumedKcal, required int? targetKcal, required bool logged}) {
    final target = targetKcal;
    if (!logged || target == null || target <= 0) return OrbDay.unknown;
    if (consumedKcal > target + overMargin(target)) return OrbDay.over;
    if (consumedKcal >= target - atTolerance(target)) return OrbDay.at;
    return OrbDay.under;
  }

  /// How far the moon has brightened for a day in [day]'s state.
  static double fillFor(OrbDay day, {required int consumedKcal, required int? targetKcal}) => switch (day) {
        OrbDay.unknown => 0,
        OrbDay.under => (consumedKcal / math.max(targetKcal ?? 1, 1)).clamp(0.0, 1.0),
        OrbDay.at || OrbDay.over => 1,
      };

  factory OrbState.derive({
    required int consumedKcal,
    required int? targetKcal,
    required int mealsToday,
    required int planSlots,
    required Streak streak,
  }) {
    final day = dayFor(consumedKcal: consumedKcal, targetKcal: targetKcal, logged: mealsToday > 0);
    final slots = planSlots > 0 ? planSlots : 3;
    return OrbState(
      day: day,
      fill: fillFor(day, consumedKcal: consumedKcal, targetKcal: targetKcal),
      glow: (mealsToday / slots).clamp(0.0, 1.0),
      streak: streak,
    );
  }
}
