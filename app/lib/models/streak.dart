import 'dart:math' as math;

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
  /// calendar date matters). [frozenDays] count as logged.
  factory Streak.fromDays(
    Iterable<DateTime> loggedDays, {
    required DateTime today,
    Iterable<DateTime> frozenDays = const [],
    int freezesAvailable = 0,
  }) {
    final days = <DateTime>{
      for (final d in loggedDays) DateTime(d.year, d.month, d.day),
      for (final d in frozenDays) DateTime(d.year, d.month, d.day),
    };
    final t = DateTime(today.year, today.month, today.day);
    final todayCounted = days.contains(t);

    var cursor = todayCounted ? t : t.subtract(const Duration(days: 1));
    var current = 0;
    while (days.contains(cursor)) {
      current++;
      cursor = cursor.subtract(const Duration(days: 1));
    }

    // Best run anywhere in the data — an old streak that ended still counts
    // as the one to beat.
    var best = current;
    final sorted = days.toList()..sort();
    var run = 0;
    DateTime? prev;
    for (final d in sorted) {
      run = (prev != null && d.difference(prev).inDays == 1) ? run + 1 : 1;
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

/// What the orb looks like right now, derived from the day rather than from
/// a clock. The moon fills as today's intake approaches the target; the glow
/// follows how much of the day's rhythm has happened; the ring is the streak.
class OrbState {
  /// 0 = nothing logged, 1 = at target. Clamped; going over is [over].
  final double fill;

  /// Intake past 110% of target — the glow warms instead of brightening.
  final bool over;

  /// 0..1: meals eaten today against the plan's slots (or three, unplanned).
  final double glow;

  final Streak streak;

  const OrbState({required this.fill, required this.over, required this.glow, required this.streak});

  static const rest = OrbState(fill: 0, over: false, glow: 0, streak: Streak.none);

  /// The moon painter's phase: 0 is fully lit, 1 fully dark. An empty day is
  /// a thin crescent, a day at target is a near-full moon.
  double get moonPhase => 0.9 - 0.8 * fill;

  factory OrbState.derive({
    required int consumedKcal,
    required int targetKcal,
    required int mealsToday,
    required int planSlots,
    required Streak streak,
  }) {
    final target = math.max(targetKcal, 1);
    final ratio = consumedKcal / target;
    final slots = planSlots > 0 ? planSlots : 3;
    return OrbState(
      fill: ratio.clamp(0.0, 1.0),
      over: ratio > 1.1,
      glow: (mealsToday / slots).clamp(0.0, 1.0),
      streak: streak,
    );
  }
}
