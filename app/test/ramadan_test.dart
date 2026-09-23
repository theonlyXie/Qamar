import 'package:flutter_test/flutter_test.dart';

import 'package:qamar/models/nudge.dart';
import 'package:qamar/models/ramadan.dart';
import 'package:qamar/services/repositories.dart';
import 'package:qamar/state/app_state.dart';
import 'package:qamar/widgets/tree_overlay.dart';

void main() {
  final season = Season.ramadan1448;

  group('the season', () {
    test('shows itself a week before the first fast and stays a week after Eid', () {
      expect(season.days, 29);
      expect(season.phase(DateTime(2027, 1, 31)), SeasonPhase.none);
      expect(season.phase(DateTime(2027, 2, 1)), SeasonPhase.before);
      expect(season.phase(DateTime(2027, 2, 7, 23)), SeasonPhase.before);
      expect(season.phase(DateTime(2027, 2, 8)), SeasonPhase.during);
      expect(season.phase(DateTime(2027, 3, 8)), SeasonPhase.during);
      expect(season.phase(DateTime(2027, 3, 9)), SeasonPhase.after, reason: 'Eid');
      expect(season.phase(DateTime(2027, 3, 16)), SeasonPhase.after);
      expect(season.phase(DateTime(2027, 3, 17)), SeasonPhase.none);
    });

    test('counts the day of the month and the days to go', () {
      expect(season.dayOf(DateTime(2027, 2, 8, 9)), 1);
      expect(season.dayOf(DateTime(2027, 3, 8)), 29);
      expect(season.dayOf(DateTime(2027, 3, 9)), isNull);
      expect(season.daysUntil(DateTime(2027, 2, 1)), 7);
      expect(season.daysUntil(DateTime(2027, 2, 8)), isNull);
    });

    test('the server’s dates replace the estimate', () {
      final s = Season.fromJson({'key': 'ramadan_1448', 'name_ar': 'رمضان 1448', 'name_en': 'Ramadan 1448', 'starts_on': '2027-02-09', 'ends_on': '2027-03-10', 'eid_on': '2027-03-11'});
      expect(s.days, 30);
      expect(s.phase(DateTime(2027, 2, 8)), SeasonPhase.before, reason: 'the sighting moved the month a day');
    });
  });

  group('the sun over Cairo', () {
    test('iftar is at sunset and suhoor ends at dawn, to a few minutes', () {
      // Cairo, 8 February 2027 (UTC+2): sunset about 17:37, Fajr about 05:10.
      final feb8 = DateTime(2027, 2, 8);
      final sunset = SunTimes.sunset(feb8, utcOffsetMinutes: 120);
      final fajr = SunTimes.fajr(feb8, utcOffsetMinutes: 120);
      expect(sunset, inInclusiveRange(17 * 60 + 25, 17 * 60 + 50));
      expect(fajr, inInclusiveRange(4 * 60 + 55, 5 * 60 + 20));
      // A month on, the evening is later and the dawn earlier.
      final mar8 = DateTime(2027, 3, 8);
      expect(SunTimes.sunset(mar8, utcOffsetMinutes: 120), greaterThan(sunset + 10));
      expect(SunTimes.fajr(mar8, utcOffsetMinutes: 120), lessThan(fajr - 10));
      expect(SunTimes.clock(17 * 60 + 37), '17:37');
    });
  });

  group('hydration windows', () {
    final h = HydrationWindows(iftarMin: 17 * 60 + 37, fajrMin: 5 * 60 + 10);

    test('eight glasses in three windows between iftar and dawn', () {
      expect(h.windows.fold(0, (s, w) => s + w.glasses), 8);
      expect(HydrationWindows.goalMl, 2000);
      expect(h.windows.first.label(false), 'Iftar');
      expect(h.windows.last.toMin, 24 * 60 + 5 * 60 + 10, reason: 'suhoor ends at the next dawn');
    });

    test('knows which window is open, and when the person is fasting', () {
      expect(h.current(18 * 60)?.labelEn, 'Iftar');
      expect(h.current(21 * 60)?.labelEn, 'After taraweeh');
      expect(h.current(4 * 60)?.labelEn, 'Suhoor', reason: 'past midnight counts as the same night');
      expect(h.current(12 * 60), isNull);
      expect(h.fastingAt(12 * 60), isTrue);
      expect(h.fastingAt(19 * 60), isFalse);
      expect(h.fastingAt(4 * 60), isFalse);
    });
  });

  group('nudges on a fasting day', () {
    test('ask about iftar and suhoor instead of lunch and dinner', () {
      expect(NudgeSchedule.slotsFor(2, fasting: true), [MealSlot.iftar, MealSlot.suhoor]);
      expect(NudgeSchedule.slotsFor(2), [MealSlot.lunch, MealSlot.dinner]);
      final times = const MealTimes().withRamadan(iftar: 17 * 60 + 37, suhoor: 4 * 60 + 10);
      final s = NudgeSchedule.build(perDay: 2, times: times, now: DateTime(2027, 2, 10, 12), fasting: true);
      expect(s.first.slot, MealSlot.iftar);
      expect(s.first.at, DateTime(2027, 2, 10, 17, 37));
      expect(s.map((n) => n.id).toSet().length, s.length, reason: 'ids stay unique with five slots');
      expect(NudgeCopy.text(MealSlot.iftar, DateTime(2027, 2, 10), ar: true), contains('فطرت'));
      expect(NudgeCopy.all.any((t) => t.toLowerCase().contains('log') || t.contains('سجّل')), isFalse);
    });

    test('the clock’s slots follow the fast', () {
      expect(slotForHour(19, fasting: true), MealSlot.iftar);
      expect(slotForHour(3, fasting: true), MealSlot.suhoor);
      expect(slotForHour(19), MealSlot.dinner);
    });
  });

  group('the tree in season', () {
    test('a sixth node, Ramadan, evenly spaced; five otherwise', () {
      final six = treeNodesFor(ramadan: true);
      expect(six.map((n) => n.labelEn).toList(), ['Log', 'Plan', 'Water', 'Progress', 'Me', 'Ramadan']);
      for (var i = 0; i < six.length; i++) {
        expect(six[i].angle, closeTo(i * 60, 0.01));
      }
      expect(six.last.screen, AppScreen.ramadan);
      expect(treeNodesFor(ramadan: false), same(kTreeNodes));
    });
  });

  group('the app in season', () {
    AppState at(DateTime now) => AppState(clock: () => now);

    test('out of season nothing shows; in season the question is asked once', () {
      expect(at(DateTime(2026, 9, 21)).seasonVisible, isFalse);
      final s = at(DateTime(2027, 2, 3, 10));
      expect(s.seasonVisible, isTrue);
      expect(s.fastingPromptDue, isTrue);
      s.dismissFastingPrompt();
      expect(s.fastingPromptDue, isFalse);
    });

    test('saying yes turns the day into iftar and suhoor: two-litre water, sun-set times, seasonal questions', () async {
      final s = at(DateTime(2027, 2, 10, 12));
      await s.setFasting(true);
      expect(s.fasting, isTrue);
      expect(s.fastingPromptDue, isFalse);
      expect(s.water.goalMl, 2000);
      // The sun's times for the day, on the phone's own clock (the test host may not be in Cairo).
      expect(s.nudgeTimes.iftar, SunTimes.sunset(DateTime(2027, 2, 10)));
      expect(s.nudgeTimes.suhoor, SunTimes.fajr(DateTime(2027, 2, 10)) - 60, reason: 'the suhoor question comes an hour before dawn');
      expect(s.hydrationWindows.fastingAt(12 * 60), isTrue);
      await s.setFasting(false);
      expect(s.fasting, isFalse);
      expect(s.water.goalMl, 3000);
    });

    test('the switch is off outside the month even when set', () async {
      final s = at(DateTime(2027, 3, 12));
      await s.setFasting(true);
      expect(s.fasting, isFalse, reason: 'Eid: no fast, whatever the profile remembers');
      expect(s.seasonPhase, SeasonPhase.after);
    });
  });

  group('the Eid report', () {
    String iso(String x) => x;
    final target = 2000;

    test('reads the month back: days, average, scale, longest run', () {
      final history = [
        for (var d = 0; d < 29; d++)
          if (d != 10) DayTotals(day: DateTime(2027, 2, 8).add(Duration(days: d)), kcal: 1900, meals: 2),
        DayTotals(day: DateTime(2027, 2, 1), kcal: 5000, meals: 3),
      ];
      final r = EidReport.build(
        season: season,
        history: history,
        weights: [WeightReading(at: DateTime(2027, 2, 9), kg: 82.0), WeightReading(at: DateTime(2027, 3, 7), kg: 80.4), WeightReading(at: DateTime(2027, 1, 1), kg: 90)],
        targetKcal: target,
        iso: iso,
      );
      expect(r.daysLogged, 28);
      expect(r.full, isFalse);
      expect(r.avgKcal, 1900);
      expect(r.weightDelta, closeTo(-1.6, 0.001));
      expect(r.bestRun, 18);
      expect(r.lines.map((l) => l.en).join('\n'), allOf(contains('28 of 29 days'), contains('5% below'), contains('down 1.6 kg'), contains('18 days in a row')));
      expect(r.lines.any((l) => l.en.contains('9.6 kg')), isFalse, reason: 'the January reading is not the month');
    });

    test('a whole month is said plainly, and an empty one honestly', () {
      final full = EidReport.build(
        season: season,
        history: [for (var d = 0; d < 29; d++) DayTotals(day: DateTime(2027, 2, 8).add(Duration(days: d)), kcal: 2000, meals: 2)],
        weights: const [],
        targetKcal: target,
        iso: iso,
      );
      expect(full.full, isTrue);
      expect(full.lines.first.en, contains('the whole month'));
      expect(full.lines.any((l) => l.en.contains('about on your target')), isTrue);

      final empty = EidReport.build(season: season, history: const [], weights: const [], targetKcal: target, iso: iso);
      expect(empty.daysLogged, 0);
      expect(empty.avgKcal, isNull);
      expect(empty.lines.last.en, contains('Eid Mubarak'));
      expect(empty.text(ar: false, site: 'https://dr-qamar.com'), endsWith('https://dr-qamar.com'));
    });
  });
}
