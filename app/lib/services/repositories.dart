import '../models/meal.dart';
import '../models/profile.dart';
import '../models/water.dart';

/// Repository interfaces mirroring the Supabase schema in
/// supabase/migrations/0001_core_schema.sql. These are the seam a real
/// backend plugs into; nothing in lib/screens/ or lib/state/app_state.dart
/// depends on them yet (see app/README.md for the wiring plan).
abstract class ProfileRepository {
  Future<Profile?> loadProfile(String userId);
  Future<void> saveProfile(String userId, Profile profile);
  Future<Target> saveTarget(String userId, Target target, {required Profile inputs});
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
}

abstract class WaterRepository {
  Future<String> addSip(String userId, WaterSip sip);
  Future<void> removeSip(String userId, String id);
  Future<List<WaterSip>> sipsForDay(String userId, DateTime day);
}

abstract class WalletRepository {
  Future<({int available, int lifetime})> balance(String userId);
  Future<void> credit(String userId, {required int amount, required String reason, required String idempotencyKey});
  Future<void> redeem(String userId, {required SpendItemDef item, required String idempotencyKey});
  Future<List<LedgerEntry>> ledger(String userId);

  /// Claims today's quest, and reports what the server decided.
  ///
  /// The client does not get to say whether the quest was completed. The
  /// database checks that a meal was logged today in Cairo, credits 250 once
  /// per Cairo day under a key it owns, and returns the balance it arrived at.
  /// [reason] is `ok`, `already_claimed`, or `no_meal_today` — the last is a
  /// normal morning, not an error, so it comes back as a value rather than an
  /// exception.
  Future<QuestResult> completeDailyQuest(String userId);
}

/// What the server did with a quest claim.
class QuestResult {
  final bool credited;
  final String reason;
  final int amount;
  final int available;
  const QuestResult({
    required this.credited,
    required this.reason,
    required this.amount,
    required this.available,
  });

  factory QuestResult.fromJson(Map<String, dynamic> json) => QuestResult(
        credited: json['credited'] == true,
        reason: (json['reason'] as String?) ?? 'ok',
        amount: json['amount'] is num ? (json['amount'] as num).round() : 0,
        available: json['available'] is num ? (json['available'] as num).round() : 0,
      );
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

/// Payload shape for [MealRepository.saveDraft] — matches meal_drafts.
class MealAnalysisDraft {
  final String inputType;
  final List<({ConfirmItemDef def, int qty})> items;
  final String? rawText;
  final String? mediaPath;
  const MealAnalysisDraft({required this.inputType, required this.items, this.rawText, this.mediaPath});
}
