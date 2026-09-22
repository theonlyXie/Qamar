// The habit loop's trigger, as the blueprint bounds it: two questions a day
// at this person's meal times, in Qamar's voice, only for the first fourteen
// days, lowerable to zero and never raisable above two.
import 'package:flutter_test/flutter_test.dart';
import 'package:qamar/models/nudge.dart';

void main() {
  final morning = DateTime(2026, 9, 21, 9, 0);
  const times = MealTimes.typical;

  group('schedule', () {
    test('two a day are lunch and dinner; one a day is lunch; zero is nothing', () {
      expect(NudgeSchedule.slotsFor(2), [MealSlot.lunch, MealSlot.dinner]);
      expect(NudgeSchedule.slotsFor(1), [MealSlot.lunch]);
      expect(NudgeSchedule.slotsFor(0), isEmpty);
      expect(NudgeSchedule.slotsFor(9), hasLength(2), reason: 'the ceiling is two');
    });

    test('the whole fourteen-day window up front, at the meal times, oldest first', () {
      // The phone fires only what is already scheduled, and the schedule is
      // rebuilt only while the app runs — so a person who stops opening it
      // must still have every question the window holds.
      final s = NudgeSchedule.build(perDay: 2, times: times, now: morning, firstDay: DateTime(2026, 9, 21));
      expect(s.length, 28, reason: 'fourteen days, two a day');
      expect(s.first.slot, MealSlot.lunch);
      expect(s.first.at, DateTime(2026, 9, 21, 14, 0));
      expect(s[1].at, DateTime(2026, 9, 21, 20, 30));
      expect(s.last.at, DateTime(2026, 10, 4, 20, 30), reason: 'day 13 is the window’s last');
      for (var i = 1; i < s.length; i++) {
        expect(s[i].at.isAfter(s[i - 1].at), isTrue);
      }
    });

    test('a window that started days ago schedules exactly what is left of it', () {
      final tenDaysIn = DateTime(2026, 9, 11);
      final s = NudgeSchedule.build(perDay: 2, times: times, now: morning, firstDay: tenDaysIn);
      expect(s.length, 8, reason: 'days 10 to 13, two a day');
      expect(s.map((n) => n.dayIndex).toSet(), {0, 1, 2, 3});
      expect(s.last.at, DateTime(2026, 9, 24, 20, 30));
    });

    test('the whole window and both reminders fit under the phone’s pending limit', () {
      expect(
        NudgeSchedule.externalDays * NudgeSchedule.maxPerDay + NudgeSchedule.reservedPending,
        lessThanOrEqualTo(NudgeSchedule.maxPending),
        reason: 'iOS drops pending notifications past 64 without saying so',
      );
      final s = NudgeSchedule.build(perDay: 9, times: times, now: morning, days: 400);
      expect(s.length, lessThanOrEqualTo(NudgeSchedule.maxPending - NudgeSchedule.reservedPending));
      expect(s.length, 28, reason: 'a longer horizon still stops at the window');
    });

    test('each day decides its own fast, so a schedule can cross the first one', () {
      final firstFast = DateTime(2026, 9, 24);
      bool fastingOn(DateTime d) => !d.isBefore(firstFast);
      MealTimes timesOn(DateTime d) => fastingOn(d) ? times.withRamadan(iftar: 17 * 60 + d.day, suhoor: 4 * 60) : times;
      final s = NudgeSchedule.build(perDay: 2, times: times, now: morning, firstDay: morning, fastingOn: fastingOn, timesOn: timesOn);

      final before = s.where((n) => n.at.isBefore(firstFast)).map((n) => n.slot).toSet();
      expect(before, {MealSlot.lunch, MealSlot.dinner});
      final after = s.where((n) => !n.at.isBefore(firstFast)).toList();
      expect(after.map((n) => n.slot).toSet(), {MealSlot.iftar, MealSlot.suhoor});
      expect(after.firstWhere((n) => n.slot == MealSlot.iftar).at, DateTime(2026, 9, 24, 17, 24), reason: 'that day’s sunset, not today’s');
      expect(s.map((n) => n.id).toSet().length, s.length, reason: 'ids stay unique across the switch');
    });

    test('today\'s question is dropped once its time has passed or the meal is logged', () {
      final afterLunch = DateTime(2026, 9, 21, 15, 0);
      final s = NudgeSchedule.build(perDay: 2, times: times, now: afterLunch);
      expect(s.where((n) => n.dayIndex == 0).map((n) => n.slot), [MealSlot.dinner]);

      final logged = NudgeSchedule.build(perDay: 2, times: times, now: morning, loggedToday: {MealSlot.lunch});
      expect(logged.where((n) => n.dayIndex == 0).map((n) => n.slot), [MealSlot.dinner]);
      expect(logged.where((n) => n.dayIndex == 1).length, 2, reason: 'tomorrow is untouched');
    });

    test('push nudges end fourteen days after the first day', () {
      final day13 = DateTime(2026, 9, 21).subtract(const Duration(days: 13));
      final s = NudgeSchedule.build(perDay: 2, times: times, now: morning, firstDay: day13);
      expect(s.map((n) => n.dayIndex).toSet(), {0}, reason: 'today is day 13, tomorrow is day 14');

      final day14 = DateTime(2026, 9, 21).subtract(const Duration(days: 14));
      expect(NudgeSchedule.build(perDay: 2, times: times, now: morning, firstDay: day14), isEmpty);

      expect(NudgeSchedule.build(perDay: 2, times: times, now: morning, firstDay: null).length, 28,
          reason: 'a window that has not started yet starts today');
    });

    test('learned meal times move the questions', () {
      final late = const MealTimes(lunch: 15 * 60 + 30, dinner: 22 * 60);
      final s = NudgeSchedule.build(perDay: 2, times: late, now: morning);
      expect(s.first.at, DateTime(2026, 9, 21, 15, 30));
      expect(s[1].at, DateTime(2026, 9, 21, 22, 0));
    });

    test('ids are stable per day and slot, so a rebuild replaces rather than stacks', () {
      final a = NudgeSchedule.build(perDay: 2, times: times, now: morning);
      final b = NudgeSchedule.build(perDay: 2, times: times, now: morning.add(const Duration(minutes: 5)));
      expect(a.map((n) => n.id).toList(), b.map((n) => n.id).toList());
      expect(a.map((n) => n.id).toSet().length, a.length);
    });
  });

  group('waiting', () {
    test('a question waits from its meal time for three hours, unless the meal is logged', () {
      expect(NudgeSchedule.waiting(perDay: 2, times: times, now: DateTime(2026, 9, 21, 13, 59)), isNull);
      expect(NudgeSchedule.waiting(perDay: 2, times: times, now: DateTime(2026, 9, 21, 14, 0))?.slot, MealSlot.lunch);
      expect(NudgeSchedule.waiting(perDay: 2, times: times, now: DateTime(2026, 9, 21, 16, 59))?.slot, MealSlot.lunch);
      expect(NudgeSchedule.waiting(perDay: 2, times: times, now: DateTime(2026, 9, 21, 17, 0)), isNull);
      expect(NudgeSchedule.waiting(perDay: 2, times: times, now: DateTime(2026, 9, 21, 21, 0))?.slot, MealSlot.dinner);
      expect(NudgeSchedule.waiting(perDay: 2, times: times, now: DateTime(2026, 9, 21, 14, 30), loggedToday: {MealSlot.lunch}), isNull);
      expect(NudgeSchedule.waiting(perDay: 0, times: times, now: DateTime(2026, 9, 21, 14, 30)), isNull);
      expect(NudgeSchedule.waiting(perDay: 1, times: times, now: DateTime(2026, 9, 21, 21, 0)), isNull, reason: 'one a day never asks about dinner');
    });
  });

  group('the free week’s reminder', () {
    final end = DateTime(2026, 9, 28, 12);

    test('fires 48 hours before the week ends, with its own id and payload', () {
      final n = NudgeSchedule.trialReminder(trialEnd: end, now: DateTime(2026, 9, 22, 9));
      expect(n, isNotNull);
      expect(n!.at, DateTime(2026, 9, 26, 12));
      expect(n.kind, NudgeKind.trialEnding);
      expect(n.id, 90, reason: 'never collides with a meal question’s id');
      expect(n.payload, 'trial:ending');
      expect(n.text(ar: false), 'Two days left of your week with Qamar+. Keep the plan going?');
      expect(n.text(ar: true), contains('قمر+'));
    });

    test('nothing to schedule without a trial, or once the 48-hour mark has passed', () {
      expect(NudgeSchedule.trialReminder(trialEnd: null, now: DateTime(2026, 9, 22)), isNull);
      expect(NudgeSchedule.trialReminder(trialEnd: end, now: DateTime(2026, 9, 27)), isNull);
      expect(NudgeSchedule.trialReminder(trialEnd: end, now: DateTime(2026, 9, 26, 12)), isNull, reason: 'exactly at the mark is too late to schedule');
    });

    test('the reminder’s words are not a nag', () {
      for (final ar in [true, false]) {
        final t = NudgeCopy.trialEnding(ar: ar).toLowerCase();
        expect(t.contains('expir') || t.contains('don’t forget') || t.contains('reminder'), isFalse);
      }
    });
  });

  group('voice', () {
    test('every line is a question in Qamar\'s voice; none says log, forget or reminder', () {
      for (final line in NudgeCopy.all) {
        final lower = line.toLowerCase();
        expect(lower.contains('forget'), isFalse, reason: line);
        expect(lower.contains('log'), isFalse, reason: line);
        expect(lower.contains('remind'), isFalse, reason: line);
        expect(line.contains('متنساش'), isFalse, reason: line);
        expect(line.contains('سجّل'), isFalse, reason: line);
        expect(line.contains('تذكير'), isFalse, reason: line);
      }
    });

    test('the phrasing alternates by day so the same words do not arrive every afternoon', () {
      final a = NudgeCopy.text(MealSlot.lunch, DateTime(2026, 9, 21), ar: true);
      final b = NudgeCopy.text(MealSlot.lunch, DateTime(2026, 9, 22), ar: true);
      expect(a, isNot(b));
      expect(NudgeCopy.text(MealSlot.lunch, DateTime(2026, 9, 23), ar: true), a);
    });
  });

  group('meal times', () {
    test('the server\'s profile fills in per slot and keeps typical hours for the rest', () {
      final t = MealTimes.fromJson({'breakfast': null, 'lunch': 15 * 60 + 12, 'dinner': 21 * 60});
      expect(t.breakfast, MealTimes.typical.breakfast);
      expect(t.lunch, 15 * 60 + 12);
      expect(t.dinner, 21 * 60);
      expect(MealTimes.fromJson({'lunch': -5}).lunch, MealTimes.typical.lunch, reason: 'nonsense is ignored');
    });

    test('the hour cut matches the plan screen', () {
      expect(slotForHour(10), MealSlot.breakfast);
      expect(slotForHour(11), MealSlot.lunch);
      expect(slotForHour(16), MealSlot.lunch);
      expect(slotForHour(17), MealSlot.dinner);
      expect(slotForHour(23), MealSlot.dinner);
    });
  });
}
