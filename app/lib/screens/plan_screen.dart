import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../l10n/words.dart';
import '../models/plan.dart';
import '../models/problem.dart';
import '../state/app_state.dart';
import '../theme/app_theme.dart';
import '../theme/colors.dart';
import '../theme/icons.dart';
import '../theme/layout.dart';
import '../theme/motion.dart';
import '../theme/text_styles.dart';
import '../widgets/common.dart';
import '../widgets/explain.dart';
import '../widgets/kit.dart';

/// The day's meals, generated for this person (the kit's Diets page): the
/// day's total on its lavender card, then each meal plainly on its own card
/// under a pastel band naming the slot — what goes on the plate, one tap to
/// swap it — and one tap to shop the lot.
///
/// The plan is the one the assistant built from their own numbers; when
/// there isn't one it says so and offers to build it, since an empty plan is
/// recoverable and a plausible wrong one is not.
class PlanScreen extends StatefulWidget {
  const PlanScreen({super.key});

  /// A meal's swap, and "Shop this plan"'s button, for tests.
  static Key swapKey(String slotId) => ValueKey('plan-swap-$slotId');
  static const shopKey = ValueKey('plan-shop');

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
    // A tab's page: its name, and no way back (the tab bar is the way).
    final title = QPageTitle(title: state.t.plan, isAr: state.isAr);

    // No plan yet, or one that could not be written: the state sits in the
    // middle of the free space under the title, not stuck to its top with
    // the rest of the screen empty below (O10).
    if (!state.hasPlan) {
      return CustomScrollView(
        slivers: [
          SliverPadding(
            padding: const EdgeInsets.fromLTRB(20, QLayout.pageTop, 20, 0),
            sliver: SliverToBoxAdapter(child: title),
          ),
          SliverFillRemaining(
            hasScrollBody: false,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(20, 20, 20, QLayout.pageBottom),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Expanded(child: QStateArea(child: _PlanEmpty(state: state))),
                  // On the general-guidance route there is no plan for a
                  // changed day to rewrite, so nothing offers to.
                  if (!state.generalGuidance) ...[
                    const SizedBox(height: 16),
                    _DayChanged(state: state),
                  ],
                ],
              ),
            ),
          ),
        ],
      );
    }

    final meals = state.planMeals();
    final why = state.plan?.rationale;
    final isAr = state.isAr;
    return ListView(
      padding: const EdgeInsets.fromLTRB(20, QLayout.pageTop, 20, QLayout.pageBottom),
      children: [
        title,
        const SizedBox(height: 16),
        // The kit's lavender card over its list: the day, its total against
        // the target, and why it is built the way it is.
        PastelCard(
          color: QColors.lavender,
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(isAr ? 'خطة النهارده' : 'Today’s plan', style: QText.body(size: 18, weight: FontWeight.w600, color: QColors.onPastel)),
            const SizedBox(height: 4),
            _DayTotal(state: state, kcal: meals.fold(0, (sum, m) => sum + mealKcal(m))),
            if (why != null && why.isNotEmpty) ...[
              const SizedBox(height: 6),
              Text(why, style: QText.body(size: 15, color: QColors.onPastelSecondary)),
            ],
          ]),
        ),
        const SizedBox(height: 16),
        // A rewrite that did not happen (the plan's cap, a failure, a
        // fasting switch it could not follow) is said above the plan it
        // left in place, never only where it was asked (O10).
        if (state.planProblem case final problem? when !state.planLoading) ...[
          QStateCard(problem: problem),
          const SizedBox(height: 14),
        ],
        if (state.nudgePromptDue) ...[
          _NudgePrompt(state: state),
          const SizedBox(height: 14),
        ],
        QSectionTitle(isAr ? 'الوجبات' : 'Meals', isAr: isAr),
        for (final m in meals) ...[
          _MealCard(state: state, meal: m),
          const SizedBox(height: 14),
        ],
        if (state.canShopPlan) ...[
          _ShopCard(state: state),
          const SizedBox(height: 14),
        ],
        const SizedBox(height: 6),
        _DayChanged(state: state),
      ],
    );
  }
}

/// How far an [Explainable] insets what it holds: its 4 points of padding and
/// its hairline, drawn when the orb hovers.
const _explainInset = 5.0;

/// The day's total on the lavender card, against the target.
class _DayTotal extends StatelessWidget {
  final AppState state;
  final int kcal;
  const _DayTotal({required this.state, required this.kcal});

