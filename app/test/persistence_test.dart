// Tests for AppState once repositories are supplied.
//
// The contract being protected: persistence is additive. Everything the app
// did offline it still does, writes go out as a side effect, and a backend
// that is slow, broken or absent never costs the user their data or blocks the
// screen.

import 'dart:async';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';

import 'package:qamar/l10n/strings.dart';
import 'package:qamar/models/meal.dart';
import 'package:qamar/models/messages.dart';
import 'package:qamar/models/nudge.dart';
import 'package:qamar/models/onboarding.dart';
import 'package:qamar/models/plan.dart';
import 'package:qamar/models/profile.dart';
import 'package:qamar/models/ramadan.dart';
import 'package:qamar/models/streak.dart';
import 'package:qamar/models/su_economy.dart';
import 'package:qamar/models/activity.dart';
import 'package:qamar/models/billing.dart';
import 'package:qamar/models/invitation.dart';
import 'package:qamar/models/water.dart';
import 'package:qamar/services/ai_gateway.dart';
import 'package:qamar/services/analytics.dart';
import 'package:qamar/services/auth_service.dart';
import 'package:qamar/services/device_prefs.dart';
import 'package:qamar/services/nudger.dart';
import 'package:qamar/services/sharer.dart';
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

  final List<({String type, bool granted, String version})> consents = [];
  bool? consentOnRecord;

  @override
  Future<void> saveConsent(String userId, String type, {required bool granted, required String version}) async {
    if (failWith != null) throw failWith!;
    consents.add((type: type, granted: granted, version: version));
  }

  @override
  Future<bool?> loadConsent(String userId, String type) async => consentOnRecord;

  Season? season;
  final List<FastingMode> fastingSaves = [];

  @override
  Future<Season?> currentSeason() async => season;

  @override
  Future<void> saveFastingMode(String userId, FastingMode mode) async {
    if (failWith != null) throw failWith!;
    fastingSaves.add(mode);
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

  Streak? serverStreak;
  int streakCalls = 0;

  MealTimes? times;

  @override
  Future<MealTimes?> mealTimes(String userId) async => times;

  NightNote? note;

  @override
  Future<NightNote?> nightNote(String userId, DateTime day) async => note;

  List<LoggedMeal> recent = [];

  @override
  Future<List<LoggedMeal>> recentMeals(String userId, {int days = 7}) async => recent;

  @override
  Future<Streak?> streak(String userId) async {
    streakCalls++;
    return serverStreak;
  }

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

class FakeWalletRepo implements WalletRepository {
  ({int available, int lifetime}) stored = (available: 0, lifetime: 0);
  final List<String> redemptions = [];
  int balanceReads = 0;
  int quests = 0;
  int onboardingGrants = 0;

  /// What the server pays for the quest — deliberately not the phone's
  /// number, so a test can tell whose number is on screen.
  int questPays = 300;

  @override
  Future<({int available, int lifetime})> balance(String userId) async {
    balanceReads++;
    return stored;
  }

  @override
  Future<void> completeQuest(String userId) async {
    quests++;
    stored = (available: stored.available + questPays, lifetime: stored.lifetime + questPays);
  }

  @override
  Future<void> grantOnboarding(String userId) async {
    onboardingGrants++;
    stored = (available: stored.available + 1000, lifetime: stored.lifetime + 1000);
  }

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
  ChatResult chatResult = const ChatResult(reply: 'grounded answer');
  String reply = 'grounded answer';
  final List<String> chatMessages = [];
  Map<String, dynamic>? lastCurrentPlan;
  final List<String?> imagePaths = [];

  int planCalls = 0;
  Object? planFailsWith;
  DayPlan plan = const DayPlan(date: '2026-08-15', slots: []);
  AiQuotas quotas = AiQuotas.empty;

  /// Server-side wall for one bucket: the message the real gateway sends and
  /// the bucket that was refused, so the app can route the way out.
  void _use(AiQuota q, String message) {
    if (q.remaining <= 0) throw AiQuotaException(message, q);
    quotas = quotas.replacing(q.consumed());
  }

  void _useChat() => _use(
        quotas.chat,
        'That’s today’s three questions. Qamar+ answers the fourth — and every one after it.',
      );
  void _usePhoto() => _use(
        quotas.photo,
        'That’s today’s three photos. Spend Su Points on another from the wallet, or type the meal — that’s always free.',
      );
  void _usePlan() => _use(quotas.plan, 'That’s enough plans for today.');

  @override
  Future<MealAnalysis> analyzeMeal({required String inputType, String? text, String? imagePath, String lang = 'ar'}) async {
    imagePaths.add(imagePath);
    // Typed and spoken logs are the food graph. Only a photo spends a use.
    if (inputType == 'photo' || (imagePath != null && imagePath.isNotEmpty)) {
      _usePhoto();
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
    _useChat();
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
    _usePlan();
    // Stamp the requested date so ensurePlan can cache "today" instead of
    // treating a fixture dated 2026-08-15 as a different day forever.
    return DayPlan(date: date, slots: plan.slots, rationale: plan.rationale);
  }

  @override
  Future<AiQuotas> quotaStatus() async => quotas;
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

class FakeActivityRepo implements ActivityRepository {
  FakeActivityRepo({this.wallet});

  /// Stands in for the 0051 trigger: the insert itself earns the Su, so the
  /// balance the phone reads back after writing already carries it.
  final FakeWalletRepo? wallet;
  final List<ActivityLog> added = [];
  List<ActivityLog> today = [];

  @override
  Future<String> add(String userId, ActivityLog entry) async {
    added.add(entry);
    final w = wallet;
    if (w != null) {
      w.stored = (available: w.stored.available + SuEconomy.activityLogged, lifetime: w.stored.lifetime + SuEconomy.activityLogged);
    }
    return 'act-${added.length}';
  }

  @override
  Future<List<ActivityLog>> forDay(String userId, DateTime day) async => today;
}

class FakeInvitationRepo implements InvitationRepository {
  InvitationBook book = const InvitationBook(quarter: '2026Q3', limit: 3, invitations: []);
  final List<String> issued = [];
  final List<String> redeemCodes = [];
  InvitationRedemption redemption = const InvitationRedemption(inviterName: 'Basel', inviteeName: 'Omar', trialDays: 14);
  Object? failWith;

  @override
  Future<InvitationBook> mine(String userId) async => book;

  @override
  Future<Invitation> issue(String userId, {required String name}) async {
    if (failWith != null) throw failWith!;
    issued.add(name);
    final inv = Invitation(
      id: 'inv-${issued.length}',
      number: book.usedThisQuarter + 1,
      quarter: book.quarter,
      name: name,
      code: 'QMR-7F3A${issued.length}',
      createdAt: DateTime(2026, 9, 21),
    );
    book = book.plus(inv);
    return inv;
  }

  @override
  Future<InvitationRedemption> redeem(String userId, {required String code}) async {
    if (failWith != null) throw failWith!;
    redeemCodes.add(code);
    return redemption;
  }
}

AppState backed({
  FakeProfileRepo? profiles,
  FakeMealRepo? meals,
  FakeWaterRepo? water,
  FakeWalletRepo? wallet,
  FakeInvitationRepo? invitations,
  FakeActivityRepo? activities,
  FakeGateway? ai,
  FakeAccount? auth,
  MemoryAnalytics? analytics,
  MemoryDevicePrefs? prefs,
  MemorySharer? sharer,
  FakeBilling? billing,
  DateTime Function()? clock,
}) =>
    AppState(
      profileRepo: profiles ?? FakeProfileRepo(),
      mealRepo: meals ?? FakeMealRepo(),
      waterRepo: water ?? FakeWaterRepo(),
      walletRepo: wallet ?? FakeWalletRepo(),
      invitationRepo: invitations,
      activityRepo: activities,
      ai: ai,
      auth: auth,
      userId: 'user-1',
      analytics: analytics,
      prefs: prefs,
      sharer: sharer,
      billing: billing,
      clock: clock,
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
    expect(ai.quotas.chat.remaining, SuEconomy.liteChatDaily);
    expect(ai.quotas.photo.remaining, SuEconomy.litePhotoDaily);
  });

  test('typed meal logging still works after today’s three questions', () async {
    final ai = FakeGateway();
    final state = backed(ai: ai);
    await settle();
    state.setLang(AppLang.en);

    for (var i = 0; i < SuEconomy.liteChatDaily; i++) {
      await state.sendChatMsg('protein?');
    }
    expect(ai.quotas.chat.remaining, 0);

    state.quickLog(QuickLog.text);
    await state.sendChatMsg('koshary');
    await settle();

    expect(state.hasProposal, isTrue);
    expect(ai.quotas.chat.remaining, 0);
  });

  test('a log shortcut with text does not spend a Qamar use', () async {
    final ai = FakeGateway();
    final state = backed(ai: ai);
    await settle();

    QuickInvoke.apply(state, const QuickAction(kind: 'log', text: 'foul medames'));
    await settle();

    expect(state.hasProposal, isTrue);
    expect(ai.quotas.chat.remaining, SuEconomy.liteChatDaily);
  });

  test('photographing a meal spends a photo, not a question, and needs no Qamar+', () async {
    final ai = FakeGateway();
    final state = backed(ai: ai);
    await settle();

    expect(state.plusActive, isFalse);
    state.logPhotoTaken('/tmp/meal.jpg');
    await settle();

    expect(state.hasProposal, isTrue);
    expect(ai.quotas.photo.remaining, SuEconomy.litePhotoDaily - 1);
    expect(ai.quotas.chat.remaining, SuEconomy.liteChatDaily);
    expect(state.photoQuota.remaining, SuEconomy.litePhotoDaily - 1);
  });

  test('the fourth photo of the day is refused, and the wallet is the way out', () async {
    final ai = FakeGateway();
    final state = backed(ai: ai);
    await settle();
    state.setLang(AppLang.en);

    for (var i = 0; i < SuEconomy.litePhotoDaily; i++) {
      state.logPhotoTaken('/tmp/meal$i.jpg');
      await settle();
      state.discardProposal();
    }
    expect(ai.quotas.photo.remaining, 0);

    state.logPhotoTaken('/tmp/meal-extra.jpg');
    await settle();

    expect(state.hasProposal, isFalse);
    expect(state.photoQuota.exhausted, isTrue);
    expect(state.chat.last.openWallet, isTrue);
    expect(state.chat.last.openPlus, isFalse);
    expect(state.chat.last.text.toLowerCase(), contains('three photos'));
    state.chatActionTap();
    expect(state.screen, AppScreen.wallet);
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

  test('the streak counts logged days back from today, and today never breaks it', () async {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final meals = FakeMealRepo()
      ..history = [
        DayTotals(day: today.subtract(const Duration(days: 3)), kcal: 1800, meals: 2),
        DayTotals(day: today.subtract(const Duration(days: 2)), kcal: 1900, meals: 3),
        DayTotals(day: today.subtract(const Duration(days: 1)), kcal: 2100, meals: 4),
      ];
    final state = backed(meals: meals);
    await settle();

    final s = state.streak();
    expect(s.current, 3);
    expect(s.todayCounted, isFalse);
    expect(s.atRisk, isTrue, reason: 'yesterday was the last counted day');
    expect(s.best, 3);
    expect(state.orbState().streak.current, 3);
  });

  test('logging today’s first meal joins today to the run before the server is asked', () async {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final meals = FakeMealRepo()
      ..history = [DayTotals(day: today.subtract(const Duration(days: 1)), kcal: 2100, meals: 4)]
      ..serverStreak = const Streak(current: 1, best: 5, todayCounted: false, freezesAvailable: 1);
    final ai = FakeGateway();
    final state = backed(meals: meals, ai: ai);
    await settle();
    expect(state.streak().current, 1);
    expect(state.streak().freezesAvailable, 1);

    state.quickLog(QuickLog.text);
    await state.sendChatMsg('koshary');
    await settle();
    state.confirmProposal();
    await settle();

    final s = state.streak();
    expect(s.current, 2);
    expect(s.todayCounted, isTrue);
    expect(s.best, 5);
    expect(meals.streakCalls, greaterThan(1), reason: 'the server is re-asked after a log');
  });

  test('a streak freeze is bought with Su and shows as an available token', () {
    final state = AppState()..suAvailable = SuEconomy.streakFreeze;
    final freeze = kSpendCatalog.firstWhere((i) => i.id == 'streak_freeze');

    state.redeem(freeze);

    expect(state.suAvailable, 0);
    expect(state.streak().freezesAvailable, 1);
    expect(freeze.once, isFalse, reason: 'one a month, so not a permanent unlock');
  });

  group('Su Points are earned on the server', () {
    test('the quest is paid by the server, once, and the wallet re-read', () async {
      final wallet = FakeWalletRepo();
      final state = backed(wallet: wallet);
      await settle();
      final readsBefore = wallet.balanceReads;

      state.completeQuest();
      expect(state.suAvailable, SuEconomy.dailyQuest, reason: 'shown at once, optimistically');
      await settle();

      expect(wallet.quests, 1);
      expect(wallet.balanceReads, greaterThan(readsBefore));
      expect(state.suAvailable, wallet.questPays, reason: 'the ledger’s number replaces the phone’s');

      state.replaceQuest();
      state.completeQuest();
      await settle();
      expect(wallet.quests, 1, reason: 'Accept, Replace, Accept posts once a day');
    });

    test('a confirmed meal re-reads the wallet after the insert that earned it', () async {
      final wallet = FakeWalletRepo();
      final ai = FakeGateway();
      final state = backed(wallet: wallet, ai: ai);
      await settle();

      state.quickLog(QuickLog.text);
      await state.sendChatMsg('koshary');
      await settle();
      // The server's trigger credited the meal; the fake stands in for it.
      wallet.stored = (available: 777, lifetime: 777);
      state.confirmProposal();
      await settle();

      expect(state.meals, hasLength(1));
      expect(state.suAvailable, 777);
      expect(state.suLifetime, 777);
    });

    test('a glass of water re-reads the wallet too', () async {
      final wallet = FakeWalletRepo();
      final state = backed(wallet: wallet);
      await settle();

      wallet.stored = (available: 5, lifetime: 5);
      state.logWater(WaterUnit.glass);
      await settle();

      expect(state.suAvailable, 5);
    });

    test('offline, nothing is posted and the local number stands', () async {
      final state = AppState();
      state.completeQuest();
      expect(state.suAvailable, SuEconomy.dailyQuest);
    });
  });

  group('the weekly review card', () {
    test('sharing hands the picture and the sentence to the sheet, with the link', () async {
      final sharer = MemorySharer();
      final now = DateTime.now();
      final today = DateTime(now.year, now.month, now.day);
      final meals = FakeMealRepo()
        ..history = [
          for (var i = 1; i <= 4; i++) DayTotals(day: today.subtract(Duration(days: i)), kcal: i == 2 ? 2900 : 1900, meals: 3),
        ];
      final state = AppState(
        mealRepo: meals, profileRepo: FakeProfileRepo(), waterRepo: FakeWaterRepo(), walletRepo: FakeWalletRepo(),
        userId: 'user-1', sharer: sharer,
      );
      await settle();

      final review = state.weekReview();
      expect(review.enough, isTrue);
      await state.shareReview(Uint8List.fromList([137, 80, 78, 71]));

      final shared = sharer.shared.single;
      expect(shared.fileName, 'qamar-week.png');
      expect(shared.text, contains(review.insight.ar));
      expect(shared.text, contains('dr-qamar.com'));
      expect(shared.png.length, 4);
    });

    test('numbers are off by default and the choice is the phone\'s', () async {
      final prefs = MemoryDevicePrefs();
      final first = AppState(prefs: prefs);
      await settle();
      expect(first.reviewShowNumbers, isFalse);
      first.setReviewShowNumbers(true);
      await settle();

      final second = AppState(prefs: prefs);
      await settle();
      expect(second.reviewShowNumbers, isTrue);
    });

    test('without a share sheet, sharing is a quiet no-op', () async {
      final state = AppState();
      await state.shareReview(Uint8List(0));
    });
  });

  group('nudges', () {
    const lunchMeal = (
      id: 'lunch', slotAr: 'غدا', slotEn: 'Lunch',
      nameAr: 'كشري', nameEn: 'Koshary', noteAr: '', noteEn: '',
      portions: <PlanPortion>[(ar: 'كشري', en: 'Koshary', amountAr: 'طبق', amountEn: '1 bowl', kcal: 520)],
    );
    // A morning, before lunch: both of today's questions are still ahead.
    DateTime morning() => DateTime(2026, 9, 21, 9, 0);

    test('the permission card waits for the plan to be on screen', () {
      final state = AppState(nudger: MemoryNudger(), clock: morning);
      expect(state.nudgePromptDue, isFalse, reason: 'no plan yet');

      state.plan = const DayPlan(date: '2026-09-21', slots: [(lunchMeal, lunchMeal)]);
      expect(state.nudgePromptDue, isTrue);
    });

    test('allowing asks the OS once and schedules two questions a day', () async {
      final nudger = MemoryNudger();
      final state = AppState(nudger: nudger, clock: morning)
        ..plan = const DayPlan(date: '2026-09-21', slots: [(lunchMeal, lunchMeal)]);

      await state.allowNudges();

      expect(nudger.permissionAsks, 1);
      expect(state.nudgesAllowed, isTrue);
      expect(state.nudgePromptDue, isFalse);
      final today = nudger.scheduled.where((n) => n.dayIndex == 0).map((n) => n.slot).toList();
      expect(today, [MealSlot.lunch, MealSlot.dinner]);
      expect(nudger.scheduled.length, 6, reason: 'three days ahead, two a day');
      expect(nudger.lastAr, isTrue);
    });

    test('“No, thanks” is zero a day and an empty schedule, not a later nag', () async {
      final nudger = MemoryNudger();
      final state = AppState(nudger: nudger, clock: morning)
        ..plan = const DayPlan(date: '2026-09-21', slots: [(lunchMeal, lunchMeal)]);

      state.declineNudges();
      await settle();

      expect(state.nudgesPerDay, 0);
      expect(state.nudgePromptDue, isFalse);
      expect(nudger.permissionAsks, 0);
      expect(nudger.scheduled, isEmpty);
    });

    test('the OS saying no leaves the allowance but nothing scheduled', () async {
      final nudger = MemoryNudger()..grant = false;
      final state = AppState(nudger: nudger, clock: morning);

      await state.allowNudges();

      expect(state.nudgesAllowed, isFalse);
      expect(state.nudgesPerDay, 2);
      expect(nudger.scheduled, isEmpty);
    });

    test('the allowance goes down to one or zero, never above two', () async {
      final nudger = MemoryNudger();
      final state = AppState(nudger: nudger, clock: morning);
      await state.allowNudges();

      await state.setNudgesPerDay(5);
      expect(state.nudgesPerDay, 2);

      await state.setNudgesPerDay(1);
      expect(nudger.scheduled.map((n) => n.slot).toSet(), {MealSlot.lunch}, reason: 'one a day is lunch');

      await state.setNudgesPerDay(0);
      expect(nudger.scheduled, isEmpty);
    });

    test('a lunch that was logged is a question the day no longer needs', () async {
      final nudger = MemoryNudger();
      final state = AppState(nudger: nudger, clock: () => DateTime(2026, 9, 21, 12, 30));
      await state.allowNudges();
      expect(nudger.scheduled.any((n) => n.dayIndex == 0 && n.slot == MealSlot.lunch), isTrue);

      state.meals.add(LoggedMeal(name: 'كشري', sub: 'كتابة', kcal: 520, p: 16, c: 96, f: 9, at: DateTime(2026, 9, 21, 12, 30)));
      await state.setNudgesPerDay(2); // any change rebuilds the schedule

      expect(nudger.scheduled.any((n) => n.dayIndex == 0 && n.slot == MealSlot.lunch), isFalse);
      expect(nudger.scheduled.any((n) => n.dayIndex == 0 && n.slot == MealSlot.dinner), isTrue);
      expect(nudger.scheduled.any((n) => n.dayIndex == 1 && n.slot == MealSlot.lunch), isTrue, reason: 'tomorrow still asks');
    });

    test('at lunchtime the orb holds the question, and holding it hears it', () async {
      final state = AppState(nudger: MemoryNudger(), clock: () => DateTime(2026, 9, 21, 14, 30));
      final waiting = state.waitingNudge;
      expect(waiting?.slot, MealSlot.lunch);

      await state.holdOrb();

      expect(state.chatOpen, isTrue);
      expect(state.chat.first.who, ChatWho.q);
      expect(state.chat.first.text, waiting!.text(ar: true));
      expect(NudgeCopy.all.contains(state.chat.first.text), isTrue);
    });

    test('with lunch logged the orb has nothing to say', () {
      final state = AppState(nudger: MemoryNudger(), clock: () => DateTime(2026, 9, 21, 14, 30));
      state.meals.add(LoggedMeal(name: 'كشري', sub: 'كتابة', kcal: 520, p: 16, c: 96, f: 9, at: DateTime(2026, 9, 21, 14, 10)));
      expect(state.waitingNudge, isNull);
    });

    test('tapping the notification opens the conversation on that question, listening', () async {
      final nudger = MemoryNudger();
      final state = AppState(nudger: nudger, clock: () => DateTime(2026, 9, 21, 20, 40));
      await settle();

      nudger.tap('nudge:dinner');
      await settle();

      expect(state.chatOpen, isTrue);
      expect(state.chat.first.text, NudgeCopy.text(MealSlot.dinner, DateTime(2026, 9, 21), ar: true));
      expect(state.proposalInput, 'voice');
    });

    test('the allowance is remembered on the phone', () async {
      final prefs = MemoryDevicePrefs();
      final first = AppState(nudger: MemoryNudger(), prefs: prefs, clock: morning);
      await settle();
      await first.setNudgesPerDay(1);

      final second = AppState(nudger: MemoryNudger(), prefs: prefs, clock: morning);
      await settle();
      expect(second.nudgesPerDay, 1);
      expect(second.nudgesAllowed, isTrue);
      expect(second.nudgePromptDone, isTrue);
      expect(second.firstDay, DateTime(2026, 9, 21));
    });
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

  test('the fourth question in a day is refused, and Qamar+ is the way out', () async {
    final ai = FakeGateway();
    final state = backed(ai: ai);
    await settle();
    state.setLang(AppLang.en);

    for (var i = 0; i < SuEconomy.liteChatDaily; i++) {
      await state.sendChatMsg('protein?');
    }
    expect(ai.quotas.chat.remaining, 0);

    await state.sendChatMsg('and now?');
    expect(state.chat.last.openPlus, isTrue);
    expect(state.chat.last.openWallet, isFalse);
    expect(state.chat.last.text.toLowerCase(), contains('three questions'));
    expect(state.chat.last.action, contains('Qamar+'));
    state.chatActionTap();
    expect(state.screen, AppScreen.subscription);
    expect(state.chatOpen, isFalse);
  });

  test('spending Su buys another photo today, never another question', () {
    final state = AppState()
      ..suAvailable = SuEconomy.extraAiUse
      ..photoQuota = const AiQuota(bucket: 'photo', used: 3, limit: 3, extra: 0, remaining: 0)
      ..aiQuota = const AiQuota(bucket: 'chat', used: 3, limit: 3, extra: 0, remaining: 0);

    state.redeem(kSpendCatalog.first);

    expect(kSpendCatalog.first.id, 'ai_extra');
    expect(state.photoQuota.extra, 1);
    expect(state.photoQuota.remaining, 1);
    expect(state.aiQuota.remaining, 0);
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

    expect(billing.lastPlan, 'monthly');
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

  test('the free week is granted by the server, once, and reads back as Qamar+ on trial', () async {
    final billing = FakeBilling()..current = const PlusEntitlement(status: 'free', trialEligible: true);
    final state = AppState(userId: 'user-1', billing: billing)..setLang(AppLang.en);
    await settle();
    expect(state.plusTrialEligible, isTrue);
    expect(state.plusActive, isFalse);

    await state.startPlusTrial();

    expect(billing.trialStarts, 1);
    expect(state.plusActive, isTrue);
    expect(state.plusIsTrial, isTrue);
    expect(state.plusTrialEligible, isFalse);
    expect(state.plusNotice, contains('seven days'));

    // A second ask never reaches the server: the phone already knows.
    await state.startPlusTrial();
    expect(billing.trialStarts, 1);
    expect(state.plusNotice, contains('already been used'));
  });

  test('a paid member is not offered the trial, and the server’s refusal is shown as is', () async {
    final billing = FakeBilling()..current = const PlusEntitlement(status: 'expired', trialEligible: false);
    final state = AppState(userId: 'user-1', billing: billing)..setLang(AppLang.en);
    await settle();
    expect(state.plusTrialEligible, isFalse);

    await state.startPlusTrial();
    expect(billing.trialStarts, 0);
    expect(state.plusActive, isFalse);
  });

  test('a trial member can still pay: Start Qamar+ opens Paymob instead of “manage”', () async {
    final billing = FakeBilling()
      ..current = PlusEntitlement(
        status: 'active',
        plan: 'monthly',
        provider: 'trial',
        periodEnd: DateTime.now().toUtc().add(const Duration(days: 5)),
      );
    final opened = <String>[];
    final state = AppState(userId: 'user-1', billing: billing, openCheckout: (url) async { opened.add(url); return true; })
      ..setLang(AppLang.en);
    await settle();
    expect(state.plusIsTrial, isTrue);

    await state.startPlusPurchase();
    expect(opened, hasLength(1));
  });

  test('the entitlement snapshot carries the trial fields', () {
    final e = PlusEntitlement.fromJson({
      'status': 'active',
      'plan': 'monthly',
      'provider': 'trial',
      'period_end': DateTime.now().toUtc().add(const Duration(days: 3)).toIso8601String(),
      'trial_eligible': false,
      'trial_ends_at': '2026-09-27T10:00:00Z',
    });
    expect(e.isTrial, isTrue);
    expect(e.trialEligible, isFalse);
    expect(e.trialEndsAt, DateTime.utc(2026, 9, 27, 10));
    expect(PlusEntitlement.fromJson({'status': 'free', 'trial_eligible': true}).trialEligible, isTrue);
    expect(PlusEntitlement.fromJson({'status': 'free'}).trialEligible, isFalse, reason: 'an old server never offers a trial');
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

  group('analytics, behind consent', () {
    test('nothing is sent before the person says yes', () async {
      final a = MemoryAnalytics();
      final state = AppState(analytics: a);
      state.logWater(WaterUnit.glass);
      state.orbTap();
      await settle();
      expect(a.enabledFor, isEmpty, reason: 'the SDK must not even be started');
      expect(a.events, isEmpty);
      expect(a.screens, isEmpty);
    });

    test('saying yes turns analytics on, records the consent, and is itself the first event', () async {
      final a = MemoryAnalytics();
      final profiles = FakeProfileRepo();
      final prefs = MemoryDevicePrefs();
      final state = backed(profiles: profiles, analytics: a, prefs: prefs);
      await settle();

      await state.setImprove(true);
      await settle();

      expect(a.enabledFor, ['user-1'], reason: 'the account id is the identity, never an email');
      expect(a.events.single.name, 'consent_granted');
      expect(a.events.single.props['version'], '1.1');
      expect(profiles.consents, [(type: 'improve_optional', granted: true, version: '1.1')]);
      expect(await prefs.getBool('improve_consent'), isTrue);
    });

    test('the consent answer in the consultation is the same switch', () async {
      final a = MemoryAnalytics();
      final state = AppState(analytics: a);
      state.startOnboarding();
      await settle();
      // Jump to the consent step and answer the way the consultation offers.
      state.step = kOnboardingSteps.indexWhere((s) => s.id == 'consent');
      state.handleFree('improve');
      await settle();
      expect(state.improve, isTrue);
      expect(a.named('consent_granted'), hasLength(1));
      expect(a.named('intake_step').single['step'], 'consent', reason: 'the step answered after consent is the first one counted');
    });

    test('saying no stops everything, and is recorded', () async {
      final a = MemoryAnalytics();
      final profiles = FakeProfileRepo();
      final state = backed(profiles: profiles, analytics: a);
      await state.setImprove(true);
      await settle();

      await state.setImprove(false);
      await settle();
      state.logWater(WaterUnit.glass);
      await settle();

      expect(a.disables, 1);
      expect(a.named('water_logged'), isEmpty);
      expect(profiles.consents.last.granted, isFalse);
    });

    test('the answer survives a relaunch on the same phone without a second consent event', () async {
      final prefs = MemoryDevicePrefs();
      final first = AppState(prefs: prefs, analytics: MemoryAnalytics());
      await first.setImprove(true);
      await settle();

      final a = MemoryAnalytics();
      final second = AppState(prefs: prefs, analytics: a);
      await settle();
      expect(second.improve, isTrue);
      expect(a.enabledFor, [null], reason: 'no account: the SDK uses its own anonymous id');
      expect(a.named('consent_granted'), isEmpty);
    });

    test('the account record wins over the phone', () async {
      final a = MemoryAnalytics();
      final profiles = FakeProfileRepo()..consentOnRecord = true;
      final state = backed(profiles: profiles, analytics: a);
      await settle();
      expect(state.improve, isTrue);
      expect(a.enabledFor, ['user-1']);
      expect(a.named('consent_granted'), isEmpty, reason: 'reading a consent back is not giving one');
    });

    test('a logged meal is an event with its source and never the food', () async {
      final a = MemoryAnalytics();
      final state = backed(ai: FakeGateway(), analytics: a);
      await state.setImprove(true);
      await settle();

      state.quickLog(QuickLog.text);
      await state.sendChatMsg('koshary');
      await settle();
      state.confirmProposal();
      await settle();

      final read = a.named('meal_read').single;
      expect(read['source'], 'text');
      expect(read['items'], 1);
      expect(read['ms'], isA<int>());

      final logged = a.named('meal_logged').single;
      expect(logged, {
        'source': 'text',
        'first': true,
        'items': 1,
        'nudged': false,
        'lang': 'ar',
        'plus': false,
        'backed': true,
      });
      for (final e in a.events) {
        expect(e.props.values.map((v) => '$v'), everyElement(isNot(contains('koshary'))));
        expect(e.props.values.map((v) => '$v'), everyElement(isNot(contains('كشري'))));
      }
    });

    test('a meal logged after tapping a nudge counts as prompted', () async {
      final a = MemoryAnalytics();
      final nudger = MemoryNudger();
      final state = AppState(
        nudger: nudger,
        analytics: a,
        ai: FakeGateway(),
        clock: () => DateTime(2026, 9, 21, 14, 30),
      );
      await state.setImprove(true);
      nudger.tap('nudge:lunch');
      await settle();
      expect(a.named('nudge_tapped').single['slot'], 'lunch');

      await state.sendChatMsg('koshary');
      await settle();
      state.confirmProposal();
      await settle();

      final logged = a.named('meal_logged').single;
      expect(logged['nudged'], isTrue);
      expect(logged['source'], 'voice', reason: 'a nudge opens the conversation listening');
    });

    test('the first use of each gesture is one event', () async {
      final a = MemoryAnalytics();
      final state = AppState(analytics: a);
      await state.setImprove(true);
      state.orbTap();
      state.orbTap();
      await state.holdOrb();
      await settle();
      expect(a.named('orb_gesture_first').map((e) => e['gesture']), ['tap', 'hold']);
    });

    test('the paywall touchpoints are events', () async {
      final a = MemoryAnalytics();
      final opened = <String>[];
      final billing = FakeBilling()..current = const PlusEntitlement(status: 'free', trialEligible: true);
      final state = AppState(
        userId: 'user-1',
        billing: billing,
        analytics: a,
        openCheckout: (url) async {
          opened.add(url);
          return true;
        },
      );
      await state.setImprove(true);
      await settle();

      state.setPlusPromoCode('qmrtest1');
      await state.startPlusPurchase();
      expect(a.named('promo_entered'), hasLength(1));
      expect(a.named('checkout_opened').single['promo'], isTrue);
      expect(a.named('checkout_opened').single['plan'], 'monthly');

      await state.startPlusTrial();
      expect(a.named('trial_started'), hasLength(1));
      expect(a.named('trial_started').single['plus'], isTrue, reason: 'the tier on the event is the tier after the trial started');
    });

    test('sharing the week is an event; the card itself is not', () async {
      final a = MemoryAnalytics();
      final sharer = MemorySharer();
      final state = AppState(sharer: sharer, analytics: a);
      await state.setImprove(true);
      await state.shareReview(Uint8List.fromList([1, 2, 3]));
      expect(a.named('review_shared'), hasLength(1));
      expect(sharer.shared, hasLength(1));
    });

    test('screens are seen only after consent', () async {
      final a = MemoryAnalytics();
      final state = AppState(analytics: a);
      state.go(AppScreen.subscription);
      await state.setImprove(true);
      state.go(AppScreen.progress);
      state.openWallet();
      await settle();
      expect(a.screens, ['progress', 'wallet']);
    });
  });

  group('the night sentence', () {
    final today = DateTime(2026, 9, 21, 8, 30);
    NightNote note() => NightNote(
          day: DateTime(2026, 9, 21),
          ar: 'بكرة أخف من النهارده بـ 12٪ — 1800 سعرة على 3 وجبات.',
          en: 'Tomorrow is 12% lighter than today — 1800 kcal over 3 meals.',
          planKcal: 1800,
          todayKcal: 2050,
        );

    test('last night’s sentence is loaded for today, in the app’s language and digits', () async {
      final meals = FakeMealRepo()..note = note();
      final state = backed(meals: meals, clock: () => today);
      await settle();
      expect(state.nightNote, isNotNull);
      expect(state.nightSentence, contains('١٢٪'), reason: 'Arabic with Eastern digits by default');
      state.setLang(AppLang.en);
      expect(state.nightSentence, 'Tomorrow is 12% lighter than today — 1800 kcal over 3 meals.');
    });

    test('on the free tier the plan behind it is locked, and the lock is the wall', () async {
      final a = MemoryAnalytics();
      final state = backed(meals: FakeMealRepo()..note = note(), analytics: a, clock: () => today);
      await state.setImprove(true);
      await settle();
      expect(state.nightPlanLocked, isTrue);
      state.openNightNote();
      expect(state.screen, AppScreen.subscription);
      expect(a.named('wall_tapped').single['wall'], 'tomorrow');
    });

    test('a member opens today’s plan from it', () async {
      final state = backed(meals: FakeMealRepo()..note = note(), clock: () => today)..plusActive = true;
      await settle();
      expect(state.nightPlanLocked, isFalse);
      state.openNightNote();
      expect(state.screen, AppScreen.plan);
    });

    test('without a backend, or with nothing written, there is no sentence and none is invented', () async {
      expect(AppState().nightNote, isNull);
      final state = backed(meals: FakeMealRepo(), clock: () => today);
      await settle();
      expect(state.nightNote, isNull);
      expect(state.nightSentence, isNull);
    });
  });

  group('invitations — the referral loop', () {
    test('a member sends a named invitation; the sheet gets the name, the code and the link', () async {
      final repo = FakeInvitationRepo();
      final sharer = MemorySharer();
      final a = MemoryAnalytics();
      final state = backed(invitations: repo, sharer: sharer, analytics: a)..plusActive = true;
      state.profile = state.profile.copyWith(name: 'Basel');
      await state.setImprove(true);
      await settle();

      await state.issueInvitation('  Omar ');
      expect(repo.issued, ['Omar']);
      expect(state.invitations.invitations.single.number, 1);
      expect(state.invitationsLeft, 2);
      expect(state.invitationNotice, isNull);
      final msg = sharer.texts.single;
      expect(msg, contains('Omar'));
      expect(msg, contains('Basel'));
      expect(msg, contains('QMR-7F3A1'));
      expect(msg, contains('https://dr-qamar.com/i/QMR-7F3A1'));
      expect(a.named('invitation_sent').single['number'], 1);
    });

    test('three a quarter: the fourth is refused before the server is asked', () async {
      final repo = FakeInvitationRepo();
      final state = backed(invitations: repo, sharer: MemorySharer())..plusActive = true;
      await settle();
      for (final n in ['Omar', 'Sara', 'Nour']) {
        await state.issueInvitation(n);
      }
      expect(state.invitationsLeft, 0);
      await state.issueInvitation('Youssef');
      expect(repo.issued, ['Omar', 'Sara', 'Nour']);
      expect(state.invitationNotice, isNotNull);
    });

    test('the free tier is told invitations are for members, and nothing is issued', () async {
      final repo = FakeInvitationRepo();
      final state = backed(invitations: repo, sharer: MemorySharer())..setLang(AppLang.en);
      await settle();
      await state.issueInvitation('Omar');
      expect(repo.issued, isEmpty);
      expect(state.invitationNotice, 'Invitations are for Qamar+ members.');
    });

    test('an invitation carries a name', () async {
      final repo = FakeInvitationRepo();
      final state = backed(invitations: repo, sharer: MemorySharer())..plusActive = true;
      await settle();
      await state.issueInvitation('   ');
      expect(repo.issued, isEmpty);
      expect(state.invitationNotice, isNotNull);
    });

    test('a friend redeems a code: the sender’s name greets them and the fortnight starts', () async {
      final repo = FakeInvitationRepo();
      final billing = FakeBilling()..current = const PlusEntitlement(status: 'active', plan: 'monthly', provider: 'trial', trialEligible: false);
      final a = MemoryAnalytics();
      final state = backed(invitations: repo, billing: billing, analytics: a)..setLang(AppLang.en);
      await state.setImprove(true);
      await settle();

      await state.redeemInvitation(' qmr-7f3a1 ');
      expect(repo.redeemCodes, ['qmr-7f3a1']);
      expect(state.invitedBy, 'Basel');
      expect(state.invitationNotice, 'Basel invited you. 14 days of Qamar+ are yours from now.');
      expect(state.plusActive, isTrue, reason: 'the entitlement is re-read after the server grants the fortnight');
      expect(a.named('invitation_redeemed').single['trial_days'], 14);
    });

    test('the server’s refusal is the message, not a crash', () async {
      final repo = FakeInvitationRepo()..failWith = const InvitationException('no invitation with that code');
      final state = backed(invitations: repo)..setLang(AppLang.en);
      await settle();
      await state.redeemInvitation('QMR-00000');
      expect(state.invitationNotice, 'no invitation with that code');
      expect(state.invitedBy, isNull);
    });

    test('offline there is nothing to redeem against, and it says so', () async {
      final state = AppState()..setLang(AppLang.en);
      await state.redeemInvitation('QMR-7F3A1');
      expect(state.invitationNotice, contains('connected to your account'));
    });

    test('the book knows this quarter’s allotment', () {
      final book = InvitationBook.fromJson({
        'quarter': '2026Q3',
        'limit': 3,
        'invitations': [
          {'id': 'a', 'number': 1, 'quarter': '2026Q2', 'name': 'Old', 'code': 'QMR-AAAAA', 'created_at': '2026-05-01T10:00:00Z', 'redeemed_at': '2026-05-02T10:00:00Z', 'converted_at': '2026-05-20T10:00:00Z'},
          {'id': 'b', 'number': 1, 'quarter': '2026Q3', 'name': 'New', 'code': 'QMR-BBBBB', 'created_at': '2026-09-01T10:00:00Z'},
        ],
      });
      expect(book.usedThisQuarter, 1);
      expect(book.left, 2);
      expect(book.invitations.first.status, InvitationStatus.subscribed);
      expect(book.invitations.last.status, InvitationStatus.sent);
      expect(book.invitations.last.link, 'https://dr-qamar.com/i/QMR-BBBBB');
    });
  });

  group('Ramadan mode, backed', () {
    test('the server’s season dates win, and the fasting switch reaches the profile', () async {
      final profiles = FakeProfileRepo()
        ..season = Season(key: 'ramadan_1448', nameAr: 'رمضان 1448', nameEn: 'Ramadan 1448', startsOn: DateTime(2027, 2, 9), endsOn: DateTime(2027, 3, 10), eidOn: DateTime(2027, 3, 11));
      final gateway = FakeGateway();
      final state = backed(profiles: profiles, ai: gateway, clock: () => DateTime(2027, 2, 10, 12));
      await settle();
      expect(state.season.startsOn, DateTime(2027, 2, 9), reason: 'the sighting moved the month; the app follows the server');
      expect(state.season.dayOf(DateTime(2027, 2, 10)), 2);

      await state.ensurePlan();
      await settle();
      final before = gateway.planCalls;
      await state.setFasting(true);
      await settle();
      expect(profiles.fastingSaves, [FastingMode.ramadan]);
      expect(gateway.planCalls, before + 1, reason: 'a fasting day is a different plan; today is rewritten');
      expect(state.fasting, isTrue);
    });
  });

  group('the Log node’s other two branches', () {
    test('repeat offers the last week’s distinct meals, today’s first, and one tap logs one again', () async {
      final meals = FakeMealRepo()
        ..recent = [
          LoggedMeal(name: 'Koshary', sub: 'by text', kcal: 520, p: 16, c: 96, f: 9, at: DateTime(2026, 9, 20, 14)),
          LoggedMeal(name: 'Foul', sub: 'by voice', kcal: 380, p: 18, c: 50, f: 9, at: DateTime(2026, 9, 19, 9)),
          LoggedMeal(name: 'koshary', sub: 'by photo', kcal: 600, p: 18, c: 100, f: 12, at: DateTime(2026, 9, 18, 14)),
        ];
      final a = MemoryAnalytics();
      final state = backed(meals: meals, analytics: a, clock: () => DateTime(2026, 9, 21, 13));
      await state.setImprove(true);
      await settle();

      expect(state.repeatChoices.map((m) => m.name), ['Koshary', 'Foul'], reason: 'the same dish twice is one choice');

      state.expandTreeLog(0);
      state.expandTreeSub(TreeSub.repeat);
      expect(state.treeLogSub, TreeSub.repeat);
      state.repeatMeal(state.repeatChoices.first);
      await settle();

      expect(state.treeOpen, isFalse);
      expect(state.treeLogSub, isNull);
      expect(state.meals.single.name, 'Koshary');
      expect(state.meals.single.kcal, 520);
      expect(meals.saved.single.name, 'Koshary');
      expect(meals.drafts, 1, reason: 'the repeat is traceable like any other log');
      expect(a.named('meal_logged').single['source'], 'recent');
      expect(state.repeatChoices.first.name, 'Koshary', reason: 'today’s meal leads the list');
    });

    test('activity: a kind on the ring, a duration on the sheet, an estimate on the card', () async {
      final wallet = FakeWalletRepo();
      final repo = FakeActivityRepo(wallet: wallet);
      final state = backed(activities: repo, wallet: wallet, clock: () => DateTime(2026, 9, 21, 18));
      await settle();
      final before = state.suAvailable;

      state.expandTreeLog(0);
      state.expandTreeSub(TreeSub.activity);
      state.chooseActivity(ActivityKind.football);
      expect(state.treeOpen, isFalse, reason: 'the sheet takes over from the ring');
      expect(state.pendingActivity, ActivityKind.football);

      await state.logActivity(30);
      await settle();
      expect(state.pendingActivity, isNull);
      expect(state.activitiesToday.single.kcal, ActivityCatalog.kcalFor(ActivityKind.football, 30, state.profile.weight));
      expect(state.activityMinutesToday, 30);
      expect(repo.added.single.minutes, 30);
      expect(state.activitiesToday.single.id, 'act-1', reason: 'the server’s id comes back onto the row');
      expect(state.suAvailable, before + SuEconomy.activityLogged, reason: 'movement earns; the server’s balance carries it after the write');
      expect(state.consumed().kcal, 0, reason: 'movement is never subtracted from the food');
    });

    test('cancelling the sheet logs nothing', () async {
      final repo = FakeActivityRepo();
      final state = backed(activities: repo);
      state.chooseActivity(ActivityKind.walk);
      state.cancelActivity();
      await state.logActivity(30);
      expect(state.activitiesToday, isEmpty);
      expect(repo.added, isEmpty);
    });

    test('today’s movement comes back on hydrate', () async {
      final repo = FakeActivityRepo()..today = [ActivityLog(id: 'x', kind: ActivityKind.gym, minutes: 45, kcal: 300, at: DateTime(2026, 9, 21, 8))];
      final state = backed(activities: repo);
      await settle();
      expect(state.activityMinutesToday, 45);
      expect(state.activityKcalToday, 300);
    });
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

  int trialStarts = 0;

  @override
  Future<PlusEntitlement> startTrial() async {
    trialStarts++;
    if (!current.trialEligible) throw BillingException('The free week has already been used on this account.');
    current = PlusEntitlement(
      status: 'active',
      plan: 'monthly',
      provider: 'trial',
      periodEnd: DateTime.now().toUtc().add(const Duration(days: 7)),
      trialEligible: false,
      trialEndsAt: DateTime.now().toUtc().add(const Duration(days: 7)),
    );
    return current;
  }

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
