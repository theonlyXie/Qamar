import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../state/app_state.dart';
import '../theme/app_theme.dart';
import '../theme/colors.dart';
import '../theme/text_styles.dart';
import '../widgets/common.dart';
import '../widgets/explain.dart';

/// One component of a planned meal. The plan is only actionable if it says how
/// much of each thing to eat — a bare "620 kcal" tells you the answer without
/// telling you what to put on the plate.
typedef PlanPortion = ({String ar, String en, String amountAr, String amountEn, int kcal});

typedef PlanMeal = ({
  String slotAr,
  String slotEn,
  String nameAr,
  String nameEn,
  String noteAr,
  String noteEn,
  List<PlanPortion> portions,
});

/// Meal totals are summed from the portions rather than written down
/// separately, so the headline number can never drift from the breakdown —
/// including when the lunch swap drops the rice.
int _mealKcal(PlanMeal m) => m.portions.fold(0, (sum, p) => sum + p.kcal);

const _breakfast = (
  slotAr: 'فطار',
  slotEn: 'Breakfast',
  nameAr: 'فول + عيش بلدي + خضار',
  nameEn: 'Foul + baladi bread + vegetables',
  noteAr: 'بروتين ٢٤ جم',
  noteEn: '24 g protein',
  portions: <PlanPortion>[
    (ar: 'فول مدمس', en: 'Foul medames', amountAr: '١٥٠ جم', amountEn: '150 g', kcal: 180),
    (ar: 'عيش بلدي', en: 'Baladi bread', amountAr: 'رغيف ونص', amountEn: '1½ loaves', kcal: 220),
    (ar: 'طماطم وخيار', en: 'Tomato & cucumber', amountAr: '١٠٠ جم', amountEn: '100 g', kcal: 30),
    (ar: 'زيت زيتون', en: 'Olive oil', amountAr: 'معلقة صغيرة', amountEn: '1 tsp', kcal: 50),
  ],
);

const _lunchWithRice = (
  slotAr: 'غدا',
  slotEn: 'Lunch',
  nameAr: 'فراخ مشوية + رز + سلطة',
  nameEn: 'Grilled chicken + rice + salad',
  noteAr: 'بديل متاح',
  noteEn: 'Swap available',
  portions: <PlanPortion>[
    (ar: 'صدور فراخ مشوية', en: 'Grilled chicken breast', amountAr: '١٥٠ جم', amountEn: '150 g', kcal: 250),
    (ar: 'رز أبيض مطبوخ', en: 'Cooked white rice', amountAr: '١٥٠ جم', amountEn: '150 g', kcal: 200),
    (ar: 'سلطة خضرا', en: 'Green salad', amountAr: '١٥٠ جم', amountEn: '150 g', kcal: 45),
    (ar: 'زيت زيتون', en: 'Olive oil', amountAr: 'معلقة كبيرة', amountEn: '1 tbsp', kcal: 125),
  ],
);

const _lunchNoRice = (
  slotAr: 'غدا',
  slotEn: 'Lunch',
  nameAr: 'فراخ مشوية + سلطة',
  nameEn: 'Grilled chicken + salad',
  noteAr: 'من غير نشويات — أخف ١٧٠ سعر',
  noteEn: 'No starch — 170 kcal lighter',
  portions: <PlanPortion>[
    (ar: 'صدور فراخ مشوية', en: 'Grilled chicken breast', amountAr: '١٨٠ جم', amountEn: '180 g', kcal: 300),
    (ar: 'سلطة خضرا', en: 'Green salad', amountAr: '٢٠٠ جم', amountEn: '200 g', kcal: 60),
    (ar: 'زيت زيتون', en: 'Olive oil', amountAr: 'معلقة صغيرة', amountEn: '1 tsp', kcal: 50),
    (ar: 'عيش سن', en: 'Wholemeal bread', amountAr: 'نص رغيف', amountEn: '½ loaf', kcal: 40),
  ],
);

const _dinner = (
  slotAr: 'عشا',
  slotEn: 'Dinner',
  nameAr: 'زبادي + فاكهة + شوفان',
  nameEn: 'Yogurt + fruit + oats',
  noteAr: 'خفيف قبل النوم',
  noteEn: 'Light before sleep',
  portions: <PlanPortion>[
    (ar: 'زبادي يوناني', en: 'Greek yogurt', amountAr: '٢٠٠ جم', amountEn: '200 g', kcal: 130),
    (ar: 'شوفان', en: 'Oats', amountAr: '٤٠ جم', amountEn: '40 g', kcal: 150),
    (ar: 'موزة', en: 'Banana', amountAr: 'واحدة متوسطة', amountEn: '1 medium', kcal: 100),
  ],
);

class PlanScreen extends StatelessWidget {
  const PlanScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    final t = state.t;

