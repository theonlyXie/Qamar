/// Calendar days on the phone's own clock, stepped and counted by the
/// calendar and never by 24-hour durations.
///
/// A day is not always 24 hours. Egypt moves its clocks forward an hour as
/// the last Friday of April begins (that day has 23 hours, and its midnight
/// does not exist: Dart gives 01:00), and back an hour as the last Thursday
/// of October ends (that day has 25). Stepped by `Duration(days: n)` across
/// either change, a date lands at 23:00 the day before or at 01:00, which is
/// no longer the first instant of any day: a lookup keyed by days misses it,
/// and in April its weekday is the day before. Counted with
/// `difference(...).inDays`, two midnights either side of April are a day
/// short. A meal time found by adding minutes to midnight is an hour late on
/// the day the clocks go forward.
///
/// So every step and count of days in lib/ goes through here. CI runs in
/// UTC, where none of this can be seen, so days_test.dart reads lib/ itself
/// and fails, in any time zone, if a `Duration(days:)` step or an `inDays`
/// count comes back anywhere else; cairo_days_test.dart runs the scenarios
/// in Cairo time (checks.yml, "Test in Cairo time").
abstract final class Days {
  /// The first instant of [d]'s calendar day: its midnight, or 01:00 on the
  /// day the clocks go forward at midnight.
  static DateTime of(DateTime d) => _day(d, d.year, d.month, d.day);

  /// The calendar day [n] days after [d]'s (before it, when [n] is
  /// negative), as that day's first instant.
  static DateTime add(DateTime d, int n) => _day(d, d.year, d.month, d.day + n);

  /// [minutes] after midnight on [day]'s calendar day, on the wall clock: a
  /// meal at 14:00 is at 14:00 on the day the clocks change too.
  static DateTime at(DateTime day, int minutes) =>
      day.isUtc ? DateTime.utc(day.year, day.month, day.day, 0, minutes) : DateTime(day.year, day.month, day.day, 0, minutes);

  /// [t] moved back [n] calendar days, at the same wall-clock time: "a week
  /// ago, now".
  static DateTime ago(DateTime t, int n) => t.isUtc
      ? DateTime.utc(t.year, t.month, t.day - n, t.hour, t.minute, t.second, t.millisecond, t.microsecond)
      : DateTime(t.year, t.month, t.day - n, t.hour, t.minute, t.second, t.millisecond, t.microsecond);

  /// Whole calendar days from [from]'s day to [to]'s (negative when [to] is
  /// earlier), whatever hours lie between them. Counted on UTC dates, which
  /// are always 24 hours apart.
  static int between(DateTime from, DateTime to) =>
      DateTime.utc(to.year, to.month, to.day).difference(DateTime.utc(from.year, from.month, from.day)).inDays;

  static DateTime _day(DateTime like, int y, int m, int d) => like.isUtc ? DateTime.utc(y, m, d) : DateTime(y, m, d);
}
