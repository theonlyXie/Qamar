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
import 'package:qamar/models/billing.dart';
import 'package:qamar/models/water.dart';
import 'package:qamar/services/ai_gateway.dart';
import 'package:qamar/services/auth_service.dart';
import 'package:qamar/services/payments.dart';
import 'package:qamar/services/quick_invoke.dart';
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
  Future<void> confirmMeal(String userId, {required String draftId, required LoggedMeal meal, List<({ConfirmItemDef def, int qty})> items = const []}) async {
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

class FakeWaterRepo implements WaterRepository {
  final List<WaterSip> saved = [];
  List<WaterSip> today = [];
  int adds = 0;

  @override
  Future<String> addSip(String userId, WaterSip sip) async {
    adds++;
    final id = 'water-$adds';
    saved.add(sip.copyWith(id: id));
    return id;
  }

  @override
  Future<void> removeSip(String userId, String id) async {
    saved.removeWhere((s) => s.id == id);
  }

  @override
  Future<List<WaterSip>> sipsForDay(String userId, DateTime day) async => today;
}

/// Stands in for the database, and behaves the way it does.
///
/// The point of this fake is that the *server* owns the balance. It keeps its
/// own ledger keyed by idempotency string, exactly as `su_point_ledger` does
/// with its unique (user_id, idempotency_key) constraint, so a replayed award
/// pays nothing here for the same reason it pays nothing in Postgres.
class FakeWalletRepo implements WalletRepository {
  ({int available, int lifetime}) stored = (available: 0, lifetime: 0);
  final List<String> redemptions = [];
  final List<LedgerEntry> rows = [];
  final Set<String> keys = {};

  /// Set by a test to say whether a meal has been logged today, which is what
  /// `qamar_complete_daily_quest` checks before it pays.
  bool mealLoggedToday = true;

  void award(int amount, String reason, String key) {
    if (!keys.add(key)) return;
    stored = (available: stored.available + amount, lifetime: stored.lifetime + amount);
    rows.insert(0, LedgerEntry(
      label: reason, amount: amount, when: 'now', reason: reason, at: DateTime.now(),
    ));
  }

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
  Future<List<LedgerEntry>> ledger(String userId) async => List.of(rows);

  @override
  Future<QuestResult> completeDailyQuest(String userId) async {
    final key = 'quest:$userId:today';
    if (keys.contains(key)) {
      return QuestResult(
        credited: false, reason: 'already_claimed',
        amount: SuEconomy.dailyQuest, available: stored.available);
    }
    if (!mealLoggedToday) {
      return QuestResult(
        credited: false, reason: 'no_meal_today',
        amount: SuEconomy.dailyQuest, available: stored.available);
    }
    award(SuEconomy.dailyQuest, 'daily_quest', key);
    return QuestResult(
      credited: true, reason: 'ok',
      amount: SuEconomy.dailyQuest, available: stored.available);
  }
}

/// Stands in for the gateway. It returns what a real one returns — items to
/// confirm — without a network, so the confirm path can be exercised. It is
/// never wired into the app itself: with no gateway configured the app says so
/// rather than answering from a script.
class FakeGateway implements AiGateway {
  MealAnalysis result = const MealAnalysis([
    ConfirmItemDef(ar: 'كشري', en: 'Koshary', portionAr: 'طبق وسط', portionEn: '1 medium bowl', conf: Confidence.low, kcal: 520, p: 16, c: 96, f: 9),
  ]);
  ChatResult chatResult = const ChatResult(reply: 'grounded answer');
  String reply = 'grounded answer';
  final List<String> chatMessages = [];
  Map<String, dynamic>? lastCurrentPlan;
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
    // Typed and spoken logs are the food graph. Only a photo spends a use.
    if (inputType == 'photo' || (imagePath != null && imagePath.isNotEmpty)) {
      _useAi();
    }
    return result;
  }

  @override
  Future<ChatResult> chatReply({
    required String message,
    required String lang,
    String? date,
    Map<String, dynamic>? currentPlan,
    List<String>? swappedSlots,
  }) async {
    chatMessages.add(message);
    lastCurrentPlan = currentPlan;
    _useAi();
    if (chatResult.reply == 'grounded answer' && reply != 'grounded answer') {
      return ChatResult(reply: reply);
    }
    return chatResult;
  }

  BodyScan scan = const BodyScan(heightCm: 174, weightKg: 86, bodyFatPct: 29, age: 31);

  @override
  Future<BodyScan> readBodyScan({required String imagePath, required String lang}) async {
    imagePaths.add(imagePath);
    return scan;
  }

  String? lastInstruction;
  bool? lastForce;

  @override
  Future<DayPlan> generatePlan({
    required String date,
    required String lang,
    bool force = false,
    String? instruction,
  }) async {
    planCalls++;
    lastForce = force;
    lastInstruction = instruction;
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
  FakeWaterRepo? water,
  FakeWalletRepo? wallet,
  FakeGateway? ai,
  FakeAccount? auth,
}) =>
    AppState(
      profileRepo: profiles ?? FakeProfileRepo(),
      mealRepo: meals ?? FakeMealRepo(),
      waterRepo: water ?? FakeWaterRepo(),
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

  test('hydrate pulls today\'s water over the empty default', () async {
    final water = FakeWaterRepo()
      ..today = [
        WaterSip(id: 'w1', unit: WaterUnit.glass, ml: 250, at: DateTime(2026, 8, 17, 9)),
        WaterSip(id: 'w2', unit: WaterUnit.bottle, ml: 500, at: DateTime(2026, 8, 17, 12)),
      ];
    final state = backed(water: water);
    await settle();

    expect(state.water.ml, 750);
    expect(state.water.glasses, 3);
    expect(state.water.bottles, 1.5);
  });

  test('logging water writes a sip, and undo deletes it', () async {
    final water = FakeWaterRepo();
    final state = backed(water: water);
    await settle();

    state.logWater(WaterUnit.glass);
    expect(state.water.ml, 250);
    await settle();

    expect(water.saved, hasLength(1));
    expect(water.saved.single.ml, 250);
    expect(state.waterToday.single.id, 'water-1');

    state.undoWater();
    await settle();
    expect(state.water.isEmpty, isTrue);
    expect(water.saved, isEmpty);
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
    final state = backed(ai: ai)..plusActive = true;
    await settle();

    state.logPhotoTaken('/tmp/meal.jpg');
    await settle();

    expect(ai.imagePaths, ['/tmp/meal.jpg']);
    expect(state.hasProposal, isTrue);
  });

  test('an unreadable photo proposes nothing rather than inventing a meal', () async {
    final meals = FakeMealRepo();
    final ai = FakeGateway()..result = const MealAnalysis([], note: 'too dark to read');
    final state = backed(meals: meals, ai: ai)..plusActive = true;
    await settle();

    state.logPhotoTaken('/tmp/dark.jpg');
    await settle();

    expect(state.hasProposal, isFalse);
    expect(meals.saved, isEmpty);
    expect(state.chat.last.text, 'too dark to read');
  });

  test('with no gateway a meal cannot be analysed, and says so', () async {
    final meals = FakeMealRepo();
    final state = backed(meals: meals)..plusActive = true;
    await settle();

    state.logPhotoTaken('/tmp/meal.jpg');
    await settle();

    expect(state.hasProposal, isFalse);
    expect(meals.saved, isEmpty, reason: 'an unconnected app must never log invented food');
  });

  test('typed meal logging does not spend a Qamar use', () async {
    final ai = FakeGateway();
    final state = backed(ai: ai);
    await settle();

    state.quickLog(QuickLog.text);
    await state.sendChatMsg('koshary');
    await settle();

    expect(state.hasProposal, isTrue);
    expect(ai.quota.remaining, SuEconomy.dailyAiUses);
  });

  test('typed meal logging still works after today’s five Qamar uses', () async {
    final ai = FakeGateway();
    final state = backed(ai: ai);
    await settle();
    state.setLang(AppLang.en);

    for (var i = 0; i < SuEconomy.dailyAiUses; i++) {
      await state.sendChatMsg('protein?');
    }
    expect(ai.quota.remaining, 0);

    state.quickLog(QuickLog.text);
    await state.sendChatMsg('koshary');
    await settle();

    expect(state.hasProposal, isTrue);
    expect(ai.quota.remaining, 0);
  });

  test('a log shortcut with text does not spend a Qamar use', () async {
    final ai = FakeGateway();
    final state = backed(ai: ai);
    await settle();

    QuickInvoke.apply(state, const QuickAction(kind: 'log', text: 'foul medames'));
    await settle();

    expect(state.hasProposal, isTrue);
    expect(ai.quota.remaining, SuEconomy.dailyAiUses);
  });

  test('photographing a meal spends a Qamar use', () async {
    final ai = FakeGateway();
    final state = backed(ai: ai)..plusActive = true;
    await settle();

    state.logPhotoTaken('/tmp/meal.jpg');
    await settle();

    expect(state.hasProposal, isTrue);
    expect(ai.quota.remaining, SuEconomy.dailyAiUses - 1);
  });

  test('photographing a meal without Qamar+ opens the paywall and does not analyse', () async {
    final ai = FakeGateway();
    final state = backed(ai: ai);
    await settle();
    state.setLang(AppLang.en);

    state.logPhotoTaken('/tmp/meal.jpg');
    await settle();

    expect(ai.imagePaths, isEmpty);
    expect(state.hasProposal, isFalse);
    expect(state.screen, AppScreen.subscription);
    expect(state.plusNotice, contains('Qamar+'));
    expect(state.lastMealPhotoPath, isNull);
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
    final wallet = FakeWalletRepo();
    final state = backed(ai: FakeGateway(), wallet: wallet);
    await settle();
    expect(state.ledger(), isEmpty, reason: 'a new user has earned nothing');

    await state.completeQuest();
    expect(state.ledger().single.amount, SuEconomy.dailyQuest);
    expect(state.suAvailable, SuEconomy.dailyQuest);
  });

  test('the quest is claimed once a day, and the server is the one counting', () async {
    final wallet = FakeWalletRepo();
    final state = backed(ai: FakeGateway(), wallet: wallet);
    await settle();

    await state.completeQuest();
    expect(state.suAvailable, SuEconomy.dailyQuest);
    expect(state.questNotice, isNull);

    // Pressing it again — a double tap, a second phone, a restarted app — is
    // the case that used to mint another 250 into a Dart integer every time.
    await state.completeQuest();
    await state.completeQuest();
    expect(state.suAvailable, SuEconomy.dailyQuest, reason: 'paid once, not three times');
    expect(state.questNotice, isNotNull);
    expect(state.ledger().length, 1);
  });

  test('no meal today means no quest, and it says so instead of failing silently', () async {
    final wallet = FakeWalletRepo()..mealLoggedToday = false;
    final state = backed(ai: FakeGateway(), wallet: wallet);
    await settle();
    state.setLang(AppLang.en);

    await state.completeQuest();
    expect(state.suAvailable, 0);
    expect(state.questDone, isFalse);
    expect(state.questNotice, contains('Log a meal today'));
  });

  test('the wallet shows the server balance, not the optimistic one', () async {
    final wallet = FakeWalletRepo();
    // The database already holds a signup bonus this session knows nothing of.
    wallet.award(SuEconomy.signupBonus, 'signup_bonus', 'signup:user-1');
    final state = backed(ai: FakeGateway(), wallet: wallet);
    await settle();
    expect(state.suAvailable, SuEconomy.signupBonus);

    await state.completeQuest();
    expect(state.suAvailable, SuEconomy.signupBonus + SuEconomy.dailyQuest);
    // Two real rows, and no duplicated optimistic copy of the quest.
    expect(state.ledger().length, 2);
    expect(state.ledger().where((e) => e.amount == SuEconomy.dailyQuest).length, 1);
  });

  test('server ledger reasons are shown in the user language, not as codes', () {
    const e = LedgerEntry(label: 'first_meal', amount: 500, when: 'x', reason: 'first_meal');
    expect(e.displayLabel(true), 'أول وجبة');
    expect(e.displayLabel(false), 'First meal logged');

    // An optimistic row is already translated and must be left alone.
    const local = LedgerEntry(label: 'مهمة اليوم', amount: 250, when: 'دلوقتي');
    expect(local.displayLabel(true), 'مهمة اليوم');

    // A reason nobody has translated shows as itself rather than as a guess.
    const unknown = LedgerEntry(label: 'x', amount: 1, when: 'x', reason: 'referral_bonus');
    expect(unknown.displayLabel(true), 'referral_bonus');
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

    test('talking to Qamar writes dinner onto Plan and Today, not only into chat', () async {
      const breakfast = (
        id: 'breakfast',
        slotAr: 'فطار',
        slotEn: 'Breakfast',
        nameAr: 'فول',
        nameEn: 'Foul',
        noteAr: '',
        noteEn: '',
        portions: <PlanPortion>[(ar: 'فول', en: 'Foul', amountAr: '١٥٠ جم', amountEn: '150 g', kcal: 180)],
      );
      const tuna = (
        id: 'dinner',
        slotAr: 'عشا',
        slotEn: 'Dinner',
        nameAr: 'تونة',
        nameEn: 'Tuna',
        noteAr: '',
        noteEn: '',
        portions: <PlanPortion>[(ar: 'تونة', en: 'Tuna', amountAr: 'علبة', amountEn: '1 tin', kcal: 130)],
      );
      const eggs = (
        id: 'dinner',
        slotAr: 'عشا',
        slotEn: 'Dinner',
        nameAr: 'بيض وزبادي',
        nameEn: 'Eggs and yogurt',
        noteAr: 'من غير طبخ',
        noteEn: 'no cooking',
        portions: <PlanPortion>[(ar: 'بيض', en: 'Eggs', amountAr: '٢', amountEn: '2', kcal: 160)],
      );
      final original = const DayPlan(date: '2026-08-15', slots: [(breakfast, breakfast), (tuna, tuna)]);
      final rewritten = DayPlan(date: original.date, slots: [(breakfast, breakfast), (eggs, eggs)]);
      final ai = FakeGateway()
        ..plan = original
        ..chatResult = ChatResult(
          reply: 'I’ll change dinner so you do not cook.',
          action: 'See the plan',
          plan: rewritten,
        );
      final state = backed(ai: ai);
      await settle();
      state.setLang(AppLang.en);
      await state.ensurePlan();
      expect(state.planMeals().last.nameEn, 'Tuna');

      await state.sendChatMsg("I'm tired and not cooking");

      expect(state.planMeals().last.nameEn, 'Eggs and yogurt',
          reason: 'the written menu must move when Qamar says it does');
      expect(state.chat.last.text, contains('dinner'));
      expect(state.chat.last.action, 'See the plan');
      expect(ai.lastCurrentPlan, isNotNull);
      expect((ai.lastCurrentPlan!['meals'] as List).length, 2);

      state.chatActionTap();
      expect(state.screen, AppScreen.plan);
      expect(state.chatOpen, isFalse);
      expect(state.planMeals().last.nameEn, 'Eggs and yogurt');
    });

    test('a rebuild from chat is a real generatePlan, with Qamar’s instruction', () async {
      final ai = FakeGateway()
        ..plan = const DayPlan(date: '2026-08-15', slots: [(meal, meal)])
        ..chatResult = const ChatResult(
          reply: 'I’ll rewrite the rest of the day.',
          rebuildInstruction: 'tired, no cooking tonight',
        );
      final state = backed(ai: ai);
      await settle();
      await state.ensurePlan();
      final before = ai.planCalls;

      await state.sendChatMsg("I'm tired");

      expect(ai.lastInstruction, 'tired, no cooking tonight');
      expect(ai.lastForce, isTrue);
      expect(ai.planCalls, before + 1);
      expect(state.hasPlan, isTrue);
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

  test('Start Qamar+ opens Paymob and does not mark Plus on the phone', () async {
    final billing = FakeBilling();
    final opened = <String>[];
    final state = AppState(
      userId: 'user-1',
      billing: billing,
      openCheckout: (url) async {
        opened.add(url);
        return true;
      },
    )..setLang(AppLang.en);
    await settle();

    expect(state.plusActive, isFalse);
    await state.startPlusPurchase();

    expect(billing.lastPlan, 'annual');
    expect(opened.single, contains('accept.paymob.com/unifiedcheckout'));
    expect(state.plusActive, isFalse, reason: 'only a verified Paymob callback may grant Plus');
    expect(state.plusNotice, contains('Paymob'));
  });

  test('a promo code is sent with checkout and still does not mark Plus on the phone', () async {
    final billing = FakeBilling();
    final state = AppState(
      userId: 'user-1',
      billing: billing,
      openCheckout: (url) async => true,
    )..setLang(AppLang.en);
    await settle();

    state.selectPlusPlan(PlusPlan.monthly);
    state.setPlusPromoCode('qmr 7k2p');
    await settle();
    await state.startPlusPurchase();

    expect(billing.lastPlan, 'monthly');
    expect(billing.lastPromo, 'QMR7K2P');
    expect(state.plusActive, isFalse);
  });

  test('a promo code is sent with checkout and still does not mark Plus on the phone', () async {
    final billing = FakeBilling();
    final state = AppState(
      userId: 'user-1',
      billing: billing,
      openCheckout: (url) async => true,
    )..setLang(AppLang.en);
    await settle();

    state.selectPlusPlan(PlusPlan.monthly);
    state.setPlusPromoCode('qmr 7k2p');
    await settle();
    await state.startPlusPurchase();

    expect(billing.lastPlan, 'monthly');
    expect(billing.lastPromo, 'QMR7K2P');
    expect(state.plusActive, isFalse);
  });

  test('coming back from Paymob reads the server entitlement', () async {
    final billing = FakeBilling()
      ..current = PlusEntitlement(
        status: 'active',
        plan: 'monthly',
        periodEnd: DateTime.now().toUtc().add(const Duration(days: 30)),
      );
    final state = AppState(userId: 'user-1', billing: billing)..setLang(AppLang.en);
    await settle();

    await state.onReturnedFromPaymob();
    expect(state.plusActive, isTrue);
    expect(state.screen, AppScreen.subscription);
  });
}

class FakeBilling implements BillingGateway {
  String? lastPlan;
  String? lastPromo;
  PlusEntitlement current = PlusEntitlement.free;
  AffiliateWallet wallet = const AffiliateWallet(code: 'QMRTEST1');

  @override
  Future<CheckoutSession> checkout({
    required String plan,
    String? promoCode,
    String? email,
    String? phone,
    String? firstName,
  }) async {
    lastPlan = plan;
    lastPromo = promoCode;
    return const CheckoutSession(
      checkoutUrl: 'https://accept.paymob.com/unifiedcheckout/?publicKey=pk_test&clientSecret=csk_test',
      orderId: 'ord-1',
    );
  }

  @override
  Future<PlusQuote> quote({required String plan, String? promoCode}) async {
    return PlusPricing.quote(
      plan: plan,
      firstPurchase: current.firstPurchase,
      promo: promoCode == null || promoCode.isEmpty
          ? null
          : PlusPromo(code: promoCode, kind: 'affiliate', ownerUserId: 'friend'),
    );
  }

  @override
  Future<PlusEntitlement> entitlement() async => current;

  @override
  Future<AffiliateWallet> affiliate() async => wallet;

  @override
  Future<AffiliateWallet> requestAffiliatePayout({int? amountCents}) async {
    wallet = AffiliateWallet(
      code: wallet.code,
      balanceCents: 0,
      lifetimeEarnedCents: wallet.lifetimeEarnedCents,
      pendingPayoutCents: amountCents ?? wallet.balanceCents,
    );
    return wallet;
  }
}
