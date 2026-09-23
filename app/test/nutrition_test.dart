// Logic tests for the parts of AppState where a silent wrong answer would
// matter most: the calorie maths, the eligibility gate, and the orb's
// hit-testing. All pure Dart — no widgets, no network.

import 'dart:convert';
import 'dart:ui' show Offset, Rect;

import 'package:flutter_test/flutter_test.dart';

import 'package:qamar/models/activity.dart';
import 'package:qamar/models/basket.dart';
import 'package:qamar/models/pending_write.dart';
import 'package:qamar/models/plan.dart';
import 'package:qamar/models/meal.dart';
import 'package:qamar/models/messages.dart';
import 'package:qamar/models/onboarding.dart';
import 'package:qamar/models/profile.dart';
import 'package:qamar/models/quest.dart';
import 'package:qamar/models/streak.dart';
import 'package:qamar/models/su_economy.dart';
import 'package:qamar/models/billing.dart';
import 'package:qamar/models/water.dart';
import 'package:qamar/services/ai_gateway.dart';
import 'package:qamar/services/device_prefs.dart';
import 'package:qamar/l10n/strings.dart';
import 'package:qamar/state/app_state.dart';
import 'package:qamar/state/chat_replies.dart';
import 'package:qamar/widgets/explain.dart';
import 'package:qamar/theme/colors.dart';
import 'package:qamar/widgets/living_orb.dart';
import 'package:qamar/widgets/tree_overlay.dart';

/// Long enough for answerStep's 260ms hand-off plus a margin.
Future<void> settle() => Future<void>.delayed(const Duration(milliseconds: 500));

/// A plan as the gateway actually returns it, parsed by the real client code.
///
/// Testing the constants that used to live in models/plan.dart proved only
/// that they had been typed correctly. This exercises the path a real plan
/// takes: JSON off the wire, through HttpAiGateway's parser, into the app.
/// Dinner deliberately arrives with no "alt" — the gateway is allowed to omit
/// one, and the app has to notice rather than offer a swap to nothing.
const _planJson = '''
{"date":"2026-08-15","plan":{
  "rationale_ar":"مناسب لهدفك","rationale_en":"Fits your target",
  "meals":[
    {"slot":"breakfast","name_ar":"فول","name_en":"Foul","note_ar":"","note_en":"",
     "portions":[{"ar":"فول","en":"Foul","amount_ar":"١٥٠ جم","amount_en":"150 g","kcal":180},
                 {"ar":"عيش","en":"Bread","amount_ar":"رغيف","amount_en":"1 loaf","kcal":140}],
     "alt":{"name_ar":"بيض وجبنة","name_en":"Eggs and cheese","note_ar":"","note_en":"",
            "portions":[{"ar":"بيض","en":"Eggs","amount_ar":"٢","amount_en":"2","kcal":160},
                        {"ar":"جبنة","en":"Cheese","amount_ar":"٣٠ جم","amount_en":"30 g","kcal":160}]}},
    {"slot":"dinner","name_ar":"تونة","name_en":"Tuna","note_ar":"","note_en":"",
     "portions":[{"ar":"تونة","en":"Tuna","amount_ar":"علبة","amount_en":"1 tin","kcal":130}]}
  ]}}
''';

DayPlan parsedPlan() => PlanOnlyGateway().parse(_planJson);

/// Reuses the shipping parser rather than reimplementing it in the test.
class PlanOnlyGateway extends HttpAiGateway {
  PlanOnlyGateway() : super(baseUrl: 'http://test', authTokenProvider: _noToken);
  static String _noToken() => '';
  DayPlan parse(String body) => planFromBody(body, 'en', '2026-08-15');
}

