// The week, the streak and the meal questions across Egypt's clock changes:
// forward an hour as the last Friday of April begins (24 Apr 2026, a 23-hour
// day), back an hour as the last Thursday of October ends (29 Oct 2026, a
// 25-hour day). Stepped by 24 hours, the week after either change found
// none of its past days, April's read each as the day before, the offline
// streak stopped at the change, and questions set before it came an hour off.
//
// Only a phone on Cairo time can show this, so these run for real in the
// "Test in Cairo time" step of checks.yml (TZ=Africa/Cairo, REQUIRE_CAIRO)
// and are skipped anywhere else. days_test.dart holds the same line in any
// time zone by reading lib/ for day arithmetic done with durations.

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

import 'package:qamar/l10n/strings.dart';
import 'package:qamar/main.dart';
import 'package:qamar/models/meal.dart';
import 'package:qamar/models/nudge.dart';
import 'package:qamar/services/repositories.dart';
import 'package:qamar/state/app_state.dart';
import 'package:qamar/state/today_focus.dart';
import 'package:qamar/widgets/week_glance_card.dart';

import 'support/app_fonts.dart';

/// This process keeps Cairo's clock: EET, then EEST from 24 Apr to 29 Oct.
final bool inCairo = [
  (DateTime(2026, 4, 23, 12), 2),
  (DateTime(2026, 4, 24, 12), 3),
  (DateTime(2026, 10, 29, 12), 3),
  (DateTime(2026, 10, 30, 12), 2),
].every((c) => c.$1.timeZoneOffset == Duration(hours: c.$2));

/// Set by checks.yml's Cairo step, where skipping would hide a lost TZ.
const bool requireCairo = bool.fromEnvironment('REQUIRE_CAIRO');

final Object _skip = inCairo ? false : 'needs Cairo time: TZ=Africa/Cairo (checks.yml, "Test in Cairo time")';

/// A person who logged every day of the fortnight before [now], and today.
AppState _loggedEveryDay(DateTime now, {int days = 14}) {
  final s = AppState(clock: () => now)..setLang(AppLang.en);
  s.setFasting(false);
  s.dismissOrbTutorial();
  for (var back = 1; back <= days; back++) {
    // As the repository builds a day: the calendar date of a meal.
    s.dayHistory.add(DayTotals(day: DateTime(now.year, now.month, now.day - back), kcal: 1900, meals: 2));
  }
  s.meals.add(LoggedMeal(name: 'Foul', sub: '', kcal: 450, p: 20, c: 55, f: 14, at: now));
  s.go(AppScreen.today);
  return s;
}

List<String> _row(AppState s) => [for (final d in s.week()) kWeekdayShortEn[d.day.weekday - 1]];

void main() {
  setUpAll(() async {
    await loadAppFonts();
    for (final name in const ['com.qamar.app/quick_events', 'com.qamar.app/quick_invoke']) {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(MethodChannel(name), (call) async => null);
    }
  });

  test('the Cairo step runs on Cairo time', () {
    if (requireCairo) expect(inCairo, isTrue, reason: 'TZ=Africa/Cairo did not reach the test process');
  });

  group('the morning after the clocks go back, Friday 30 October 2026', () {
    final friday = DateTime(2026, 10, 30, 9);

    test('all seven days are logged, the week card is due and the offline streak is 15', () {
      final s = _loggedEveryDay(friday);
      expect(_row(s), ['Sa', 'Su', 'Mo', 'Tu', 'We', 'Th', 'Fr']);
      expect(s.week().where((d) => d.meals > 0).length, 7);
      expect(s.weekReview().fills.every((f) => f != null), isTrue, reason: 'every moon a reading, none at rest');
      expect(s.weekCardDue, isTrue);
      expect(todayFocus(s), TodayCard.weekCard);
      expect(s.serverStreak, isNull, reason: 'offline: the streak is counted on the phone');
      expect(s.streak().current, 15);
      expect(s.streak().best, 15);
    }, skip: _skip);

    testWidgets('Today carries the week card', (tester) async {
      final s = _loggedEveryDay(friday);
      await tester.binding.setSurfaceSize(const Size(390, 1400));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      await tester.pumpWidget(ChangeNotifierProvider.value(value: s, child: const QamarApp()));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
      expect(find.byType(WeekGlanceCard), findsOneWidget);
    }, skip: _skip != false);
  });

  group('the clocks go forward, Friday 24 April 2026', () {
    test('on the day itself the row reads Sa…Fr, Friday present, every day logged', () {
      final s = _loggedEveryDay(DateTime(2026, 4, 24, 9));
      expect(_row(s), ['Sa', 'Su', 'Mo', 'Tu', 'We', 'Th', 'Fr']);
      expect(s.week().where((d) => d.meals > 0).length, 7);
      expect(s.weekCardDue, isTrue);
      expect(s.streak().current, 15);
    }, skip: _skip);

    test('the Saturday after, the row still holds Friday, and every day logged', () {
      final s = _loggedEveryDay(DateTime(2026, 4, 25, 9));
      expect(_row(s), ['Su', 'Mo', 'Tu', 'We', 'Th', 'Fr', 'Sa'], reason: 'the week ending today, Friday the 24th in it');
      expect([for (final d in s.week()) d.day.day], [19, 20, 21, 22, 23, 24, 25]);
      expect(s.week().where((d) => d.meals > 0).length, 7);
      expect(s.streak().current, 15);
      expect(s.streak().best, 15);
    }, skip: _skip);

    test('the next review day compares with a whole last week', () {
      final s = _loggedEveryDay(DateTime(2026, 5, 1, 9));
      expect(s.lastWeek().where((d) => d.meals > 0).length, 7, reason: '18 to 24 April, across the change');
    }, skip: _skip);
  });

  group('meal questions set before a change come at the same wall-clock time after it', () {
    for (final (name, now) in [
      ('from Wednesday 22 April', DateTime(2026, 4, 22, 10)),
      ('from Tuesday 27 October', DateTime(2026, 10, 27, 10)),
    ]) {
      test(name, () {
        final schedule = NudgeSchedule.build(perDay: 2, times: MealTimes.typical, now: now, firstDay: now, days: 8);
        expect({for (final n in schedule) (n.at.month, n.at.day)}.length, 8, reason: 'eight days, each its own date');
        expect(schedule.length, 16, reason: 'lunch and dinner, eight days');
        for (final n in schedule) {
          expect((n.at.hour, n.at.minute), n.slot == MealSlot.lunch ? (14, 0) : (20, 30), reason: '${n.slot.name} on ${n.at.month}/${n.at.day}');
        }
      }, skip: _skip);
    }

    test('the fortnight still ends on its fourteenth day when the change falls inside it', () {
      final schedule = NudgeSchedule.build(perDay: 2, times: MealTimes.typical, now: DateTime(2026, 4, 25, 10), firstDay: DateTime(2026, 4, 17));
      final last = schedule.map((n) => n.at).reduce((a, b) => a.isAfter(b) ? a : b);
      expect((last.month, last.day), (4, 30), reason: '17 to 30 April is fourteen days, not fifteen');
    }, skip: _skip);

    test('on the day the clocks go forward, lunch waits on the orb from 14:00', () {
      final waiting = NudgeSchedule.waiting(perDay: 2, times: MealTimes.typical, now: DateTime(2026, 4, 24, 14, 30));
      expect(waiting?.slot, MealSlot.lunch);
      expect((waiting!.at.hour, waiting.at.minute), (14, 0));
    }, skip: _skip);
  });
}
