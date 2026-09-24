import 'days.dart';
import 'su_economy.dart';

class Target {
  final int kcal;
  final int protein;
  final int carbs;
  final int fat;
  const Target({required this.kcal, required this.protein, required this.carbs, required this.fat});
}

class Totals {
  final int kcal;
  final int p;
  final int c;
  final int f;
  const Totals({this.kcal = 0, this.p = 0, this.c = 0, this.f = 0});
}

class LoggedMeal {
  final String name;
  final String sub;
  final int kcal;
  final int p;
  final int c;
  final int f;

  /// When it was logged. Null only for rows written before this existed.
  final DateTime? at;

  /// What started this log, captured when it started (see [LogPrompt]):
  /// the day-30 habit metric reads it. Null: not known.
  final String? prompt;

  /// A meal question was waiting on the orb when this log started, whatever
  /// the path. Null: not known.
  final bool? orbWaiting;

  const LoggedMeal({required this.name, required this.sub, required this.kcal, required this.p, required this.c, required this.f, this.at, this.prompt, this.orbWaiting});

  Map<String, dynamic> toJson() => {
        'name': name,
        'sub': sub,
        'kcal': kcal,
        'p': p,
        'c': c,
        'f': f,
        if (at != null) 'at': at!.toIso8601String(),
        if (prompt != null) 'prompt': prompt,
        if (orbWaiting != null) 'orb_waiting': orbWaiting,
      };

  factory LoggedMeal.fromJson(Map<String, dynamic> j) => LoggedMeal(
        name: (j['name'] ?? '') as String,
        sub: (j['sub'] ?? '') as String,
        kcal: (j['kcal'] as num?)?.round() ?? 0,
        p: (j['p'] as num?)?.round() ?? 0,
        c: (j['c'] as num?)?.round() ?? 0,
        f: (j['f'] as num?)?.round() ?? 0,
        at: j['at'] is String ? DateTime.tryParse(j['at'] as String) : null,
        prompt: LogPrompt.values.contains(j['prompt']) ? j['prompt'] as String : null,
        orbWaiting: j['orb_waiting'] is bool ? j['orb_waiting'] as bool : null,
      );
}

/// What started a meal log — the distinction the day-30 habit metric rests
/// on (meal_logs.prompt, 0059). Captured when the log starts, because by the
/// time it is confirmed the orb's waiting question has gone.
abstract final class LogPrompt {
  /// A notification was tapped within 30 minutes before the log began.
  static const push = 'push';

  /// The log began from a hold that opened Qamar's waiting meal question,
  /// asked on screen.
  static const inApp = 'in_app';

  /// Everything else — including a log from the tree while the orb pulsed,
  /// which is the habit itself.
  static const none = 'none';

  static const values = [push, inApp, none];
}

enum Confidence { high, med, low }

class ConfirmItemDef {
  final String ar;
  final String en;
  final String portionAr;
  final String portionEn;
  final Confidence conf;
  final int kcal;
  final int p;
  final int c;
  final int f;

  /// The row in the food graph this item was matched to, and the weight eaten.
  ///
  /// Null when Qamar could not identify the food confidently. That is a normal
  /// outcome and not an error — but it is the difference between a meal that
  /// can later answer "was I short on iron" and one that only ever knew its
  /// calories. Both travel through to the log; nothing downstream may invent
  /// them.
  final String? qamarFoodId;
  final double? grams;

  /// True when the user named the portion, false when Qamar assumed a default.
  final bool portionMatched;

  const ConfirmItemDef({
    required this.ar,
    required this.en,
    required this.portionAr,
    required this.portionEn,
    required this.conf,
    required this.kcal,
    required this.p,
    required this.c,
    required this.f,
    this.qamarFoodId,
    this.grams,
    this.portionMatched = false,
  });
  /// The same keys the gateway sends, so a queued item reads back like a fresh one.
  Map<String, dynamic> toJson() => {
        'ar': ar,
        'en': en,
        'portionAr': portionAr,
        'portionEn': portionEn,
        'confidence': conf.name,
        'kcal': kcal,
        'proteinG': p,
        'carbsG': c,
        'fatG': f,
        if (qamarFoodId != null) 'qamar_food_id': qamarFoodId,
        if (grams != null) 'grams': grams,
        'portion_matched': portionMatched,
      };

