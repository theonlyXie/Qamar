import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/meal.dart';
import '../state/app_state.dart';
import '../theme/app_theme.dart';
import '../theme/colors.dart';
import '../theme/text_styles.dart';
import '../widgets/common.dart';

class ConfirmScreen extends StatelessWidget {
  const ConfirmScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    final t = state.t;
    final items = state.confirmItemsWithQty();
    final totals = state.confirmTotals();

    String confLabel(Confidence c) => switch (c) {
          Confidence.high => state.isAr ? 'ثقة عالية' : 'High confidence',
          Confidence.med => state.isAr ? 'ثقة متوسطة' : 'Medium confidence',
          Confidence.low => state.isAr ? 'ثقة منخفضة' : 'Low confidence',
        };

    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 56, 20, 40),
      children: [
        Text(t.confirmMeal, style: QText.display(size: 30, height: 38, color: const Color(0xFFF5F7FF))),
        const SizedBox(height: 4),
        Text(t.nothingWrites, style: QText.body(size: 13, color: QColors.textMuted)),
        const SizedBox(height: 14),
        Container(
          height: 120,
          alignment: Alignment.center,
          decoration: QDecor.card(color: QColors.cardDeep, radius: QRadii.xl),
          child: Text(t.sourcePreview, style: QText.number(size: 11, weight: FontWeight.w500, color: QColors.textFaint, letterSpacing: 1.4)),
        ),
        const SizedBox(height: 14),
        for (var i = 0; i < items.length; i++) ...[
          Container(
            margin: const EdgeInsets.only(bottom: 12),
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
            decoration: QDecor.card(color: QColors.cardDeep, border: QColors.borderFaint, radius: QRadii.lg),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(state.isAr ? items[i].def.ar : items[i].def.en, style: QText.body(size: 15, weight: FontWeight.w600, color: QColors.textPrimary)),
                          Text(state.isAr ? items[i].def.portionAr : items[i].def.portionEn, style: QText.body(size: 12, color: QColors.textMuted)),
                        ],
                      ),
                    ),
                    ConfidenceBadge(high: items[i].def.conf == Confidence.high, label: confLabel(items[i].def.conf)),
                  ],
                ),
                const SizedBox(height: 8),
                Row(
                  children: [
                    QRoundIconButton(icon: Icons.remove, onTap: () => state.decQty(i), size: 30),
                    SizedBox(width: 44, child: Text('${items[i].q}×', textAlign: TextAlign.center, style: QText.number(size: 14, weight: FontWeight.w600, color: QColors.textMid))),
                    QRoundIconButton(icon: Icons.add, onTap: () => state.incQty(i), size: 30),
                    const Spacer(),
                    Text('${items[i].def.kcal * items[i].q} kcal', style: QText.number(size: 14, weight: FontWeight.w600, color: QColors.cyan)),
                  ],
                ),
              ],
            ),
          ),
        ],
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          decoration: BoxDecoration(color: QColors.amber.withOpacity(0.08), border: Border.all(color: QColors.amber.withOpacity(0.35)), borderRadius: BorderRadius.circular(QRadii.lg)),
          child: Text(t.uncertainNote, style: QText.body(size: 13, height: 20, color: QColors.amberSoft)),
        ),
        const SizedBox(height: 12),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 2),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(t.approx, style: QText.number(size: 15, weight: FontWeight.w500, color: QColors.textMuted)),
              Text('${totals.kcal} kcal · P ${totals.p} · C ${totals.c} · F ${totals.f}', style: QText.number(size: 15, weight: FontWeight.w600, color: QColors.textPrimary)),
            ],
          ),
        ),
        const SizedBox(height: 12),
        QPrimaryButton(label: t.confirmAndLog, onTap: state.confirmMeal, height: 56),
        const SizedBox(height: 4),
        Center(
          child: TextButton(onPressed: () => state.go(AppScreen.today), child: Text(t.cancel, style: QText.body(size: 14, weight: FontWeight.w500, color: QColors.textMuted))),
        ),
      ],
    );
  }
}
