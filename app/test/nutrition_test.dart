// Logic tests for the parts of AppState where a silent wrong answer would
// matter most: the calorie maths, the eligibility gate, and the orb's
// hit-testing. All pure Dart — no widgets, no network.

import 'dart:convert';
import 'dart:ui' show Offset, Rect;

import 'package:flutter_test/flutter_test.dart';

import 'package:qamar/models/messages.dart';
import 'package:qamar/models/onboarding.dart';
import 'package:qamar/models/plan.dart';
import 'package:qamar/models/profile.dart';
import 'package:qamar/models/su_economy.dart';
import 'package:qamar/models/billing.dart';
import 'package:qamar/services/ai_gateway.dart';
import 'package:qamar/l10n/strings.dart';
import 'package:qamar/state/app_state.dart';
import 'package:qamar/state/chat_replies.dart';
import 'package:qamar/widgets/explain.dart';
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
    test('a new wallet is level 1, a 2,500 signup is already level 3', () {
      expect(SuEconomy.levelFor(0), 1);
      expect(SuEconomy.levelFor(SuEconomy.signupBonus), 3);
      expect(SuEconomy.levelFor(99 * SuEconomy.levelXp), 99);
      expect(SuEconomy.levelFor(200000), SuEconomy.maxLevel);
    });

    test('the earn and spend table is in hundreds, not 3 / 5 / 20', () {
      expect(SuEconomy.dailyQuest, greaterThanOrEqualTo(100));
      expect(SuEconomy.mealLogged, greaterThanOrEqualTo(100));
      expect(SuEconomy.extraAiUse, greaterThanOrEqualTo(SuEconomy.mealLogged));
      expect(SuEconomy.signupBonus, greaterThanOrEqualTo(1000));
    });
  });

  group('Qamar+ Egypt billing', () {
    test('is priced in EGP for Paymob, not a foreign store', () {
      expect(PlusCatalog.currency, 'EGP');
      expect(PlusCatalog.provider, 'paymob');
      expect(PlusCatalog.monthly.amountPounds, 500);
      expect(PlusCatalog.monthly.amountCents, 50000);
      expect(PlusCatalog.quarterly.amountPounds, 249);
      expect(PlusCatalog.annual.amountPounds, 249);
      expect(PlusCatalog.annual.periodDays, 365);
      expect(PlusCatalog.quarterly.periodDays, 90);
    });

    test('first users get 30% off the 500 list', () {
      expect(PlusCatalog.firstUserOffPercent, 30);
      expect(PlusCatalog.firstUserMonthlyCents, (PlusCatalog.listMonthlyCents * 0.7).round());
      final q = PlusPricing.quote(plan: 'monthly', firstPurchase: true);
      expect(q.amountPounds, 350);
      expect(q.pricingReason, 'first_user');
    });

    test('an affiliate code is 299 in, 50 to the marketer, 249 net', () {
      final q = PlusPricing.quote(
        plan: 'monthly',
        firstPurchase: true,
        promo: const PlusPromo(code: 'QMR7K2P', kind: 'affiliate', ownerUserId: 'friend'),
        buyerUserId: 'buyer',
      );
      expect(q.amountPounds, 299);
      expect(q.affiliateCommissionCents, 5000);
      expect(q.amountCents - q.affiliateCommissionCents, PlusCatalog.affiliateNetCents);
      expect(PlusCatalog.affiliateNetCents, PlusCatalog.packCents);
      expect(q.pricingReason, 'affiliate');
    });

    test('1 year is 50% off and matches the 3-month cash price', () {
      final year = PlusPricing.quote(plan: 'annual', firstPurchase: false);
      final three = PlusPricing.quote(plan: 'quarterly', firstPurchase: false);
      expect(year.amountPounds, 249);
      expect(three.amountPounds, 249);
      expect(year.pricingReason, 'annual_half');
      expect(three.pricingReason, 'quarterly_pack');
    });

    test('you cannot use your own affiliate code', () {
      final q = PlusPricing.quote(
        plan: 'monthly',
        firstPurchase: true,
        promo: const PlusPromo(code: 'QMR7K2P', kind: 'affiliate', ownerUserId: 'me'),
        buyerUserId: 'me',
      );
      expect(q.amountPounds, 350);
      expect(q.affiliateCommissionCents, 0);
      expect(q.promoError, isNotNull);
    });

    test('affiliate cash is not Su Points', () {
      expect(AffiliateWallet.empty.currency, 'EGP');
      expect(AffiliateWallet.empty.canRedeem, isFalse);
      expect(
        const AffiliateWallet(balanceCents: 5000).canRedeem,
        isTrue,
      );
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
