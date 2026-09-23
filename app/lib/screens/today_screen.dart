import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../models/plan.dart';
import '../models/reply.dart';
import '../models/streak.dart';
import '../models/water.dart';
import '../models/ramadan.dart';
import '../state/app_state.dart';
import '../widgets/billing_moment_card.dart';
import '../state/today_focus.dart';
import '../theme/app_theme.dart';
import '../theme/colors.dart';
import '../theme/layout.dart';
import '../theme/text_styles.dart';
import '../widgets/common.dart';
import '../widgets/explain.dart';
import '../widgets/general_guidance_card.dart';
import '../widgets/moon.dart';
import '../widgets/orb_gesture_guide.dart';
import '../widgets/quest_card.dart';
import '../widgets/week_glance_card.dart';

class TodayScreen extends StatefulWidget {
  const TodayScreen({super.key});

  /// Keys the layout contract test finds zones and cards by.
  static Key zoneKey(TodayZone zone) => ValueKey('today-zone-${zone.name}');
  static Key cardKey(TodayCard card) => ValueKey('today-card-${card.name}');
  static const guideKey = ValueKey('today-guide-below');

  /// The calorie card's one line saying these are estimates.
  static const estimateKey = ValueKey('today-estimate');

  @override
  State<TodayScreen> createState() => _TodayScreenState();
}

class _TodayScreenState extends State<TodayScreen> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final state = context.read<AppState>();
      state.ensurePlan();
      // The quest held may have expired, and the next gap is then chosen.
      state.refreshQuest();
    });
  }

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    final due = todayCardsDue(state);
    final nextMeal = state.nextMeal();
    // The gestures card leaves the slot at the first hold; until all three
    // are learned (or it is put away) it waits below the fold.
    final guideBelow = !state.orbTutorialDone && !state.holdTutorialDue;

    // The zones, in the order the layout contract fixes (O15). A zone with
    // nothing to show takes no space, so the screen closes up.
    final zones = <TodayZone, Widget?>{
      TodayZone.header: _Header(state: state),
      TodayZone.qamar: QamarCard(state: state),
      // No target on the general-guidance route, so no numbers: its card
      // takes the slot instead.
      TodayZone.numbers: state.generalGuidance ? null : _NumbersCard(state: state),
      TodayZone.slot: due.isEmpty ? null : _slotCard(state, due.first),
      TodayZone.water: const _WaterCard(),
      TodayZone.runnersUp: (due.length < 2 && !guideBelow)
          ? null
          : Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              for (final (i, card) in due.skip(1).indexed) ...[
                if (i > 0) const SizedBox(height: 14),
                _slotCard(state, card),
              ],
              if (guideBelow) ...[
                if (due.length > 1) const SizedBox(height: 14),
                KeyedSubtree(key: TodayScreen.guideKey, child: OrbGestureGuide(state: state)),
              ],
            ]),
      TodayZone.nextMeal: nextMeal == null ? null : _NextMealCard(state: state, meal: nextMeal),
      TodayZone.activity: state.activitiesToday.isEmpty ? null : _ActivityCard(state: state),
      TodayZone.meals: state.meals.isEmpty ? null : _LoggedMeals(state: state),
    };

    return ListView(
      padding: const EdgeInsets.fromLTRB(20, QLayout.pageTop, 20, QLayout.pageBottom),
      children: [
        for (final zone in TodayZone.values)
          if (zones[zone] case final w?) ...[
            KeyedSubtree(key: TodayScreen.zoneKey(zone), child: w),
            const SizedBox(height: 14),
          ],
      ],
    );
  }

  /// A contender's card, keyed so the layout contract can find it.
  static Widget _slotCard(AppState state, TodayCard card) => KeyedSubtree(
        key: TodayScreen.cardKey(card),
        child: switch (card) {
          TodayCard.safety => GeneralGuidanceCard(state: state),
          TodayCard.tutorial => OrbGestureGuide(state: state),
          TodayCard.billing => BillingMomentCard(state: state),
          TodayCard.fasting => _FastingPrompt(state: state),
          TodayCard.weekCard => WeekGlanceCard(state: state),
          TodayCard.earnedMonth => _EarnedMonthCard(state: state),
          TodayCard.quest => QuestCard(state: state),
        },
      );
}

