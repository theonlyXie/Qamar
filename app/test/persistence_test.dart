// Tests for AppState once repositories are supplied.
//
// The contract being protected: persistence is additive. Everything the app
// did offline it still does, writes go out as a side effect, and a backend
// that is slow, broken or absent never costs the user their data or blocks the
// screen.

import 'dart:async';

import 'package:flutter_test/flutter_test.dart';

import 'package:qamar/l10n/strings.dart';
import 'package:qamar/models/meal.dart';
import 'package:qamar/models/plan.dart';
import 'package:qamar/models/profile.dart';
import 'package:qamar/models/su_economy.dart';
import 'package:qamar/services/ai_gateway.dart';
import 'package:qamar/services/auth_service.dart';
import 'package:qamar/services/repositories.dart';
import 'package:qamar/state/app_state.dart';

class FakeProfileRepo implements ProfileRepository {
  Profile? stored;
  int saves = 0;
  int targetSaves = 0;
  Object? failWith;

  @override
  Future<Profile?> loadProfile(String userId) async => stored;

  @override
  Future<void> saveProfile(String userId, Profile profile) async {
    if (failWith != null) throw failWith!;
    saves++;
    stored = profile;
  }

  @override
  Future<Target> saveTarget(String userId, Target target, {required Profile inputs}) async {
    if (failWith != null) throw failWith!;
    targetSaves++;
    return target;
  }
}

class FakeMealRepo implements MealRepository {
  final List<LoggedMeal> saved = [];
  List<LoggedMeal> today = [];
  int drafts = 0;

  @override
  Future<String> saveDraft(String userId, MealAnalysisDraft draft) async {
    drafts++;
    return 'draft-$drafts';
  }

  @override
  Future<void> confirmMeal(String userId, {required String draftId, required LoggedMeal meal}) async {
    saved.add(meal);
  }

  @override
  Future<List<LoggedMeal>> mealsForDay(String userId, DateTime day) async => today;

  List<DayTotals> history = [];
  List<WeightReading> weights = [];
  final List<double> recorded = [];

  @override
  Future<List<DayTotals>> dailyTotals(String userId, {int days = 7}) async => history;

  @override
  Future<List<WeightReading>> weightHistory(String userId, {int days = 60}) async => weights;

  @override
  Future<void> recordWeight(String userId, {required double kg, DateTime? at}) async => recorded.add(kg);
}

class FakeWalletRepo implements WalletRepository {
  ({int available, int lifetime}) stored = (available: 0, lifetime: 0);
  final List<String> redemptions = [];

  @override
  Future<({int available, int lifetime})> balance(String userId) async => stored;

  @override
  Future<void> credit(String userId, {required int amount, required String reason, required String idempotencyKey}) {
    throw UnsupportedError('server-side only');
  }

  @override
  Future<void> redeem(String userId, {required SpendItemDef item, required String idempotencyKey}) async {
    redemptions.add(item.id);
  }

  @override
  Future<List<LedgerEntry>> ledger(String userId) async => [];
}

/// Stands in for the gateway. It returns what a real one returns — items to
/// confirm — without a network, so the confirm path can be exercised. It is
/// never wired into the app itself: with no gateway configured the app says so
/// rather than answering from a script.
class FakeGateway implements AiGateway {
  MealAnalysis result = const MealAnalysis([
    ConfirmItemDef(ar: 'كشري', en: 'Koshary', portionAr: 'طبق وسط', portionEn: '1 medium bowl', conf: Confidence.low, kcal: 520, p: 16, c: 96, f: 9),
  ]);
  String reply = 'grounded answer';
  final List<String?> imagePaths = [];

  int planCalls = 0;
  Object? planFailsWith;
  DayPlan plan = const DayPlan(date: '2026-08-15', slots: []);
  AiQuota quota = AiQuota.empty;

  void _useAi() {
    if (quota.remaining <= 0) {
      throw AiQuotaException(
        'That’s today’s five Qamar uses. Log a meal or finish the daily quest to earn Su Points, then spend them on another use from the wallet. They refresh at Cairo midnight.',
        quota,
      );
    }
    quota = quota.consumed();
  }

  @override
  Future<MealAnalysis> analyzeMeal({required String inputType, String? text, String? imagePath, String lang = 'ar'}) async {
    imagePaths.add(imagePath);
    _useAi();
    return result;
  }

