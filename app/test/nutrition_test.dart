// Logic tests for the parts of AppState where a silent wrong answer would
// matter most: the calorie maths, the eligibility gate, and the orb's
// hit-testing. All pure Dart — no widgets, no network.

import 'dart:ui' show Offset, Rect;

import 'package:flutter_test/flutter_test.dart';

import 'package:qamar/models/messages.dart';
import 'package:qamar/models/onboarding.dart';
import 'package:qamar/models/plan.dart';
import 'package:qamar/models/profile.dart';
import 'package:qamar/l10n/strings.dart';
import 'package:qamar/state/app_state.dart';
import 'package:qamar/state/chat_replies.dart';
import 'package:qamar/widgets/explain.dart';
import 'package:qamar/widgets/tree_overlay.dart';

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

  secondRound();
  languageTests();

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

/// Regression tests for the second round of front-end fixes.
void secondRound() {
  group('per-slot meal swap', () {
    test('swapping one slot leaves the others alone', () {
      final state = AppState();
      expect(state.isSlotSwapped('breakfast'), isFalse);

      state.toggleSlotSwap('breakfast');

      expect(state.isSlotSwapped('breakfast'), isTrue);
      // The original bug: one shared flag meant this also flipped.
      expect(state.isSlotSwapped('lunch'), isFalse);
      expect(state.isSlotSwapped('dinner'), isFalse);
    });

    test('each slot toggles independently and back', () {
      final state = AppState();
      for (final id in ['breakfast', 'lunch', 'dinner']) {
        state.toggleSlotSwap(id);
      }
      expect(state.swappedSlots, {'breakfast', 'lunch', 'dinner'});

      state.toggleSlotSwap('lunch');
      expect(state.isSlotSwapped('lunch'), isFalse);
      expect(state.isSlotSwapped('breakfast'), isTrue);
      expect(state.isSlotSwapped('dinner'), isTrue);
    });

    test('every slot has a distinct alternative under the same id', () {
      for (final (base, alt) in kPlanSlots) {
        expect(alt.id, base.id, reason: 'the alternative must fill the same slot');
        expect(alt.nameEn, isNot(base.nameEn));
        expect(mealKcal(alt), greaterThan(0));
      }
    });

    test('meal totals equal the sum of their portions', () {
      for (final (base, alt) in kPlanSlots) {
        for (final m in [base, alt]) {
          var sum = 0;
          for (final p in m.portions) {
            sum += p.kcal;
          }
          expect(mealKcal(m), sum);
        }
      }
    });
  });

  group('orb radial menu', () {
    test('hold opens the menu and clears any stale hover', () {
      final state = AppState();
      state.openTreeHold();
      expect(state.treeOpen, isTrue);
      expect(state.treeHold, isTrue);
      expect(state.treeHoverNode, isNull);
      expect(state.treeLogExpanded, isFalse);
    });

    test('ending the hold tears down all menu state', () {
      final state = AppState()..openTreeHold();
      state.setTreeHover(1, null);
      state.expandTreeLog(1);
      state.endTreeHold();

      expect(state.treeHold, isFalse);
      expect(state.treeHoverNode, isNull);
      expect(state.treeHoverSub, isNull);
      expect(state.treeLogExpanded, isFalse);
    });

    test('quick logging opens the conversation and never changes screen', () {
      final state = AppState()..openTreeHold();
      final before = state.screen;
      state.quickLog(QuickLog.text);

      expect(state.treeOpen, isFalse);
      expect(state.treeHold, isFalse);
      expect(state.chatOpen, isTrue);
      expect(state.screen, before, reason: 'logging must not push a page');
    });

    test('speaking opens the conversation and tries to listen for real', () async {
      // No Dictation injected — the device has no recogniser, as far as this
      // AppState is concerned.
      final state = AppState()..openTreeHold();
      state.quickLog(QuickLog.voice);
      await Future<void>.delayed(const Duration(milliseconds: 50));

      expect(state.chatOpen, isTrue);
      // It must NOT pretend to listen. The old implementation sat in
      // `listening` for 1.5s and then inserted a scripted sentence; the real
      // one reports that dictation is unavailable and leaves typing open.
      expect(state.chatState, ChatState.idle);
      expect(state.dictationError, isNotNull);
      expect(state.chat.any((c) => c.who == ChatWho.u), isFalse,
          reason: 'nothing may be said on the user behalf');
    });

    test('an unconnected assistant admits it rather than inventing a reply', () async {
      final state = AppState();
      expect(state.hasAssistant, isFalse);

      await state.sendChatMsg('how much protein today?');

      final reply = state.chat.lastWhere((c) => c.who == ChatWho.q);
      // The canned replies live in chat_replies.dart; none of them may appear.
      expect(kChatRepliesEn.any((r) => r.d == reply.text), isFalse,
          reason: 'a scripted answer must never be presented as the assistant');
      expect(state.chatState, ChatState.idle);
    });

    test('a photographed meal lands in the conversation, not a confirm page', () {
      final state = AppState();
      final before = state.screen;
      state.quickLog(QuickLog.photo);
      state.logPhotoTaken('/tmp/meal.jpg');

      expect(state.screen, before);
      expect(state.chatOpen, isTrue);
      expect(state.lastMealPhotoPath, '/tmp/meal.jpg');
      expect(state.chat.any((c) => c.who == ChatWho.u), isTrue);
    });

    test('the log methods sit on distinct ring positions', () {
      final seen = <Offset>{};
      for (var i = 0; i < kLogMethods.length; i++) {
        final c = TreeGeometry.localSubCenter(1, i);
        for (final other in seen) {
          // Overlapping circles were why only one of them could be tapped.
          expect((c - other).distance, greaterThan(60), reason: 'methods overlap');
        }
        seen.add(c);
      }
      expect(seen.length, kLogMethods.length);
    });

    test('exactly one node is the log action, and it has no destination', () {
      final logs = kTreeNodes.where((n) => n.action == TreeAction.log).toList();
      expect(logs.length, 1);
      expect(logs.single.screen, isNull, reason: 'logging must not open a page');
    });

    test('the tree still reaches the wallet', () {
      expect(kTreeNodes.any((n) => n.screen == AppScreen.wallet), isTrue);
    });
  });

  group('birth-date wheels', () {
    test('setting a month clamps an out-of-range day', () {
      final state = AppState();
      state.setBirthDay(31);
      state.setBirthMonth(2);
      expect(state.profile.birthMonth, 2);
      expect(state.profile.birthDay, lessThanOrEqualTo(state.birthMonthLength));
      expect(state.birthMonthLength, anyOf(28, 29), reason: 'February');
    });

    test('height and weight setters clamp to their ranges', () {
      final state = AppState();
      state.setHeight(999);
      state.setWeight(1);
      expect(state.profile.height, lessThanOrEqualTo(210));
      expect(state.profile.weight, greaterThanOrEqualTo(40));
    });
  });

  group('explanations', () {
    test('a meal explanation names every portion and its amount', () {
      final (lunch, _) = kPlanSlots[1];
      final ex = mealExplanation(lunch);

      for (final p in lunch.portions) {
        expect(ex.bodyEn, contains(p.en));
        expect(ex.bodyEn, contains(p.amountEn));
        expect(ex.bodyAr, contains(p.ar));
      }
      expect(ex.bodyEn, contains('${mealKcal(lunch)}'));
    });
  });
}

