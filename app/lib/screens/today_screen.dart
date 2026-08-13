import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../state/app_state.dart';
import '../theme/app_theme.dart';
import '../theme/colors.dart';
import '../theme/text_styles.dart';
import '../widgets/common.dart';

class TodayScreen extends StatelessWidget {
  const TodayScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    final t = state.t;
    final tg = state.target();
    final con = state.consumed();
    final remaining = (tg.kcal - con.kcal).clamp(0, 1 << 30);
    final nameOr = state.profile.name.isNotEmpty ? state.profile.name : (state.isAr ? 'يا صاحبي' : 'friend');

    double pct(int a, int b) => b == 0 ? 0 : (a / b).clamp(0, 1).toDouble();

    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 56, 20, 160),
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(state.isAr ? 'صباح الخير،' : 'Good morning,', style: QText.body(size: 14, color: QColors.textMuted)),
                  Text(nameOr, style: QText.display(size: 34, height: 42, color: const Color(0xFFF5F7FF))),
                ],
              ),
            ),
            Row(
              children: [
                Material(
                  color: Colors.transparent,
                  child: InkWell(
                    borderRadius: BorderRadius.circular(999),
                    onTap: state.openWallet,
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 6),
                      decoration: BoxDecoration(border: Border.all(color: QColors.gold.withOpacity(0.4)), borderRadius: BorderRadius.circular(999), color: const Color(0xFF0F1730)),
                      child: Row(mainAxisSize: MainAxisSize.min, children: [
                        const SuCoinIcon(size: 16),
                        const SizedBox(width: 6),
                        Text('${state.suAvailable}', style: QText.number(size: 11, weight: FontWeight.w600, color: QColors.gold)),
                      ]),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                  decoration: BoxDecoration(border: Border.all(color: QColors.borderSoft), borderRadius: BorderRadius.circular(999), color: QColors.cardDeep),
                  child: Row(mainAxisSize: MainAxisSize.min, children: [
                    Container(width: 8, height: 8, decoration: const BoxDecoration(shape: BoxShape.circle, color: QColors.green)),
                    const SizedBox(width: 8),
                    Text(state.isAr ? 'المستوى ${state.level()}' : 'Level ${state.level()}', style: QText.number(size: 11, weight: FontWeight.w500, color: QColors.textMid)),
                  ]),
                ),
              ],
            ),
          ],
        ),
        const SizedBox(height: 14),
        Container(
          padding: const EdgeInsets.all(14),
          decoration: QDecor.card(gradient: const LinearGradient(colors: [QColors.cardMid, QColors.cardDeep]), radius: QRadii.xl),
          child: Row(
            children: [
              ClipRRect(borderRadius: BorderRadius.circular(12), child: Image.asset('assets/images/qamar_orb_sm.png', width: 40, height: 40, fit: BoxFit.cover)),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  con.kcal > 0
                      ? (state.isAr ? 'سجّلت وجبة النهاردة. باقي عشا خفيف فيه بروتين ونكون قفلنا اليوم صح.' : 'You logged a meal today. A light protein dinner closes the day well.')
                      : (state.isAr ? 'أهم حاجة النهاردة: تسجّل أول وجبة. الباقي أنا هظبطه معاك.' : 'The one thing today: log your first meal. I’ll handle the rest with you.'),
                  style: QText.body(size: 14, height: 21, color: QColors.textHigh),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 14),
        Container(
          padding: const EdgeInsets.all(20),
          decoration: QDecor.card(gradient: const LinearGradient(colors: [QColors.cardMid, QColors.cardSlate]), border: QColors.borderStrong, radius: QRadii.xxxl,
              shadow: [BoxShadow(color: QColors.blue.withOpacity(0.12), blurRadius: 40)]),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(crossAxisAlignment: CrossAxisAlignment.baseline, textBaseline: TextBaseline.alphabetic, children: [
                ShaderMask(
                  shaderCallback: (r) => QColors.cyanVioletGradient.createShader(r),
                  child: Text('$remaining', style: QText.number(size: 38, weight: FontWeight.w600, color: Colors.white)),
                ),
                const SizedBox(width: 8),
                Text(t.kcalRemaining, style: QText.body(size: 13, weight: FontWeight.w500, color: QColors.textMuted)),
              ]),
              const SizedBox(height: 16),
              _MacroRow(label: t.protein, text: '${con.p} / ${tg.protein} g', pct: pct(con.p, tg.protein)),
              const SizedBox(height: 12),
              _MacroRow(label: t.carbs, text: '${con.c} / ${tg.carbs} g', pct: pct(con.c, tg.carbs)),
              const SizedBox(height: 12),
              _MacroRow(label: t.fat, text: '${con.f} / ${tg.fat} g', pct: pct(con.f, tg.fat)),
              const SizedBox(height: 14),
              Row(
                children: [
                  Expanded(child: Text(t.estimateNote, style: QText.body(size: 11, color: QColors.textFaint))),
                  QOutlineButton(label: t.whyCta, onTap: state.openWhy, height: 30),
                ],
              ),
            ],
          ),
        ),
        const SizedBox(height: 14),
        Container(
          padding: const EdgeInsets.all(16),
          decoration: QDecor.card(color: QColors.cardDeep, border: QColors.green.withOpacity(0.4), radius: QRadii.xl),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(t.nextMeal, style: QText.body(size: 11, weight: FontWeight.w500, color: QColors.green, letterSpacing: 0.4)),
              Text(state.isAr ? 'فراخ مشوية + رز + سلطة' : 'Grilled chicken + rice + salad', style: QText.body(size: 17, weight: FontWeight.w600, color: QColors.textPrimary)),
              Text(state.isAr ? 'حوالي ٦٢٠ سعر · متاح بديل' : 'About 620 kcal · swap available', style: QText.body(size: 13, color: QColors.textMuted)),
              const SizedBox(height: 8),
              Row(children: [
                QOutlineButton(label: t.swap, onTap: state.togglePlanSwap, height: 34, color: QColors.textMid),
                const SizedBox(width: 8),
                QOutlineButton(label: t.openPlan, onTap: () => state.go(AppScreen.plan), height: 34, color: QColors.textMid),
              ]),
            ],
          ),
        ),
        const SizedBox(height: 14),
        Container(
          padding: const EdgeInsets.all(16),
          decoration: QDecor.card(color: QColors.cardDeep, radius: QRadii.xl),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(t.nextQuest, style: QText.body(size: 11, weight: FontWeight.w500, color: QColors.textMuted, letterSpacing: 0.4)),
                  Row(mainAxisSize: MainAxisSize.min, children: [
                    const SuCoinIcon(size: 15),
                    const SizedBox(width: 5),
                    Text('+5', style: QText.number(size: 12, weight: FontWeight.w600, color: QColors.gold)),
                  ]),
                ],
              ),
              Text(state.isAr ? 'سجّل الغدا قبل ٤ العصر' : 'Log lunch before 4pm', style: QText.body(size: 16, weight: FontWeight.w600, color: QColors.textPrimary)),
              Text(
                state.isAr ? 'لما تسجّل بدري بقدر أعدّل العشا قبل ما اليوم يخلص.' : 'Logging early lets me adjust dinner before the day ends.',
                style: QText.body(size: 13, color: QColors.textMuted),
              ),
              const SizedBox(height: 8),
              Row(children: [
                Material(
                  color: Colors.transparent,
                  child: InkWell(
                    borderRadius: BorderRadius.circular(999),
                    onTap: state.completeQuest,
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                      decoration: BoxDecoration(color: QColors.violet.withOpacity(0.16), border: Border.all(color: QColors.violet.withOpacity(0.55)), borderRadius: BorderRadius.circular(999)),
                      child: Text(state.questDone ? t.done2 : t.accept, style: QText.body(size: 13, weight: FontWeight.w500, color: const Color(0xFFE9ECFF))),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                QOutlineButton(label: t.replace, onTap: state.replaceQuest, height: 34, color: QColors.textMuted),
              ]),
            ],
          ),
        ),
        const SizedBox(height: 14),
        QPrimaryButton(label: t.logMeal, onTap: () => state.go(AppScreen.log), height: 56),
        if (state.meals.isNotEmpty) ...[
          const SizedBox(height: 18),
          Text(t.loggedToday, style: QText.body(size: 11, weight: FontWeight.w500, color: QColors.textMuted, letterSpacing: 0.4)),
          const SizedBox(height: 8),
          for (final m in state.meals) ...[
            Container(
              margin: const EdgeInsets.only(bottom: 8),
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
              decoration: QDecor.card(color: QColors.cardDeep, border: QColors.borderFaint, radius: QRadii.lg),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text(m.name, style: QText.body(size: 15, weight: FontWeight.w600, color: QColors.textPrimary)),
                    Text(m.sub, style: QText.body(size: 12, color: QColors.textMuted)),
                  ]),
                  Text('${m.kcal} kcal', style: QText.number(size: 15, weight: FontWeight.w600, color: QColors.cyan)),
                ],
              ),
            ),
          ],
        ],
      ],
    );
  }
}

class _MacroRow extends StatelessWidget {
  final String label;
  final String text;
  final double pct;
  const _MacroRow({required this.label, required this.text, required this.pct});
  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
          Text(label, style: QText.body(size: 12, weight: FontWeight.w500, color: QColors.textMuted)),
          Text(text, style: QText.body(size: 12, weight: FontWeight.w500, color: QColors.textMuted)),
        ]),
        const SizedBox(height: 6),
        ClipRRect(
          borderRadius: BorderRadius.circular(999),
          child: LinearProgressIndicator(
            value: pct,
            minHeight: 6,
            backgroundColor: QColors.borderFaint,
            valueColor: const AlwaysStoppedAnimation(QColors.green),
          ),
        ),
      ],
    );
  }
}
