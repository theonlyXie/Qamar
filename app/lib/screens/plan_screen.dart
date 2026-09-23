import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/plan.dart';
import '../models/problem.dart';
import '../state/app_state.dart';
import '../theme/app_theme.dart';
import '../theme/colors.dart';
import '../theme/layout.dart';
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

    final header = <Widget>[
      Row(children: [
        QBackButton(onTap: state.back, isAr: state.isAr),
        const SizedBox(width: 6),
        Expanded(child: Text(t.plan, style: QText.display(size: 30, ar: QText.arabic(t.plan), color: QColors.textPrimary))),
      ]),
      const SizedBox(height: 4),
      Text(t.planSub, style: QText.body(size: 14, height: 22, color: QColors.textMuted)),
      const SizedBox(height: 10),
    ];

    // No plan yet, or one that could not be written: the state sits in the
    // middle of the free space under the header, not stuck to its top with
    // the rest of the screen empty below (O10).
    if (!state.hasPlan) {
      return CustomScrollView(
        slivers: [
          SliverPadding(
            padding: const EdgeInsets.fromLTRB(20, QLayout.pageTop, 20, 0),
            sliver: SliverList(delegate: SliverChildListDelegate(header)),
          ),
          SliverFillRemaining(
            hasScrollBody: false,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(20, 0, 20, QLayout.pageBottom),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Expanded(child: QStateArea(child: _PlanEmpty(state: state))),
                  const SizedBox(height: 14),
                  _DayChanged(state: state),
                ],
              ),
            ),
          ),
        ],
      );
    }

    return ListView(
      padding: const EdgeInsets.fromLTRB(20, QLayout.pageTop, 20, QLayout.pageBottom),
      children: [
        ...header,
        ...[
          // A rewrite that did not happen (the plan's cap, a failure, a
          // fasting switch it could not follow) is said above the plan it
          // left in place, never only where it was asked (O10).
          if (state.planProblem case final problem? when !state.planLoading) ...[
            QStateCard(problem: problem),
            const SizedBox(height: 10),
          ],
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
              explanation: mealExplanation(m, iso: state.iso, digits: state.digits),
              child: _MealCard(state: state, meal: m),
            ),
          if (state.canShopPlan) ...[
            _ShopCard(state: state),
            const SizedBox(height: 14),
          ],
        ],
        _DayChanged(state: state),
      ],
    );
  }
}

/// "Day changed?" and the way to say so: the conversation adjusts the route.
class _DayChanged extends StatelessWidget {
  final AppState state;
  const _DayChanged({required this.state});

  @override
  Widget build(BuildContext context) {
    final t = state.t;
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 10),
      decoration: BoxDecoration(
        color: QColors.violet.withValues(alpha: 0.1),
        border: Border.all(color: QColors.violet.withValues(alpha: 0.4)),
        borderRadius: BorderRadius.circular(QRadii.xl),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(t.dayChanged, style: QText.body(size: 15, weight: FontWeight.w500, color: QColors.textPrimary)),
          const SizedBox(height: 4),
          // Drawn as a 40pt pill, touched across 48 (O11).
          QTapArea(
            onTap: state.openChat,
            builder: (context, pressed) => AnimatedOpacity(
              opacity: pressed ? 0.82 : 1,
              duration: const Duration(milliseconds: 90),
              child: Container(
                height: 40,
                padding: const EdgeInsets.symmetric(horizontal: 18),
                alignment: Alignment.center,
                decoration: const BoxDecoration(gradient: QColors.brandGradient, borderRadius: BorderRadius.all(Radius.circular(QRadii.pill))),
                child: Text(t.adjustRoute, style: QText.body(size: 13, weight: FontWeight.w600, color: QColors.onAccent)),
              ),
            ),
          ),
        ],
      ),
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

    // A failed plan says what happened and offers the next step as its
    // button ("Try again", "Finish the questions"…), in place of the build
    // button (O10).
    final problem = state.planProblem;
    if (problem != null && !busy && !state.generalGuidance) return QStateCard(problem: problem);

    // Nothing written yet, and nothing wrong: an empty state, with the way
    // on as its button. The same two sentences as before, as what and why.
    if (!busy && !state.generalGuidance) {
      return QStateCard(
        problem: Problem(
          what: isAr ? 'لسه مفيش خطة لليوم.' : 'No plan for today yet.',
          why: isAr ? 'هبنيها على هدفك واللي بتتجنبه.' : 'I’ll build it around your target and what you avoid.',
          action: ProblemAction(isAr ? 'اعملي خطة النهاردة' : 'Build today’s plan', () => state.ensurePlan(force: true)),
          kind: ProblemKind.empty,
        ),
      );
    }

    // Writing, or the general-guidance note (no button: it could only be
    // refused).
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        gradient: const LinearGradient(colors: [QColors.cardMid, QColors.cardDeep]),
        border: Border.all(color: QColors.borderSoft),
        borderRadius: BorderRadius.circular(QRadii.xl),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            state.generalGuidance ? state.generalGuidancePlanNote : (isAr ? 'بكتب خطة اليوم…' : 'Writing today’s plan…'),
            style: QText.body(size: 14, height: 22, color: QColors.textHigh),
          ),
          if (busy && !state.generalGuidance) ...[
            const SizedBox(height: 14),
            QPrimaryButton(label: isAr ? 'ثانية…' : 'One moment…', onTap: null, height: 48),
          ],
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
          ExplainMark(
            child: Text(isAr ? '${state.iso('$kcal')} سعر' : '$kcal kcal',
                style: QText.number(size: 15, weight: FontWeight.w600, color: QColors.cyan)),
          ),
          const SizedBox(width: 8),
          Text('· $vsTarget', style: QText.body(size: 11, color: QColors.textMuted)),
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
                style: QText.body(size: 11, weight: FontWeight.w500, color: QColors.textMuted)),
            ExplainMark(
              child: Text(isAr ? '${state.iso('$kcal')} سعر' : '$kcal kcal',
                  style: QText.number(size: 12, weight: FontWeight.w600, color: QColors.cyan)),
            ),
          ]),
          Text(isAr ? meal.nameAr : meal.nameEn,
              style: QText.body(size: 15, weight: FontWeight.w600, color: QColors.textPrimary)),
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
                        style: QText.body(size: 11, weight: FontWeight.w500, color: QColors.textMuted)),
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