  @override
  Widget build(BuildContext context) {
    final isAr = state.isAr;
    final diff = kcal - state.target().kcal;
    final vsTarget = diff == 0
        ? (isAr ? 'على هدفك بالظبط' : 'right on your target')
        : diff < 0
            ? (isAr ? 'أقل من هدفك بـ ${state.iso('${-diff}')}' : '${-diff} under your target')
            : (isAr ? 'أعلى من هدفك بـ ${state.iso('$diff')}' : '$diff over your target');
    // The explainable's inset hangs outside the line, so the figure starts
    // at the page's edge, as everything under the title does.
    return Transform.translate(
      offset: Offset(isAr ? _explainInset : -_explainInset, 0),
      child: Explainable(
        id: 'plan_total',
        child: Wrap(
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            ExplainMark(
              child: Text(isAr ? '${state.iso('$kcal')} سعر' : '$kcal kcal', style: QText.number(size: 15, weight: FontWeight.w600, color: QColors.onPastel, ar: isAr)),
            ),
            // Arabic takes its own comma: a "·" there reads as a zero.
            Text(isAr ? '، $vsTarget' : ' · $vsTarget', style: QText.body(size: 15, color: QColors.onPastelSecondary)),
          ],
        ),
      ),
    );
  }
}

/// One meal (the kit's diet card): a pastel band with the slot, its glyph
/// and its figure where the kit has its photo; under it what, what goes on
/// the plate, and the one tap to swap it.
class _MealCard extends StatelessWidget {
  final AppState state;
  final PlanMeal meal;
  const _MealCard({required this.state, required this.meal});

  /// Each slot's pastel and glyph: the morning's lime and sunrise, midday's
  /// mint and sun, the evening's lavender and moon; the rest coral.
  static ({Color color, IconData icon}) lookOf(String id) => switch (id) {
        'breakfast' || 'suhoor' => (color: QColors.lime, icon: QIcons.sunrise),
        'lunch' => (color: QColors.mint, icon: QIcons.sunset),
        'dinner' || 'iftar' => (color: QColors.lavender, icon: QIcons.moon),
        _ => (color: QColors.coral, icon: QIcons.plan),
      };

