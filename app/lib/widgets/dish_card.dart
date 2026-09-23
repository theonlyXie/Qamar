import 'package:flutter/material.dart';

import '../models/dishes.dart';
import '../models/nudge.dart';
import '../theme/app_theme.dart';
import '../theme/colors.dart';
import '../theme/text_styles.dart';

/// One real Egyptian dish with its numbers (O5): named, portioned, costed.
///
/// With a [targetKcal] it also says what share of the person's day it is —
/// the first moment of value in the consultation. Without one (the welcome
/// entry, before any target exists) it shows the dish and its numbers alone.
/// Always labelled as an estimate: the portions are household sizes.
class DishCard extends StatelessWidget {
  final EgyptianDish dish;
  final DishFacts facts;
  final int? targetKcal;

  /// The meal it is suggested for; null leaves the line out.
  final MealSlot? slot;

  final bool isAr;

  /// Digits the way the app draws them (Eastern or Western, bidi-isolated).
  final String Function(String) iso;

  const DishCard({
    super.key,
    required this.dish,
    required this.facts,
    this.targetKcal,
    this.slot,
    required this.isAr,
    required this.iso,
  });

  static String slotLine(MealSlot slot, bool isAr) => switch (slot) {
        MealSlot.breakfast => isAr ? 'على الفطار مثلاً' : 'For breakfast, for example',
        MealSlot.lunch => isAr ? 'على الغدا مثلاً' : 'For lunch, for example',
        MealSlot.dinner => isAr ? 'على العشا مثلاً' : 'Tonight, for example',
        MealSlot.iftar => isAr ? 'على الإفطار مثلاً' : 'For iftar, for example',
        MealSlot.suhoor => isAr ? 'على السحور مثلاً' : 'For suhoor, for example',
      };

  /// "About 507 kcal · 23% of your 2180" / "حوالي ٥٠٧ سعرة · ٢٣٪ من هدفك ٢١٨٠".
  String costLine() {
    final t = targetKcal;
    final share = t == null || t <= 0 ? null : (facts.kcal * 100 / t).round();
    if (isAr) {
      final base = 'حوالي ${iso('${facts.kcal}')} سعرة';
      return share == null ? base : '$base · ${iso('$share')}٪ من هدفك ${iso('$t')}';
    }
    final base = 'About ${facts.kcal} kcal';
    return share == null ? base : '$base · $share% of your $t';
  }

  String macroLine() => isAr
      ? 'بروتين ${iso('${facts.protein}')} جم · كربوهيدرات ${iso('${facts.carbs}')} جم · دهون ${iso('${facts.fat}')} جم'
      : 'Protein ${facts.protein} g · Carbs ${facts.carbs} g · Fat ${facts.fat} g';

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        gradient: const LinearGradient(colors: [QColors.surfaceRaised, QColors.surface], begin: Alignment.topLeft, end: Alignment.bottomRight),
        border: Border.all(color: QColors.ink.withValues(alpha: 0.4)),
        borderRadius: BorderRadius.circular(QRadii.card),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          if (slot != null) ...[
            Text(slotLine(slot!, isAr), style: QText.body(size: 11, weight: FontWeight.w500, color: QColors.ink)),
            const SizedBox(height: 6),
          ],
          Text(isAr ? dish.nameAr : dish.nameEn, style: QText.body(size: 17, height: 24, weight: FontWeight.w600, color: QColors.ink)),
          const SizedBox(height: 2),
          Text(dish.portions(isAr), style: QText.body(size: 12, height: 18, color: QColors.inkTertiary)),
          const SizedBox(height: 10),
          Text(costLine(), style: QText.body(size: 15, height: 22, weight: FontWeight.w600, color: QColors.ink)),
          const SizedBox(height: 2),
          Text(macroLine(), style: QText.body(size: 12, height: 18, color: QColors.inkSecondary)),
          const SizedBox(height: 8),
          Text(
            isAr ? 'تقدير — بحصص البيت، والأرقام من قاعدة بيانات الأكل.' : 'An estimate — household portions, numbers from the food database.',
            style: QText.body(size: 11, height: 16, color: QColors.inkSecondary),
          ),
        ],
      ),
    );
  }
}
