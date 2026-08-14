// Logic tests for the parts of AppState where a silent wrong answer would
// matter most: the calorie maths, the eligibility gate, and the orb's
// hit-testing. All pure Dart — no widgets, no network.

import 'dart:ui' show Offset, Rect;

import 'package:flutter_test/flutter_test.dart';

import 'package:qamar/models/onboarding.dart';
import 'package:qamar/models/profile.dart';
import 'package:qamar/state/app_state.dart';
import 'package:qamar/widgets/explain.dart';

/// Long enough for answerStep's 260ms hand-off plus a margin.
Future<void> settle() => Future<void>.delayed(const Duration(milliseconds: 500));

void main() {
  group('Mifflin-St Jeor', () {
    test('applies the sex-specific constant', () {
      final male = AppState()..profile = const Profile(gender: Gender.male);
      final female = AppState()..profile = const Profile(gender: Gender.female);

      // The equations differ only by +5 vs -161 on the BMR, which the activity
      // factor then scales.
      final delta = male.target().kcal - female.target().kcal;
      expect(delta, closeTo(166 * 1.5, 10));
      expect(male.target().kcal, greaterThan(female.target().kcal));
    });

    test('a lose goal lands below a maintain goal', () {
      final lose = AppState()..profile = const Profile(goal: Goal.lose);
      final maintain = AppState()..profile = const Profile(goal: Goal.maintain);
      expect(lose.target().kcal, lessThan(maintain.target().kcal));
    });

    test('never returns an unsafely low target', () {
      final tiny = AppState()
        ..profile = const Profile(weight: 40, height: 140, goal: Goal.lose, activity: 1.35);
      expect(tiny.target().kcal, greaterThanOrEqualTo(1500));
    });

    test('macros are consistent with the calorie total', () {
      final t = (AppState()..profile = const Profile()).target();
      final fromMacros = t.protein * 4 + t.carbs * 4 + t.fat * 9;
      expect(fromMacros, closeTo(t.kcal, 12));
    });
  });

  group('age', () {
    test('counts a birthday that has not happened yet this year', () {
      final now = DateTime.now();
      final tomorrow = now.add(const Duration(days: 1));
      final p = Profile(birthYear: now.year - 30, birthMonth: tomorrow.month, birthDay: tomorrow.day);
      // Only decrement when tomorrow is genuinely later in the same year.
      if (tomorrow.year == now.year) expect(p.age, 29);
    });

    test('clamps February correctly on a leap year', () {
      expect(Profile.daysInMonth(2024, 2), 29);
      expect(Profile.daysInMonth(2025, 2), 28);
      expect(Profile.daysInMonth(2000, 2), 29);
      expect(Profile.daysInMonth(1900, 2), 28);
    });

    test('copyWith(age:) round-trips', () {
      for (final want in [18, 25, 40, 67]) {
        expect(const Profile().copyWith(age: want).age, want);
      }
    });
  });

  group('eligibility gate', () {
    test('an under-18 birth date blocks before any target is calculated', () async {
      final state = AppState();
      expect(kOnboardingSteps.first.id, 'dob');

      state.profile = state.profile.copyWith(age: 15);
      state.primarySubmit();
      await settle();

      expect(state.blocked, isTrue);
      expect(state.minor, isTrue);
      expect(state.step, 0, reason: 'must not advance past the gate');
    });

    test('an adult birth date advances', () async {
      final state = AppState();
      state.profile = state.profile.copyWith(age: 30);
      state.primarySubmit();
      await settle();

      expect(state.blocked, isFalse);
      expect(state.step, 1);
    });

    test('exactly 18 is allowed', () async {
      final state = AppState();
      state.profile = state.profile.copyWith(age: 18);
      state.primarySubmit();
      await settle();

      expect(state.blocked, isFalse);
    });
  });

  group('birth-date steppers', () {
    test('month wraps and clamps the day', () {
      final state = AppState();
      state.profile = state.profile.copyWith(birthMonth: 1, birthDay: 31);
      state.bumpBirthMonth(1); // -> February
      expect(state.profile.birthMonth, 2);
      expect(state.profile.birthDay, lessThanOrEqualTo(29));
    });

    test('year stays inside a sane range', () {
      final state = AppState();
      for (var i = 0; i < 200; i++) {
        state.bumpBirthYear(1);
      }
      expect(state.profile.birthYear, lessThanOrEqualTo(DateTime.now().year - 10));
    });
  });

  group('explain registry', () {
    test('the smallest matching region wins', () {
      final reg = ExplainRegistry.instance;
      reg.register('card', const Rect.fromLTWH(0, 0, 300, 200));
      reg.register('value', const Rect.fromLTWH(10, 10, 60, 30));

      expect(reg.hitTest(const Offset(30, 20)), 'value');
      expect(reg.hitTest(const Offset(250, 150)), 'card');
      expect(reg.hitTest(const Offset(400, 400)), isNull);

      reg.unregister('card');
      reg.unregister('value');
    });

    test('every explainable id used in the UI has copy behind it', () {
      // Guards against wiring up an Explainable whose id has no entry, which
      // would open an empty sheet.
      for (final id in ['kcal_remaining', 'protein', 'carbs', 'fat', 'su_points', 'level', 'plan_total', 'target_kcal']) {
        expect(kExplanations[id], isNotNull, reason: 'missing explanation for "$id"');
      }
    });
  });
}