  @override
  Widget build(BuildContext context) {
    final isAr = state.isAr;
    final kcal = mealKcal(meal);
    final name = isAr ? meal.nameAr : meal.nameEn;
    final note = isAr ? meal.noteAr : meal.noteEn;
    final swapped = state.isSlotSwapped(meal.id);
    final still = MediaQuery.disableAnimationsOf(context);

    final look = lookOf(meal.id);
    final content = Column(
      key: ValueKey('${meal.id}:$name'),
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(name, style: QText.body(size: 17, weight: FontWeight.w600, color: QColors.ink)),
        if (note.isNotEmpty) ...[
          const SizedBox(height: 2),
          Text(note, style: QText.body(size: 15, color: QColors.inkSecondary)),
        ],
        if (meal.portions.isNotEmpty) ...[
          const SizedBox(height: 10),
          const Divider(color: QColors.hairline, height: 1, thickness: 1),
          const SizedBox(height: 6),
          // What goes on the plate, and how much: the portions a plan is
          // only actionable with. Their calories are the meal's, above, and
          // the orb explains the split.
          for (final p in meal.portions)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 4),
              child: Row(children: [
                Expanded(child: Text(isAr ? p.ar : p.en, style: QText.body(size: 15, color: QColors.ink))),
                const SizedBox(width: 12),
                Text(isAr ? state.digits(p.amountAr) : p.amountEn, style: QText.body(size: 15, color: QColors.inkSecondary)),
              ]),
            ),
        ],
      ],
    );

    return Container(
      clipBehavior: Clip.antiAlias,
      decoration: QDecor.card(),
      // The whole meal is what the orb explains: dropped on it, the portions
      // and their calories.
      child: Explainable(
        id: 'plan_meal_${meal.id}',
        explanation: mealExplanation(meal, iso: state.iso, digits: state.digits),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Container(
              color: look.color,
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
              // A pastel, so the dotted mark on the figure is black.
              child: DefaultTextStyle.merge(style: const TextStyle(color: QColors.onPastel), child: Row(children: [
                PastelGlyph(look.icon, size: 36),
                const SizedBox(width: 10),
                Expanded(child: Text(isAr ? meal.slotAr : meal.slotEn, style: QText.body(size: 18, weight: FontWeight.w600, color: QColors.onPastel))),
                ExplainMark(
                  child: Text(isAr ? '${state.iso('$kcal')} سعر' : '$kcal kcal', style: QText.number(size: 15, weight: FontWeight.w600, color: QColors.onPastel, ar: isAr)),
                ),
              ])),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 14),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
            // A swap changes the meal in place: the new one fades in where the
            // old one was, and the card takes its size at once, so nothing
            // grows while the words change.
            AnimatedSwitcher(
              duration: Duration(milliseconds: still ? 150 : 200),
              switchInCurve: Curves.easeOutCubic,
              switchOutCurve: Curves.easeOutCubic,
              layoutBuilder: (current, previous) => Stack(
                alignment: AlignmentDirectional.topStart,
                children: [
                  for (final p in previous) Positioned(top: 0, left: 0, right: 0, child: p),
                  if (current != null) current,
                ],
              ),
              child: content,
            ),
            // Only when the slot really has somewhere else to go: a button
            // that swaps a dish for itself is worse than no button. Logging
            // the meal is the orb's job, not a button here.
            if (state.slotHasAlternative(meal.id)) ...[
              const SizedBox(height: 12),
              QOutlineButton(
                key: PlanScreen.swapKey(meal.id),
                icon: QIcons.swap,
                label: swapped ? (isAr ? 'رجّعها' : 'Swap back') : state.t.swap,
                height: 36,
                onTap: () {
                  HapticFeedback.selectionClick();
                  state.toggleSlotSwap(meal.id);
                },
              ),
            ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// "Day changed?", and the way to say so: the conversation rewrites the plan.
class _DayChanged extends StatelessWidget {
  final AppState state;
  const _DayChanged({required this.state});

  @override
  Widget build(BuildContext context) {
    final t = state.t;
    return Row(children: [
      Expanded(child: Text(t.dayChanged, style: QText.body(size: 15, color: QColors.inkSecondary))),
      const SizedBox(width: 12),
      QOutlineButton(label: t.adjustRoute, onTap: state.openChat, height: 36),
    ]);
  }
}

/// Shown when there is no plan: building it, refused, the general-guidance
/// route, or simply not built yet.
class _PlanEmpty extends StatelessWidget {
  final AppState state;
  const _PlanEmpty({required this.state});

  @override
  Widget build(BuildContext context) {
    final isAr = state.isAr;
    final busy = state.planLoading;

    // No target on the general-guidance route, so no plan: the note says
    // why, with no button, since a plan could only be refused.
    if (state.generalGuidance) {
      return Container(
        padding: const EdgeInsets.all(20),
        decoration: QDecor.card(),
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          const Padding(padding: EdgeInsets.only(top: 1), child: QIcon(QIcons.safety, size: 20, color: QColors.ink)),
          const SizedBox(width: 12),
          Expanded(child: Text(state.generalGuidancePlanNote, style: QText.body(size: 17, color: QColors.ink))),
        ]),
      );
    }

    // Writing: a breathing dot and what is happening, in words.
    if (busy) {
      return Container(
        padding: const EdgeInsets.all(20),
        decoration: QDecor.card(),
        child: Row(children: [
          const _BreathingDot(),
          const SizedBox(width: 12),
          Expanded(child: Text(isAr ? 'بكتب خطة النهارده…' : 'Writing today’s plan…', style: QText.body(size: 17, color: QColors.ink))),
        ]),
      );
    }

    // A failed plan says what happened and offers the next step as its
    // button ("Try again", "Finish the questions"…), in place of the build
    // button (O10).
    final problem = state.planProblem;
    if (problem != null) return QStateCard(problem: problem);

    // Nothing written yet, and nothing wrong: an empty state, with the way
    // on as its button.
    return QStateCard(
      problem: Problem(
        what: isAr ? 'لسه مفيش خطة لليوم.' : 'No plan for today yet.',
        why: isAr ? 'هبنيها على هدفك واللي بتتجنبه.' : 'I’ll build it around your target and what you avoid.',
        action: ProblemAction(isAr ? 'اعملي خطة النهاردة' : 'Build today’s plan', () => state.ensurePlan(force: true)),
        kind: ProblemKind.empty,
      ),
    );
  }
}

/// Waiting, said with light rather than a spinner: a dot that breathes
/// between full and half brightness every 2.4 seconds, and holds still
/// with reduce-motion on.
class _BreathingDot extends StatefulWidget {
  const _BreathingDot();

  @override
  State<_BreathingDot> createState() => _BreathingDotState();
}

class _BreathingDotState extends State<_BreathingDot> with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(vsync: this, duration: QMotion.ring);

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (MediaQuery.disableAnimationsOf(context)) {
      _c.stop();
      _c.value = 0;
    } else if (!_c.isAnimating) {
      _c.repeat();
    }
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => RepaintBoundary(
        child: AnimatedBuilder(
          animation: _c,
          builder: (context, _) => Opacity(
            opacity: 0.75 + 0.25 * math.cos(2 * math.pi * _c.value),
            child: const SizedBox.square(dimension: 10, child: DecoratedBox(decoration: BoxDecoration(color: QColors.ink, shape: BoxShape.circle))),
          ),
        ),
      );
}