  factory ConfirmItemDef.fromJson(Map<String, dynamic> j) => ConfirmItemDef(
        ar: (j['ar'] ?? j['en'] ?? '') as String,
        en: (j['en'] ?? j['ar'] ?? '') as String,
        portionAr: (j['portionAr'] ?? '') as String,
        portionEn: (j['portionEn'] ?? '') as String,
        conf: Confidence.values.asNameMap()[j['confidence']?.toString()] ?? Confidence.low,
        kcal: (j['kcal'] as num?)?.round() ?? 0,
        p: (j['proteinG'] as num?)?.round() ?? 0,
        c: (j['carbsG'] as num?)?.round() ?? 0,
        f: (j['fatG'] as num?)?.round() ?? 0,
        qamarFoodId: j['qamar_food_id'] as String?,
        grams: (j['grams'] as num?)?.toDouble(),
        portionMatched: j['portion_matched'] == true,
      );
}

class LedgerEntry {
  final String label;
  final int amount; // negative for spends
  final String when;

  /// The database's `su_point_ledger.reason` when this row came from the
  /// server — `first_meal`, `daily_quest`, `signup_bonus`. Null for rows the
  /// app wrote optimistically, which already carry a translated [label].
  final String? reason;

  /// The raw `created_at`, when there is one, so the wallet can render a time
  /// instead of an ISO string.
  final DateTime? at;

  const LedgerEntry({
    required this.label,
    required this.amount,
    required this.when,
    this.reason,
    this.at,
  });

  /// What to actually put on screen.
  ///
  /// A server row arrives as a snake_case reason code. Printing it puts
  /// `economy_v2_signup_topup` in front of an Arabic-first user, which is how
  /// it read until this existed. Anything unrecognised falls back to the code
  /// rather than to a wrong guess — a reason nobody has translated yet should
  /// look untranslated, not look like something else.
  String displayLabel(bool isAr) {
    final r = reason;
    if (r == null) return label;
    // A redemption is 'redemption:<catalog id>' (qamar_wallet_redeem): named
    // after what was bought.
    if (r.startsWith('redemption:')) {
      final id = r.substring('redemption:'.length);
      for (final item in [...kSpendCatalog, kQuestionExtra]) {
        if (item.id == id) return isAr ? item.nameAr : item.nameEn;
      }
      return isAr ? 'استبدال' : 'Redemption';
    }
    return switch (r) {
      'signup_bonus' => isAr ? 'هدية التسجيل' : 'Signup bonus',
      'economy_v2_signup_topup' => isAr ? 'تعويض رصيد البداية' : 'Starting balance top-up',
      'onboarding' => isAr ? 'إكمال التهيئة' : 'Onboarding completed',
      'first_meal' => isAr ? 'أول وجبة' : 'First meal logged',
      'meal_log' || 'meal_logged' => isAr ? 'تأكيد وجبة' : 'Meal confirmed',
      'daily_quest' => isAr ? 'مهمة اليوم' : 'Primary daily quest',
      'water' => isAr ? 'كوباية مية' : 'A glass of water',
      'streak_week' => isAr ? 'أسبوع كامل ورا بعض' : 'A week in a row',
      'activity_logged' => isAr ? 'حركة' : 'Activity logged',
      'season_full_log' => isAr ? 'رمضان كله متسجّل' : 'All of Ramadan logged',
      'invitation_sender_reward' => isAr ? 'صاحبك اشترك' : 'Your friend subscribed',
      'invitation_friend_reward' => isAr ? 'هدية الدعوة' : 'Your invitation gift',
      _ => r.startsWith('redeem_') || r == 'redeem'
          ? (isAr ? 'استبدال' : 'Redemption')
          : r,
    };
  }

  /// A short, local rendering of [at], seen at [now] (the app's clock).
  /// Falls back to [when] for optimistic rows, which set it to "just now" in
  /// the right language already. Past the first day it counts calendar days
  /// ([Days]), not 24-hour spans, so the day the clocks change is one day.
  String displayWhen(bool isAr, {DateTime? now}) {
    final t = at;
    if (t == null) return when;
    final seen = now ?? DateTime.now();
    final d = seen.difference(t);
    if (d.inMinutes < 1) return isAr ? 'دلوقتي' : 'Just now';
    if (d.inHours < 1) {
      final m = d.inMinutes;
      return isAr ? 'من ${_arCount(m, 'دقيقة', 'دقيقتين', 'دقايق')}' : '${m}m ago';
    }
    final days = Days.between(t.toLocal(), seen.toLocal());
    if (days < 1 || d.inHours < 24) {
      final h = d.inHours;
      return isAr ? 'من ${_arCount(h, 'ساعة', 'ساعتين', 'ساعات')}' : '${h}h ago';
    }
    if (days < 7) {
      if (days == 1) return isAr ? 'امبارح' : 'Yesterday';
      return isAr ? 'من ${_arCount(days, 'يوم', 'يومين', 'أيام')}' : '${days}d ago';
    }
    final l = t.toLocal();
    final mm = l.month.toString().padLeft(2, '0');
    final dd = l.day.toString().padLeft(2, '0');
    return '$dd/$mm';
  }