    final meals = <PlanMeal>[
      _breakfast,
      state.planSwap ? _lunchNoRice : _lunchWithRice,
      _dinner,
    ];
    final dayTotal = meals.fold(0, (sum, m) => sum + _mealKcal(m));

    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 56, 20, 160),
      children: [
        Text(t.plan, style: QText.display(size: 30, height: 38, color: const Color(0xFFF5F7FF))),
        const SizedBox(height: 4),
        Text(t.planSub, style: QText.body(size: 14, height: 22, color: QColors.textMuted)),
        const SizedBox(height: 10),
        Explainable(id: 'plan_total', child: _DayTotal(state: state, kcal: dayTotal)),
        const SizedBox(height: 14),
        for (final m in meals) _MealCard(state: state, meal: m),
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: QColors.violet.withValues(alpha: 0.1),
            border: Border.all(color: QColors.violet.withValues(alpha: 0.4)),
            borderRadius: BorderRadius.circular(QRadii.xl),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(t.dayChanged, style: QText.body(size: 15, weight: FontWeight.w500, color: const Color(0xFFE9ECFF))),
              const SizedBox(height: 8),
              Material(
                color: Colors.transparent,
                child: InkWell(
                  borderRadius: BorderRadius.circular(999),
                  onTap: state.openChat,
                  child: Ink(
                    padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 10),
                    decoration: const BoxDecoration(gradient: QColors.brandGradient, borderRadius: BorderRadius.all(Radius.circular(999))),
                    child: Text(t.adjustRoute, style: QText.body(size: 13, weight: FontWeight.w600, color: Colors.white)),
                  ),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _DayTotal extends StatelessWidget {
  final AppState state;
  final int kcal;
  const _DayTotal({required this.state, required this.kcal});

  @override
  Widget build(BuildContext context) {
    final target = state.target().kcal;
    final diff = kcal - target;
    final isAr = state.isAr;
    final label = isAr ? 'إجمالي الخطة' : 'Plan total';
    final vsTarget = diff == 0
        ? (isAr ? 'مطابق لهدفك' : 'matches your target')
        : diff < 0
            ? (isAr ? 'أقل من هدفك بـ ${state.iso('${-diff}')}' : '${-diff} under your target')
            : (isAr ? 'أعلى من هدفك بـ ${state.iso('$diff')}' : '$diff over your target');

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: QDecor.card(color: QColors.cardNavy, border: QColors.borderFaint, radius: QRadii.lg),
      child: Row(
        children: [
          Text(label, style: QText.body(size: 12, color: QColors.textMuted)),
          const Spacer(),
          Text(isAr ? '${state.iso('$kcal')} سعر' : '$kcal kcal',
              style: QText.number(size: 15, weight: FontWeight.w600, color: QColors.cyan)),
          const SizedBox(width: 8),
          Text('· $vsTarget', style: QText.body(size: 11, color: QColors.textFaint)),
        ],
      ),
    );
  }
}

class _MealCard extends StatelessWidget {
  final AppState state;
  final PlanMeal meal;
  const _MealCard({required this.state, required this.meal});

  @override
  Widget build(BuildContext context) {
    final t = state.t;
    final isAr = state.isAr;
    final kcal = _mealKcal(meal);

    return Container(
      margin: const EdgeInsets.only(bottom: 14),
      padding: const EdgeInsets.all(16),
      decoration: QDecor.card(gradient: const LinearGradient(colors: [QColors.cardMid, QColors.cardDeep]), radius: QRadii.xl),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
            Text(isAr ? meal.slotAr : meal.slotEn,
                style: QText.body(size: 11, weight: FontWeight.w500, color: QColors.textMuted, letterSpacing: 0.4)),
            Text(isAr ? '${state.iso('$kcal')} سعر' : '$kcal kcal',
                style: QText.number(size: 12, weight: FontWeight.w600, color: QColors.cyan)),
          ]),
          Text(isAr ? meal.nameAr : meal.nameEn,
              style: QText.body(size: 16, weight: FontWeight.w600, color: QColors.textPrimary)),
          Text(isAr ? meal.noteAr : meal.noteEn, style: QText.body(size: 12, color: QColors.textMuted)),
          const SizedBox(height: 12),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            decoration: QDecor.card(color: QColors.cardNavy, border: QColors.borderFaint, radius: QRadii.md),
            child: Column(
              children: [
                Row(
                  children: [
                    Text(isAr ? 'المقادير' : 'Portions',
                        style: QText.body(size: 10, weight: FontWeight.w500, color: QColors.textFaint, letterSpacing: 0.5)),
                  ],
                ),
                const SizedBox(height: 6),
                for (final p in meal.portions) ...[
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 3),
                    child: Row(
                      children: [
                        Expanded(
                          child: Text(isAr ? p.ar : p.en,
                              style: QText.body(size: 13, color: QColors.textHigh), overflow: TextOverflow.ellipsis),
                        ),
                        const SizedBox(width: 8),
                        Text(isAr ? p.amountAr : p.amountEn,
                            style: QText.body(size: 12, weight: FontWeight.w500, color: QColors.textMid)),
                        const SizedBox(width: 10),
                        SizedBox(
                          width: 52,
                          child: Text(isAr ? state.iso('${p.kcal}') : '${p.kcal}',
                              textAlign: isAr ? TextAlign.left : TextAlign.right,
                              style: QText.number(size: 12, color: QColors.textMuted)),
                        ),
                      ],
                    ),
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(height: 10),
          Row(children: [
            QOutlineButton(label: t.swap, onTap: state.togglePlanSwap, height: 34, color: QColors.textMid),
            const SizedBox(width: 8),
            QOutlineButton(label: t.markEaten, onTap: () => state.go(AppScreen.log), height: 34, color: QColors.textMid),
          ]),
        ],
      ),
    );
  }
}
