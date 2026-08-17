import 'package:supabase_flutter/supabase_flutter.dart';

import '../models/meal.dart';
import '../models/profile.dart';
import '../models/water.dart';
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
      // weight_kg and body_fat_pct are numeric since 0007, so these arrive as
      // doubles and a cast straight to int? throws. Read as num and round:
      // Profile still models them as int, so the stored decimal is preserved in
      // the database and in weight_entries — which is what the weight trend
      // reads — but rounded for display here.
      height: (row['height_cm'] as num?)?.round() ?? 172,
      weight: (row['weight_kg'] as num?)?.round() ?? 82,
      fat: (row['body_fat_pct'] as num?)?.round() ?? 27,
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
        'birth_date': '${inputs.birthYear.toString().padLeft(4, '0')}-'
            '${inputs.birthMonth.toString().padLeft(2, '0')}-'
            '${inputs.birthDay.toString().padLeft(2, '0')}',
        'gender': inputs.gender.name,
        'age_at_calculation': inputs.age,
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

  @override
  Future<List<DayTotals>> dailyTotals(String userId, {int days = 7}) async {
    final now = DateTime.now();
    final from = DateTime(now.year, now.month, now.day).subtract(Duration(days: days - 1));
    final rows = await _client
        .from('meal_logs')
        .select('kcal, logged_at')
        .eq('user_id', userId)
        .gte('logged_at', from.toIso8601String())
        .order('logged_at');

    // Grouped here rather than in SQL so this needs no extra database object;
    // a week of one person's meals is a few dozen rows.
    final byDay = <String, ({DateTime day, int kcal, int meals})>{};
    for (final r in rows as List) {
      final at = DateTime.parse(r['logged_at'] as String).toLocal();
      final day = DateTime(at.year, at.month, at.day);
      final key = day.toIso8601String();
      final prev = byDay[key];
      byDay[key] = (
        day: day,
        kcal: (prev?.kcal ?? 0) + (r['kcal'] as num).round(),
        meals: (prev?.meals ?? 0) + 1,
      );
    }
    final out = byDay.values.map((e) => DayTotals(day: e.day, kcal: e.kcal, meals: e.meals)).toList()
      ..sort((a, b) => a.day.compareTo(b.day));
    return out;
  }

  @override
  Future<List<WeightReading>> weightHistory(String userId, {int days = 60}) async {
    final from = DateTime.now().subtract(Duration(days: days));
    final rows = await _client
        .from('weight_entries')
        .select('value_kg, measured_at')
        .eq('user_id', userId)
        .gte('measured_at', from.toIso8601String())
        .order('measured_at');
    return (rows as List)
        .map((r) => WeightReading(
              at: DateTime.parse(r['measured_at'] as String).toLocal(),
              kg: (r['value_kg'] as num).toDouble(),
            ))
        .toList();
  }

  @override
  Future<void> recordWeight(String userId, {required double kg, DateTime? at}) async {
    await _client.from('weight_entries').insert({
      'user_id': userId,
      'value_kg': kg,
      if (at != null) 'measured_at': at.toIso8601String(),
    });
  }
}

class SupabaseWaterRepository implements WaterRepository {
  final SupabaseClient _client;
  const SupabaseWaterRepository(this._client);

  @override
  Future<String> addSip(String userId, WaterSip sip) async {
    final row = await _client
        .from('water_logs')
        .insert({
          'user_id': userId,
          'amount_ml': sip.ml,
          'unit': sip.unit.name,
          'logged_at': sip.at.toUtc().toIso8601String(),
        })
        .select('id')
        .single();
    return row['id'] as String;
  }

  @override
  Future<void> removeSip(String userId, String id) async {
    await _client.from('water_logs').delete().eq('id', id).eq('user_id', userId);
  }

  @override
  Future<List<WaterSip>> sipsForDay(String userId, DateTime day) async {
    final start = DateTime(day.year, day.month, day.day).toIso8601String();
    final end = DateTime(day.year, day.month, day.day + 1).toIso8601String();
    final rows = await _client
        .from('water_logs')
        .select()
        .eq('user_id', userId)
        .gte('logged_at', start)
        .lt('logged_at', end)
        .order('logged_at');
    return (rows as List).map((r) {
      final unit = (r['unit'] as String?) == 'bottle' ? WaterUnit.bottle : WaterUnit.glass;
      return WaterSip(
        id: r['id'] as String?,
        unit: unit,
        ml: (r['amount_ml'] as num).round(),
        at: DateTime.parse(r['logged_at'] as String).toLocal(),
      );
    }).toList();
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

  /// Awarding points is deliberately not something a client can do.
  ///
  /// `qamar_wallet_credit` is EXECUTE-revoked from anon and authenticated
  /// (migration 0003): if the app could call it, any user could award
  /// themselves an unlimited balance. Points must be credited by the server
  /// after it has verified the action that earned them. Calling this from the
  /// client would fail with a permission error at the database, so it fails
  /// here instead, where the reason is legible.
  @override
  Future<void> credit(String userId, {required int amount, required String reason, required String idempotencyKey}) {
    throw UnsupportedError(
      'Su Points can only be credited server-side. Award them from an Edge '
      'Function using the service role after verifying the earning action.',
    );
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
