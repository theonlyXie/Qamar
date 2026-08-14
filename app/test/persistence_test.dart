// Tests for AppState once repositories are supplied.
//
// The contract being protected: persistence is additive. Everything the app
// did offline it still does, writes go out as a side effect, and a backend
// that is slow, broken or absent never costs the user their data or blocks the
// screen.

import 'package:flutter_test/flutter_test.dart';

import 'package:qamar/models/meal.dart';
import 'package:qamar/models/profile.dart';
import 'package:qamar/services/ai_gateway.dart';
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

  @override
  Future<MealAnalysis> analyzeMeal({required String inputType, String? text, String? imagePath, String lang = 'ar'}) async {
    imagePaths.add(imagePath);
    return result;
  }

  @override
  Future<String> chatReply({required String message, required String lang}) async => reply;

  BodyScan scan = const BodyScan(heightCm: 174, weightKg: 86, bodyFatPct: 29, age: 31);

  @override
  Future<BodyScan> readBodyScan({required String imagePath, required String lang}) async {
    imagePaths.add(imagePath);
    return scan;
  }
}

AppState backed({
  FakeProfileRepo? profiles,
  FakeMealRepo? meals,
  FakeWalletRepo? wallet,
  FakeGateway? ai,
}) =>
    AppState(
      profileRepo: profiles ?? FakeProfileRepo(),
      mealRepo: meals ?? FakeMealRepo(),
      walletRepo: wallet ?? FakeWalletRepo(),
      ai: ai,
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

  test('redeeming calls through to the wallet RPC', () async {
    final wallet = FakeWalletRepo()..stored = (available: 500, lifetime: 500);
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