/// Today's zones, top to bottom: the layout contract (O15).
///
/// Above the fold on a 390x844 phone: the header, Qamar's card with "Log a
/// meal", the numbers, and the one contextual slot ([todayFocus]). Below:
/// water, the cards that lost the slot (the quest among them), the next
/// meal, movement and the meals logged today. Every seat builds inside this order; the
/// contract test (test/today_layout_test.dart) holds it.
enum TodayZone { header, qamar, numbers, slot, water, runnersUp, nextMeal, activity, meals }

/// The greeting, the name, and the two game elements, each a named piece
/// that can be removed: the streak line (seat 3, O4) and the one Su chip
/// (O9). With "Points and streaks" off (showScore) both go and the header
/// closes up.
class _Header extends StatelessWidget {
  final AppState state;
  const _Header({required this.state});

  @override
  Widget build(BuildContext context) {
    final nameOr = state.profile.name.isNotEmpty ? state.profile.name : (state.isAr ? 'يا صاحبي' : 'friend');
    final streak = state.showScore ? streakLineFor(state) : null;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(state.isAr ? 'صباح الخير،' : 'Good morning,', style: QText.body(size: 14, color: QColors.textMuted)),
              Text(nameOr, style: QText.display(size: 30, ar: QText.arabic(nameOr), color: QColors.textPrimary)),
              if (streak != null) TodayStreakLine(text: streak),
            ],
          ),
        ),
        // One Su display on Today, and it opens the wallet (O9). Level
        // lives in the wallet only.
        if (state.showScore) SuChip(state: state),
      ],
    );
  }
}

/// The streak line's words: Qamar's one sentence under the name, from the
/// second day ("Fourth day running." / "رابع يوم ورا بعض.", O4). It shows
/// once today's meal has joined the run, so it never asks anyone to keep
/// anything; with no line the header closes up. See [streakSentence].
String? streakLineFor(AppState state) => streakSentence(state.streak(), ar: state.isAr, iso: state.iso);

/// The streak line, a named piece of the header so it can go whole.
class TodayStreakLine extends StatelessWidget {
  final String text;
  const TodayStreakLine({super.key, required this.text});

  @override
  Widget build(BuildContext context) =>
      Text(text, style: QText.body(size: 14, height: 20, color: QColors.textMid));
}

/// The day's sentence in Qamar's card. What it says is seat 3's (O3, O15):
/// in the morning, before the first log, it is last night's note about the
/// day; otherwise the day's line. [fromNight] says the night note is what
/// is shown, so the card carries its link to the plan.
({String text, bool fromNight}) todaySentenceFor(AppState state) {
  final isAr = state.isAr;
  final logged = state.consumed().kcal > 0;
  final night = state.nightSentence;
  if (!logged && night != null && night.isNotEmpty) return (text: night, fromNight: true);
  return (
    // Once something is logged, the day read in words (O3): the same reading
    // Qamar gives after each meal, so it changes when the day does.
    text: logged
        ? dayLineFor(state.dayNumbers(), ar: isAr, iso: state.iso)
        : (isAr ? 'أهم حاجة النهاردة: تسجّل أول وجبة. الباقي أنا هظبطه معاك.' : 'The one thing today: log your first meal. I’ll handle the rest with you.'),
    fromNight: false,
  );
}

/// Qamar's card (O15): the day's sentence, and under it "Log a meal".
///
/// The button is Today's one primary action and it stays above the fold. It
/// opens the tree already on Log rather than going round it, so using it
/// shows where logging lives. The night note, which was a card of its own,
/// is the sentence here in the morning, with its link to today's plan.
class QamarCard extends StatelessWidget {
  final AppState state;
  const QamarCard({super.key, required this.state});

  /// The "Log a meal" button, for tests.
  static const logKey = ValueKey('today-log-a-meal');

  /// The lock card's free-week offer, for tests.
  static const lockOfferKey = ValueKey('today-lock-offer');