/// Shop this plan: the plan's portions as a basket at the signed partner.
/// Only when a partner is configured; the commission is said out loud.
class _ShopCard extends StatelessWidget {
  final AppState state;
  const _ShopCard({required this.state});

  @override
  Widget build(BuildContext context) {
    final isAr = state.isAr;
    final basket = state.basket;
    final partner = state.groceryPartner;
    final shown = basket.lines.take(4).toList();
    final more = basket.count - shown.length;
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: QColors.green.withValues(alpha: 0.07),
        border: Border.all(color: QColors.green.withValues(alpha: 0.3)),
        borderRadius: BorderRadius.circular(QRadii.xl),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(children: [
            const Icon(Icons.shopping_basket_outlined, size: 16, color: QColors.green),
            const SizedBox(width: 6),
            Text(isAr ? 'اشتري خطة النهاردة' : 'Shop this plan',
                style: QText.body(size: 15, weight: FontWeight.w600, color: QColors.textHigh)),
          ]),
          const SizedBox(height: 6),
          Text(
            isAr
                ? '${state.iso('${basket.count}')} صنف من أطباق النهاردة، في سلة ${partner.name}. قمر بياخد عمولة صغيرة من الشريك؛ الخطة نفسها مش بتتغير عشانها.'
                : '${basket.count} item${basket.count == 1 ? '' : 's'} from today’s dishes, into ${partner.name}’s basket. Qamar earns a small commission from the partner; the plan itself never changes for it.',
            style: QText.body(size: 12, height: 18, color: QColors.textMuted),
          ),
          const SizedBox(height: 10),
          for (final l in shown)
            Padding(
              padding: const EdgeInsets.only(bottom: 4),
              child: Row(children: [
                Expanded(child: Text(l.name(ar: isAr), style: QText.body(size: 13, color: QColors.textHigh))),
                Text(l.amount(ar: isAr), style: QText.body(size: 12, color: QColors.textMuted)),
              ]),
            ),
          if (more > 0)
            Text(isAr ? '+${state.iso('$more')} كمان' : '+$more more', style: QText.body(size: 12, color: QColors.textMuted)),
          const SizedBox(height: 10),
          QPrimaryButton(
            label: isAr ? 'افتح السلة في ${partner.name}' : 'Open the basket at ${partner.name}',
            height: 44,
            onTap: () { state.shopThisPlan(); },
          ),
          if (state.shopNotice != null) ...[
            const SizedBox(height: 8),
            Text(state.shopNotice!, style: QText.body(size: 12, color: QColors.amberSoft)),
          ],
        ],
      ),
    );
  }
}
