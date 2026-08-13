import '../models/meal.dart';
import '../models/profile.dart';

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
  Future<void> confirmMeal(String userId, {required String draftId, required LoggedMeal meal});
  Future<List<LoggedMeal>> mealsForDay(String userId, DateTime day);
}

abstract class WalletRepository {
  Future<({int available, int lifetime})> balance(String userId);
  Future<void> credit(String userId, {required int amount, required String reason, required String idempotencyKey});
  Future<void> redeem(String userId, {required SpendItemDef item, required String idempotencyKey});
  Future<List<LedgerEntry>> ledger(String userId);
}

/// Payload shape for [MealRepository.saveDraft] — matches meal_drafts.
class MealAnalysisDraft {
  final String inputType;
  final List<({ConfirmItemDef def, int qty})> items;
  final String? rawText;
  final String? mediaPath;
  const MealAnalysisDraft({required this.inputType, required this.items, this.rawText, this.mediaPath});
}