  @override
  Widget build(BuildContext context) {
    final isAr = state.isAr;
    final line = todaySentenceFor(state);
    final locked = state.nightPlanLocked;
    // The first locked card offers the free week once more (O12). It is
    // counted once it has been drawn, not when it is merely possible.
    final offerWeek = locked && line.fromNight && state.lockCardTrialOffer;
    if (offerWeek) WidgetsBinding.instance.addPostFrameCallback((_) => state.recordLockCardOffer());
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: QDecor.card(gradient: const LinearGradient(colors: [QColors.cardMid, QColors.cardDeep]), radius: QRadii.card),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              const QamarMoon(size: 40),
              const SizedBox(width: 12),
              Expanded(
                child: Text(line.text, key: const ValueKey('today-sentence'), style: QText.body(size: 14, height: 21, color: QColors.textHigh)),
              ),
            ],
          ),
          // The night note's way on: today's plan, or where the wall is. A
          // returning line has no plan behind it (plan_kcal 0, 0062), so
          // there is nothing to open and no link.
          if (line.fromNight && (state.nightNote?.planKcal ?? 0) > 0)
            Align(
              alignment: AlignmentDirectional.centerStart,
              child: InkWell(
                key: offerWeek ? lockOfferKey : null,
                borderRadius: BorderRadius.circular(QRadii.control),
                onTap: offerWeek ? state.acceptLockCardTrial : state.openNightNote,
                child: ConstrainedBox(
                  constraints: const BoxConstraints(minHeight: 48),
                  child: Padding(
                    padding: const EdgeInsetsDirectional.only(start: 52, end: 8),
                    child: Row(mainAxisSize: MainAxisSize.min, children: [
                      Icon(offerWeek ? Icons.card_giftcard : (locked ? Icons.lock_outline : Icons.arrow_outward), size: 14, color: locked ? QColors.gold : QColors.textMuted),
                      const SizedBox(width: 6),
                      Flexible(
                        child: Text(
                          offerWeek
                              ? (isAr
                                  ? 'افتح الخطة بأسبوعك المجاني: ${state.iso('${AppState.trialOfferDays}')} أيام، من غير بطاقة'
                                  : 'Open the plan with your free week: ${AppState.trialOfferDays} days, no card')
                              : locked
                                  ? (isAr ? 'الخطة الكاملة في قمر+' : 'The full plan is Qamar+')
                                  : (isAr ? 'افتح خطة النهارده' : 'Open today’s plan'),
                          style: QText.body(size: 12, color: locked ? QColors.gold : QColors.textMuted),
                        ),
                      ),
                    ]),
                  ),
                ),
              ),
            )
          else
            const SizedBox(height: 12),
          QPrimaryButton(key: logKey, label: isAr ? 'سجّل وجبة' : 'Log a meal', onTap: state.openTreeOnLog, height: 48),
        ],
      ),
    );
  }
}

/// The day's numbers: calories left and the three macros.
class _NumbersCard extends StatelessWidget {
  final AppState state;
  const _NumbersCard({required this.state});

