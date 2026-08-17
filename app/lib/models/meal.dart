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
  const SpendItemDef({
    required this.id,
    required this.price,
    required this.nameAr,
    required this.nameEn,
    required this.whatAr,
    required this.whatEn,
    required this.limitAr,
    required this.limitEn,
  });
}

/// Ported 1:1 from the prototype's SPEND catalogue (Su Points redemptions).
const List<SpendItemDef> kSpendCatalog = [
  SpendItemDef(
    id: 'photo', price: 20,
    nameAr: 'مسح وجبة بالصورة زيادة', nameEn: 'Extra photo meal scan',
    whatAr: 'مسحة إضافية بعد ما حد الشهر يخلص.', whatEn: 'One additional photo scan after the monthly allowance is used.',
    limitAr: 'لحد ٥ مرات في الشهر · فشل تقني يرجّع النقاط', limitEn: 'Up to 5 per month · technical failure auto-refunds',
  ),
  SpendItemDef(
    id: 'insight', price: 30,
    nameAr: 'متابعة أعمق لرأي الأسبوع', nameEn: 'Deep weekly-insight follow-up',
    whatAr: 'متابعة واحدة محدودة مع قمر على رأي الأسبوع.', whatEn: 'One bounded Qamar follow-up on an eligible weekly insight.',
    limitAr: 'مرة لكل رأي · حدود الأمان شغالة', limitEn: 'Once per insight · safety limits still apply',
  ),
  SpendItemDef(
    id: 'plan', price: 25,
    nameAr: 'تجديد خطة اليوم', nameEn: 'Plan refresh bundle',
    whatAr: 'توليد خطة يوم إضافية أو تلات بدائل زيادة.', whatEn: 'One extra day-plan regeneration or three extra substitutions.',
    limitAr: 'باقتين كحد أقصى في الشهر · مش مطلوبة لإصلاح خطة غير آمنة', limitEn: 'Max two bundles/month · never needed to fix an unsafe plan',
  ),
  SpendItemDef(
    id: 'cosmetic', price: 50,
    nameAr: 'شكل جديد للقمر والشجرة', nameEn: 'Orb and tree cosmetic',
    whatAr: 'فتح دائم لشكل معروف مقدّماً، مفيش ميزة تغذية.', whatEn: 'Clearly previewed permanent unlock with no nutrition advantage.',
    limitAr: '٥٠–٢٠٠ نقطة · سعر ثابت · مفيش صناديق عشوائية', limitEn: '50–200 points · fixed price · no random boxes',
  ),
];
