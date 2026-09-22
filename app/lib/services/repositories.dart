import '../models/activity.dart';
import '../models/invitation.dart';
import '../models/meal.dart';
import '../models/nudge.dart';
import '../models/profile.dart';
import '../models/ramadan.dart';
import '../models/streak.dart';
import '../models/water.dart';

/// Repository interfaces mirroring the Supabase schema in
/// supabase/migrations/0001_core_schema.sql. These are the seam a real
/// backend plugs into; nothing in lib/screens/ or lib/state/app_state.dart
/// depends on them yet (see app/README.md for the wiring plan).
abstract class ProfileRepository {
  Future<Profile?> loadProfile(String userId);
  Future<void> saveProfile(String userId, Profile profile);
  Future<Target> saveTarget(String userId, Target target, {required Profile inputs});

  /// The consent log is append-only: one row per change, the latest row is
  /// the answer. [type] is one of [ConsentType].
  Future<void> saveConsent(String userId, String type, {required bool granted, required String version});

  /// The latest answer on record for [type]; null when never asked.
  Future<bool?> loadConsent(String userId, String type);

  /// The season in view (a week before Ramadan to a week after Eid), with the
  /// dates the operator confirmed after the sighting; null when none.
  Future<Season?> currentSeason();

  /// The fasting switch, on the profile so the night job writes the right
  /// kind of day.
  Future<void> saveFastingMode(String userId, FastingMode mode);

  /// Start was pressed — [via] is 'chat' or 'scan'. The denominator of
  /// intake completion; the first one on the account is the one kept.
  Future<void> recordIntakeStart(String userId, {required String via});

  /// When this account began (auth.users.created_at, through
  /// qamar_account_day0): day 0 for the kill metrics and for the phone's
  /// fourteen-day push window alike. Null when the server cannot say.
  Future<DateTime?> accountDay0(String userId);
}

/// The two consents the schema knows (consents.type).
abstract final class ConsentType {
  /// Processing the person's answers at all — required to use the app.
  static const processing = 'processing_required';

  /// Using anonymised usage to improve the service — optional, and the gate
  /// on analytics.
  static const improve = 'improve_optional';

  /// Share weekly adherence with the nutritionist whose code is on the
  /// subscription. Optional, off until said yes to, withdrawable.
  static const adherence = 'adherence_share';
}

abstract class MealRepository {
  Future<String> saveDraft(String userId, MealAnalysisDraft draft);
  /// Writes the log. [items] is the confirmed item list, and carries the food
  /// ids and gram weights that let anything past calories be computed later —
  /// pass it, or the log records four totals and nothing else.
  Future<void> confirmMeal(
    String userId, {
    required String draftId,
    required LoggedMeal meal,
    List<({ConfirmItemDef def, int qty})> items,
  });
  Future<List<LoggedMeal>> mealsForDay(String userId, DateTime day);

  /// One entry per day that has any logged meal, most recent last. Days with
  /// nothing logged are simply absent — the Progress screen shows them as the
  /// empty days they were rather than interpolating.
  Future<List<DayTotals>> dailyTotals(String userId, {int days = 7});

  /// Weight readings, oldest first. Empty until the user has weighed in.
  Future<List<WeightReading>> weightHistory(String userId, {int days = 60});

  Future<void> recordWeight(String userId, {required double kg, DateTime? at});

  /// The server's streak: computed from meal_logs, with freezes applied.
  /// Null when the backend has no answer (older schema, offline).
  Future<Streak?> streak(String userId);

  /// When this person eats, learned from their logs (qamar_meal_time_profile).
  /// Null when the backend has no answer.
  Future<MealTimes?> mealTimes(String userId);

  /// Last night's sentence about [day], written by the gateway's night job;
  /// null when none was written (a new account, an empty day, no job yet).
  Future<NightNote?> nightNote(String userId, DateTime day);

  /// The last [days] days of meals, newest first — what "repeat a meal"
  /// offers. Duplicates by name are the caller's to fold.
  Future<List<LoggedMeal>> recentMeals(String userId, {int days = 7});
}

/// Movement logged by hand (activity_logs, migration 0051).
abstract class ActivityRepository {
  /// Writes the row and returns its id.
  Future<String> add(String userId, ActivityLog entry);
  Future<List<ActivityLog>> forDay(String userId, DateTime day);
}

/// The referral loop's server side (migration 0049). Every call is the
/// signed-in person's own: their book, an invitation they issue, a code they
/// redeem. Refusals arrive as [InvitationException] with the server's reason.
abstract class InvitationRepository {
  Future<InvitationBook> mine(String userId);
  Future<Invitation> issue(String userId, {required String name});
  Future<InvitationRedemption> redeem(String userId, {required String code});
}

class InvitationException implements Exception {
  final String message;
  const InvitationException(this.message);
  @override
  String toString() => message;
}

abstract class WaterRepository {
  Future<String> addSip(String userId, WaterSip sip);
  Future<void> removeSip(String userId, String id);
  Future<List<WaterSip>> sipsForDay(String userId, DateTime day);
}

abstract class WalletRepository {
  Future<({int available, int lifetime})> balance(String userId);
  Future<void> credit(String userId, {required int amount, required String reason, required String idempotencyKey});

  /// Today's quest, done. The server pays it once per Cairo day whatever
  /// the phone says (qamar_complete_quest).
  Future<void> completeQuest(String userId);

  /// The onboarding bonus, once per account (qamar_grant_onboarding).
  Future<void> grantOnboarding(String userId);
  Future<void> redeem(String userId, {required SpendItemDef item, required String idempotencyKey});
  Future<List<LedgerEntry>> ledger(String userId);
}

/// A day's logged intake, as recorded — never estimated or back-filled.
class DayTotals {
  final DateTime day;
  final int kcal;
  final int meals;
  const DayTotals({required this.day, required this.kcal, required this.meals});
}

class WeightReading {
  final DateTime at;
  final double kg;
  const WeightReading({required this.at, required this.kg});
}

/// The one sentence written at night about the coming day: tomorrow against
/// today, no dish named. On Qamar+ the plan is behind it; on the free tier it
/// is what stands in for the plan, with the plan locked.
class NightNote {
  final DateTime day;
  final String ar;
  final String en;
  final int planKcal;
  final int todayKcal;
  const NightNote({required this.day, required this.ar, required this.en, required this.planKcal, required this.todayKcal});
}

/// Payload shape for [MealRepository.saveDraft] — matches meal_drafts.
class MealAnalysisDraft {
  final String inputType;
  final List<({ConfirmItemDef def, int qty})> items;
  final String? rawText;
  final String? mediaPath;
  const MealAnalysisDraft({required this.inputType, required this.items, this.rawText, this.mediaPath});
}