/// Language switching must be available and non-destructive.
void languageTests() {
  group('language', () {
    test('defaults to Arabic, right-to-left', () {
      final state = AppState();
      expect(state.lang, AppLang.ar);
      expect(state.isAr, isTrue);
      expect(state.lang.isRtl, isTrue);
    });

    test('switching mid-onboarding keeps answers and position', () async {
      final state = AppState();
      state.profile = state.profile.copyWith(age: 30);
      state.primarySubmit();
      await settle();
      final stepBefore = state.step;

      state.setLang(AppLang.en);

      expect(state.lang, AppLang.en);
      expect(state.lang.isRtl, isFalse);
      expect(state.step, stepBefore, reason: 'must not restart the conversation');
      expect(state.profile.age, 30, reason: 'answers already given must survive');
      expect(state.msgs, isNotEmpty);
    });

    test('every onboarding step has both languages', () {
      for (final step in kOnboardingSteps) {
        expect(step.askAr.trim(), isNotEmpty, reason: step.id);
        expect(step.askEn.trim(), isNotEmpty, reason: step.id);
        expect(step.askAr, isNot(step.askEn), reason: '${step.id} is untranslated');
        for (final o in step.options) {
          expect(o.ar.trim(), isNotEmpty, reason: '${step.id} option');
          expect(o.en.trim(), isNotEmpty, reason: '${step.id} option');
        }
      }
    });

    test('tree and log labels are translated', () {
      for (final n in kTreeNodes) {
        expect(n.label(true).trim(), isNotEmpty);
        expect(n.label(false).trim(), isNotEmpty);
        expect(n.label(true), isNot(n.label(false)));
      }
      for (final m in kLogMethods) {
        expect(m.label(true), isNot(m.label(false)));
      }
    });

    test('explanations carry both languages', () {
      for (final e in kExplanations.entries) {
        expect(e.value.titleAr, isNot(e.value.titleEn), reason: e.key);
        expect(e.value.bodyAr.trim(), isNotEmpty, reason: e.key);
        expect(e.value.bodyEn.trim(), isNotEmpty, reason: e.key);
        expect(e.value.soWhatAr.trim(), isNotEmpty, reason: e.key);
        expect(e.value.soWhatEn.trim(), isNotEmpty, reason: e.key);
      }
    });
  });
}