  @override
  Future<String> chatReply({required String message, required String lang}) async {
    _useAi();
    return reply;
  }

  BodyScan scan = const BodyScan(heightCm: 174, weightKg: 86, bodyFatPct: 29, age: 31);

  @override
  Future<BodyScan> readBodyScan({required String imagePath, required String lang}) async {
    imagePaths.add(imagePath);
    return scan;
  }

  @override
  Future<DayPlan> generatePlan({required String date, required String lang}) async {
    planCalls++;
    if (planFailsWith != null) throw planFailsWith!;
    _useAi();
    // Stamp the requested date so ensurePlan can cache "today" instead of
    // treating a fixture dated 2026-08-15 as a different day forever.
    return DayPlan(date: date, slots: plan.slots, rationale: plan.rationale);
  }

  @override
  Future<AiQuota> quotaStatus() async => quota;
}

class FakeAccount implements Account {
  final List<String> linkStarts = [];
  final List<String> signInStarts = [];
  final List<OAuthChoice> oauthStarts = [];
  Object? failWith;
  Object? oauthFailsWith;
  bool linked = false;

  final _changes = StreamController<void>.broadcast();

  @override
  Stream<void> get changes => _changes.stream;

  @override
  Future<void> startOAuth(OAuthChoice provider) async {
    if (oauthFailsWith != null) throw oauthFailsWith!;
    oauthStarts.add(provider);
    // A real provider flow leaves the app here; nothing is linked until the
    // browser comes back, which the test drives with [returnFromBrowser].
  }

  /// Simulates the deep link that brings the user back, signed in.
  void returnFromBrowser({bool success = true}) {
    linked = success;
    _changes.add(null);
  }

  @override
  bool get isAnonymous => !linked;

  @override
  String? get email => linked ? 'nour@example.com' : null;

  @override
  Future<void> startLink(String email) async {
    if (failWith != null) throw failWith!;
    linkStarts.add(email);
  }

  @override
  Future<void> confirmLink({required String email, required String token}) async {
    if (failWith != null) throw failWith!;
    linked = true;
  }

  @override
  Future<void> startSignIn(String email) async => signInStarts.add(email);

  @override
  Future<void> confirmSignIn({required String email, required String token}) async => linked = true;
}

AppState backed({
  FakeProfileRepo? profiles,
  FakeMealRepo? meals,
  FakeWalletRepo? wallet,
  FakeGateway? ai,
  FakeAccount? auth,
}) =>
    AppState(
      profileRepo: profiles ?? FakeProfileRepo(),
      mealRepo: meals ?? FakeMealRepo(),
      walletRepo: wallet ?? FakeWalletRepo(),
      ai: ai,
      auth: auth,
      userId: 'user-1',
    );

Future<void> settle() => Future<void>.delayed(const Duration(milliseconds: 60));

