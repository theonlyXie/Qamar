import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../state/app_state.dart';
import '../theme/app_theme.dart';
import '../theme/colors.dart';
import '../theme/text_styles.dart';
import '../widgets/common.dart';

class PlanScreen extends StatelessWidget {
  const PlanScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    final t = state.t;
    final isAr = state.isAr;

    final meals = [
      (
        slot: isAr ? 'فطار' : 'Breakfast',
        name: isAr ? 'فول + عيش بلدي + خضار' : 'Foul + baladi bread + vegetables',
        note: isAr ? 'بروتين ٢٤ جم' : '24 g protein',
        kcal: '480 kcal',
        onSwap: state.togglePlanSwap,
      ),
      (
        slot: isAr ? 'غدا' : 'Lunch',
        name: state.planSwap ? (isAr ? 'فراخ مشوية + سلطة' : 'Grilled chicken + salad') : (isAr ? 'فراخ مشوية + رز + سلطة' : 'Grilled chicken + rice + salad'),
        note: isAr ? 'بديل متاح' : 'Swap available',
        kcal: '620 kcal',
        onSwap: state.togglePlanSwap,
      ),
      (
        slot: isAr ? 'عشا' : 'Dinner',
        name: isAr ? 'زبادي + فاكهة + شوفان' : 'Yogurt + fruit + oats',
        note: isAr ? 'خفيف قبل النوم' : 'Light before sleep',
        kcal: '380 kcal',
        onSwap: state.togglePlanSwap,
      ),
    ];

    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 56, 20, 160),
      children: [
        Text(t.plan, style: QText.display(size: 30, height: 38, color: const Color(0xFFF5F7FF))),
        const SizedBox(height: 4),
        Text(t.planSub, style: QText.body(size: 14, height: 22, color: QColors.textMuted)),
        const SizedBox(height: 14),
        for (final m in meals) ...[
          Container(
            margin: const EdgeInsets.only(bottom: 14),
            padding: const EdgeInsets.all(16),
            decoration: QDecor.card(gradient: const LinearGradient(colors: [QColors.cardMid, QColors.cardDeep]), radius: QRadii.xl),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
                  Text(m.slot, style: QText.body(size: 11, weight: FontWeight.w500, color: QColors.textMuted, letterSpacing: 0.4)),
                  Text(m.kcal, style: QText.number(size: 12, weight: FontWeight.w600, color: QColors.cyan)),
                ]),
                Text(m.name, style: QText.body(size: 16, weight: FontWeight.w600, color: QColors.textPrimary)),
                Text(m.note, style: QText.body(size: 12, color: QColors.textMuted)),
                const SizedBox(height: 8),
                Row(children: [
                  QOutlineButton(label: t.swap, onTap: m.onSwap, height: 34, color: QColors.textMid),
                  const SizedBox(width: 8),
                  QOutlineButton(label: t.markEaten, onTap: () => state.go(AppScreen.log), height: 34, color: QColors.textMid),
                ]),
              ],
            ),
          ),
        ],
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(color: QColors.violet.withOpacity(0.1), border: Border.all(color: QColors.violet.withOpacity(0.4)), borderRadius: BorderRadius.circular(QRadii.xl)),
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
