/// Su Points and the daily AI allowance.
///
/// These are the numbers the product actually shows. They used to be 20, 5 and
/// 3 — too small to feel like a score, and useless the day a leaderboard lands.
/// Lifetime earned is the ranking number (it never goes down when you spend).
/// Available is what you can spend on another Qamar use after today's five.
class SuEconomy {
  SuEconomy._();

  /// The blueprint's walls, per Cairo day. Lite: three meal photos (a body
  /// scan counts as one) and three questions to Qamar. The fourth question
  /// meets Qamar+ first; under it, once a Cairo day, that one question can
  /// be bought with Su ([extraQuestion]). Typing or speaking a meal is never
  /// counted.
  static const int litePhotoDaily = 3;
  static const int liteChatDaily = 3;
  static const int plusPhotoDaily = 30;
  static const int plusChatDaily = 50;

  /// How many extra photos Su can buy in one Cairo day, so a stolen session
  /// cannot drain the wallet overnight.
  static const int extraAiDailyCap = 10;

  /// What each action pays. The server's su_economy_config (migration 0046)
  /// is the authority — these mirror it so the phone can show the number a
  /// second before the ledger confirms it.
  /// The server pays this on sign-up (migration 0004) and is the authority;
  /// it used to say 2,500 here while the ledger said 100, and the first
  /// hydrate corrected the screen downwards. Signing up earns little on
  /// purpose — points are for logging, not for arriving.
  static const int signupBonus = 100;
  static const int onboarding = 1000;
  static const int firstMeal = 500;
  static const int mealLogged = 100;
  static const int dailyQuest = 250;

  /// A stretch of movement logged by hand. The operator's number, under the
  /// daily cap like everything else.
  static const int activityLogged = 50;

  /// A glass of water, for the first eight glasses of the day. Half rate on
  /// the free tier.
  static const int waterSip = 10;
  static const int waterSipLite = 5;
  static const int waterSipsPaidDaily = 8;

  /// The ring completes at day 7 and pays this, once per completed week.
  static const int streakWeek = 100;

  /// Earned points per Cairo day, one-offs (signup, onboarding) excluded.
  static const int dailyEarnCap = 1500;

  /// One more meal photo today, after the free three.
  static const int extraAiUse = 400;

  /// One question past the free three, bought at the wall, at most once a
  /// Cairo day (O13, 0066): twice a photo. The price charged is the server's
  /// su_economy_config 'question_extra', which can be tuned without a
  /// release; the app reads it on each wallet refresh and shows that. This is
  /// only the number shown before the first read.
  static const int extraQuestion = 800;

  static const int weeklyInsight = 600;
  /// One freeze a month covers one empty day in a streak: the day it is
  /// taken on or a later one, never a day already missed (0064).
  static const int streakFreeze = 600;
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

/// One credit, as the orb shows it in passing (O9): a coin and the signed
/// amount, for [SuReceipt.showFor] after [at], then gone. Never a balance,
/// and never zero — only something earned makes one.
class SuReceipt {
  final int amount;
  final DateTime at;

  /// Counts credits in this session, so two equal credits in a row still
  /// each show.
  final int seq;
  const SuReceipt({required this.amount, required this.at, required this.seq});

  static const showFor = Duration(seconds: 2);
}

/// Server-authoritative counters for one bucket: 'photo', 'chat' or 'plan'.
class AiQuota {
  final String bucket;
  final int used;
  final int limit;
  final int extra;
  final int remaining;
  const AiQuota({
    required this.bucket,
    required this.used,
    required this.limit,
    required this.extra,
    required this.remaining,
  });

  /// A fresh Lite day, before the server has said anything.
  static const empty = AiQuota(bucket: 'chat', used: 0, limit: SuEconomy.liteChatDaily, extra: 0, remaining: SuEconomy.liteChatDaily);
  static const emptyPhoto = AiQuota(bucket: 'photo', used: 0, limit: SuEconomy.litePhotoDaily, extra: 0, remaining: SuEconomy.litePhotoDaily);

  bool get exhausted => remaining <= 0;

  factory AiQuota.fromJson(Map<String, dynamic> json, {String fallbackBucket = 'chat'}) {
    final bucket = json['bucket'] is String ? json['bucket'] as String : fallbackBucket;
    final used = _int(json['used']);
    final limit = _int(json['limit'], bucket == 'photo' ? SuEconomy.litePhotoDaily : SuEconomy.liteChatDaily);
    final extra = _int(json['extra']);
    final remaining = json['remaining'] is num
        ? (json['remaining'] as num).round()
        : (limit + extra - used).clamp(0, 1 << 30);
    return AiQuota(bucket: bucket, used: used, limit: limit, extra: extra, remaining: remaining);
  }

  static int _int(Object? v, [int fallback = 0]) => v is num ? v.round() : fallback;

  AiQuota consumed() {
    final next = used + 1;
    final cap = limit + extra;
    return AiQuota(
      bucket: bucket,
      used: next,
      limit: limit,
      extra: extra,
      remaining: (cap - next).clamp(0, cap),
    );
  }

  AiQuota withExtra(int n) {
    final nextExtra = extra + n;
    return AiQuota(
      bucket: bucket,
      used: used,
      limit: limit,
      extra: nextExtra,
      remaining: (limit + nextExtra - used).clamp(0, 1 << 30),
    );
  }
}

/// Every bucket at once, as `/quota` reports it.
class AiQuotas {
  final AiQuota chat;
  final AiQuota photo;
  final AiQuota plan;
  final bool plus;
  const AiQuotas({required this.chat, required this.photo, required this.plan, this.plus = false});

  static const empty = AiQuotas(
    chat: AiQuota.empty,
    photo: AiQuota.emptyPhoto,
    plan: AiQuota(bucket: 'plan', used: 0, limit: 3, extra: 0, remaining: 3),
  );

  factory AiQuotas.fromJson(Map<String, dynamic> json) {
    AiQuota bucket(String name, AiQuota fallback) {
      final raw = json[name];
      return raw is Map ? AiQuota.fromJson(Map<String, dynamic>.from(raw), fallbackBucket: name) : fallback;
    }
    return AiQuotas(
      chat: bucket('chat', AiQuota.fromJson(json)),
      photo: bucket('photo', AiQuota.emptyPhoto),
      plan: bucket('plan', AiQuotas.empty.plan),
      plus: json['plus'] == true,
    );
  }

  AiQuotas replacing(AiQuota q) => switch (q.bucket) {
        'photo' => AiQuotas(chat: chat, photo: q, plan: plan, plus: plus),
        'plan' => AiQuotas(chat: chat, photo: photo, plan: q, plus: plus),
        _ => AiQuotas(chat: q, photo: photo, plan: plan, plus: plus),
      };
}