void main() {
  basketTests();
  pendingWriteTests();
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

  group('Su Points scale', () {
    test('a new wallet is level 1, and signing up does not buy a level', () {
      expect(SuEconomy.levelFor(0), 1);
      expect(SuEconomy.levelFor(SuEconomy.signupBonus), 1);
      expect(SuEconomy.levelFor(SuEconomy.onboarding + SuEconomy.firstMeal + SuEconomy.mealLogged * 5), 3);
      expect(SuEconomy.levelFor(99 * SuEconomy.levelXp), 99);
      expect(SuEconomy.levelFor(200000), SuEconomy.maxLevel);
    });

    test('the earn and spend table is in hundreds, not 3 / 5 / 20', () {
      expect(SuEconomy.dailyQuest, greaterThanOrEqualTo(100));
      expect(SuEconomy.mealLogged, greaterThanOrEqualTo(100));
      expect(SuEconomy.extraAiUse, greaterThanOrEqualTo(SuEconomy.mealLogged));
      expect(SuEconomy.signupBonus, 100, reason: 'the signup trigger (migration 0004) pays 100; the phone mirrors the ledger');
    });
  });

  group('daily quest', () {
    test('the phone has no way to pay the quest: nothing credits it, however often the card is used', () {
      // The loop that used to mint (accept, replace, accept…) has no
      // equivalent now: the card's only control puts the quest away, and the
      // server pays it from the meal or glass that meets it (0061).
      final state = AppState();
      state.quest = DayQuest(kind: QuestKind.lunchBy16, done: false, expiresAt: DateTime.now().add(const Duration(hours: 2)));
      final start = state.suAvailable;
      for (var i = 0; i < 5; i++) {
        state.skipQuest();
      }
      expect(state.suAvailable, start);
      expect(state.ledger(), isEmpty);
      expect(state.questDue, isFalse, reason: 'put away for the day');
      state.dispose();
    });
  });

  group('Qamar+ Egypt billing', () {
    test('is priced in EGP for Paymob, one plan, 500 a month', () {
      expect(PlusCatalog.currency, 'EGP');
      expect(PlusCatalog.provider, 'paymob');
      expect(PlusCatalog.monthly.amountPounds, 500);
      expect(PlusCatalog.monthly.amountCents, 50000);
      expect(PlusCatalog.monthly.periodDays, 30);
      expect(PlusPlan.values, [PlusPlan.monthly]);
      expect(PlusCatalog.byId('annual'), PlusCatalog.monthly);
    });

    test('a first purchase costs the same as every other one', () {
      final q = PlusPricing.quote(plan: 'monthly', firstPurchase: true);
      expect(q.amountPounds, 500);
      expect(q.pricingReason, 'list');
      expect(q.discounted, isFalse);
    });

    test("a professional's code leaves the price alone and sends them 20% for 12 months", () {
      final q = PlusPricing.quote(
        plan: 'monthly',
        firstPurchase: true,
        promo: const PlusPromo(code: 'QMR7K2P', kind: 'affiliate', ownerUserId: 'dr-sara'),
        buyerUserId: 'client',
      );
      expect(q.amountPounds, 500);
      expect(q.discounted, isFalse);
      expect(q.pricingReason, 'affiliate');
      expect(q.affiliateCommissionCents, 10000);
      expect(PlusCatalog.proShareCents, 10000);
      expect(PlusCatalog.proShareMonths, 12);
      expect(q.promoError, isNull);
    });

    test('you cannot use your own code', () {
      final q = PlusPricing.quote(
        plan: 'monthly',
        firstPurchase: true,
        promo: const PlusPromo(code: 'QMR7K2P', kind: 'affiliate', ownerUserId: 'me'),
        buyerUserId: 'me',
      );
      expect(q.amountPounds, 500);
      expect(q.affiliateCommissionCents, 0);
      expect(q.promoError, isNotNull);
    });

    test('the professional is paid in EGP, not Su Points', () {
      expect(AffiliateWallet.empty.currency, 'EGP');
      expect(AffiliateWallet.empty.canRedeem, isFalse);
      expect(const AffiliateWallet(balanceCents: 5000).canRedeem, isTrue);
    });
  });

  group('water', () {
    test('a glass is 250 ml and a bottle is two glasses', () {
      expect(Water.glassMl, 250);
      expect(Water.bottleMl, 500);
      expect(Water.goalMl, 3000);
      expect(Water.mlFor(WaterUnit.bottle), Water.glassMl * 2);
    });

    test('the card reads glasses, bottles, litres, and litres left from one total', () {
      const empty = WaterStatus(0);
      expect(empty.glasses, 0);
      expect(empty.bottles, 0);
      expect(empty.litres, 0);
      expect(empty.litresLeft, 3);

      const oneGlass = WaterStatus(250);
      expect(oneGlass.glasses, 1);
      expect(oneGlass.bottles, 0.5);
      expect(oneGlass.litres, 0.25);
      expect(oneGlass.litresLeft, 2.75);

      const goal = WaterStatus(3000);
      expect(goal.glasses, 12);
      expect(goal.bottles, 6);
      expect(goal.litres, 3);
      expect(goal.litresLeft, 0);
      expect(WaterStatus.qty(goal.litres), '3');
      expect(WaterStatus.qty(oneGlass.litres), '0.25');
    });

    test('logging a glass then a bottle adds, and undo takes the last sip off', () {
      final state = AppState();
      expect(state.water.isEmpty, isTrue);

      state.logWater(WaterUnit.glass);
      state.logWater(WaterUnit.bottle);

      expect(state.water.ml, 750);
      expect(state.water.glasses, 3);
      expect(state.water.bottles, 1.5);
      expect(state.water.litresLeft, 2.25);

      state.undoWater();
      expect(state.water.ml, 250);
      state.undoWater();
      expect(state.water.isEmpty, isTrue);
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
    final dob = kOnboardingSteps.indexWhere((s) => s.id == 'dob');
    final targetInputs = ['gender', 'body', 'activity'].map((id) => kOnboardingSteps.indexWhere((s) => s.id == id));

    test('the date of birth comes after the goal and before every question that feeds the target', () {
      expect(dob, greaterThan(kOnboardingSteps.indexWhere((s) => s.id == 'goal')));
      for (final i in targetInputs) {
        expect(dob, lessThan(i), reason: 'the 18+ gate runs before any target input');
      }
    });

    test('an under-18 birth date blocks before any target is calculated', () async {
      final state = AppState();
      state.step = dob;
      state.profile = state.profile.copyWith(age: 15);
      state.primarySubmit();
      await settle();

      expect(state.blocked, isTrue);
      expect(state.minor, isTrue);
      expect(state.step, dob, reason: 'must not advance past the gate');
    });

    test('an adult birth date advances', () async {
      final state = AppState();
      state.step = dob;
      state.profile = state.profile.copyWith(age: 30);
      state.primarySubmit();
      await settle();

      expect(state.blocked, isFalse);
      expect(state.step, dob + 1);
    });

    test('exactly 18 is allowed', () async {
      final state = AppState();
      state.step = dob;
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
  streakAndOrb();
  gesturesAndDigits();
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
      for (final id in ['kcal_remaining', 'protein', 'carbs', 'fat', 'su_points', 'level', 'plan_total', 'target_kcal', 'water', 'streak']) {
        expect(kExplanations[id], isNotNull, reason: 'missing explanation for "$id"');
      }
    });
  });
}

void gesturesAndDigits() {
  group('three gestures, taught by doing', () {
    test('the card stays until each gesture has actually been made', () async {
      final state = AppState();
      expect(state.orbTutorialDone, isFalse);
      expect(state.gesturesLearned, isEmpty);

      state.orbTap();
      expect(state.gesturesLearned, {OrbGesture.tap});
      expect(state.orbTutorialDone, isFalse);

      await state.holdOrb();
      expect(state.gesturesLearned, containsAll([OrbGesture.tap, OrbGesture.hold]));
      expect(state.orbTutorialDone, isFalse);

      state.openExplain(kExplanations['protein']!);
      expect(state.orbTutorialDone, isTrue);
    });

    test('“Got it” dismisses it without pretending the gestures were learned', () {
      final state = AppState();
      state.dismissOrbTutorial();
      expect(state.orbTutorialDone, isTrue);
      expect(state.gesturesLearned, isEmpty);
    });

    test('a phone remembers that it has been taught', () async {
      final prefs = MemoryDevicePrefs();
      final first = AppState(prefs: prefs);
      first.orbTap();
      await first.holdOrb();
      first.openExplain(kExplanations['protein']!);
      await Future<void>.delayed(Duration.zero);

      final second = AppState(prefs: prefs);
      await Future<void>.delayed(Duration.zero);
      expect(second.orbTutorialDone, isTrue, reason: 'the same phone, a new launch');

      expect(AppState(prefs: MemoryDevicePrefs()).orbTutorialDone, isFalse, reason: 'a different phone starts fresh');
    });
  });

  group('digits', () {
    test('Arabic draws ٠١٢ by default and can switch to 012; English is untouched', () async {
      final state = AppState();
      expect(state.isAr, isTrue);
      expect(state.iso('82'), '\u2066٨٢\u2069');
      expect(state.formatSu(2500), '٢٬٥٠٠');

      state.setEasternDigits(false);
      expect(state.iso('82'), '\u206682\u2069');
      expect(state.formatSu(2500), '2,500');

      state.setLang(AppLang.en);
      state.setEasternDigits(true);
      expect(state.iso('82'), '\u206682\u2069', reason: 'the preference is Arabic-only');
    });

    test('the choice survives a relaunch on the same phone', () async {
      final prefs = MemoryDevicePrefs();
      AppState(prefs: prefs).setEasternDigits(false);
      await Future<void>.delayed(Duration.zero);
      final again = AppState(prefs: prefs);
      await Future<void>.delayed(Duration.zero);
      expect(again.easternDigits, isFalse);
    });

    test('EGP follows the same preference', () {
      expect(formatEgp(500, ar: true), '٥٠٠ ج.م');
      expect(formatEgp(500, ar: true, eastern: false), '500 ج.م');
      expect(formatEgp(500, ar: false), 'EGP 500');
    });
  });
}

void streakAndOrb() {
  final today = DateTime(2026, 9, 20);
  DateTime ago(int d) => today.subtract(Duration(days: d));

  group('streak', () {
    test('consecutive logged days count back from yesterday when today is empty', () {
      final s = Streak.fromDays([ago(1), ago(2), ago(3)], today: today);
      expect(s.current, 3);
      expect(s.todayCounted, isFalse);
      expect(s.atRisk, isTrue);
    });

    test('today counts as soon as it has a meal', () {
      final s = Streak.fromDays([today, ago(1)], today: today);
      expect(s.current, 2);
      expect(s.todayCounted, isTrue);
      expect(s.atRisk, isFalse);
    });

    test('a gap two days ago ends the run there, but the old run is still the best', () {
      final s = Streak.fromDays([today, ago(1), ago(3), ago(4), ago(5), ago(6)], today: today);
      expect(s.current, 2);
      expect(s.best, 4);
    });

    test('a frozen day bridges the gap; the client never invents one', () {
      final s = Streak.fromDays([today, ago(1), ago(3)], today: today, frozenDays: [ago(2)]);
      expect(s.current, 4);
      expect(s.frozenDays, [ago(2)]);
      expect(Streak.fromDays([today, ago(1), ago(3)], today: today).current, 2);
    });

    test('nothing logged is zero, not at risk', () {
      final s = Streak.fromDays(const [], today: today);
      expect(s.current, 0);
      expect(s.atRisk, isFalse);
    });

    test('the server snapshot parses', () {
      final s = Streak.fromJson({'current': 4, 'best': 9, 'today_counted': true, 'freezes_available': 1, 'frozen_days': ['2026-09-17']});
      expect(s.current, 4);
      expect(s.best, 9);
      expect(s.todayCounted, isTrue);
      expect(s.freezesAvailable, 1);
      expect(s.frozenDays.single, DateTime(2026, 9, 17));
    });
  });

  group('orb state', () {
    test('an empty day is unknown: the moon at rest, never a dark crescent, and no meals counted', () {
      final o = OrbState.derive(consumedKcal: 0, targetKcal: 2000, mealsToday: 0, planSlots: 3, streak: Streak.none);
      expect(o.day, OrbDay.unknown);
      expect(o.fill, 0);
      expect(o.glow, 0);
      expect(o.over, isFalse);
      expect(o.moonPhase, isNull, reason: 'the resting drift, as on every screen not reading a day; it used to pin 0.92, near dark');
    });

    test('a day at target is a near-full moon', () {
      final o = OrbState.derive(consumedKcal: 2000, targetKcal: 2000, mealsToday: 3, planSlots: 3, streak: Streak.none);
      expect(o.fill, 1);
      expect(o.glow, 1);
      expect(o.moonPhase, closeTo(0.06, 1e-9));
      expect(o.over, isFalse);
    });

    test('running over the target warms the glow instead of filling further', () {
      final o = OrbState.derive(consumedKcal: 2600, targetKcal: 2000, mealsToday: 4, planSlots: 3, streak: Streak.none);
      expect(o.fill, 1);
      expect(o.over, isTrue);
    });

    test('without a plan the glow reads meals against three', () {
      final o = OrbState.derive(consumedKcal: 600, targetKcal: 2000, mealsToday: 1, planSlots: 0, streak: Streak.none);
      expect(o.glow, closeTo(1 / 3, 1e-9));
    });

    test('the state follows the app: logging a meal fills the moon and starts the ring', () {
      final state = AppState();
      final before = state.orbState();
      expect(before.fill, 0);
      expect(before.streak.current, 0);

      state.meals.add(const LoggedMeal(name: 'Koshary', sub: 'typed', kcal: 700, p: 16, c: 120, f: 10));
      final after = state.orbState();
      expect(after.fill, greaterThan(0));
      expect(after.streak.current, 1);
      expect(after.streak.todayCounted, isTrue);
    });
  });

  group('streak ring', () {
    test('fills one segment a day and closes at seven', () {
      expect(StreakRingPainter.fraction(0), 0);
      expect(StreakRingPainter.fraction(1), closeTo(1 / 7, 1e-9));
      expect(StreakRingPainter.fraction(7), 1);
      expect(StreakRingPainter.fraction(8), closeTo(1 / 7, 1e-9));
      expect(StreakRingPainter.fraction(14), 1);
    });

    test('the dots grow with the run, in the one ink (no colour warms)', () {
      expect({for (final n in [1, 3, 7, 30]) StreakRingPainter.colorFor(n)}, {QColors.ink});
      expect(StreakRingPainter.dotScale(1), lessThan(StreakRingPainter.dotScale(3)));
      expect(StreakRingPainter.dotScale(3), lessThan(StreakRingPainter.dotScale(7)));
      expect(StreakRingPainter.dotScale(7), StreakRingPainter.dotScale(30));
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

    test('a parsed plan keeps each alternative in its own slot', () {
      final plan = parsedPlan();

      expect(plan.slots.length, 2);
      for (final (base, alt) in plan.slots) {
        expect(alt.id, base.id, reason: 'the alternative must fill the same slot');
        expect(mealKcal(base), greaterThan(0));
      }
      expect(plan.slots.first.$1.id, 'breakfast');
      expect(plan.slots.first.$2.nameEn, isNot(plan.slots.first.$1.nameEn));
    });

    test('a chat reply that rewrote dinner is the same shape Plan already parses', () {
      final result = chatResultFromJson(
        jsonDecode('''
{"reply":"I’ll change dinner.","action":"See the plan","date":"2026-08-15",
 "plan":{"rationale_en":"Fits your target","meals":[
   {"slot":"dinner","name_ar":"بيض","name_en":"Eggs","note_ar":"","note_en":"",
    "portions":[{"ar":"بيض","en":"Eggs","amount_ar":"٢","amount_en":"2","kcal":160}]}
 ]}}
''') as Map<String, dynamic>,
        lang: 'en',
        date: '2026-08-15',
      );
      expect(result.changedPlan, isTrue);
      expect(result.plan!.slots.single.$1.nameEn, 'Eggs');
      expect(mealKcal(result.plan!.slots.single.$1), 160);
    });

    test('a rebuild instruction is read even when the meals are not in the reply', () {
      final result = chatResultFromJson({
        'reply': 'I’ll rewrite the day.',
        'plan_update': {'kind': 'rebuild', 'instruction': 'no cooking tonight'},
      }, lang: 'en', date: '2026-08-17');
      expect(result.plan, isNull);
      expect(result.rebuildInstruction, 'no cooking tonight');
    });

    test('meal totals equal the sum of their portions', () {
      for (final (base, alt) in parsedPlan().slots) {
        for (final m in [base, alt]) {
          var sum = 0;
          for (final p in m.portions) {
            sum += p.kcal;
          }
          expect(mealKcal(m), sum);
        }
      }
    });

    test('a meal with no alternative offered gets no swap button', () async {
      final state = AppState(ai: PlanOnlyGateway(), userId: null);
      // dinner comes back without an "alt", so it must not offer a swap.
      state.plan = parsedPlan();
      expect(state.slotHasAlternative('breakfast'), isTrue);
      expect(state.slotHasAlternative('dinner'), isFalse,
          reason: 'a slot whose alternative is itself must not pretend to swap');
    });

    test('with no plan there are no meals, and none are invented', () {
      final state = AppState();
      expect(state.hasPlan, isFalse);
      expect(state.planMeals(), isEmpty);
      expect(state.nextMeal(), isNull);
    });
  });

  group('orb radial menu', () {
    test('tapping the orb on Today opens the tree, and again closes it', () {
      final state = AppState()..go(AppScreen.today);
      state.orbTap();
      expect(state.treeOpen, isTrue);
      state.orbTap();
      expect(state.treeOpen, isFalse);
    });

    test('tapping the orb anywhere else is Back to Today, not the menu', () {
      for (final s in [AppScreen.plan, AppScreen.progress, AppScreen.you, AppScreen.wallet, AppScreen.subscription]) {
        final state = AppState()..go(s);
        state.orbTap();
        expect(state.screen, AppScreen.today, reason: 'from $s');
        expect(state.treeOpen, isFalse, reason: 'from $s');
      }
    });

    test('holding the orb opens the conversation and tries to listen for real', () async {
      // No Dictation injected — the device has no recogniser, as far as this
      // AppState is concerned.
      final state = AppState()..go(AppScreen.today);
      state.toggleTree();
      await state.holdOrb();

      expect(state.chatOpen, isTrue);
      expect(state.treeOpen, isFalse, reason: 'the menu folds when the conversation opens');
      // It must NOT pretend to listen: it reports that dictation is unavailable
      // and leaves typing open, and nothing is said on the user's behalf.
      expect(state.chatState, ChatState.idle);
      expect(state.dictationError, isNotNull);
      expect(state.chat.any((c) => c.who == ChatWho.u), isFalse);
    });

    test('Log fans out its methods, Water fans out its units, never both', () {
      final state = AppState()..toggleTree();
      final log = kTreeNodes.indexWhere((n) => n.action == TreeAction.log);
      final water = kTreeNodes.indexWhere((n) => n.action == TreeAction.water);
      state.expandTreeLog(log);
      expect(state.treeLogExpanded, isTrue);
      expect(state.treeWaterExpanded, isFalse);
      state.expandTreeWater(water);
      expect(state.treeWaterExpanded, isTrue);
      expect(state.treeLogExpanded, isFalse);
      state.closeTree();
      expect(state.treeExpanded, isFalse);
      expect(state.treeOpen, isFalse);
    });

    test('one tap on a water unit logs it and closes the tree', () {
      final state = AppState()..toggleTree();
      final before = state.screen;
      state.quickWater(WaterUnit.tea);
      expect(state.treeOpen, isFalse);
      expect(state.water.ml, Water.teaMl);
      expect(state.screen, before, reason: 'water never pushes a page');
      expect(kWaterChoices.map((c) => c.unit).toSet(), WaterUnit.values.toSet());
    });

    test('quick logging opens the conversation and never changes screen', () {
      final state = AppState()..toggleTree();
      final before = state.screen;
      state.quickLog(QuickLog.text);

      expect(state.treeOpen, isFalse);
      expect(state.chatOpen, isTrue);
      expect(state.screen, before, reason: 'logging must not push a page');
    });

    test('speaking opens the conversation and tries to listen for real', () async {
      final state = AppState()..toggleTree();
      state.quickLog(QuickLog.voice);
      await Future<void>.delayed(const Duration(milliseconds: 50));

      expect(state.chatOpen, isTrue);
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
      final state = AppState()..plusActive = true;
      final before = state.screen;
      state.quickLog(QuickLog.photo);
      state.logPhotoTaken('/tmp/meal.jpg');

      expect(state.screen, before);
      expect(state.chatOpen, isTrue);
      expect(state.lastMealPhotoPath, '/tmp/meal.jpg');
      expect(state.chat.any((c) => c.who == ChatWho.u), isTrue);
    });

    test('photographing a meal needs no Qamar+: Lite gets three a day', () {
      final state = AppState();
      state.setLang(AppLang.en);
      expect(state.plusActive, isFalse);
      expect(state.photoQuota.remaining, SuEconomy.litePhotoDaily);

      state.quickLog(QuickLog.photo);

      expect(state.screen, isNot(AppScreen.subscription));
      expect(state.plusNotice, isNull);
    });

    test('fanned-out choices sit on distinct ring positions, however many there are', () {
      for (final count in [kLogMethods.length, kWaterChoices.length, kActivityChoices.length, 1, 5]) {
        final seen = <Offset>{};
        for (var i = 0; i < count; i++) {
          final c = treeSubCenter(i, of: count);
          for (final other in seen) {
            // Overlapping circles were why only one of them could be tapped.
            expect((c - other).distance, greaterThan(60), reason: 'choices overlap at $count');
          }
          seen.add(c);
        }
        expect(seen.length, count);
      }
    });

    test('the Log node has the blueprint’s four branches plus typing, and Activity fans out the movements people name', () {
      expect(kLogMethods.map((m) => m.labelEn).toList(), ['Speak', 'Type', 'Photo', 'Repeat', 'Activity']);
      expect(kActivityChoices.map((a) => a.kind).toSet(), ActivityKind.values.toSet());
      expect(ActivityCatalog.kcalFor(ActivityKind.football, 30, 82), 287, reason: '7 MET × 82 kg × 0.5 h');
      expect(ActivityCatalog.kcalFor(ActivityKind.walk, 60, 70), 245);
    });

    test('exactly one node logs and one waters, and neither opens a page', () {
      final logs = kTreeNodes.where((n) => n.action == TreeAction.log).toList();
      final waters = kTreeNodes.where((n) => n.action == TreeAction.water).toList();
      expect(logs.length, 1);
      expect(waters.length, 1);
      expect(logs.single.screen, isNull, reason: 'logging must not open a page');
      expect(waters.single.screen, isNull, reason: 'water must not open a page');
    });

    test('the five nodes are Log, Plan, Water, Progress and Me, evenly spaced; Today is the background', () {
      expect(kTreeNodes.map((n) => n.labelEn).toList(), ['Log', 'Plan', 'Water', 'Progress', 'Me']);
      expect(kTreeNodes.any((n) => n.screen == AppScreen.today), isFalse, reason: 'today is what the orb floats over');
      expect(kTreeNodes.any((n) => n.screen == AppScreen.wallet), isFalse, reason: 'the wallet lives under Me');
      for (var i = 0; i < kTreeNodes.length; i++) {
        expect(kTreeNodes[i].angle, closeTo(i * 360 / kTreeNodes.length, 0.01));
      }
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
      final (lunch, _) = parsedPlan().slots.first;
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
      state.step = kOnboardingSteps.indexWhere((s) => s.id == 'dob');
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

void basketTests() {
  const koshary = (ar: 'كشري', en: 'Koshary', amountAr: 'طبق', amountEn: '1 bowl', kcal: 520);
  const salad = (ar: 'سلطة', en: 'Salad', amountAr: 'طبق صغير', amountEn: '1 small plate', kcal: 60);
  const chicken = (ar: 'فراخ مشوية', en: 'Grilled chicken', amountAr: 'ربع', amountEn: '1/4', kcal: 290);
  const lunch = (
    id: 'lunch', slotAr: 'غدا', slotEn: 'Lunch', nameAr: 'كشري', nameEn: 'Koshary', noteAr: '', noteEn: '',
    portions: <PlanPortion>[koshary, salad],
  );
  const dinner = (
    id: 'dinner', slotAr: 'عشا', slotEn: 'Dinner', nameAr: 'فراخ', nameEn: 'Chicken', noteAr: '', noteEn: '',
    portions: <PlanPortion>[chicken, salad],
  );

  group('shop this plan', () {
    test('the basket is every distinct portion of the day, first occurrence wins', () {
      final b = GroceryBasket.fromMeals(const [lunch, dinner]);
      expect(b.lines.map((l) => l.en).toList(), ['Koshary', 'Salad', 'Grilled chicken']);
      expect(b.count, 3);
      expect(b.lines[1].amount(ar: true), 'طبق صغير');
    });

    test('a template with placeholders is filled and encoded; one without gets query parameters', () {
      final b = GroceryBasket.fromMeals(const [lunch]);
      const templated = GroceryPartner(url: 'https://partner.example/basket?q={items}&aff={ref}&l={lang}', name: 'Breadfast', ref: 'qamar aff');
      final u = b.link(templated, ar: false);
      expect(u.toString(), 'https://partner.example/basket?q=Koshary%2CSalad&aff=qamar%20aff&l=en');

      const plain = GroceryPartner(url: 'https://partner.example/basket?src=qamar', name: 'Rabbit', ref: 'QMR');
      final v = b.link(plain, ar: true);
      expect(v.queryParameters['src'], 'qamar', reason: 'the partner’s own parameters are kept');
      expect(v.queryParameters['items'], 'كشري,سلطة');
      expect(v.queryParameters['ref'], 'QMR');
      expect(v.queryParameters['lang'], 'ar');
    });

    test('no partner, no shopping', () {
      expect(GroceryPartner.none.enabled, isFalse);
      expect(const GroceryPartner(url: '  ', name: 'x', ref: '').enabled, isFalse);
    });
  });
}

void pendingWriteTests() {
  group('the queue’s wire shape', () {
    test('every durable write round-trips through JSON', () {
      final meal = LoggedMeal(name: 'Koshary', sub: 'Lunch', kcal: 520, p: 14, c: 90, f: 10, at: DateTime.utc(2026, 9, 21, 13));
      final item = const ConfirmItemDef(ar: 'كشري', en: 'Koshary', portionAr: 'طبق', portionEn: '1 bowl', conf: Confidence.high, kcal: 520, p: 14, c: 90, f: 10, qamarFoodId: 'food-1', grams: 350, portionMatched: true);
      final sip = WaterSip(unit: WaterUnit.tea, ml: 150, at: DateTime.utc(2026, 9, 21, 9));
      final act = ActivityLog(kind: ActivityKind.run, minutes: 25, kcal: 290, at: DateTime.utc(2026, 9, 21, 18));

      final writes = [
        PendingWrite(kind: PendingKind.meal, payload: {'meal': meal.toJson(), 'items': [{'def': item.toJson(), 'qty': 2}], 'input': 'text', 'raw': 'koshary'}, at: DateTime.utc(2026, 9, 21, 13)),
        PendingWrite(kind: PendingKind.water, payload: sip.toJson(), at: DateTime.utc(2026, 9, 21, 9), attempts: 2),
        PendingWrite(kind: PendingKind.activity, payload: act.toJson(), at: DateTime.utc(2026, 9, 21, 18)),
      ];
      final back = PendingWrite.decode(PendingWrite.encode(writes));
      expect(back.map((w) => w.kind).toList(), [PendingKind.meal, PendingKind.water, PendingKind.activity]);
      expect(back[1].attempts, 2);

      final m = LoggedMeal.fromJson((back[0].payload['meal'] as Map).cast<String, dynamic>());
      expect((m.name, m.kcal, m.at), ('Koshary', 520, DateTime.utc(2026, 9, 21, 13)));
      final d = ConfirmItemDef.fromJson(((back[0].payload['items'] as List).first['def'] as Map).cast<String, dynamic>());
      expect((d.en, d.conf, d.qamarFoodId, d.grams, d.portionMatched), ('Koshary', Confidence.high, 'food-1', 350.0, true));
      final w = WaterSip.fromJson(back[1].payload);
      expect((w.unit, w.ml), (WaterUnit.tea, 150));
      final a = ActivityLog.fromJson(back[2].payload);
      expect((a.kind, a.minutes, a.kcal), (ActivityKind.run, 25, 290));
    });

    test('garbage in the preferences is an empty queue, not a crash', () {
      expect(PendingWrite.decode(null), isEmpty);
      expect(PendingWrite.decode('not json'), isEmpty);
      expect(PendingWrite.decode('[{"kind":"teleport","payload":{},"at":"2026-09-21T00:00:00Z"}]'), isEmpty);
    });
  });
}
