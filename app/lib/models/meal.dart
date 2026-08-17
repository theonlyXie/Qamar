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
  const LoggedMeal({required this.name, required this.sub, required this.kcal, required this.p, required this.c, required this.f});
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
}

class LedgerEntry {
  final String label;
  final int amount; // negative for spends
  final String when;
  const LedgerEntry({required this.label, required this.amount, required this.when});
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

/// Su Points redemptions. Extra Qamar uses are how the five-a-day cap flexes;
/// cosmetics are the prestige sink for a later leaderboard.
const List<SpendItemDef> kSpendCatalog = [
  SpendItemDef(
    id: 'ai_extra',
    price: SuEconomy.extraAiUse,
    once: false,
    grantsAiUses: 1,
    nameAr: 'استخدام زيادة لقمر',
    nameEn: 'Extra Qamar use',
    whatAr: 'استخدام إضافي النهارده — سؤال، تصوير طبق، أو كتابة الخطة.',
    whatEn: 'One more use today — a question, photographing a plate, or writing the plan.',
    limitAr: 'لحد ١٠ زيادة في اليوم · بكرة الصبح بيتجددوا',
    limitEn: 'Up to 10 extras a day · refreshes at Cairo midnight',
  ),
  SpendItemDef(
    id: 'insight',
    price: SuEconomy.weeklyInsight,
    nameAr: 'متابعة أعمق لرأي الأسبوع',
    nameEn: 'Deep weekly-insight follow-up',
    whatAr: 'متابعة واحدة محدودة مع قمر على رأي الأسبوع.',
    whatEn: 'One bounded Qamar follow-up on an eligible weekly insight.',
    limitAr: 'مرة لكل رأي · حدود الأمان شغالة',
    limitEn: 'Once per insight · safety limits still apply',
  ),
  SpendItemDef(
    id: 'cosmetic',
    price: SuEconomy.cosmetic,
    nameAr: 'شكل جديد للقمر والشجرة',
    nameEn: 'Orb and tree cosmetic',
    whatAr: 'فتح دائم لشكل معروف مقدّماً، مفيش ميزة تغذية.',
    whatEn: 'Clearly previewed permanent unlock with no nutrition advantage.',
    limitAr: 'سعر ثابت · مفيش صناديق عشوائية',
    limitEn: 'Fixed price · no random boxes',
  ),
];
