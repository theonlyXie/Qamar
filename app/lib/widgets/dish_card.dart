import 'package:flutter/material.dart';

import '../models/dishes.dart';
import '../models/nudge.dart';
import '../theme/app_theme.dart';
import '../theme/colors.dart';
import '../theme/icons.dart';
import '../theme/text_styles.dart';

/// One real Egyptian dish with its numbers (O5): named, portioned, costed.
///
/// With a [targetKcal] it also says what share of the person's day it is,
/// the consultation's first moment of value. Without one it shows the dish
/// and its numbers alone. Always said to be an estimate: the portions are
/// household sizes.
///
/// A card on the page (the qamar-design skill): the flat surface, a hairline,
/// the card corner; an eyebrow for the meal, the dish as the lead line, its
/// numbers under it in two steps of ink.
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

  /// The meal it is for, as the card's eyebrow.
  static String slotLine(MealSlot slot, bool isAr) => switch (slot) {
        MealSlot.breakfast => isAr ? 'على الفطار' : 'For breakfast',
        MealSlot.lunch => isAr ? 'على الغدا' : 'For lunch',
        MealSlot.dinner => isAr ? 'على العشا' : 'Tonight',
        MealSlot.iftar => isAr ? 'على الإفطار' : 'For iftar',
        MealSlot.suhoor => isAr ? 'على السحور' : 'For suhoor',
      };

  /// "About 507 kcal · 23% of your 2180" / "حوالي ٥٠٧ سعرة، ٢٣٪ من هدفك ٢١٨٠"
  /// (the Arabic comma: beside Arabic digits a middle dot reads as a zero).
  String costLine() {
    final t = targetKcal;
    final share = t == null || t <= 0 ? null : (facts.kcal * 100 / t).round();
    if (isAr) {
      final base = 'حوالي ${iso('${facts.kcal}')} سعرة';
      return share == null ? base : '$base، ${iso('$share')}٪ من هدفك ${iso('$t')}';
    }
    final base = 'About ${facts.kcal} kcal';
    return share == null ? base : '$base · $share% of your $t';
  }

  String macroLine() => isAr
      ? 'بروتين ${iso('${facts.protein}')} جم · كربوهيدرات ${iso('${facts.carbs}')} جم · دهون ${iso('${facts.fat}')} جم'
      : 'Protein ${facts.protein} g · Carbs ${facts.carbs} g · Fat ${facts.fat} g';

  /// What the numbers are: an estimate, at home-sized portions.
  static String estimateLine(bool isAr) => isAr ? 'تقدير، بحصص البيت.' : 'An estimate, for home-sized portions.';

  /// The kit's diet card, as the plan draws a meal: the slot on a mint band
  /// where the kit has its photo, the dish and its figures under it.
  @override
  Widget build(BuildContext context) {
    return Container(
      clipBehavior: Clip.antiAlias,
      decoration: QDecor.card(),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            color: QColors.mint,
            padding: const EdgeInsets.symmetric(horizontal: QSpace.lg, vertical: QSpace.md),
            child: Row(children: [
              Container(
                width: 34,
                height: 34,
                decoration: const BoxDecoration(shape: BoxShape.circle, color: QColors.pastelTrack),
                child: const Center(child: QIcon(QIcons.plan, size: 18, color: QColors.onPastel)),
              ),
              const SizedBox(width: QSpace.md),
              Expanded(
                child: Text(
                  slot != null ? slotLine(slot!, isAr) : (isAr ? 'طبق من خطتك' : 'A dish from your plan'),
                  style: QText.body(size: 15, weight: FontWeight.w600, color: QColors.onPastel),
                ),
              ),
            ]),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(QSpace.lg, QSpace.md, QSpace.lg, QSpace.lg),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(isAr ? dish.nameAr : dish.nameEn, style: QText.body(size: 17, weight: FontWeight.w600)),
                const SizedBox(height: 2),
                Text(dish.portions(isAr), style: QText.body(size: 13, color: QColors.inkSecondary)),
                const SizedBox(height: QSpace.md),
                Text(costLine(), style: QText.number(size: 15, weight: FontWeight.w600, ar: isAr)),
                const SizedBox(height: 2),
                Text(macroLine(), style: QText.body(size: 13, color: QColors.inkSecondary)),
                const SizedBox(height: QSpace.md),
                Text(estimateLine(isAr), style: QText.body(size: 12, color: QColors.inkTertiary)),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
