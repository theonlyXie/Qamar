// What the moon says about a day (seat 4): unknown, under, at, over.
//
// An unlogged day reads as unknown, never dark — and so does every day on the
// general-guidance route, where there is no target to read a day against. A
// day's moon only brightens from the resting crescent, so logging a small
// meal never draws it darker than logging nothing. The halo warms only past
// what an estimate can tell apart from the target, not at 110%.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:qamar/models/meal.dart';
import 'package:qamar/models/profile.dart';
import 'package:qamar/models/review.dart';
import 'package:qamar/models/streak.dart';
import 'package:qamar/services/repositories.dart';
import 'package:qamar/state/app_state.dart';
import 'package:qamar/widgets/moon.dart';
import 'package:qamar/widgets/review_card.dart';

OrbDay _day(int kcal, {int? target = 2000, bool logged = true}) => OrbState.dayFor(consumedKcal: kcal, targetKcal: target, logged: logged);

void main() {
  group('the four states', () {
    test('nothing logged is unknown, whatever the target', () {
      expect(_day(0, logged: false), OrbDay.unknown);
      expect(_day(0, target: null, logged: false), OrbDay.unknown);
    });

    test('with no target (general guidance) a logged day is unknown too', () {
      expect(_day(1800, target: null), OrbDay.unknown);
      expect(_day(4000, target: null), OrbDay.unknown, reason: 'no target, nothing to be over');
    });

    test('under, then at within 5% (never under 100 kcal)', () {
      expect(_day(300), OrbDay.under);
      expect(_day(1899), OrbDay.under);
      expect(_day(1900), OrbDay.at);
      expect(_day(2000), OrbDay.at);
      expect(OrbState.atTolerance(1500), 100);
    });

    test('over only past what an estimate can tell apart: a quarter, or 400 kcal', () {
      expect(_day(2200), OrbDay.at, reason: '110% used to warm the halo; it is inside the estimate');
      expect(_day(2500), OrbDay.at);
      expect(_day(2501), OrbDay.over);
      expect(OrbState.overMargin(2000), 500);
      expect(OrbState.overMargin(1500), 400, reason: 'never under 400 kcal');
      expect(_day(1900, target: 1500), OrbDay.at);
      expect(_day(1901, target: 1500), OrbDay.over);
    });
  });

  group('the moon only brightens', () {
    test('an unknown day is the moon at rest: no phase is pinned', () {
      expect(OrbState.rest.moonPhase, isNull);
      final unknown = OrbState.derive(consumedKcal: 0, targetKcal: 2000, mealsToday: 0, planSlots: 3, streak: Streak.none);
      expect(unknown.day, OrbDay.unknown);
      expect(unknown.moonPhase, isNull, reason: 'the decorative drift, never a dark moon');
    });

    test('a day starts at the resting crescent and only brightens toward full', () {
      expect(OrbState.phaseForFill(0), OrbState.restPhase);
      var last = OrbState.restPhase;
      for (var kcal = 50; kcal <= 3000; kcal += 50) {
        final s = OrbState.derive(consumedKcal: kcal, targetKcal: 2000, mealsToday: 1, planSlots: 3, streak: Streak.none);
        final phase = s.moonPhase!;
        expect(phase, lessThanOrEqualTo(OrbState.restPhase), reason: '$kcal kcal is never darker than nothing logged');
        expect(phase, lessThanOrEqualTo(last), reason: 'more eaten, never darker');
        last = phase;
      }
      expect(last, moreOrLessEquals(OrbState.fullPhase));
    });

    test('the halo warms only for an over day', () {
      OrbState at(int kcal) => OrbState.derive(consumedKcal: kcal, targetKcal: 2000, mealsToday: 3, planSlots: 3, streak: Streak.none);
      expect(at(2200).over, isFalse);
      expect(at(2600).over, isTrue);
    });
  });

  group('in the app', () {
    test('Today’s orb: unknown before the first log, under after, unknown on general guidance', () {
      final s = AppState();
      expect(s.orbState().day, OrbDay.unknown);
      s.meals.add(LoggedMeal(name: 'فول', sub: '', kcal: 400, p: 20, c: 50, f: 10));
      expect(s.orbState().day, OrbDay.under);
      s.profile = s.profile.copyWith(safety: SafetyAnswer.pregnant);
      expect(s.generalGuidance, isTrue);
      expect(s.orbState().day, OrbDay.unknown, reason: 'no target on the general-guidance route');
      expect(s.orbState().moonPhase, isNull);
    });

    WeekReview review({bool hasTarget = true}) {
      final monday = DateTime(2026, 9, 21);
      final week = [
        for (var i = 0; i < 7; i++)
          DayTotals(day: monday.add(Duration(days: i)), kcal: i.isEven ? 1900 : 0, meals: i.isEven ? 2 : 0),
      ];
      return WeekReview.build(week: week, lastWeek: const [], targetKcal: 2000, streak: Streak.none, iso: (x) => x, hasTarget: hasTarget);
    }

    test('the week: an unlogged day is unknown, and every day is without a target', () {
      final r = review();
      expect(r.orbDays, [OrbDay.at, OrbDay.unknown, OrbDay.at, OrbDay.unknown, OrbDay.at, OrbDay.unknown, OrbDay.at]);
      expect(r.fills.where((f) => f == null).length, 3);
      expect(review(hasTarget: false).orbDays.toSet(), {OrbDay.unknown});
    });

    testWidgets('the shared card draws an unlogged day at rest, faint, never as a dark moon', (tester) async {
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(body: Center(child: ReviewCard(review: review(), isAr: false, showNumbers: false, showStreak: true, footer: 'x', iso: (x) => x))),
      ));
      final phases = tester.widgetList<QamarMoon>(find.byType(QamarMoon)).map((m) => m.staticPhase).toList();
      expect(phases, hasLength(7));
      expect(phases.where((p) => p == 1.0), isEmpty, reason: 'no day is drawn fully dark');
      expect(phases.where((p) => p == OrbState.restPhase), hasLength(3), reason: 'the three unlogged days rest');
    });
  });
}
