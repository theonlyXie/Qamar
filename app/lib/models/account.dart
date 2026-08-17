/// Account extras that are not the nutrition Profile: cosmetics, reminders,
/// structured memory, micronutrient rows, quest credit.
library;

class AccountSettings {
  final bool calmMode;
  final String orbCosmetic;
  final int insightUnlocks;
  final List<String> achievements;

  const AccountSettings({
    this.calmMode = false,
    this.orbCosmetic = 'default',
    this.insightUnlocks = 0,
    this.achievements = const [],
  });

  bool get goldOrb => orbCosmetic == 'gold';

  AccountSettings copyWith({
    bool? calmMode,
    String? orbCosmetic,
    int? insightUnlocks,
    List<String>? achievements,
  }) =>
      AccountSettings(
        calmMode: calmMode ?? this.calmMode,
        orbCosmetic: orbCosmetic ?? this.orbCosmetic,
        insightUnlocks: insightUnlocks ?? this.insightUnlocks,
        achievements: achievements ?? this.achievements,
      );
}

class MealReminders {
  final String breakfastHhmm;
  final String lunchHhmm;
  final String dinnerHhmm;
  final bool enabled;

  const MealReminders({
    this.breakfastHhmm = '08:00',
    this.lunchHhmm = '13:00',
    this.dinnerHhmm = '19:00',
    this.enabled = true,
  });

  MealReminders copyWith({
    String? breakfastHhmm,
    String? lunchHhmm,
    String? dinnerHhmm,
    bool? enabled,
  }) =>
      MealReminders(
        breakfastHhmm: breakfastHhmm ?? this.breakfastHhmm,
        lunchHhmm: lunchHhmm ?? this.lunchHhmm,
        dinnerHhmm: dinnerHhmm ?? this.dinnerHhmm,
        enabled: enabled ?? this.enabled,
      );
}

class MemoryFact {
  final String id;
  final String field;
  final String value;
  final bool fromServer;

  const MemoryFact({
    required this.id,
    required this.field,
    required this.value,
    this.fromServer = false,
  });
}

class NutrientGap {
  final String code;
  final String nameAr;
  final String nameEn;
  final String unit;
  final String status;
  final double? pctOfTarget;
  final double? coveragePct;

  const NutrientGap({
    required this.code,
    required this.nameAr,
    required this.nameEn,
    required this.unit,
    required this.status,
    this.pctOfTarget,
    this.coveragePct,
  });

  bool get isShortfall => status == 'short' || status == 'low';
}

class QuestCredit {
  final bool credited;
  final String cairoDay;
  final int amount;
  const QuestCredit({required this.credited, required this.cairoDay, required this.amount});
}

class WeeklyInsight {
  final String winAr;
  final String winEn;
  final String patternAr;
  final String patternEn;
  final String nextAr;
  final String nextEn;

  const WeeklyInsight({
    required this.winAr,
    required this.winEn,
    required this.patternAr,
    required this.patternEn,
    required this.nextAr,
    required this.nextEn,
  });

  String text(bool isAr) => isAr
      ? '$winAr $patternAr $nextAr'
      : '$winEn $patternEn $nextEn';
}