  @override
  Widget build(BuildContext context) {
    final t = state.t;
    final tg = state.target();
    final con = state.consumed();
    final remaining = (tg.kcal - con.kcal).clamp(0, 1 << 30);
    double pct(int a, int b) => b == 0 ? 0 : (a / b).clamp(0, 1).toDouble();
    // Within its budget above the fold (O15, <=290pt; about 250 here): the
    // number with its unit under it and the question it raises beside it,
    // the three macros in tight rows, and one line saying these are
    // estimates, in a colour that passes AA.
    return Container(
          padding: const EdgeInsets.fromLTRB(20, 16, 20, 14),
          decoration: QDecor.card(gradient: const LinearGradient(colors: [QColors.cardMid, QColors.cardSlate]), border: QColors.borderStrong, radius: QRadii.card,
              shadow: [BoxShadow(color: QColors.blue.withValues(alpha: 0.12), blurRadius: 40)]),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(crossAxisAlignment: CrossAxisAlignment.center, children: [
                Expanded(
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Explainable(
                      id: 'kcal_remaining',
                      child: ExplainMark(
                        child: ShaderMask(
                          shaderCallback: (r) => QColors.cyanVioletGradient.createShader(r),
                          child: Text(state.digits('$remaining'), style: QText.number(size: 40, height: 46, weight: FontWeight.w600, color: QColors.textPrimary)),
                        ),
                      ),
                    ),
                    Text(t.kcalRemaining, style: QText.body(size: 13, height: 18, weight: FontWeight.w500, color: QColors.textMuted)),
                  ]),
                ),
                const SizedBox(width: 8),
                // Next to the number it explains.
                QOutlineButton(label: t.whyCta, onTap: state.openWhy, height: 30),
              ]),
              const SizedBox(height: 12),
              Explainable(id: 'protein', child: _MacroRow(label: t.protein, text: state.isAr ? '${state.iso('${con.p} / ${tg.protein}')} جم' : '${con.p} / ${tg.protein} g', pct: pct(con.p, tg.protein))),
              const SizedBox(height: 10),
              Explainable(id: 'carbs', child: _MacroRow(label: t.carbs, text: state.isAr ? '${state.iso('${con.c} / ${tg.carbs}')} جم' : '${con.c} / ${tg.carbs} g', pct: pct(con.c, tg.carbs))),
              const SizedBox(height: 10),
              Explainable(id: 'fat', child: _MacroRow(label: t.fat, text: state.isAr ? '${state.iso('${con.f} / ${tg.fat}')} جم' : '${con.f} / ${tg.fat} g', pct: pct(con.f, tg.fat))),
              const SizedBox(height: 12),
              Text(t.estimateNote, key: TodayScreen.estimateKey, maxLines: 1, style: QText.body(size: 12, height: 16, color: QColors.textMuted)),
            ],
          ),
        );
  }
}

/// The next planned meal, once a plan exists for this person.
class _NextMealCard extends StatelessWidget {
  final AppState state;
  final PlanMeal meal;
  const _NextMealCard({required this.state, required this.meal});

  @override
  Widget build(BuildContext context) {
    final t = state.t;
    final nextMeal = meal;
    return Explainable(
            id: 'next_meal',
            explanation: mealExplanation(nextMeal, iso: state.iso, digits: state.digits),
            child: Container(
              padding: const EdgeInsets.all(16),
              decoration: QDecor.card(color: QColors.cardDeep, border: QColors.green.withOpacity(0.4), radius: QRadii.card),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(t.nextMeal, style: QText.body(size: 11, weight: FontWeight.w500, color: QColors.green)),
                  Text(state.isAr ? nextMeal.nameAr : nextMeal.nameEn,
                      style: QText.body(size: 17, weight: FontWeight.w600, color: QColors.textPrimary)),
                  ExplainMark(
                    child: Text(
                      state.isAr
                          ? 'حوالي ${state.iso('${mealKcal(nextMeal)}')} سعر'
                          : 'About ${mealKcal(nextMeal)} kcal',
                      style: QText.body(size: 13, color: QColors.textMuted),
                    ),
                  ),
                  const SizedBox(height: 8),
                  Row(children: [
                    // Only offered when the slot really has somewhere else to go.
                    if (state.slotHasAlternative(nextMeal.id)) ...[
                      QOutlineButton(label: t.swap, onTap: () => state.toggleSlotSwap(nextMeal.id), height: 34, color: QColors.textMid),
                      const SizedBox(width: 8),
                    ],
                    QOutlineButton(label: t.openPlan, onTap: () => state.go(AppScreen.plan), height: 34, color: QColors.textMid),
                  ]),
                ],
              ),
            ),
          );
  }
}

/// The meals logged today.
class _LoggedMeals extends StatelessWidget {
  final AppState state;
  const _LoggedMeals({required this.state});

  @override
  Widget build(BuildContext context) {
    final t = state.t;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
          const SizedBox(height: 4),
          Text(t.loggedToday, style: QText.body(size: 11, weight: FontWeight.w500, color: QColors.textMuted)),
          const SizedBox(height: 8),
          for (final m in state.meals) ...[
            Container(
              margin: const EdgeInsets.only(bottom: 8),
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
              decoration: QDecor.card(color: QColors.cardDeep, border: QColors.borderFaint, radius: QRadii.control),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text(m.name, style: QText.body(size: 15, weight: FontWeight.w600, color: QColors.textPrimary)),
                    Text(m.sub, style: QText.body(size: 12, color: QColors.textMuted)),
                  ]),
                  Text(state.isAr ? '${state.iso('${m.kcal}')} سعر' : '${m.kcal} kcal', style: QText.number(size: 15, weight: FontWeight.w600, color: QColors.cyan)),
                ],
              ),
            ),
          ],
      ],
    );
  }
}