  /// "دقيقة", "دقيقتين", "٣ دقايق", "١١ دقيقة": one and two are words, three
  /// to ten take the plural, and eleven on the singular again. Digits stay
  /// Western here; the screen passes the line through its own [AppState.iso].
  static String _arCount(int n, String one, String two, String few) => switch (n) {
        1 => one,
        2 => two,
        >= 3 && <= 10 => '$n $few',
        _ => '$n $one',
      };
}

class SpendItemDef {
  final String id;
  final int price;
  final String nameAr, nameEn, whatAr, whatEn, limitAr, limitEn;
  final bool once;
  final int grantsAiUses;
  const SpendItemDef({
    required this.id,
    required this.price,
    required this.nameAr,
    required this.nameEn,
    required this.whatAr,
    required this.whatEn,
    required this.limitAr,
    required this.limitEn,
    this.once = true,
    this.grantsAiUses = 0,
  });
}

/// Su Points redemptions. Extra photos are how the three-a-day wall flexes.
/// A question is not sold here: it is bought only at the wall, as that one
/// question ([kQuestionExtra]). Cosmetics are the prestige sink for a later
/// leaderboard.
/// The fourth question, bought with Su at the wall (O13, 0066): never listed
/// in the wallet, only offered under the Qamar+ wall, once a Cairo day, when
/// the balance covers it. Its price is the server's (AppState.questionPrice).
const SpendItemDef kQuestionExtra = SpendItemDef(
  id: 'chat_extra',
  price: SuEconomy.extraQuestion,
  once: false,
  nameAr: 'سؤال زيادة النهارده',
  nameEn: 'One more question today',
  whatAr: 'السؤال اللي وقف عند الحد، بنقاط Su.',
  whatEn: 'The question that met the limit, asked with Su.',
  limitAr: 'مرة في اليوم',
  limitEn: 'Once a day',
);

const List<SpendItemDef> kSpendCatalog = [
  SpendItemDef(
    id: 'ai_extra',
    price: SuEconomy.extraAiUse,
    once: false,
    grantsAiUses: 1,
    nameAr: 'صورة زيادة النهارده',
    nameEn: 'Extra photo today',
    whatAr: 'صوّر وجبة رابعة النهارده بعد التلاتة المجانية.',
    whatEn: 'Photograph a fourth meal today, after the free three.',
    limitAr: 'لحد ١٠ زيادة في اليوم · بيتجددوا نص الليل بتوقيت القاهرة',
    limitEn: 'Up to 10 extras a day · refreshes at Cairo midnight',
  ),
  SpendItemDef(
    id: 'streak_freeze',
    price: SuEconomy.streakFreeze,
    once: false,
    nameAr: 'تجميد السلسلة',
    nameEn: 'Streak freeze',
    // Forward only (0064): it covers the day it is taken on or a later one,
    // never a day already missed — there is no "restore my streak" purchase.
    whatAr: 'يوم واحد من غير تسجيل ميقطعش سلسلتك، من يوم ما تاخده ولقدام. بيتصرف لوحده لما يوم يفوت — بس مبيرجّعش يوم فات قبل ما تاخده.',
    whatEn: 'From the day you take it, one day without a log will not break your streak. Applied automatically when a day is missed — never to a day missed before you took it.',
    limitAr: 'مرة في الشهر · ميتشتراش بفلوس',
    limitEn: 'Once a month · never for money',
  ),
  SpendItemDef(
    id: 'insight',
    price: SuEconomy.weeklyInsight,
    nameAr: 'اسأل أكتر عن أسبوعك',
    nameEn: 'Ask more about your week',
    whatAr: 'سؤال متابعة واحد لقمر عن خلاصة أسبوعك.',
    whatEn: 'One follow-up question to Qamar about your weekly insight.',
    limitAr: 'مرة لكل خلاصة · حدود الأمان شغالة',
    limitEn: 'Once per insight · safety limits still apply',
  ),
  SpendItemDef(
    id: 'cosmetic',
    price: SuEconomy.cosmetic,
    nameAr: 'شكل جديد للقمر',
    nameEn: 'A new look for the moon',
    whatAr: 'بيفضل معاك على طول، وبتشوفه قبل ما تاخده. بيغيّر الشكل بس، مش النصايح.',
    whatEn: 'Yours for good, and you see it before you take it. It changes the look only, never the advice.',
    limitAr: 'سعر ثابت · مفيش صناديق عشوائية',
    limitEn: 'Fixed price · no random boxes',
  ),
];