/// The one place notification permission is asked: after the plan is on
/// screen, with the reason in a sentence. "No" is zero a day, not a prompt
/// again next week. Its answer is not the screen's one thing to do, so both
/// ways are quiet.
class _NudgePrompt extends StatelessWidget {
  final AppState state;
  const _NudgePrompt({required this.state});

  @override
  Widget build(BuildContext context) {
    final isAr = state.isAr;
    // The question on the kit's mint, its two answers black and quiet.
    return PastelCard(
      color: QColors.mint,
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(children: [
            const PastelGlyph(QIcons.bell, size: 36),
            const SizedBox(width: 10),
            Expanded(
              child: Text(isAr ? 'أسألك في مواعيد أكلك؟' : 'Shall I ask at your meal times?', style: QText.body(size: 17, weight: FontWeight.w600, color: QColors.onPastel)),
            ),
          ]),
          const SizedBox(height: 8),
          Text(
            isAr
                ? 'مرتين في اليوم، زي «الغدا إيه النهارده؟»، أول أسبوعين بس. تغيّرها من «حسابي» في أي وقت.'
                : 'Twice a day, like “What’s for lunch today?”, for your first two weeks. Change it any time in Me.',
            style: QText.body(size: 15, color: QColors.onPastelSecondary),
          ),
          const SizedBox(height: 8),
          Row(children: [
            QPastelButton(label: isAr ? 'اسمح' : 'Allow', height: 36, onTap: state.allowNudges),
            const SizedBox(width: 8),
            QTapArea(
              onTap: state.declineNudges,
              builder: (context, pressed) => Padding(
                padding: const EdgeInsets.symmetric(horizontal: 12),
                child: Text(isAr ? 'لا، شكراً' : 'No, thanks', style: QText.body(size: 15, weight: FontWeight.w600, color: pressed ? QColors.onPastelSecondary : QColors.onPastel)),
              ),
            ),
          ]),
        ],
      ),
    );
  }
}

/// The plan's portions, counted as the basket counts them: صنف واحد،
/// صنفين، ٣ أصناف، ١١ صنف.
const _item = Counted(en: 'item', enPlural: 'items', arOne: 'صنف واحد', arTwo: 'صنفين', arFew: 'أصناف', arMany: 'صنف');

/// Shop this plan: the plan's portions as a basket at the signed partner,
/// in one tap. Only when a partner is configured; the commission is said
/// out loud, under the button.
class _ShopCard extends StatelessWidget {
  final AppState state;
  const _ShopCard({required this.state});

  @override
  Widget build(BuildContext context) {
    final isAr = state.isAr;
    final partner = state.groceryPartner.name;
    final items = _item.of(state.basket.count, ar: isAr, iso: state.iso);
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: QDecor.card(),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(children: [
            const QIcon(QIcons.shop, size: 22, color: QColors.ink),
            const SizedBox(width: 8),
            Expanded(child: Text(isAr ? 'اشتري خطة النهارده' : 'Shop this plan', style: QText.body(size: 17, weight: FontWeight.w600, color: QColors.ink))),
          ]),
          const SizedBox(height: 6),
          Text(
            isAr ? '$items من أكل النهارده، جاهزين في سلة $partner.' : '$items from today’s meals, ready in $partner’s basket.',
            style: QText.body(size: 15, color: QColors.inkSecondary),
          ),
          const SizedBox(height: 16),
          // The screen's one white button, unless a problem's card above the
          // plan has the one thing to do; then shopping steps back.
          if (state.planProblem != null && !state.planLoading)
            QOutlineButton(
              key: PlanScreen.shopKey,
              icon: QIcons.shop,
              label: isAr ? 'اطلب من $partner' : 'Shop at $partner',
              onTap: () => state.shopThisPlan(),
            )
          else
            QPrimaryButton(
              key: PlanScreen.shopKey,
              label: isAr ? 'اطلب من $partner' : 'Shop at $partner',
              onTap: () => state.shopThisPlan(),
            ),
          if (state.shopNotice case final notice?) ...[
            const SizedBox(height: 10),
            Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              const Padding(padding: EdgeInsets.only(top: 1), child: QIcon(QIcons.error, size: 16, color: QColors.ink)),
              const SizedBox(width: 8),
              Expanded(child: Text(notice, style: QText.body(size: 13, color: QColors.ink))),
            ]),
          ],
          const SizedBox(height: 10),
          Text(
            isAr ? 'قمر بياخد عمولة صغيرة من $partner، والخطة عمرها ما بتتغيّر عشانها.' : 'Qamar earns a small commission from $partner. The plan never changes for it.',
            style: QText.body(size: 12, color: QColors.inkTertiary),
          ),
        ],
      ),
    );
  }
}
