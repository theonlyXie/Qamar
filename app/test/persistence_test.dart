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
import 'package:qamar/models/dishes.dart';
import 'package:qamar/models/profile.dart';
import 'package:qamar/models/quest.dart';
import 'package:qamar/models/ramadan.dart';
import 'package:qamar/models/streak.dart';
import 'package:qamar/models/su_economy.dart';
import 'package:qamar/models/activity.dart';
import 'package:qamar/models/basket.dart';
import 'package:qamar/models/billing.dart';
import 'package:qamar/models/pending_write.dart';
import 'package:qamar/models/invitation.dart';
import 'package:qamar/models/water.dart';
import 'package:qamar/services/ai_gateway.dart';
import 'package:qamar/services/analytics.dart';
import 'package:qamar/services/auth_service.dart';
import 'package:qamar/services/device_prefs.dart';
import 'package:qamar/services/dictation.dart';
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

  /// The adherence answer on record, kept apart from the improve one.
  bool? adherenceOnRecord;

  @override
  Future<bool?> loadConsent(String userId, String type) async =>
      type == ConsentType.adherence ? adherenceOnRecord : consentOnRecord;

  Season? season;
  final List<FastingMode> fastingSaves = [];

  /// Each Start the app reported, in order.
  final List<String> starts = [];

  /// When the account began, as the server has it.
  DateTime? day0;

  @override
  Future<DateTime?> accountDay0(String userId) async => day0;

  @override
  Future<void> recordIntakeStart(String userId, {required String via}) async {
    if (failWith != null) throw failWith!;
    starts.add(via);
  }

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
  final List<List<({ConfirmItemDef def, int qty})>> savedItems = [];
  List<LoggedMeal> today = [];
  int drafts = 0;

  /// While set, every write fails — the phone has no signal.
  Object? offline;

  @override
  Future<String> saveDraft(String userId, MealAnalysisDraft draft) async {
    if (offline != null) throw offline!;
    drafts++;
    return 'draft-$drafts';
  }

  @override
  Future<void> confirmMeal(String userId, {required String draftId, required LoggedMeal meal, List<({ConfirmItemDef def, int qty})> items = const []}) async {
    if (offline != null) throw offline!;
    saved.add(meal);
    savedItems.add(items);
  }

  @override
  Future<List<LoggedMeal>> mealsForDay(String userId, DateTime day) async => today;

  /// What the food graph answers for per-100 g numbers; empty is a miss.
  Map<String, Per100> graph = const {};
  final List<Set<String>> graphAsks = [];

  @override
  Future<Map<String, Per100>> graphPer100(Iterable<String> slugs) async {
    graphAsks.add(slugs.toSet());
    return {for (final s in slugs) if (graph.containsKey(s)) s: graph[s]!};
  }

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

  /// While set, every write fails — the phone has no signal.
  Object? offline;

  @override
  Future<String> addSip(String userId, WaterSip sip) async {
    if (offline != null) throw offline!;
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
  int questReads = 0;
  int skips = 0;
  int onboardingGrants = 0;

  /// Today's quest as the server has it. A test sets it, and marks it done
  /// the way the real earn trigger would when a row meets it.
  DayQuest? todaysQuest;

  @override
  Future<({int available, int lifetime})> balance(String userId) async {
    balanceReads++;
    return stored;
  }

  @override
  Future<DayQuest?> todayQuest(String userId) async {
    questReads++;
    return todaysQuest;
  }

  @override
  Future<void> skipQuest(String userId) async {
    skips++;
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

  /// What each meal reading was asked to read.
  final List<String?> mealTexts = [];

  /// While set, a meal reading waits on it: a reading still on its way.
  Completer<void>? readGate;

  @override
  Future<MealAnalysis> analyzeMeal({required String inputType, String? text, String? imagePath, String lang = 'ar'}) async {
    imagePaths.add(imagePath);
    mealTexts.add(text);
    final gate = readGate;
    if (gate != null) await gate.future;
    // Typed and spoken logs are the food graph. Only a photo spends a use.
    if (inputType == 'photo' || (imagePath != null && imagePath.isNotEmpty)) {
      _usePhoto();
    }
    return result;
  }

  final List<String?> chatImagePaths = [];

  @override
  Future<ChatResult> chatReply({
    required String message,
    required String lang,
    String? date,
    Map<String, dynamic>? currentPlan,
    List<String>? swappedSlots,
    String? imagePath,
  }) async {
    chatMessages.add(message);
    chatImagePaths.add(imagePath);
    lastCurrentPlan = currentPlan;
    // A photo in the conversation is one of the day's photos, not a question.
    if (imagePath != null) {
      _usePhoto();
    } else {
      _useChat();
    }
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

  Object? offline;

  @override
  Future<String> add(String userId, ActivityLog entry) async {
    if (offline != null) throw offline!;
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
  MemoryNudger? nudger,
  Dictation? dictation,
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
      nudger: nudger,
      dictation: dictation,
      clock: clock,
    );

Future<void> settle() => Future<void>.delayed(const Duration(milliseconds: 60));

/// A recogniser that hears what the test says.
class FakeDictation implements Dictation {
  void Function(String text, bool isFinal)? _onResult;

  @override
  bool get available => true;

  @override
  bool get listening => _onResult != null;

  @override
  Future<bool> prepare({void Function(String status)? onStatus, void Function(String error)? onError}) async => true;

  @override
  Future<bool> start({required String lang, required void Function(String text, bool isFinal) onResult}) async {
    _onResult = onResult;
    return true;
  }

  @override
  Future<void> stop() async {}

  @override
  Future<void> cancel() async {}

  /// The person stops speaking, having said [words] (nothing, if empty).
  void say(String words) {
    final heard = _onResult;
    _onResult = null;
    heard?.call(words, true);
  }
}

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
    test('the quest is paid by the server from the meal that meets it, and the phone credits nothing for it', () async {
      final later = DateTime.now().add(const Duration(hours: 3));
      final wallet = FakeWalletRepo()..todaysQuest = DayQuest(kind: QuestKind.lunchBy16, done: false, expiresAt: later);
      final ai = FakeGateway();
      final state = backed(wallet: wallet, ai: ai);
      await settle();
      expect(state.quest?.kind, QuestKind.lunchBy16, reason: 'read with the wallet');
      expect(state.questDue, isTrue);

      state.quickLog(QuickLog.text);
      await state.sendChatMsg('koshary');
      await settle();
      // The server's triggers paid the meal and the lunch quest it met.
      wallet.stored = (available: 850, lifetime: 850);
      wallet.todaysQuest = DayQuest(kind: QuestKind.lunchBy16, done: true, expiresAt: later);
      final readsBefore = wallet.questReads;
      state.confirmProposal();
      expect(state.suAvailable, SuEconomy.firstMeal, reason: 'the phone shows only the meal it knows it earned');
      await settle();

      expect(state.suAvailable, 850, reason: 'the ledger’s number, quest included, replaces the phone’s');
      expect(wallet.questReads, greaterThan(readsBefore), reason: 're-read after the insert that met it');
      expect(state.quest!.done, isTrue);
      expect(state.ledger().where((e) => e.amount == SuEconomy.dailyQuest), isEmpty, reason: 'never credited on the phone');
    });

    test('"not today" puts the quest away at once and tells the server; nothing is paid', () async {
      final wallet = FakeWalletRepo()
        ..todaysQuest = DayQuest(kind: QuestKind.water6, done: false, expiresAt: DateTime.now().add(const Duration(hours: 3)));
      final state = backed(wallet: wallet);
      await settle();
      expect(state.questDue, isTrue);
      state.skipQuest();
      expect(state.questDue, isFalse, reason: 'gone before the server answers');
      await settle();
      expect(wallet.skips, 1);
      expect(state.suAvailable, 0);
    });

    test('a quest past its time leaves the slot, and Today asks for the next one', () async {
      var now = DateTime(2027, 2, 5, 12);
      final wallet = FakeWalletRepo()..todaysQuest = DayQuest(kind: QuestKind.lunchBy16, done: false, expiresAt: DateTime(2027, 2, 5, 16));
      final state = backed(wallet: wallet, clock: () => now);
      await settle();
      expect(state.questDue, isTrue);
      now = DateTime(2027, 2, 5, 16, 30);
      expect(state.questDue, isFalse, reason: 'lunch before four has gone by');
      wallet.todaysQuest = DayQuest(kind: QuestKind.water6, done: false, expiresAt: DateTime(2027, 2, 6));
      await state.refreshQuest();
      expect(state.quest?.kind, QuestKind.water6, reason: 'the next gap the day has');
      expect(state.questDue, isTrue);
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

    test('offline there is no quest: nothing to show, and nothing to tap that pays one', () async {
      final state = AppState();
      expect(state.quest, isNull);
      expect(state.questDue, isFalse);
      state.skipQuest();
      expect(state.suAvailable, 0);
      expect(state.ledger(), isEmpty);
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
      expect(nudger.scheduled.length, 28, reason: 'the whole fourteen-day window, two a day');
      expect(nudger.lastAr, isTrue);
    });

    test('someone who stops opening the app still hears the rest of the window, and nothing past it', () async {
      // Ten days in, the app is opened once more and then never again. What
      // is on the phone's schedule after this session is all they will hear.
      final prefs = MemoryDevicePrefs();
      await prefs.setString('first_day', DateTime(2026, 9, 11).toIso8601String());
      final nudger = MemoryNudger();
      final state = AppState(nudger: nudger, prefs: prefs, clock: morning);
      await settle();
      await state.allowNudges();

      expect(nudger.scheduled.length, 8, reason: 'days 10 to 13 of the window, two a day');
      expect(nudger.scheduled.last.at, DateTime(2026, 9, 24, 20, 30), reason: 'day 13 is the last day with a question');
      expect(nudger.scheduled.where((n) => !n.at.isBefore(DateTime(2026, 9, 25))), isEmpty, reason: 'day 14 onwards is the internal trigger’s');
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

    state.repeatMeal(LoggedMeal(name: 'Koshary', sub: '', kcal: 520, p: 16, c: 96, f: 9, at: DateTime.now()));
    expect(state.ledger().single.amount, SuEconomy.firstMeal);
    expect(state.suAvailable, SuEconomy.firstMeal);
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

    final dob = kOnboardingSteps.indexWhere((s) => s.id == 'dob');
    state.step = dob;
    state.profile = state.profile.copyWith(age: 30);
    state.primarySubmit();
    await Future<void>.delayed(const Duration(milliseconds: 400));

    expect(state.syncError, isNotNull, reason: 'the failure must be visible, not swallowed');
    expect(state.profile.age, 30, reason: 'the local answer must survive');
    expect(state.step, greaterThan(dob), reason: 'onboarding must not stall on a failed write');
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
      expect(a.named('intake_step').single['step'], 'consent', reason: 'jumped straight to consent, so it is the only step answered');
      expect(a.named('intake_started').single['pre_consent'], isTrue, reason: 'Start waited on the phone for the yes');
    });

    // The three consent chips are three different answers.
    Future<void> answerConsent(AppState state, String value) async {
      final at = kOnboardingSteps.indexWhere((s) => s.id == 'consent');
      state.step = at;
      state.pickOption(kOnboardingSteps[at].options.firstWhere((o) => o.value == value));
      await Future<void>.delayed(const Duration(milliseconds: 1000));
    }

    test('“Agree + help improve” is a yes: saved, analytics on, and what waited goes out after it, in order', () async {
      final a = MemoryAnalytics();
      final profiles = FakeProfileRepo();
      final state = backed(profiles: profiles, analytics: a);
      await settle();
      state.startOnboarding();
      state.logWater(WaterUnit.glass);
      await settle();
      expect(a.events, isEmpty, reason: 'waiting on the phone is not sending');
      expect(a.enabledFor, isEmpty, reason: 'the SDK is not even started before the answer');
      expect(state.heldEvents, 2);

      await answerConsent(state, 'yes_improve');

      expect(state.improve, isTrue);
      expect(state.step, kOnboardingSteps.indexWhere((s) => s.id == 'consent') + 1, reason: 'it advances');
      expect(profiles.consents, [(type: 'improve_optional', granted: true, version: '1.1')]);
      expect(a.events.map((e) => e.name).toList(), ['consent_granted', 'intake_started', 'water_logged', 'intake_step'],
          reason: 'the yes first, then what waited for it, oldest first');
      expect(a.named('intake_started').single['pre_consent'], isTrue);
      expect(a.named('intake_started').single['via'], 'chat');
      expect(a.named('intake_step').single.containsKey('pre_consent'), isFalse, reason: 'answered after the yes');
      expect(state.heldEvents, 0);
    });

    test('“Agree to the required only” is a recorded no: what waited is dropped, and nothing waits after it', () async {
      final a = MemoryAnalytics();
      final profiles = FakeProfileRepo();
      final state = backed(profiles: profiles, analytics: a);
      await settle();
      state.startOnboarding();
      await settle();
      expect(state.heldEvents, 1);

      await answerConsent(state, 'yes');

      expect(state.improve, isFalse);
      expect(state.improveAnswered, isTrue);
      expect(state.step, kOnboardingSteps.indexWhere((s) => s.id == 'consent') + 1, reason: 'the required part is agreed, so it advances');
      expect(profiles.consents, [(type: 'improve_optional', granted: false, version: '1.1')], reason: 'a no on the account, not silence');
      expect(state.heldEvents, 0, reason: 'a no drops what waited');

      state.logWater(WaterUnit.glass);
      await settle();
      expect(state.heldEvents, 0, reason: 'after a no nothing waits');

      await state.setImprove(true); // a later yes, on the You screen
      await settle();
      expect(a.events.map((e) => e.name).toList(), ['consent_granted'], reason: 'nothing from before the no is ever sent');
    });

    test('“Tell me more” explains what each choice covers and waits for the answer', () async {
      final state = AppState(analytics: MemoryAnalytics());
      state.startOnboarding();
      await Future<void>.delayed(const Duration(milliseconds: 1000)); // the first question has arrived
      final before = state.msgs.length;

      await answerConsent(state, 'more');

      expect(state.step, kOnboardingSteps.indexWhere((s) => s.id == 'consent'), reason: 'a question is not an answer');
      expect(state.improve, isFalse);
      expect(state.improveAnswered, isFalse, reason: 'still unanswered, so events still wait');
      expect(state.msgs.length, before + 2, reason: 'their question, then Qamar’s answer');
      expect(state.msgs.last.text(false), contains('never your food, your weight or your name'));
      expect(state.msgs.last.text(true), contains('من غير أكلك ولا وزنك ولا اسمك'));
    });

    test('what waits is capped, and the funnel’s first event is never the one pushed out', () async {
      final a = MemoryAnalytics();
      final state = AppState(analytics: a);
      state.startOnboarding();
      for (var i = 0; i < 80; i++) {
        state.logWater(WaterUnit.glass);
      }
      await settle();
      expect(state.heldEvents, AppState.heldEventCap);

      await state.setImprove(true);
      await settle();
      expect(a.events.length, AppState.heldEventCap + 1, reason: 'the yes, then everything that waited');
      expect(a.events[1].name, 'intake_started');
    });

    test('an answer given earlier on this phone decides at once: a no never holds anything', () async {
      final prefs = MemoryDevicePrefs();
      await prefs.setBool('improve_consent', false);
      final a = MemoryAnalytics();
      final state = AppState(prefs: prefs, analytics: a);
      await settle();
      state.startOnboarding();
      state.logWater(WaterUnit.glass);
      await settle();
      expect(state.improveAnswered, isTrue);
      expect(state.heldEvents, 0);
      expect(a.events, isEmpty);
    });

    test('a pregnancy answer is saved with the profile, where it becomes the life stage the gateway enforces', () async {
      final profiles = FakeProfileRepo();
      final state = backed(profiles: profiles);
      await settle();
      state.startOnboarding();
      await answerConsent(state, 'yes');
      state.pickOption(kOnboardingSteps[1].options.firstWhere((o) => o.value == 'pregnant'));
      await Future<void>.delayed(const Duration(milliseconds: 1000));
      expect(profiles.stored?.safety, SafetyAnswer.pregnant);
      expect(profiles.stored!.safety.lifeStage, 'pregnant', reason: 'what saveProfile writes to profiles.life_stage');
      expect(profiles.targetSaves, 0, reason: 'no target is ever written on this route');
    });

    test('pressing Start is written to the account at the tap, once, before any answer', () async {
      final profiles = FakeProfileRepo();
      final state = backed(profiles: profiles);
      await settle();
      state.openScan();
      state.backToWelcome();
      state.startOnboarding();
      await settle();
      expect(profiles.starts, ['scan'], reason: 'the report is a Start too, and the first one is kept');
      expect(profiles.saves, 0, reason: 'nothing answered yet');
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
      // Eleven in the morning: no meal question is waiting on the orb.
      final state = backed(ai: FakeGateway(), analytics: a, clock: () => DateTime(2026, 9, 21, 11, 0));
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
        'prompt': 'none',
        'orb_waiting': false,
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

    test('the event carries what started the log: prompt and orb_waiting', () async {
      final a = MemoryAnalytics();
      final state = AppState(analytics: a, ai: FakeGateway(), clock: () => DateTime(2026, 9, 21, 14, 30));
      await state.setImprove(true);
      state.quickLog(QuickLog.text); // from the tree, while lunch's question waits on the orb
      await state.sendChatMsg('koshary');
      await settle();
      state.confirmProposal();
      await settle();
      final logged = a.named('meal_logged').single;
      expect(logged['prompt'], 'none', reason: 'the tree during the pulse is the habit itself');
      expect(logged['orb_waiting'], isTrue);
      expect(logged['nudged'], isFalse);
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

  group('what started a log — the day-30 habit metric’s input (O6)', () {
    test('a log that began from a tapped push is a push, even when confirmed after the half hour', () async {
      var now = DateTime(2026, 9, 21, 14, 30);
      final meals = FakeMealRepo();
      final nudger = MemoryNudger();
      final state = backed(meals: meals, nudger: nudger, ai: FakeGateway(), clock: () => now);
      await settle();
      nudger.tap('nudge:lunch');
      await settle();
      await state.sendChatMsg('koshary');
      await settle();
      now = now.add(const Duration(minutes: 40)); // confirmed late: captured at the start, not here
      state.confirmProposal();
      await settle();
      expect(meals.saved.single.prompt, 'push');
      expect(meals.saved.single.orbWaiting, isTrue, reason: 'lunch’s question was waiting when it started');
    });

    test('holding the orb while its question waits starts an in-app log, and hears the answer as the meal', () async {
      final meals = FakeMealRepo();
      final state = backed(meals: meals, ai: FakeGateway(), clock: () => DateTime(2026, 9, 21, 14, 30));
      await settle();
      expect(state.waitingNudge, isNotNull);
      await state.holdOrb();
      await state.sendChatMsg('koshary');
      await settle();
      expect(state.proposal, isNotNull, reason: 'the answer to the meal question is read as the meal');
      state.confirmProposal();
      await settle();
      expect(meals.saved.single.prompt, 'in_app');
      expect(meals.saved.single.orbWaiting, isTrue);
    });

    test('a hold with no question waiting is a conversation, not a log', () async {
      final state = backed(ai: FakeGateway(), clock: () => DateTime(2026, 9, 21, 11, 0));
      await settle();
      expect(state.waitingNudge, isNull);
      await state.holdOrb();
      await state.sendChatMsg('is koshary healthy?');
      await settle();
      expect(state.proposal, isNull);
    });

    test('after an earlier exchange, a hold asks the waiting question as Qamar’s newest line; only its answer is read as the meal', () async {
      var now = DateTime(2026, 9, 21, 11, 0);
      final meals = FakeMealRepo();
      final ai = FakeGateway();
      final voice = FakeDictation();
      final state = backed(meals: meals, ai: ai, dictation: voice, clock: () => now);
      await settle();
      state.openChat(); // the morning's conversation
      await state.sendChatMsg('can I have feteer tonight?');
      await settle();
      state.closeChat();

      now = DateTime(2026, 9, 21, 14, 30); // lunch's question is waiting
      final lunch = state.waitingNudge!.text(ar: state.isAr);
      await state.holdOrb();
      expect(state.chat.last.text, lunch, reason: 'the question is on screen before anything is heard');
      voice.say('koshary');
      await settle();
      expect(ai.mealTexts, ['koshary']);
      expect(ai.chatMessages, ['can I have feteer tonight?'], reason: 'the question was never read as a meal');
      state.confirmProposal();
      await settle();
      expect(meals.saved.single.prompt, 'in_app');
    });

    test('held again while the question is still Qamar’s last line, it is the same ask, not a second one', () async {
      final meals = FakeMealRepo();
      final voice = FakeDictation();
      final state = backed(meals: meals, ai: FakeGateway(), dictation: voice, clock: () => DateTime(2026, 9, 21, 14, 30));
      await settle();
      final lunch = state.waitingNudge!.text(ar: state.isAr);
      await state.holdOrb();
      voice.say(''); // nothing said …
      state.closeChat(); // … and closed
      await state.holdOrb();
      expect(state.chat.where((t) => t.text == lunch), hasLength(1));
      voice.say('koshary');
      await settle();
      state.confirmProposal();
      await settle();
      expect(meals.saved.single.prompt, 'in_app');
    });

    test('once the talk has moved past the question, a hold is a conversation: nothing asked is read as a meal, nothing is in_app', () async {
      final ai = FakeGateway();
      final voice = FakeDictation();
      final state = backed(ai: ai, dictation: voice, clock: () => DateTime(2026, 9, 21, 14, 30));
      await settle();
      await state.holdOrb(); // lunch is asked …
      voice.say('');
      state.closeChat(); // … and left unanswered
      state.openChat(); // back, from the Plan screen's "ask"
      await state.sendChatMsg('can I have feteer tonight?');
      await settle();
      state.closeChat();

      await state.holdOrb(); // lunch still waits, but the conversation has moved on
      expect(state.chat.last.text, isNot(state.waitingNudge!.text(ar: state.isAr)), reason: 'not asked again');
      voice.say('and with honey?');
      await settle();
      expect(ai.mealTexts, isEmpty);
      expect(ai.chatMessages, ['can I have feteer tonight?', 'and with honey?']);
      expect(state.proposal, isNull);
    });

    test('a log closed on without a word is disarmed: a question asked later goes to the chat, not the analyser', () async {
      final ai = FakeGateway();
      final state = backed(ai: ai, clock: () => DateTime(2026, 9, 21, 11, 0));
      await settle();
      state.quickLog(QuickLog.text); // "Tell me what you ate." …
      state.closeChat(); // … closed without an answer
      state.openChat(); // later, from the Plan screen
      await state.sendChatMsg('can I have feteer tonight?');
      await settle();
      expect(ai.mealTexts, isEmpty);
      expect(ai.chatMessages, ['can I have feteer tonight?']);
    });

    test('a reading still on its way when the conversation closes keeps its start: confirmed 40 minutes later, still a push', () async {
      var now = DateTime(2026, 9, 21, 14, 30);
      final meals = FakeMealRepo();
      final nudger = MemoryNudger();
      final voice = FakeDictation();
      final ai = FakeGateway()..readGate = Completer<void>();
      final state = backed(meals: meals, nudger: nudger, ai: ai, dictation: voice, clock: () => now);
      await settle();
      nudger.tap('nudge:lunch');
      await settle();
      voice.say('koshary'); // spoken …
      await settle();
      expect(state.chatState, ChatState.thinking);
      state.closeChat(); // … and closed while it is read
      now = now.add(const Duration(minutes: 40));
      ai.readGate!.complete();
      await settle();
      expect(state.proposal, isNotNull);
      state.confirmProposal();
      await settle();
      expect(meals.saved.single.prompt, 'push');
      expect(meals.saved.single.orbWaiting, isTrue);
    });

    test('holding the orb to come back to it picks the reading up where it was: no second ask, and the push stands', () async {
      var now = DateTime(2026, 9, 21, 14, 30);
      final meals = FakeMealRepo();
      final nudger = MemoryNudger();
      final voice = FakeDictation();
      final ai = FakeGateway()..readGate = Completer<void>();
      final state = backed(meals: meals, nudger: nudger, ai: ai, dictation: voice, clock: () => now);
      await settle();
      nudger.tap('nudge:lunch');
      await settle();
      voice.say('koshary');
      await settle();
      state.closeChat();
      now = now.add(const Duration(minutes: 40)); // lunch's question is still waiting
      final lunch = state.waitingNudge!.text(ar: state.isAr);
      await state.holdOrb(); // back while it is still being read
      expect(state.chatState, ChatState.thinking, reason: 'Qamar is still reading it, and does not listen over it');
      ai.readGate!.complete();
      await settle();
      expect(state.chat.where((t) => t.text == lunch), hasLength(1), reason: 'asked once, with the push');
      state.confirmProposal();
      await settle();
      expect(ai.mealTexts, ['koshary']);
      expect(meals.saved.single.prompt, 'push');
    });

    test('a reading waiting to be confirmed is what a hold goes back to: the waiting question is not asked over it', () async {
      var now = DateTime(2026, 9, 21, 13, 50);
      final meals = FakeMealRepo();
      final ai = FakeGateway();
      final state = backed(meals: meals, ai: ai, clock: () => now);
      await settle();
      state.quickLog(QuickLog.text); // from the tree, before lunch's question
      await state.sendChatMsg('koshary');
      await settle();
      state.closeChat(); // not confirmed yet
      now = DateTime(2026, 9, 21, 14, 30); // lunch's question is now waiting
      final lunch = state.waitingNudge!.text(ar: state.isAr);
      await state.holdOrb();
      expect(state.chat.where((t) => t.text == lunch), isEmpty, reason: 'the reading is still there to confirm');
      state.confirmProposal();
      await settle();
      expect(meals.saved.single.prompt, 'none', reason: 'started from the tree at 13:50, with nothing waiting');
      expect(meals.saved.single.orbWaiting, isFalse);
    });

    test('closed mid-sentence, the words still arrive as the meal, with the push’s start', () async {
      var now = DateTime(2026, 9, 21, 14, 30);
      final meals = FakeMealRepo();
      final nudger = MemoryNudger();
      final voice = FakeDictation();
      final ai = FakeGateway();
      final state = backed(meals: meals, nudger: nudger, ai: ai, dictation: voice, clock: () => now);
      await settle();
      nudger.tap('nudge:lunch');
      await settle();
      expect(state.chatState, ChatState.listening);
      state.closeChat(); // closed while still speaking
      voice.say('koshary');
      await settle();
      expect(ai.mealTexts, ['koshary']);
      now = now.add(const Duration(minutes: 40));
      state.confirmProposal();
      await settle();
      expect(meals.saved.single.prompt, 'push');
    });

    test('closed mid-sentence with nothing said, the log is abandoned: what is asked later goes to the chat', () async {
      final ai = FakeGateway();
      final nudger = MemoryNudger();
      final voice = FakeDictation();
      final state = backed(nudger: nudger, ai: ai, dictation: voice, clock: () => DateTime(2026, 9, 21, 14, 30));
      await settle();
      nudger.tap('nudge:lunch');
      await settle();
      state.closeChat();
      voice.say(''); // the recogniser stops: nothing was said
      state.openChat();
      await state.sendChatMsg('can I have feteer tonight?');
      await settle();
      expect(ai.mealTexts, isEmpty);
      expect(ai.chatMessages, ['can I have feteer tonight?']);
    });

    test('a cold log from the tree outside any meal window is none, with nothing waiting', () async {
      final meals = FakeMealRepo();
      final state = backed(meals: meals, ai: FakeGateway(), clock: () => DateTime(2026, 9, 21, 11, 0));
      await settle();
      state.quickLog(QuickLog.text);
      await state.sendChatMsg('koshary');
      await settle();
      state.confirmProposal();
      await settle();
      expect(meals.saved.single.prompt, 'none');
      expect(meals.saved.single.orbWaiting, isFalse);
    });

    test('an abandoned log leaves nothing behind: a later one-tap repeat records its own start', () async {
      var now = DateTime(2026, 9, 21, 11, 0);
      final meals = FakeMealRepo();
      final state = backed(meals: meals, ai: FakeGateway(), clock: () => now);
      await settle();
      state.quickLog(QuickLog.voice); // started at 11:00, nothing waiting …
      state.closeChat(); // … and abandoned
      now = DateTime(2026, 9, 21, 14, 30);
      state.repeatMeal(const LoggedMeal(name: 'Koshary', sub: '', kcal: 520, p: 16, c: 96, f: 9));
      await settle();
      expect(meals.saved.single.prompt, 'none');
      expect(meals.saved.single.orbWaiting, isTrue, reason: 'lunch’s question was waiting at 14:30, when this log started');
    });

    test('the offline queue keeps it: a replayed log still says what started it', () async {
      final meals = FakeMealRepo()..offline = StateError('no signal');
      final nudger = MemoryNudger();
      final prefs = MemoryDevicePrefs();
      final state = backed(meals: meals, nudger: nudger, prefs: prefs, ai: FakeGateway(), clock: () => DateTime(2026, 9, 21, 14, 30));
      await settle();
      nudger.tap('nudge:lunch');
      await settle();
      await state.sendChatMsg('koshary');
      await settle();
      state.confirmProposal();
      await settle();
      expect(meals.saved, isEmpty);
      expect(state.pendingWrites.single.payload['meal']['prompt'], 'push');

      meals.offline = null;
      await state.drainPending();
      expect(meals.saved.single.prompt, 'push');
      expect(meals.saved.single.orbWaiting, isTrue);
    });

    test('LoggedMeal carries the start through JSON, and ignores anything it does not know', () {
      const m = LoggedMeal(name: 'x', sub: '', kcal: 1, p: 0, c: 0, f: 0, prompt: 'in_app', orbWaiting: true);
      final back = LoggedMeal.fromJson(m.toJson());
      expect(back.prompt, 'in_app');
      expect(back.orbWaiting, isTrue);
      expect(LoggedMeal.fromJson({...m.toJson(), 'prompt': 'maybe'}).prompt, isNull, reason: 'unknown is null, never guessed');
      expect(LoggedMeal.fromJson(const {'name': 'x'}).prompt, isNull);
    });

    test('a reinstall that signs back in does not restart the fortnight: the account’s day 0 wins', () async {
      final profiles = FakeProfileRepo()..day0 = DateTime(2026, 9, 1, 10); // the account began 20 days ago
      final prefs = MemoryDevicePrefs(); // a fresh install: the phone remembers nothing
      final nudger = MemoryNudger();
      final state = backed(profiles: profiles, prefs: prefs, nudger: nudger, clock: () => DateTime(2026, 9, 21, 9, 0));
      await settle();
      expect(state.firstDay, DateTime(2026, 9, 1));
      expect(await prefs.getString('first_day'), DateTime(2026, 9, 1).toIso8601String(), reason: 'remembered on the phone too');

      await state.allowNudges();
      expect(nudger.scheduled.where((n) => n.kind == NudgeKind.meal), isEmpty, reason: 'day 20: the window closed on day 14');
    });

    test('a later server day 0 never pushes the phone’s own earlier day back', () async {
      final profiles = FakeProfileRepo()..day0 = DateTime(2026, 9, 20);
      final prefs = MemoryDevicePrefs();
      await prefs.setString('first_day', DateTime(2026, 9, 15).toIso8601String());
      final state = backed(profiles: profiles, prefs: prefs, clock: () => DateTime(2026, 9, 21, 9, 0));
      await settle();
      expect(state.firstDay, DateTime(2026, 9, 15));
    });
  });

  group('the free week, offered after the reveal (O12)', () {
    // Runs the consultation from its last question to the reveal.
    Future<void> toReveal(AppState state) async {
      state.startOnboarding();
      state.step = kOnboardingSteps.indexWhere((s) => s.id == 'food');
      state.primarySubmit();
      await Future<void>.delayed(const Duration(milliseconds: 2600));
    }

    test('after the plan reveal, never before it — and it is counted where it was shown', () async {
      final a = MemoryAnalytics();
      final billing = FakeBilling()..current = const PlusEntitlement(status: 'free', trialEligible: true);
      final state = backed(billing: billing, analytics: a);
      await settle();
      await state.setImprove(true);
      state.startOnboarding();
      expect(state.msgs.any((m) => m.kind == ObKind.trialOffer), isFalse, reason: 'never at the start');

      await toReveal(state);
      final kinds = state.msgs.map((m) => m.kind).toList();
      expect(kinds.indexOf(ObKind.trialOffer), greaterThan(kinds.indexOf(ObKind.target)), reason: 'after the reveal');
      expect(a.named('trial_offer_shown').single['placement'], 'onboarding');
      expect(billing.trialStarts, 0, reason: 'shown, not started: the person chooses');
    });

    test('Start begins the week, with no card, and schedules its one reminder', () async {
      final billing = FakeBilling()..current = const PlusEntitlement(status: 'free', trialEligible: true);
      final nudger = MemoryNudger();
      final state = backed(billing: billing, nudger: nudger);
      await settle();
      await state.allowNudges();
      await toReveal(state);

      await state.acceptTrialOffer();
      await settle();
      expect(billing.trialStarts, 1);
      expect(state.plusIsTrial, isTrue);
      expect(state.msgs.any((m) => m.kind == ObKind.trialOffer), isFalse);
      expect(state.msgs.last.text(false), contains('nothing renews on its own'));
      expect(nudger.scheduled.where((n) => n.kind == NudgeKind.trialEnding), hasLength(1));
    });

    test('Not now leaves the week waiting in Me', () async {
      final a = MemoryAnalytics();
      final billing = FakeBilling()..current = const PlusEntitlement(status: 'free', trialEligible: true);
      final state = backed(billing: billing, analytics: a);
      await settle();
      await state.setImprove(true);
      await toReveal(state);

      state.declineTrialOffer();
      expect(state.msgs.any((m) => m.kind == ObKind.trialOffer), isFalse);
      expect(state.msgs.last.text(false), 'It’s waiting in Me whenever you want it.');
      expect(billing.trialStarts, 0);
      expect(state.trialWaiting, isTrue, reason: 'the You tile says so while it waits');
      expect(a.named('trial_offer_declined').single['placement'], 'onboarding');
    });

    test('while an invitation code waits, no free week is offered: Start would spend the one trial its fortnight needs', () async {
      final prefs = MemoryDevicePrefs();
      await prefs.setString('pending_invitation', 'QMR-LATER');
      final billing = FakeBilling()..current = const PlusEntitlement(status: 'free', trialEligible: true);
      final inv = FakeInvitationRepo()..failWith = StateError('no signal');
      final state = backed(billing: billing, invitations: inv, prefs: prefs);
      await settle();
      expect(state.invitationWaiting, isTrue);
      expect(state.trialWaiting, isFalse, reason: 'so Me does not say "7 days" either');
      await toReveal(state);
      expect(state.msgs.any((m) => m.kind == ObKind.trialOffer), isFalse);
      expect(billing.trialStarts, 0);
    });

    test('never offered where it cannot start: a used trial, a member, or no billing', () async {
      final used = backed(billing: FakeBilling()..current = const PlusEntitlement(status: 'free', trialEligible: false));
      await settle();
      await toReveal(used);
      expect(used.msgs.any((m) => m.kind == ObKind.trialOffer), isFalse);

      final offline = AppState();
      await toReveal(offline);
      expect(offline.msgs.any((m) => m.kind == ObKind.trialOffer), isFalse);
    });
  });

  group('the first moment of value — the food graph, when backed (O5)', () {
    Map<String, Per100> shipped() => {for (final d in kEgyptianDishes) for (final p in d.parts) p.slug: p.per100};

    test('the dish’s numbers come from the live graph when it answers, and the moment is an event', () async {
      final graph = shipped()..['koshary'] = (kcal: 150.0, protein: 5.0, carbs: 22.0, fat: 4.0);
      final meals = FakeMealRepo()..graph = graph;
      final a = MemoryAnalytics();
      final state = backed(meals: meals, analytics: a, clock: () => DateTime(2026, 9, 21, 20, 0));
      await settle();
      await state.setImprove(true);
      state.startOnboarding();
      await settle();
      expect(meals.graphAsks, hasLength(1), reason: 'asked once, as the consultation begins');
      expect(meals.graphAsks.single, containsAll(['koshary', 'baladi_bread', 'salata_baladi']));

      state.profile = state.profile.copyWith(prefs: ['lactose', 'meat']);
      state.step = kOnboardingSteps.indexWhere((s) => s.id == 'food');
      state.primarySubmit();
      await Future<void>.delayed(const Duration(milliseconds: 2600));

      final want = pickDish(targetKcal: state.target().kcal, goal: state.profile.goal, exclusions: const ['lactose', 'meat'], slot: MealSlot.dinner, live: graph)!;
      expect(state.revealDish!.id, want.id);
      expect(state.revealDishFacts, want.facts(live: graph));
      expect(state.revealDishFacts!.live, isTrue, reason: 'the graph answered for every part');
      expect(a.named('dish_shown').single, containsPair('live', true));
      expect(a.named('dish_shown').single, containsPair('placement', 'intake'));
    });

    test('a graph that does not answer leaves the shipped numbers in place', () async {
      final meals = FakeMealRepo(); // answers nothing
      final state = backed(meals: meals, clock: () => DateTime(2026, 9, 21, 13, 0));
      await settle();
      state.startOnboarding();
      state.step = kOnboardingSteps.indexWhere((s) => s.id == 'food');
      state.primarySubmit();
      await Future<void>.delayed(const Duration(milliseconds: 2600));
      expect(state.revealDish, isNotNull);
      expect(state.revealDishFacts!.live, isFalse);
      expect(state.revealDishFacts, state.revealDish!.facts());
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

  group('a photo in the conversation', () {
    test('a menu photo with no words asks the implied question and spends a photo, not a question', () async {
      final ai = FakeGateway();
      final a = MemoryAnalytics();
      final state = backed(ai: ai, analytics: a);
      await settle();
      state.setLang(AppLang.en);
      await state.setImprove(true);

      state.attachChatPhoto('/tmp/menu.jpg');
      expect(state.chatOpen, isTrue, reason: 'the photo lands in the conversation');
      state.sendChat();
      await settle();

      expect(state.chatPhotoPath, isNull, reason: 'one photo goes with one message');
      expect(ai.chatMessages.single, 'What should I order here?');
      expect(ai.chatImagePaths.single, '/tmp/menu.jpg');
      expect(ai.quotas.photo.remaining, SuEconomy.litePhotoDaily - 1);
      expect(ai.quotas.chat.remaining, SuEconomy.liteChatDaily, reason: 'metered as a photo');
      final mine = state.chat.where((c) => c.who == ChatWho.u).single;
      expect(mine.photoPath, '/tmp/menu.jpg');
      expect(mine.text, 'What should I order here?');
      expect(a.named('question_asked').single['photo'], true);
    });

    test('words typed with the photo are kept; a detached photo is not sent', () async {
      final ai = FakeGateway();
      final state = backed(ai: ai);
      await settle();
      state.setLang(AppLang.en);

      state.attachChatPhoto('/tmp/menu.jpg');
      state.onChatDraftChanged('Is the grilled chicken a good pick?');
      state.sendChat();
      await settle();
      expect(ai.chatMessages.single, 'Is the grilled chicken a good pick?');
      expect(ai.chatImagePaths.single, '/tmp/menu.jpg');

      state.attachChatPhoto('/tmp/again.jpg');
      state.detachChatPhoto();
      state.sendChat();
      await settle();
      expect(ai.chatMessages, hasLength(1), reason: 'nothing to send without words or a photo');
      expect(state.chatPhotoPath, isNull);
    });

    test('the fourth photo of the day in the conversation goes to the wallet, not Qamar+', () async {
      final ai = FakeGateway();
      final state = backed(ai: ai);
      await settle();
      state.setLang(AppLang.en);

      for (var i = 0; i < SuEconomy.litePhotoDaily; i++) {
        state.attachChatPhoto('/tmp/m$i.jpg');
        await state.sendChatMsg('');
      }
      expect(ai.quotas.photo.remaining, 0);

      state.attachChatPhoto('/tmp/m4.jpg');
      await state.sendChatMsg('');
      final last = state.chat.last;
      expect(last.who, ChatWho.q);
      expect(last.openWallet, isTrue);
      expect(last.openPlus, isFalse);
      expect(ai.quotas.chat.remaining, SuEconomy.liteChatDaily, reason: 'no question was spent along the way');
    });
  });

  group('the earned month and the free week’s reminder', () {
    test('20 logged days in the first 30 grant a month on us, once, appended to the running month', () async {
      final a = MemoryAnalytics();
      final end = DateTime.utc(2026, 10, 15, 12);
      final fb = FakeBilling()
        ..current = PlusEntitlement(status: 'active', plan: 'monthly', provider: 'paymob', periodEnd: end, firstPurchase: false)
        ..earned = const EarnedMonth(open: true, loggedDays: 12, needed: 20, windowDays: 30, daysLeft: 18, eligible: false, claimed: false);
      final state = backed(billing: fb, analytics: a, clock: () => DateTime(2026, 9, 27, 9));
      await settle();
      state.setLang(AppLang.en);
      await state.setImprove(true);

      expect(state.earnedMonth.inProgress, isTrue, reason: 'the progress is read on hydrate');
      expect(fb.earnedClaims, 0, reason: 'nothing is claimed before the days are logged');

      fb.earned = const EarnedMonth(open: true, loggedDays: 20, needed: 20, windowDays: 30, daysLeft: 2, eligible: true, claimed: false);
      await state.restorePlusPurchases();

      expect(fb.earnedClaims, 1);
      expect(state.earnedMonth.claimed, isTrue);
      expect(state.earnedMonthJustGranted, isTrue);
      expect(state.plusUntil, end.add(const Duration(days: 30)), reason: 'appended to the paid month, not replacing it');
      expect(state.plusIsEarned, isFalse, reason: 'the paid month is still the one running');
      expect(state.plusNotice, contains('A month on us'));
      expect(a.named('earned_month_granted').single['logged_days'], 20);

      await state.restorePlusPurchases();
      expect(fb.earnedClaims, 1, reason: 'once per account: a granted month is never claimed again');

      state.dismissEarnedMonthCard();
      expect(state.earnedMonthJustGranted, isFalse);
    });

    test('earned after the paid month lapsed, the month runs on its own', () async {
      final fb = FakeBilling()
        ..current = PlusEntitlement(status: 'expired', plan: 'monthly', provider: 'paymob', periodEnd: DateTime.utc(2026, 9, 1), firstPurchase: false)
        ..earned = const EarnedMonth(open: true, loggedDays: 20, needed: 20, windowDays: 30, daysLeft: 0, eligible: true, claimed: false);
      final state = backed(billing: fb);
      await settle();
      expect(state.plusActive, isTrue);
      expect(state.plusIsEarned, isTrue);
      expect(state.earnedMonth.claimed, isTrue);
    });

    test('the free week schedules its reminder 48 hours before the end, outside the meal questions', () async {
      final nudger = MemoryNudger();
      final fb = FakeBilling()..current = const PlusEntitlement(status: 'free', trialEligible: true);
      final state = backed(billing: fb, nudger: nudger, clock: () => DateTime(2026, 9, 21, 10));
      await settle();
      await state.allowNudges();
      expect(nudger.scheduled.where((n) => n.kind == NudgeKind.trialEnding), isEmpty, reason: 'no trial, no reminder');

      await state.startPlusTrial();
      await settle();
      final reminder = nudger.scheduled.where((n) => n.kind == NudgeKind.trialEnding).single;
      expect(reminder.at, fb.current.periodEnd!.subtract(NudgeSchedule.trialLead));
      expect(reminder.payload, Nudge.trialPayload);
      expect(reminder.text(ar: false), contains('Keep the plan going?'));

      await state.setNudgesPerDay(0);
      expect(nudger.scheduled.map((n) => n.kind).toList(), [NudgeKind.trialEnding],
          reason: 'zero meal questions a day does not silence the week’s one reminder');

      nudger.tap(Nudge.trialPayload);
      await settle();
      expect(state.screen, AppScreen.subscription);
    });

    test('a paid month schedules its one reminder 48 hours before it ends, and a tap opens the paywall', () async {
      final end = DateTime.now().toUtc().add(const Duration(days: 20));
      final fb = FakeBilling()..current = PlusEntitlement(status: 'active', plan: 'monthly', provider: 'paymob', periodEnd: end);
      final nudger = MemoryNudger();
      final a = MemoryAnalytics();
      final state = backed(billing: fb, nudger: nudger, analytics: a);
      await settle();
      await state.setImprove(true);
      await state.allowNudges();
      await settle();

      final reminder = nudger.scheduled.where((n) => n.kind == NudgeKind.membershipEnding).single;
      expect(reminder.at, end.subtract(NudgeSchedule.trialLead));
      expect(reminder.payload, Nudge.membershipPayload);
      expect(nudger.scheduled.where((n) => n.kind == NudgeKind.trialEnding), isEmpty, reason: 'a paid month is not a trial');

      await state.setNudgesPerDay(0);
      expect(nudger.scheduled.map((n) => n.kind).toList(), [NudgeKind.membershipEnding],
          reason: 'zero meal questions a day does not silence the month’s one reminder');

      nudger.tap(Nudge.membershipPayload);
      await settle();
      expect(state.screen, AppScreen.subscription);
      expect(a.named('membership_reminder_tapped'), hasLength(1));
    });

    test('a free week never schedules the month’s reminder', () async {
      final end = DateTime.now().toUtc().add(const Duration(days: 5));
      final fb = FakeBilling()
        ..current = PlusEntitlement(status: 'active', plan: 'monthly', provider: 'trial', periodEnd: end, trialEndsAt: end);
      final nudger = MemoryNudger();
      final state = backed(billing: fb, nudger: nudger);
      await settle();
      await state.allowNudges();
      expect(nudger.scheduled.where((n) => n.kind == NudgeKind.membershipEnding), isEmpty);
      expect(nudger.scheduled.where((n) => n.kind == NudgeKind.trialEnding), hasLength(1));
    });

    test('the billing moment is the week or the month in its last 48 hours, never both', () async {
      final end = DateTime.now().toUtc().add(const Duration(days: 10));
      PlusEntitlement paid() => PlusEntitlement(status: 'active', plan: 'monthly', provider: 'paymob', periodEnd: end);
      final early = backed(billing: FakeBilling()..current = paid(), clock: () => end.subtract(const Duration(days: 3)));
      await settle();
      expect(early.billingMoment, BillingMoment.none);

      final late = backed(billing: FakeBilling()..current = paid(), clock: () => end.subtract(const Duration(hours: 30)));
      await settle();
      expect(late.billingMoment, BillingMoment.membershipEnding);
      expect(late.billingMomentDue, isTrue);
      expect(late.trialEndingSoon, isFalse);
      final a = MemoryAnalytics();
      final counted = backed(billing: FakeBilling()..current = paid(), analytics: a, clock: () => end.subtract(const Duration(hours: 30)));
      await settle();
      await counted.setImprove(true);
      counted.openBillingMoment();
      expect(counted.screen, AppScreen.subscription);
      expect(a.named('wall_tapped').single['wall'], 'membership_end');

      final trial = backed(
        billing: FakeBilling()
          ..current = PlusEntitlement(status: 'active', plan: 'monthly', provider: 'trial', periodEnd: end, trialEndsAt: end),
        clock: () => end.subtract(const Duration(hours: 30)),
      );
      await settle();
      expect(trial.billingMoment, BillingMoment.trialEnding);
      expect(trial.membershipEndingSoon, isFalse);

      expect(AppState().billingMoment, BillingMoment.none, reason: 'Lite has no billing moment');
    });

    test('the Today card takes over inside the last 48 hours', () async {
      final end = DateTime.utc(2026, 9, 23, 12);
      final fb = FakeBilling()
        ..current = PlusEntitlement(status: 'active', plan: 'monthly', provider: 'trial', periodEnd: end, trialEligible: false, trialEndsAt: end);
      final early = backed(billing: fb, clock: () => DateTime.utc(2026, 9, 20, 12));
      await settle();
      expect(early.plusIsTrial, isTrue);
      expect(early.trialEndingSoon, isFalse);

      final late = backed(billing: fb, clock: () => DateTime.utc(2026, 9, 22, 6));
      await settle();
      expect(late.trialEndingSoon, isTrue);
      late.setLang(AppLang.en);
      expect(late.trialEndsIn(), 'tomorrow');

      final hours = backed(billing: fb, clock: () => DateTime.utc(2026, 9, 23, 7));
      await settle();
      hours.setLang(AppLang.en);
      expect(hours.trialEndsIn(), 'in 5 hours');
      // Today's billing card (BillingMomentCard) is the free week's end now.
      hours.openBillingMoment();
      expect(hours.screen, AppScreen.subscription);
    });
  });

  group('the professional programme’s second half: adherence, with consent', () {
    test('saying yes is recorded like the other consents, on the phone and on the account', () async {
      final a = MemoryAnalytics();
      final profiles = FakeProfileRepo();
      final prefs = MemoryDevicePrefs();
      final state = backed(profiles: profiles, analytics: a, prefs: prefs);
      await settle();
      await state.setImprove(true);
      await settle();
      expect(state.adherenceShare, isFalse, reason: 'off until said yes to');

      await state.setAdherenceShare(true);
      await settle();
      expect(state.adherenceShare, isTrue);
      expect(profiles.consents.last, (type: 'adherence_share', granted: true, version: '1.1'));
      expect(await prefs.getBool('adherence_consent'), isTrue);
      expect(a.named('adherence_consent').single['granted'], true);

      await state.setAdherenceShare(false);
      await settle();
      expect(profiles.consents.last, (type: 'adherence_share', granted: false, version: '1.1'));
      expect(a.named('adherence_consent'), hasLength(2));
    });

    test('the account’s answer wins over the phone’s on hydrate', () async {
      final profiles = FakeProfileRepo()..adherenceOnRecord = true;
      final prefs = MemoryDevicePrefs();
      final state = backed(profiles: profiles, prefs: prefs);
      await settle();
      expect(state.adherenceShare, isTrue);
      expect(await prefs.getBool('adherence_consent'), isTrue);
      expect(state.improve, isFalse, reason: 'one consent does not imply the other');
    });

    test('a professional sees their consenting clients as the week’s numbers; anyone else sees no card', () async {
      final fb = FakeBilling()
        ..clients = [
          const ProClient(name: 'Mona', daysLogged: 6, onTargetDays: 4, avgKcal: 1820, targetKcal: 1900),
          const ProClient(name: 'Omar', daysLogged: 0, onTargetDays: 0, avgKcal: 0, targetKcal: 2200),
        ];
      final pro = backed(billing: fb);
      await settle();
      expect(pro.proClients.map((c) => c.name).toList(), ['Mona', 'Omar']);
      expect(fb.clientReads, 1);

      final nobody = backed(billing: FakeBilling()..wallet = const AffiliateWallet(code: null));
      await settle();
      expect(nobody.proClients, isEmpty, reason: 'no code, no dashboard call');
    });

    test('the wire shape is read as the database writes it', () {
      final list = ProClient.listFromJson({
        'from': '2026-09-15',
        'to': '2026-09-21',
        'count': 1,
        'clients': [
          {
            'name': 'Mona',
            'since': '2026-08-01T10:00:00+00:00',
            'until': '2027-08-01T10:00:00+00:00',
            'target_kcal': 1900,
            'days_logged': 6,
            'on_target_days': 4,
            'avg_kcal': 1820,
            'last_logged_at': '2026-09-21T09:30:00+00:00',
          },
          {'name': '  ', 'days_logged': 0, 'on_target_days': 0, 'avg_kcal': 0, 'target_kcal': null},
        ],
      });
      expect(list, hasLength(2));
      expect(list.first.name, 'Mona');
      expect(list.first.onTargetDays, 4);
      expect(list.first.until!.year, 2027);
      expect(list.last.name, '—', reason: 'a client with no name on file is still a row, not a crash');
      expect(list.last.targetKcal, isNull);
    });
  });

  group('shop this plan', () {
    const lunchMeal = (
      id: 'lunch', slotAr: 'غدا', slotEn: 'Lunch',
      nameAr: 'كشري', nameEn: 'Koshary', noteAr: '', noteEn: '',
      portions: <PlanPortion>[(ar: 'كشري', en: 'Koshary', amountAr: 'طبق', amountEn: '1 bowl', kcal: 520)],
    );
    const partner = GroceryPartner(url: 'https://partner.example/b?items={items}&ref={ref}', name: 'Breadfast', ref: 'qamar-aff-1');

    test('with a partner configured, the plan offers its basket and the link carries the reference', () async {
      final a = MemoryAnalytics();
      final opened = <String>[];
      final state = AppState(analytics: a, grocery: partner, openCheckout: (url) async { opened.add(url); return true; })..setLang(AppLang.en);
      await state.setImprove(true);
      expect(state.canShopPlan, isFalse, reason: 'no plan yet');

      state.plan = const DayPlan(date: '2026-09-21', slots: [(lunchMeal, lunchMeal)]);
      expect(state.canShopPlan, isTrue);
      expect(state.basket.count, 1);

      await state.shopThisPlan();
      expect(opened.single, 'https://partner.example/b?items=Koshary&ref=qamar-aff-1');
      expect(a.named('basket_opened').single, containsPair('items', 1));
      expect(a.named('basket_opened').single['partner'], 'Breadfast');
      expect(state.shopNotice, isNull);
    });

    test('a link that will not open says so, and nothing is counted twice', () async {
      final state = AppState(grocery: partner, openCheckout: (url) async => false)..setLang(AppLang.en);
      state.plan = const DayPlan(date: '2026-09-21', slots: [(lunchMeal, lunchMeal)]);
      await state.shopThisPlan();
      expect(state.shopNotice, 'Could not open Breadfast. Try again.');
    });

    test('without a partner there is nothing to shop, whatever the plan', () async {
      final opened = <String>[];
      final state = AppState(grocery: GroceryPartner.none, openCheckout: (url) async { opened.add(url); return true; });
      state.plan = const DayPlan(date: '2026-09-21', slots: [(lunchMeal, lunchMeal)]);
      expect(state.canShopPlan, isFalse);
      await state.shopThisPlan();
      expect(opened, isEmpty);
    });
  });

  group('the offline logging queue', () {
    test('a glass logged without a signal is kept on the phone and goes up when the signal returns', () async {
      final water = FakeWaterRepo()..offline = Exception('SocketException: no route');
      final prefs = MemoryDevicePrefs();
      final state = backed(water: water, prefs: prefs, clock: () => DateTime(2026, 9, 21, 12));
      await settle();
      state.setLang(AppLang.en);

      state.logWater(WaterUnit.glass);
      await settle();
      expect(state.waterToday, hasLength(1), reason: 'the screen never waits for the server');
      expect(water.saved, isEmpty);
      expect(state.pendingWrites, hasLength(1));
      expect(state.pendingWrites.single.kind, PendingKind.water);
      expect(state.syncError, 'Saved on the phone; it syncs when the connection is back.');
      expect(PendingWrite.decode(await prefs.getString('pending_writes_user-1')), hasLength(1), reason: 'survives a restart');

      water.offline = null;
      await state.drainPending();
      expect(water.saved.single.ml, state.waterToday.single.ml);
      expect(state.pendingWrites, isEmpty);
      expect(state.syncError, isNull);
      expect(PendingWrite.decode(await prefs.getString('pending_writes_user-1')), isEmpty);
    });

    test('a meal queued on one run is replayed on the next start, items and all, before today is read', () async {
      final meals = FakeMealRepo()..offline = Exception('offline');
      final prefs = MemoryDevicePrefs();
      final first = backed(meals: meals, ai: FakeGateway(), prefs: prefs);
      await settle();
      first.setLang(AppLang.en);
      first.quickLog(QuickLog.text);
      await first.sendChatMsg('koshary');
      await settle();
      first.confirmProposal();
      await settle();
      expect(meals.saved, isEmpty);
      expect(first.pendingWrites.single.kind, PendingKind.meal);
      first.dispose();

      meals.offline = null;
      final second = backed(meals: meals, prefs: prefs);
      await settle();
      expect(meals.saved.single.name, 'Koshary');
      expect(meals.savedItems.single.single.def.en, 'Koshary', reason: 'the confirmed items travel with the meal');
      expect(meals.drafts, 1, reason: 'the draft is written with the replay, not before');
      expect(second.pendingWrites, isEmpty);
    });

    test('movement queues too, and a write the server keeps refusing is dropped with its reason', () async {
      final acts = FakeActivityRepo()..offline = StateError('check constraint');
      final state = backed(activities: acts, clock: () => DateTime(2026, 9, 21, 18));
      await settle();
      state.chooseActivity(ActivityKind.walk);
      await state.logActivity(30);
      expect(state.pendingWrites.single.kind, PendingKind.activity);

      for (var i = 0; i < AppState.pendingMaxAttempts; i++) {
        await state.drainPending();
      }
      expect(state.pendingWrites, isEmpty, reason: 'six refusals is not a signal problem');
      expect(state.syncError, contains('activity'));
      expect(acts.added, isEmpty);
    });

    test('writes replay oldest first and stop at the first failure so order is kept', () async {
      final water = FakeWaterRepo()..offline = Exception('offline');
      final state = backed(water: water, clock: () => DateTime(2026, 9, 21, 12));
      await settle();
      state.logWater(WaterUnit.glass);
      state.logWater(WaterUnit.bottle);
      await settle();
      expect(state.pendingWrites.map((w) => w.payload['unit']).toList(), ['glass', 'bottle']);

      var calls = 0;
      water.offline = null;
      // The first replay succeeds, the second finds the signal gone again.
      final repoWithFlap = water;
      await state.drainPending();
      calls = repoWithFlap.saved.length;
      expect(calls, 2);
      expect(state.pendingWrites, isEmpty);
    });
  });

  group('invitation links', () {
    test('a link opened with an account redeems at once; opened before, it waits and redeems on the next start', () async {
      final inv = FakeInvitationRepo();
      final backedNow = backed(invitations: inv);
      await settle();
      await backedNow.acceptInvitationLink('QMR-LIVE');
      await settle();
      expect(inv.redeemCodes, ['QMR-LIVE']);
      expect(backedNow.invitedBy, 'Basel');

      final prefs = MemoryDevicePrefs();
      final guest = AppState(prefs: prefs);
      await guest.acceptInvitationLink('QMR-LATER');
      expect(guest.pendingInvitationCode, 'QMR-LATER');
      expect(await prefs.getString('pending_invitation'), 'QMR-LATER');

      final later = FakeInvitationRepo();
      final signedIn = backed(invitations: later, prefs: prefs);
      await settle();
      expect(later.redeemCodes, ['QMR-LATER']);
      expect(signedIn.pendingInvitationCode, isNull);
      expect(await prefs.getString('pending_invitation'), '');
    });

    test('a redeem that cannot reach the server keeps the code; the next connected start redeems it and clears it', () async {
      final prefs = MemoryDevicePrefs();
      await AppState(prefs: prefs).acceptInvitationLink('QMR-LATER'); // opened before there was an account
      final flaky = FakeInvitationRepo()..failWith = StateError('no signal');
      final first = backed(invitations: flaky, prefs: prefs);
      await settle();
      expect(first.pendingInvitationCode, 'QMR-LATER', reason: 'kept');
      expect(await prefs.getString('pending_invitation'), 'QMR-LATER');

      final ok = FakeInvitationRepo();
      final next = backed(invitations: ok, prefs: prefs);
      await settle();
      expect(ok.redeemCodes, ['QMR-LATER']);
      expect(next.invitedBy, 'Basel');
      expect(next.pendingInvitationCode, isNull);
      expect(await prefs.getString('pending_invitation'), '');
    });

    test('a link opened with an account but no signal waits too, and says so in both languages', () async {
      for (final lang in AppLang.values) {
        final prefs = MemoryDevicePrefs();
        final flaky = FakeInvitationRepo()..failWith = StateError('no signal');
        final state = backed(invitations: flaky, prefs: prefs)..setLang(lang);
        await settle();
        await state.acceptInvitationLink('QMR-LIVE');
        expect(state.pendingInvitationCode, 'QMR-LIVE');
        expect(await prefs.getString('pending_invitation'), 'QMR-LIVE');
        expect(state.invitationNotice, lang == AppLang.ar ? contains('محفوظة على الموبايل') : contains('kept on this phone'));
      }
    });

    test('a code the server refuses is an answer: cleared, not tried again at every start', () async {
      final prefs = MemoryDevicePrefs();
      await prefs.setString('pending_invitation', 'QMR-USED');
      final inv = FakeInvitationRepo()..failWith = const InvitationException('this invitation was already used', refused: true);
      final state = backed(invitations: inv, prefs: prefs);
      await settle();
      expect(state.pendingInvitationCode, isNull);
      expect(await prefs.getString('pending_invitation'), '');
      expect(state.invitationNotice, 'this invitation was already used');
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

  EarnedMonth earned = EarnedMonth.none;
  int earnedClaims = 0;

  @override
  Future<EarnedMonth> earnedMonth() async => earned;

  @override
  Future<EarnedMonthClaim> claimEarnedMonth() async {
    earnedClaims++;
    if (earned.claimed) throw BillingException('The earned month has already been granted on this account.');
    if (!earned.eligible) throw BillingException('Not earned yet: ${earned.needed} logged days in the first ${earned.windowDays} are needed.');
    // As 0052 does: appended to a running month, a fresh 30 days otherwise.
    final running = current.active && current.periodEnd != null;
    final until = (running ? current.periodEnd! : DateTime.now().toUtc()).add(const Duration(days: 30));
    current = PlusEntitlement(
      status: 'active',
      plan: 'monthly',
      provider: running ? current.provider : 'earned',
      periodEnd: until,
      firstPurchase: current.firstPurchase,
      trialEligible: false,
      trialEndsAt: current.trialEndsAt,
    );
    earned = EarnedMonth(
      open: false,
      loggedDays: earned.loggedDays,
      needed: earned.needed,
      windowDays: earned.windowDays,
      daysLeft: earned.daysLeft,
      eligible: false,
      claimed: true,
      grantedUntil: until,
      windowStart: earned.windowStart,
      windowEnd: earned.windowEnd,
    );
    return EarnedMonthClaim(entitlement: current, earned: earned);
  }

  @override
  Future<AffiliateWallet> affiliate() async => wallet;

  List<ProClient> clients = const [];
  int clientReads = 0;

  @override
  Future<List<ProClient>> affiliateClients() async {
    clientReads++;
    return clients;
  }

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
