// The weekly review card: one thing the person did not expect, one change,
// a moon per day — and never weight, calories only when asked for.
import 'package:flutter_test/flutter_test.dart';
import 'package:qamar/models/review.dart';
import 'package:qamar/models/streak.dart';
import 'package:qamar/services/repositories.dart';

String plain(String x) => x;

/// Monday 14 → Sunday 20 September 2026.
List<DayTotals> week(List<int> kcal) => [
      for (var i = 0; i < 7; i++) DayTotals(day: DateTime(2026, 9, 14 + i), kcal: kcal[i], meals: kcal[i] > 0 ? 3 : 0),
    ];
List<DayTotals> last(List<int> kcal) => [
      for (var i = 0; i < 7; i++) DayTotals(day: DateTime(2026, 9, 7 + i), kcal: kcal[i], meals: kcal[i] > 0 ? 3 : 0),
    ];
const none = <int>[0, 0, 0, 0, 0, 0, 0];

WeekReview build(List<int> thisWeek, {List<int> lastWeek = none, int target = 2000, Streak streak = Streak.none}) =>
    WeekReview.build(week: week(thisWeek), lastWeek: last(lastWeek), targetKcal: target, streak: streak, iso: plain);

void main() {
  test('a weekday well above the rest is the thing they did not expect, and the change names it', () {
    final r = build([1800, 1800, 1800, 2700, 1800, 0, 0]);
    expect(r.enough, isTrue);
    expect(r.insight.ar, contains('الخميس'));
    expect(r.insight.ar, contains('50'));
    expect(r.insight.en, 'You ate 50% more on Thursday than the rest of the week.');
    expect(r.change.en, 'Next week: a light dinner on Thursday.');
  });

  test('without a spike, last week is the comparison', () {
    final r = build([2000, 2000, 2000, 2000, 2000, 0, 0], lastWeek: [1600, 1600, 1600, 1600, 1600, 0, 0]);
    // The closing words wrap as one (no-break space): the card never ends on
    // "week." alone.
    expect(r.insight.en, 'Your daily average is 25% above last\u00A0week.');
    final flat = build([2000, 2000, 2000, 2000, 2000, 0, 0], lastWeek: [1960, 1960, 1960, 1960, 1960, 0, 0]);
    expect(flat.insight.en, contains('under 5%'));
  });

  test('with nothing to compare, a compliment with a number in it', () {
    final r = build([2000, 2050, 1950, 2100, 1900, 0, 0]);
    expect(r.inRange, 5);
    expect(r.insight.en, '5 of 5 logged days inside your range. That is not luck.');
    expect(r.change.en, contains('same rhythm'));
  });

  test('under three logged days there is no claim, only what is missing', () {
    final r = build([2000, 2000, 0, 0, 0, 0, 0]);
    expect(r.enough, isFalse);
    expect(r.avgKcal, isNull);
    expect(r.insight.en, contains('Log at least 3 days'));
    expect(r.insight.en, contains('1\u00A0to\u00A0go'), reason: 'the count and its words wrap as one');
    expect(r.change.en, contains('log just lunch'));
  });

  test('mostly out of range asks for three plan lunches', () {
    // Steady but under: no single day stands out, only one lands in range.
    final r = build([1600, 1650, 1700, 1750, 1800, 0, 0]);
    expect(r.inRange, 1);
    expect(r.change.en, contains('stick to the lunch on the plan'));
  });

  test('a moon per day: unlogged days are unknown and rest, logged days lit to their share of the target', () {
    final r = build([1000, 2000, 3000, 0, 0, 0, 0]);
    expect(r.fills, [0.5, 1.0, 1.0, null, null, null, null]);
    expect(r.orbDays, [OrbDay.under, OrbDay.at, OrbDay.over, OrbDay.unknown, OrbDay.unknown, OrbDay.unknown, OrbDay.unknown]);
    // A day's moon starts at the resting crescent, not a dark one, and
    // brightens to a moon a day from full at the target.
    expect(OrbState.phaseForFill(0), closeTo(OrbState.restPhase, 1e-9));
    expect(OrbState.phaseForFill(0), closeTo(0.62, 1e-9));
    expect(OrbState.phaseForFill(1), closeTo(0.06, 1e-9));
  });

  test('the average appears only with enough days, and weight never appears at all', () {
    final r = build([1800, 1800, 1800, 2700, 1800, 0, 0]);
    expect(r.avgKcal, 1980);
    for (final line in [r.insight.ar, r.insight.en, r.change.ar, r.change.en]) {
      expect(line.contains('وزن'), isFalse, reason: line);
      expect(line.contains('كجم'), isFalse, reason: line);
      expect(line.toLowerCase().contains('weight'), isFalse, reason: line);
      expect(line.contains('kg'), isFalse, reason: line);
    }
  });

  test('numbers go through the app\'s digit preference', () {
    final r = WeekReview.build(
      week: week([1800, 1800, 1800, 2700, 1800, 0, 0]),
      lastWeek: last(none),
      targetKcal: 2000,
      streak: Streak.none,
      iso: (x) => '<$x>',
    );
    expect(r.insight.ar, contains('<50>'));
  });
}