class _WaterCard extends StatelessWidget {
  const _WaterCard();

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    final isAr = state.isAr;
    final w = state.water;
    final litres = WaterStatus.qty(w.litres);
    final left = WaterStatus.qty(w.litresLeft);
    final glasses = WaterStatus.qty(w.glasses);
    final bottles = WaterStatus.qty(w.bottles);

    return Explainable(
      id: 'water',
      child: Container(
        padding: const EdgeInsets.all(20),
        decoration: QDecor.card(
          color: QColors.cardDeep,
          border: QColors.borderFaint,
          radius: QRadii.card,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(isAr ? 'الماء' : 'Water',
                style: QText.body(size: 11, weight: FontWeight.w500, color: QColors.textMuted)),
            const SizedBox(height: 8),
            Row(
              crossAxisAlignment: CrossAxisAlignment.baseline,
              textBaseline: TextBaseline.alphabetic,
              children: [
                ExplainMark(
                  child: ShaderMask(
                    shaderCallback: (r) => QColors.blueCyanGradient.createShader(r),
                    child: Text(
                      isAr ? '${state.iso(litres)} لتر' : '$litres L',
                      style: QText.number(size: 28, weight: FontWeight.w600, color: QColors.textPrimary, ar: isAr),
                    ),
                  ),
                ),
                const Spacer(),
                Text(
                  isAr ? '${state.iso(left)} لتر باقي' : '$left L left',
                  style: QText.body(size: 13, weight: FontWeight.w500, color: QColors.textMuted),
                ),
              ],
            ),
            const SizedBox(height: 6),
            Text(
              isAr
                  ? '${state.iso(glasses)} كوباية  ·  ${state.iso(bottles)} زجاجة'
                  : '$glasses glasses  ·  $bottles bottles',
              style: QText.body(size: 13, color: QColors.textMid),
            ),
            if (state.fasting) ...[
              const SizedBox(height: 8),
              _HydrationLine(state: state),
            ],
            const SizedBox(height: 12),
            ClipRRect(
              borderRadius: BorderRadius.circular(QRadii.pill),
              child: LinearProgressIndicator(
                value: w.progress,
                minHeight: 6,
                backgroundColor: QColors.borderFaint,
                valueColor: const AlwaysStoppedAnimation(QColors.cyan),
              ),
            ),
            const SizedBox(height: 14),
            Row(
              children: [
                Expanded(
                  child: _WaterAdd(
                    label: isAr ? 'كوباية' : 'Glass',
                    onTap: () => state.logWater(WaterUnit.glass),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: _WaterAdd(
                    label: isAr ? 'زجاجة' : 'Bottle',
                    onTap: () => state.logWater(WaterUnit.bottle),
                  ),
                ),
              ],
            ),
            if (!w.isEmpty) ...[
              const SizedBox(height: 4),
              Align(
                alignment: AlignmentDirectional.centerStart,
                child: TextButton(
                  onPressed: state.undoWater,
                  child: Text(
                    isAr ? 'تراجع' : 'Undo',
                    style: QText.body(size: 12, weight: FontWeight.w500, color: QColors.textMuted),
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _WaterAdd extends StatelessWidget {
  final String label;
  final VoidCallback onTap;
  const _WaterAdd({required this.label, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: QLayout.minTap,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(QRadii.control),
          onTap: () {
            HapticFeedback.lightImpact();
            onTap();
          },
          child: Ink(
            decoration: BoxDecoration(
              color: QColors.cyan.withValues(alpha: 0.10),
              border: Border.all(color: QColors.cyan.withValues(alpha: 0.35)),
              borderRadius: BorderRadius.circular(QRadii.control),
            ),
            child: Center(
              child: Text('+  $label',
                  style: QText.body(size: 14, weight: FontWeight.w600, color: QColors.cyan)),
            ),
          ),
        ),
      ),
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
          Text(label, style: QText.body(size: 12, height: 16, weight: FontWeight.w500, color: QColors.textMuted)),
          ExplainMark(child: Text(text, style: QText.body(size: 12, height: 16, weight: FontWeight.w500, color: QColors.textMid))),
        ]),
        const SizedBox(height: 5),
        ClipRRect(
          borderRadius: BorderRadius.circular(QRadii.pill),
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


/// Today's movement, as logged from the ring: what, how long, and an estimate
/// of what it cost. Shown beside the food, never subtracted from it.
class _ActivityCard extends StatelessWidget {
  final AppState state;
  const _ActivityCard({required this.state});

  @override
  Widget build(BuildContext context) {
    final isAr = state.isAr;
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: QDecor.card(color: QColors.cardDeep, border: QColors.borderFaint, radius: QRadii.card),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(children: [
            Expanded(
              child: Text(isAr ? 'حركة النهاردة' : 'Today’s movement',
                  style: QText.body(size: 11, weight: FontWeight.w500, color: QColors.textMuted)),
            ),
            Text(
              isAr
                  ? '${state.iso('${state.activityMinutesToday}')} د · ~${state.iso('${state.activityKcalToday}')} سعرة'
                  : '${state.activityMinutesToday} min · ~${state.activityKcalToday} kcal',
              style: QText.number(size: 12, weight: FontWeight.w600, color: QColors.green),
            ),
          ]),
          const SizedBox(height: 8),
          for (final a in state.activitiesToday)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 3),
              child: Row(children: [
                const Icon(Icons.directions_run, size: 14, color: QColors.green),
                const SizedBox(width: 8),
                Expanded(child: Text(a.label(ar: isAr), style: QText.body(size: 14, color: QColors.textHigh))),
                Text(isAr ? '${state.iso('${a.minutes}')} د' : '${a.minutes} min', style: QText.number(size: 12, color: QColors.textMuted)),
              ]),
            ),
          const SizedBox(height: 6),
          Text(
            isAr ? 'تقدير. بنسجّل الحركة جنب الأكل ومش بنزوّد سعرات عليها.' : 'An estimate. Movement is logged beside the food, not added to its budget.',
            style: QText.body(size: 11, height: 16, color: QColors.textMuted),
          ),
        ],
      ),
    );
  }
}

/// The one question the season asks, once: fasting this year? Yes turns the
/// plan into iftar and suhoor and the water card into windows; no leaves the
/// day as it is. Either way the seventh node stays on the tree in season.
///
/// Answered, and the plan could not be rewritten for the answer (the plan's
/// daily cap, no connection), the slot keeps one line saying so, with the
/// Plan card's way on (O10): where the answer was given, not only on Plan.
class _FastingPrompt extends StatelessWidget {
  final AppState state;
  const _FastingPrompt({required this.state});

  @override
  Widget build(BuildContext context) {
    final isAr = state.isAr;
    if (!state.fastingPromptDue) {
      if (state.fastingNotYet case final n?) {
        return QStateLine(line: n.line, action: n.action, accent: QColors.gold, icon: Icons.nightlight_round);
      }
    }
    final until = state.season.daysUntil(state.clockNow());
    final lead = until == null
        ? (isAr ? 'رمضان كريم.' : 'Ramadan Kareem.')
        : (isAr ? 'رمضان بعد ${state.iso('$until')} ${until == 1 ? 'يوم' : 'أيام'}.' : 'Ramadan is $until ${until == 1 ? 'day' : 'days'} away.');
    // Within the slot's 120 points (O15), in both languages. The answers
    // are drawn 34 tall in a 48-point touch (O11), so the 7 points of touch
    // under each outline are the card's bottom margin, and the 7 above it
    // the gap to the line over them: 8 visible points on every side.
    return Container(
      padding: const EdgeInsets.fromLTRB(14, 8, 14, 1),
      decoration: BoxDecoration(
        color: QColors.gold.withValues(alpha: 0.08),
        border: Border.all(color: QColors.gold.withValues(alpha: 0.32)),
        borderRadius: BorderRadius.circular(QRadii.card),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(children: [
            const Icon(Icons.nightlight_round, size: 14, color: QColors.gold),
            const SizedBox(width: 6),
            Expanded(
              child: Text('$lead ${isAr ? 'صايم السنة دي؟' : 'Fasting this year?'}',
                  style: QText.body(size: 14, height: 21, weight: FontWeight.w600, color: QColors.textHigh)),
            ),
          ]),
          const SizedBox(height: 2),
          Text(
            isAr
                ? 'لو أيوة: الخطة تبقى إفطار وسحور، والمياه على مواعيد الليل. ببلاش للكل.'
                : 'If yes: the plan becomes iftar and suhoor, and water moves to the night’s windows. Free for everyone.',
            style: QText.body(size: 12, height: 18, color: QColors.textMuted),
          ),
          Row(children: [
            QOutlineButton(label: isAr ? 'أيوة، صايم' : 'Yes, fasting', height: 34, color: QColors.gold, onTap: () => state.setFasting(true)),
            const SizedBox(width: 10),
            QOutlineButton(label: isAr ? 'لا' : 'No', height: 34, color: QColors.textMuted, onTap: () => state.setFasting(false)),
          ]),
        ],
      ),
    );
  }
}

/// Where the water goes on a fasting day: the window open now, or the next
/// one, with its glasses. Iftar at sunset, suhoor ending at dawn, both from
/// the sun for Cairo.
class _HydrationLine extends StatelessWidget {
  final AppState state;
  const _HydrationLine({required this.state});

  @override
  Widget build(BuildContext context) {
    final isAr = state.isAr;
    final h = state.hydrationWindows;
    final now = state.clockNow();
    final nowMin = now.hour * 60 + now.minute;
    final open = h.current(nowMin);
    final String text;
    if (open != null) {
      text = isAr
          ? 'دلوقتي: ${open.label(true)} — ${state.iso('${open.glasses}')} كوبايات'
          : 'Now: ${open.label(false)} — ${open.glasses} glasses';
    } else if (h.fastingAt(nowMin)) {
      text = isAr
          ? 'صايم. الإفطار ${state.iso(SunTimes.clock(h.iftarMin))} — ${state.iso('3')} كوبايات على الإفطار، ${state.iso('3')} بعد التراويح، ${state.iso('2')} على السحور.'
          : 'Fasting. Iftar ${SunTimes.clock(h.iftarMin)} — 3 glasses at iftar, 3 after taraweeh, 2 at suhoor.';
    } else {
      text = isAr
          ? 'بين النوافذ. السحور لحد ${state.iso(SunTimes.clock(h.fajrMin))}.'
          : 'Between windows. Suhoor until ${SunTimes.clock(h.fajrMin)}.';
    }
    return Row(children: [
      const Icon(Icons.nightlight_round, size: 13, color: QColors.gold),
      const SizedBox(width: 6),
      Expanded(child: Text(text, style: QText.body(size: 12, height: 17, color: QColors.gold))),
    ]);
  }
}



/// The earned month: progress while it is being earned, the grant when it
/// lands. Only for members — it is their first month being rewarded.
class _EarnedMonthCard extends StatelessWidget {
  final AppState state;
  const _EarnedMonthCard({required this.state});

  @override
  Widget build(BuildContext context) {
    final isAr = state.isAr;
    final e = state.earnedMonth;
    final granted = state.earnedMonthJustGranted;
    final until = state.plusUntil?.toLocal();
    final when = until == null ? '' : state.iso('${until.day}/${until.month}');
    final title = granted
        ? (isAr ? 'شهر علينا' : 'A month on us')
        : (isAr ? 'شهر علينا — قيد الكسب' : 'A month on us — being earned');
    final body = granted
        ? (isAr ? 'سجّلت ${state.iso('${e.loggedDays}')} يوم من أول ${state.iso('${e.windowDays}')}. قمر+ شغال لحد $when.' : 'You logged ${e.loggedDays} of your first ${e.windowDays} days. Qamar+ runs until $when.')
        : (isAr
            ? 'سجّلت ${state.iso('${e.loggedDays}')} يوم من ${state.iso('${e.needed}')} · باقي ${state.iso('${e.daysLeft}')} يوم'
            : '${e.loggedDays} of ${e.needed} days logged · ${e.daysLeft} days left');
    final note = granted
        ? (isAr ? 'اضغط للإخفاء' : 'Tap to dismiss')
        : (isAr ? 'سجّل ${state.iso('${e.needed}')} يوم من أول ${state.iso('${e.windowDays}')} والشهر اللي بعده علينا.' : 'Log ${e.needed} of your first ${e.windowDays} days and the next month is free.');
    final pct = e.needed == 0 ? 1.0 : (e.loggedDays / e.needed).clamp(0.0, 1.0);
    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(QRadii.card),
        onTap: granted ? state.dismissEarnedMonthCard : null,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 13),
          decoration: BoxDecoration(
            color: QColors.green.withValues(alpha: 0.07),
            border: Border.all(color: QColors.green.withValues(alpha: 0.3)),
            borderRadius: BorderRadius.circular(QRadii.card),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(children: [
                const Icon(Icons.workspace_premium_outlined, size: 15, color: QColors.green),
                const SizedBox(width: 6),
                Text(title, style: QText.body(size: 12, weight: FontWeight.w600, color: QColors.green)),
              ]),
              const SizedBox(height: 6),
              Text(body, style: QText.body(size: 14, height: 21, color: QColors.textHigh)),
              if (!granted) ...[
                const SizedBox(height: 10),
                ClipRRect(
                  borderRadius: BorderRadius.circular(QRadii.pill),
                  child: LinearProgressIndicator(
                    value: pct,
                    minHeight: 5,
                    backgroundColor: QColors.green.withValues(alpha: 0.15),
                    valueColor: const AlwaysStoppedAnimation<Color>(QColors.green),
                  ),
                ),
              ],
              const SizedBox(height: 6),
              Text(note, style: QText.body(size: 12, height: 18, color: QColors.textMuted)),
            ],
          ),
        ),
      ),
    );
  }
}