void main() {
  test('with no repositories the app is entirely local', () {
    final state = AppState();
    expect(state.isBacked, isFalse);
    expect(state.syncError, isNull);
  });

  test('hydrate pulls the saved profile, meals and balance over the defaults', () async {
    final profiles = FakeProfileRepo()..stored = const Profile(name: 'Nour', height: 165, weight: 61, gender: Gender.female);
    final meals = FakeMealRepo()
      ..today = [const LoggedMeal(name: 'Foul', sub: 'text', kcal: 400, p: 20, c: 50, f: 12)];
    final wallet = FakeWalletRepo()..stored = (available: 45, lifetime: 120);

    final state = backed(profiles: profiles, meals: meals, wallet: wallet);
    await settle();

    expect(state.profile.name, 'Nour');
    expect(state.profile.gender, Gender.female);
    expect(state.meals.single.name, 'Foul');
    expect(state.suAvailable, 45);
    expect(state.suLifetime, 120);
  });

  test('an empty backend leaves the local defaults intact', () async {
    final state = backed();
    await settle();

    expect(state.profile.height, const Profile().height);
    expect(state.meals, isEmpty);
    expect(state.syncError, isNull);
  });

  test('confirming an analysed meal writes a draft and then the log', () async {
    final meals = FakeMealRepo();
    final state = backed(meals: meals, ai: FakeGateway());
    await settle();

    state.quickLog(QuickLog.text);
    await state.sendChatMsg('koshary');
    await settle();

    expect(state.hasProposal, isTrue, reason: 'the reading must be offered before anything is written');
    expect(meals.saved, isEmpty, reason: 'nothing may be logged before the user confirms');

    state.confirmProposal();
    await settle();

    expect(meals.drafts, 1, reason: 'the confirmed draft must be traceable');
    expect(meals.saved.single.kcal, 520);
    expect(state.hasProposal, isFalse);
  });

  test('a photo is sent to the assistant, not merely displayed', () async {
    final ai = FakeGateway();
    final state = backed(ai: ai);
    await settle();

    state.logPhotoTaken('/tmp/meal.jpg');
    await settle();

    expect(ai.imagePaths, ['/tmp/meal.jpg']);
    expect(state.hasProposal, isTrue);
  });

  test('an unreadable photo proposes nothing rather than inventing a meal', () async {
    final meals = FakeMealRepo();
    final ai = FakeGateway()..result = const MealAnalysis([], note: 'too dark to read');
    final state = backed(meals: meals, ai: ai);
    await settle();

    state.logPhotoTaken('/tmp/dark.jpg');
    await settle();

    expect(state.hasProposal, isFalse);
    expect(meals.saved, isEmpty);
    expect(state.chat.last.text, 'too dark to read');
  });

  test('with no gateway a meal cannot be analysed, and says so', () async {
    final meals = FakeMealRepo();
    final state = backed(meals: meals);
    await settle();

    state.logPhotoTaken('/tmp/meal.jpg');
    await settle();

    expect(state.hasProposal, isFalse);
    expect(meals.saved, isEmpty, reason: 'an unconnected app must never log invented food');
  });

  test('an unreadable InBody report prefills nothing and asks instead', () async {
    final ai = FakeGateway()..scan = const BodyScan(note: 'the numbers are glared over');
    final state = backed(ai: ai);
    await settle();
    final before = state.profile;

    state.setScanPhoto('/tmp/inbody.jpg');
    await state.capture();
    await settle();

    expect(state.scanned, isFalse, reason: 'the body questions must still be asked');
    expect(state.profile.height, before.height);
    expect(state.profile.weight, before.weight);
    expect(state.msgs.first.ar, 'the numbers are glared over');
  });

  test('a readable InBody report fills only what was on the page', () async {
    final ai = FakeGateway()..scan = const BodyScan(heightCm: 168, weightKg: 72);
    final state = backed(ai: ai);
    await settle();
    final beforeFat = state.profile.fat;

    state.setScanPhoto('/tmp/inbody.jpg');
    await state.capture();
    await settle();

    expect(state.profile.height, 168);
    expect(state.profile.weight, 72);
    expect(state.profile.fat, beforeFat, reason: 'body fat was not on the page and must not be invented');
    expect(state.scanned, isTrue);
  });

  test('with no assistant the report is not read at all', () async {
    final state = backed();
    await settle();
    final before = state.profile;

    state.setScanPhoto('/tmp/inbody.jpg');
    await state.capture();
    await settle();

    expect(state.scanned, isFalse);
    expect(state.profile.height, before.height);
    expect(state.profile.weight, before.weight);
  });

  test('the week is what was logged, and an empty week stays empty', () async {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final meals = FakeMealRepo()
      ..history = [
        DayTotals(day: today.subtract(const Duration(days: 2)), kcal: 1900, meals: 3),
        DayTotals(day: today.subtract(const Duration(days: 1)), kcal: 2100, meals: 4),
      ];
    final state = backed(meals: meals);
    await settle();

    final week = state.week();
    expect(week.length, 7);
    expect(week.last.day, today);
    expect(state.activeDays(), 2, reason: 'only days with logged meals count');
    expect(state.mealsThisWeek(), 7);
    expect(week.where((d) => d.meals == 0).length, 5, reason: 'unlogged days must stay at zero');
  });

  test('a new user sees an empty week rather than an invented one', () async {
    final state = backed();
    await settle();

    expect(state.activeDays(), 0);
    expect(state.mealsThisWeek(), 0);
    expect(state.week().every((d) => d.kcal == 0), isTrue);
    expect(state.weightHistory, isEmpty);
  });

  test('the ledger records points as they are earned, not reconstructed', () async {
    final state = backed(ai: FakeGateway());
    await settle();
    expect(state.ledger(), isEmpty, reason: 'a new user has earned nothing');

    state.completeQuest();
    expect(state.ledger().single.amount, SuEconomy.dailyQuest);
    expect(state.suAvailable, SuEconomy.dailyQuest);
  });

  test('the sixth Qamar use in a day is refused, and the wallet is the way out', () async {
    final ai = FakeGateway();
    final state = backed(ai: ai);
    await settle();
    state.setLang(AppLang.en);

    for (var i = 0; i < SuEconomy.dailyAiUses; i++) {
      await state.sendChatMsg('protein?');
    }
    expect(ai.quota.remaining, 0);

    await state.sendChatMsg('and now?');
    expect(state.chat.last.openWallet, isTrue);
    expect(state.chat.last.text.toLowerCase(), contains('five'));
    state.chatActionTap();
    expect(state.screen, AppScreen.wallet);
    expect(state.chatOpen, isFalse);
  });

  test('spending Su lengthens today’s allowance instead of unlocking unlimited AI', () {
    final state = AppState()
      ..suAvailable = SuEconomy.extraAiUse
      ..aiQuota = const AiQuota(used: 5, limit: 5, extra: 0, remaining: 0);

    state.redeem(kSpendCatalog.first);

    expect(kSpendCatalog.first.id, 'ai_extra');
    expect(state.aiQuota.extra, 1);
    expect(state.aiQuota.remaining, 1);
    expect(state.suAvailable, 0);
  });

  group('account', () {
    test('linking sends a code and only then attaches the email', () async {
      final auth = FakeAccount();
      final state = backed(auth: auth);
      await settle();

      state.openLinkAccount();
      state.onAuthEmailChanged('nour@example.com');
      await state.sendAuthCode();

      expect(auth.linkStarts, ['nour@example.com']);
      expect(state.authCodeSent, isTrue);
      expect(state.hasAccount, isFalse, reason: 'an unverified code links nothing');

      state.onAuthCodeChanged('123456');
      await state.verifyAuthCode();

      expect(state.hasAccount, isTrue);
      expect(state.accountEmail, 'nour@example.com');
    });

    test('a malformed address never reaches the server', () async {
      final auth = FakeAccount();
      final state = backed(auth: auth);
      await settle();

      state.openLinkAccount();
      state.onAuthEmailChanged('nour@');
      await state.sendAuthCode();

      expect(auth.linkStarts, isEmpty);
      expect(state.authError, isNotNull);
      expect(state.authCodeSent, isFalse);
    });

    test('an address already in use is explained, not swallowed', () async {
      final auth = FakeAccount()..failWith = StateError('Email address already been registered');
      final state = backed(auth: auth);
      await settle();
      state.setLang(AppLang.en);

      state.openLinkAccount();
      state.onAuthEmailChanged('nour@example.com');
      await state.sendAuthCode();

      expect(state.authCodeSent, isFalse);
      expect(state.authError, contains('already registered'));
    });

    test('with no server the account UI says so rather than failing silently', () async {
      final state = AppState();
      state.openLinkAccount();
      state.onAuthEmailChanged('nour@example.com');
      await state.sendAuthCode();

      expect(state.authError, isNotNull);
      expect(state.hasAccount, isFalse);
    });
  });

  group('plan', () {
    const meal = (
      id: 'lunch', slotAr: 'غدا', slotEn: 'Lunch',
      nameAr: 'كشري', nameEn: 'Koshary', noteAr: '', noteEn: '',
      portions: <PlanPortion>[(ar: 'كشري', en: 'Koshary', amountAr: 'طبق', amountEn: '1 bowl', kcal: 520)],
    );

    test('a generated plan replaces nothing until it arrives', () async {
      final ai = FakeGateway()..plan = const DayPlan(date: '2026-08-15', slots: [(meal, meal)]);
      final state = backed(ai: ai);
      await settle();

      expect(state.hasPlan, isFalse, reason: 'no plan exists before one is asked for');

      await state.ensurePlan();
      expect(ai.planCalls, 1);
      expect(state.planMeals().single.nameEn, 'Koshary');
    });

    test('the plan is fetched once a day, not on every visit', () async {
      final ai = FakeGateway()..plan = const DayPlan(date: '2026-08-15', slots: [(meal, meal)]);
      final state = backed(ai: ai);
      await settle();

      await state.ensurePlan();
      await state.ensurePlan();
      await state.ensurePlan();
      expect(ai.planCalls, 1, reason: 'every Plan screen visit must not spend a model call');

      await state.ensurePlan(force: true);
      expect(ai.planCalls, 2, reason: 'an explicit rebuild must still work');
    });

    test('a refusal is explained, and no plan is invented to fill the gap', () async {
      final ai = FakeGateway()..planFailsWith = AiGatewayException('generatePlan failed: 409 no target yet');
      final state = backed(ai: ai);
      await settle();
      state.setLang(AppLang.en);

      await state.ensurePlan();

      expect(state.hasPlan, isFalse);
      expect(state.planMeals(), isEmpty);
      expect(state.planError, contains('target'));
    });

    test('with no assistant the plan says so rather than showing a stock menu', () async {
      final state = backed();
      await settle();

      await state.ensurePlan();

      expect(state.hasPlan, isFalse);
      expect(state.planError, isNotNull);
    });
  });

  group('one-tap sign-in', () {
    test('a provider tap opens the flow and links nothing until it returns', () async {
      final auth = FakeAccount();
      final state = backed(auth: auth);
      await settle();

      await state.signInWith(OAuthChoice.google);

      expect(auth.oauthStarts, [OAuthChoice.google]);
      expect(state.hasAccount, isFalse, reason: 'the browser tab is still open');
      expect(state.authBusy, isTrue, reason: 'the flow is not finished until the user comes back');

      auth.returnFromBrowser();
      await settle();

      expect(state.hasAccount, isTrue);
      expect(state.authBusy, isFalse);
      expect(state.authDone, isNotNull);
    });

    test('all three providers are reachable', () async {
      for (final p in OAuthChoice.values) {
        final auth = FakeAccount();
        final state = backed(auth: auth);
        await settle();
        await state.signInWith(p);
        expect(auth.oauthStarts, [p]);
      }
    });

    test('a provider that is not switched on server-side says which one', () async {
      final auth = FakeAccount()..oauthFailsWith = StateError('Unsupported provider: provider is not enabled');
      final state = backed(auth: auth);
      await settle();
      state.setLang(AppLang.en);

      await state.signInWith(OAuthChoice.facebook);

      expect(state.authBusy, isFalse, reason: 'a failed launch must not leave the buttons spinning');
      expect(state.authError, contains('Facebook'));
      expect(state.hasAccount, isFalse);
    });

    test('with no server a provider tap explains rather than hanging', () async {
      final state = AppState();
      await state.signInWith(OAuthChoice.apple);

      expect(state.authError, isNotNull);
      expect(state.authBusy, isFalse);
    });
  });

  test('redeeming calls through to the wallet RPC', () async {
    final wallet = FakeWalletRepo()..stored = (available: 5000, lifetime: 5000);
    final state = backed(wallet: wallet);
    await settle();

    final item = kSpendCatalog.first;
    state.redeem(item);
    await settle();

    expect(wallet.redemptions, [item.id]);
  });

  test('a failing write is recorded but never loses the local change', () async {
    final profiles = FakeProfileRepo()..failWith = StateError('network down');
    final state = backed(profiles: profiles);
    await settle();

    state.profile = state.profile.copyWith(age: 30);
    state.primarySubmit();
    await Future<void>.delayed(const Duration(milliseconds: 400));

    expect(state.syncError, isNotNull, reason: 'the failure must be visible, not swallowed');
    expect(state.profile.age, 30, reason: 'the local answer must survive');
    expect(state.step, greaterThan(0), reason: 'onboarding must not stall on a failed write');
  });

  test('a backend that throws on load still yields a usable app', () async {
    final profiles = FakeProfileRepo()..failWith = StateError('boom');
    // loadProfile itself returns null here; the failure path is exercised by
    // the save above. What matters is that construction never throws.
    final state = backed(profiles: profiles);
    await settle();

    expect(state.screen, AppScreen.welcome);
    expect(state.target().kcal, greaterThan(0));
  });
}
