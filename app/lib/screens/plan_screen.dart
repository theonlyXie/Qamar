import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/plan.dart';
import '../state/app_state.dart';
import '../theme/app_theme.dart';
import '../theme/colors.dart';
import '../theme/text_styles.dart';
import '../widgets/common.dart';
import '../widgets/explain.dart';

/// The day's meals, generated for this person.
///
/// The screen used to render a fixed three-meal menu that was identical for
/// every user, target and allergy. It now shows the plan the assistant built
/// from their own numbers, and when there isn't one it says so and offers to
/// build it — an empty plan is recoverable, a plausible wrong one is not.
class PlanScreen extends StatefulWidget {
  const PlanScreen({super.key});

  @override
  State<PlanScreen> createState() => _PlanScreenState();
}

class _PlanScreenState extends State<PlanScreen> {
  @override
  void initState() {
    super.initState();
    // After the first frame: ensurePlan notifies listeners, and doing that
    // during build would rebuild the tree mid-build.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) context.read<AppState>().ensurePlan();
    });
  }

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    final t = state.t;

    final meals = state.planMeals();
    final dayTotal = meals.fold(0, (sum, m) => sum + mealKcal(m));

    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 56, 20, 160),
      children: [
        Text(t.plan, style: QText.display(size: 30, height: 38, color: const Color(0xFFF5F7FF))),
        const SizedBox(height: 4),
        Text(t.planSub, style: QText.body(size: 14, height: 22, color: QColors.textMuted)),
        const SizedBox(height: 10),
        if (!state.hasPlan) ...[
          _PlanEmpty(state: state),
        ] else ...[
          Explainable(id: 'plan_total', child: _DayTotal(state: state, kcal: dayTotal)),
          if (state.nudgePromptDue) ...[
            const SizedBox(height: 10),
            _NudgePrompt(state: state),
          ],
          if (state.plan?.rationale case final why? when why.isNotEmpty) ...[
            const SizedBox(height: 8),
            Text(why, style: QText.body(size: 13, height: 20, color: QColors.textMuted)),
          ],
          const SizedBox(height: 14),
          for (final m in meals)
            Explainable(
              id: 'plan_meal_${m.id}',
              explanation: mealExplanation(m),
              child: _MealCard(state: state, meal: m),
            ),
        ],
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

/// Shown when there is no plan: building, refused, or simply not built yet.
class _PlanEmpty extends StatelessWidget {
  final AppState state;
  const _PlanEmpty({required this.state});

  @override
  Widget build(BuildContext context) {
    final isAr = state.isAr;
    final busy = state.planLoading;

    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        gradient: const LinearGradient(colors: [QColors.cardMid, QColors.cardDeep]),
        border: Border.all(color: QColors.violet.withValues(alpha: 0.35)),
        borderRadius: BorderRadius.circular(QRadii.xl),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            busy
                ? (isAr ? 'بكتب خطة اليوم…' : 'Writing today’s plan…')
                : state.planError ??
                    (isAr
                        ? 'لسه مفيش خطة لليوم. هبنيها على هدفك واللي بتتجنبه.'
                        : 'No plan for today yet. I’ll build it around your target and what you avoid.'),
            style: QText.body(size: 14, height: 22, color: QColors.textHigh),
          ),
          const SizedBox(height: 14),
          QPrimaryButton(
            label: busy
                ? (isAr ? 'ثانية…' : 'One moment…')
                : (isAr ? 'اعملي خطة النهاردة' : 'Build today’s plan'),
            onTap: busy ? null : () => state.ensurePlan(force: true),
            height: 48,
          ),
        ],
      ),
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
    final kcal = mealKcal(meal);

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
          // Only "swap" here: logging a meal is the orb's job now, not a
          // button that pushes the user into another page. And only when the
          // slot actually has an alternative — the gateway may return a meal
          // without one, and a button that swaps a dish for itself is worse
          // than no button.
          if (state.slotHasAlternative(meal.id)) ...[
            const SizedBox(height: 10),
            Row(children: [
              QOutlineButton(label: t.swap, onTap: () => state.toggleSlotSwap(meal.id), height: 34, color: QColors.textMid),
            ]),
          ],
        ],
      ),
    );
  }
}

/// The one place notification permission is asked: after the plan is on
/// screen, with the reason stated, as the blueprint has it. "No" is zero a
/// day, not a prompt again next week.
class _NudgePrompt extends StatelessWidget {
  final AppState state;
  const _NudgePrompt({required this.state});

  @override
  Widget build(BuildContext context) {
    final isAr = state.isAr;
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: QColors.violet.withValues(alpha: 0.10),
        border: Border.all(color: QColors.violet.withValues(alpha: 0.35)),
        borderRadius: BorderRadius.circular(QRadii.xl),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            isAr ? 'قمر يسأل في مواعيد أكلك' : 'Qamar asks at your meal times',
            style: QText.body(size: 15, weight: FontWeight.w600, color: QColors.textHigh),
          ),
          const SizedBox(height: 6),
          Text(
            isAr
                ? 'مرتين في اليوم، بصوت قمر: «الغدا إيه النهاردة؟» — مفيش «متنساش تسجّل». تقدر تقللها لصفر من «حسابي» في أي وقت. أول أسبوعين بس؛ بعدها بتبقى عارف لوحدك.'
                : 'Twice a day, in Qamar’s voice: “What’s for lunch today?” — never “don’t forget to log”. Lower it to zero any time from Me. Only for the first two weeks; after that you’ll know on your own.',
            style: QText.body(size: 13, height: 20, color: QColors.textMid),
          ),
          const SizedBox(height: 12),
          QPrimaryButton(
            label: isAr ? 'اسمح بالأسئلة' : 'Allow the questions',
            height: 44,
            onTap: () { state.allowNudges(); },
          ),
          const SizedBox(height: 4),
          Center(
            child: TextButton(
              onPressed: state.declineNudges,
              child: Text(isAr ? 'لا، شكراً' : 'No, thanks', style: QText.body(size: 13, color: QColors.textMuted)),
            ),
          ),
        ],
      ),
    );
  }
}