/// Today's one Su display: a coin and the balance, which opens the wallet
/// (O9); at a zero balance the coin alone. The chip draws small; its touch
/// area is the full 48 points.
class SuChip extends StatelessWidget {
  /// The balance's number, and at zero the mark under the coin, for tests.
  static const amountKey = ValueKey('su-chip-amount');
  static const coinMarkKey = ValueKey('su-chip-coin-mark');

  final AppState state;
  const SuChip({super.key, required this.state});

  @override
  Widget build(BuildContext context) {
    // At zero the coin stands alone, with no numeral: the Arabic zero is a
    // dot, and over the mark's dotted line it read as ":"; and a counter at
    // zero is a deficit on the first screen. The chip still opens the wallet,
    // can still be explained — so the dotted mark, which every explainable
    // value carries (explain_mark_test), sits under the coin instead — and
    // still says its balance to a screen reader. The first credit brings the
    // number.
    final zero = state.suAvailable <= 0;
    // Its own node, with the wallet as its tap: without container it merged
    // into the header ("Good morning, friend, Su Points: 0" as one button),
    // and excludeSemantics dropped the InkWell's tap with the rest.
    return Semantics(
      container: true,
      button: true,
      label: '${state.t.suName}: ${state.formatSu(state.suAvailable)}',
      onTap: state.openWallet,
      excludeSemantics: true,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(QRadii.pill),
          onTap: state.openWallet,
          child: ConstrainedBox(
            constraints: const BoxConstraints(minWidth: 48, minHeight: 48),
            child: Center(
              widthFactor: 1,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 6),
                decoration: BoxDecoration(border: Border.all(color: QColors.gold.withOpacity(0.4)), borderRadius: BorderRadius.circular(QRadii.pill), color: QColors.cardSlate),
                child: Explainable(
                  id: 'su_points',
                  child: Row(mainAxisSize: MainAxisSize.min, children: [
                    if (zero)
                      const ExplainMark(
                        key: SuChip.coinMarkKey,
                        child: Padding(padding: EdgeInsets.only(bottom: 4), child: SuCoinIcon(size: 16)),
                      )
                    else
                      const SuCoinIcon(size: 16),
                    if (!zero) ...[
                      const SizedBox(width: 6),
                      // 13pt: at 11 the Arabic zero read as a dot.
                      ExplainMark(child: Text(state.formatSu(state.suAvailable), key: SuChip.amountKey, style: QText.number(size: 13, weight: FontWeight.w600, color: QColors.gold))),
                    ],
                  ]),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
