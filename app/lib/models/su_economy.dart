/// Su Points and the daily AI allowance.
///
/// These are the numbers the product actually shows. They used to be 20, 5 and
/// 3 — too small to feel like a score, and useless the day a leaderboard lands.
/// Lifetime earned is the ranking number (it never goes down when you spend).
/// Available is what you can spend on another Qamar use after today's five.
class SuEconomy {
  SuEconomy._();

  /// Chat, meal analysis and plan generation share this many model calls a day.
  /// Body scans are onboarding, not this pool. Cairo midnight resets it.
  static const int dailyAiUses = 5;

  /// How many extra uses Su can buy in one Cairo day, so a stolen session
  /// cannot drain the wallet overnight.
  static const int extraAiDailyCap = 10;

  static const int signupBonus = 2500;
  static const int onboarding = 1000;
  static const int firstMeal = 500;
  static const int mealLogged = 100;
  static const int dailyQuest = 250;

  /// One more use of Qamar today, any of the three AI routes.
  static const int extraAiUse = 400;

  static const int weeklyInsight = 600;
  static const int cosmetic = 2500;

  /// Lifetime Su per level. Level is a vanity rank for later leaderboards,
  /// not a nutrition outcome.
  static const int levelXp = 1000;
  static const int maxLevel = 99;

  static int levelFor(int lifetime) {
    if (lifetime <= 0) return 1;
    final raw = 1 + lifetime ~/ levelXp;
    return raw > maxLevel ? maxLevel : raw;
  }

  static double levelPctFor(int lifetime) =>
      ((lifetime % levelXp) / levelXp * 100).toDouble();
}

/// Server-authoritative remaining uses for chat / meal analysis / plan.
class AiQuota {
  final int used;
  final int limit;
  final int extra;
  final int remaining;
  const AiQuota({
    required this.used,
    required this.limit,
    required this.extra,
    required this.remaining,
  });

  static const empty = AiQuota(used: 0, limit: SuEconomy.dailyAiUses, extra: 0, remaining: SuEconomy.dailyAiUses);

  bool get exhausted => remaining <= 0;

  factory AiQuota.fromJson(Map<String, dynamic> json) {
    final used = _int(json['used']);
    final limit = _int(json['limit'], SuEconomy.dailyAiUses);
    final extra = _int(json['extra']);
    final remaining = json['remaining'] is num
        ? (json['remaining'] as num).round()
        : (limit + extra - used).clamp(0, 1 << 30);
    return AiQuota(used: used, limit: limit, extra: extra, remaining: remaining);
  }

  static int _int(Object? v, [int fallback = 0]) => v is num ? v.round() : fallback;

  AiQuota consumed() {
    final next = used + 1;
    final cap = limit + extra;
    return AiQuota(
      used: next,
      limit: limit,
      extra: extra,
      remaining: (cap - next).clamp(0, cap),
    );
  }

  AiQuota withExtra(int n) {
    final nextExtra = extra + n;
    return AiQuota(
      used: used,
      limit: limit,
      extra: nextExtra,
      remaining: (limit + nextExtra - used).clamp(0, 1 << 30),
    );
  }
}
