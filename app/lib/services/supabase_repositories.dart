import 'package:supabase_flutter/supabase_flutter.dart';

import '../models/meal.dart';
import '../models/profile.dart';
import 'repositories.dart';

/// Supabase-backed repositories matching supabase/migrations/0001_core_schema.sql.
///
/// Reference implementation, not yet wired into the app (see app/README.md).
/// supabase_flutter's query builder API has shifted across major versions —
/// re-check each call against the version actually pinned in pubspec.yaml
/// before flipping QamarConfig.useSupabase on.
class SupabaseProfileRepository implements ProfileRepository {
  final SupabaseClient _client;
  const SupabaseProfileRepository(this._client);

  @override
  Future<Profile?> loadProfile(String userId) async {
    final row = await _client.from('profiles').select().eq('user_id', userId).maybeSingle();
    if (row == null) return null;
    final birth = DateTime.tryParse(row['birth_date'] as String? ?? '');
    return Profile(
      name: row['name'] as String? ?? '',
      birthYear: birth?.year ?? 1997,
      birthMonth: birth?.month ?? 6,
      birthDay: birth?.day ?? 15,
      gender: (row['gender'] as String?) == 'female' ? Gender.female : Gender.male,
      height: row['height_cm'] as int? ?? 172,
      weight: row['weight_kg'] as int? ?? 82,
      fat: row['body_fat_pct'] as int? ?? 27,
      goal: _goalFromDb(row['goal'] as String?),
      activity: (row['activity_factor'] as num?)?.toDouble() ?? 1.5,
      prefs: (row['food_exclusions'] as List?)?.cast<String>() ?? const [],
    );
  }

  @override
  Future<void> saveProfile(String userId, Profile profile) async {
    await _client.from('profiles').upsert({
      'user_id': userId,
      'name': profile.name,
      'birth_date': '${profile.birthYear.toString().padLeft(4, '0')}-'
          '${profile.birthMonth.toString().padLeft(2, '0')}-'
          '${profile.birthDay.toString().padLeft(2, '0')}',
      'gender': profile.gender.name,
      'height_cm': profile.height,
      'weight_kg': profile.weight,
      'body_fat_pct': profile.fat,
      'goal': profile.goal.name,
      'activity_factor': profile.activity,
      'food_exclusions': profile.prefs,
    });
  }

  @override
  Future<Target> saveTarget(String userId, Target target, {required Profile inputs}) async {
    await _client.from('targets').insert({
      'user_id': userId,
      'kcal': target.kcal,
      'protein_g': target.protein,
      'carbs_g': target.carbs,
      'fat_g': target.fat,
      'inputs': {
        'age': inputs.age,
        'height_cm': inputs.height,
        'weight_kg': inputs.weight,
        'activity_factor': inputs.activity,
        'goal': inputs.goal.name,
      },
    });
    return target;
  }

  Goal _goalFromDb(String? v) => switch (v) {
        'lose' => Goal.lose,
        'gain' => Goal.gain,
        _ => Goal.maintain,
      };
}

class SupabaseMealRepository implements MealRepository {
  final SupabaseClient _client;
  const SupabaseMealRepository(this._client);

  @override
  Future<String> saveDraft(String userId, MealAnalysisDraft draft) async {
    final row = await _client
        .from('meal_drafts')
        .insert({
          'user_id': userId,
          'input_type': draft.inputType,
          'candidate_items': draft.items
              .map((it) => {
                    'name_ar': it.def.ar,
                    'name_en': it.def.en,
                    'portion_ar': it.def.portionAr,
                    'portion_en': it.def.portionEn,
                    'confidence': it.def.conf.name,
                    'kcal': it.def.kcal,
                    'protein_g': it.def.p,
                    'carbs_g': it.def.c,
                    'fat_g': it.def.f,
                    'qty': it.qty,
                  })
              .toList(),
          'raw_text': draft.rawText,
          'media_path': draft.mediaPath,
        })
        .select('id')
        .single();
    return row['id'] as String;
  }

  @override
  Future<void> confirmMeal(String userId, {required String draftId, required LoggedMeal meal}) async {
    await _client.from('meal_logs').insert({
      'user_id': userId,
      'draft_id': draftId,
      'name': meal.name,
      'source': meal.sub,
      'items': const [],
      'kcal': meal.kcal,
      'protein_g': meal.p,
      'carbs_g': meal.c,
      'fat_g': meal.f,
    });
  }

  @override
  Future<List<LoggedMeal>> mealsForDay(String userId, DateTime day) async {
    final start = DateTime(day.year, day.month, day.day).toIso8601String();
    final end = DateTime(day.year, day.month, day.day + 1).toIso8601String();
    final rows = await _client.from('meal_logs').select().eq('user_id', userId).gte('logged_at', start).lt('logged_at', end).order('logged_at');
    return (rows as List)
        .map((r) => LoggedMeal(name: r['name'] as String, sub: r['source'] as String, kcal: r['kcal'] as int, p: r['protein_g'] as int, c: r['carbs_g'] as int, f: r['fat_g'] as int))
        .toList();
  }
}

class SupabaseWalletRepository implements WalletRepository {
  final SupabaseClient _client;
  const SupabaseWalletRepository(this._client);

  @override
  Future<({int available, int lifetime})> balance(String userId) async {
    final row = await _client.from('wallet_accounts').select().eq('user_id', userId).maybeSingle();
    if (row == null) return (available: 0, lifetime: 0);
    return (available: row['available_points'] as int, lifetime: row['lifetime_earned'] as int);
  }

  /// Credits/debits go through su_point_ledger (source of truth) — call a
  /// Postgres function or Edge Function to keep the ledger insert and the
  /// wallet_accounts balance update atomic. This client-side version is a
  /// reference sketch only; do the real balance math server-side.
  @override
  Future<void> credit(String userId, {required int amount, required String reason, required String idempotencyKey}) async {
    await _client.rpc('qamar_wallet_credit', params: {
      'p_user_id': userId,
      'p_delta': amount,
      'p_reason': reason,
      'p_idempotency_key': idempotencyKey,
    });
  }

  @override
  Future<void> redeem(String userId, {required SpendItemDef item, required String idempotencyKey}) async {
    await _client.rpc('qamar_wallet_redeem', params: {
      'p_user_id': userId,
      'p_catalog_item_id': item.id,
      'p_idempotency_key': idempotencyKey,
    });
  }

  @override
  Future<List<LedgerEntry>> ledger(String userId) async {
    final rows = await _client.from('su_point_ledger').select().eq('user_id', userId).order('created_at', ascending: false).limit(50);
    return (rows as List)
        .map((r) => LedgerEntry(label: r['reason'] as String, amount: r['delta'] as int, when: (r['created_at'] as String)))
        .toList();
  }
}
