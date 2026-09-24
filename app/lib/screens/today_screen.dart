import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../l10n/trial_words.dart';
import '../l10n/words.dart';
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
import '../theme/icons.dart';
import '../theme/layout.dart';
import '../theme/text_styles.dart';
import '../widgets/common.dart';
import '../widgets/hero_number.dart';
import '../widgets/kit.dart';
import '../widgets/mascot.dart';
import '../widgets/surface.dart';
import '../widgets/explain.dart';
import '../widgets/general_guidance_card.dart';
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

  /// The gap between Today's zones.
  static const gap = 12.0;

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
            const SizedBox(height: TodayScreen.gap),
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
/// Above the fold on a 390x844 phone, over the tab bar: the header, Qamar's
/// card with "Log a meal", the numbers, and the one contextual slot
/// ([todayFocus]). Below:
/// water, the cards that lost the slot (the quest among them), the next
/// meal, movement and the meals logged today. Every seat builds inside this order; the
/// contract test (test/today_layout_test.dart) holds it.
enum TodayZone { header, qamar, numbers, slot, water, runnersUp, nextMeal, activity, meals }

/// The kit's header: Qamar's face in its lavender circle saying good
/// morning, the name under the greeting, and the game's two elements, each a
/// named piece that can be removed: the streak line (seat 3, O4) and the one
/// Su chip (O9). With "Points and streaks" off (showScore) both go and the
/// header closes up. In the season, a moon button beside the chip opens
/// Ramadan.
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
        Container(
          width: 44,
          height: 44,
          decoration: const BoxDecoration(shape: BoxShape.circle, color: QColors.lavender),
          child: const Center(child: MoonMascot(size: 32, mood: MoonMood.joy)),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(greetingFor(state.clockNow(), ar: state.isAr), style: QText.body(size: 13, color: QColors.inkSecondary)),
              // The two lines as tall as a touch (48), so the header closes up
              // under the name even beside the season's round button.
              const SizedBox(height: 2),
              Text(nameOr, style: QText.body(size: 18, height: 27, weight: FontWeight.w600, color: QColors.ink), maxLines: 1, overflow: TextOverflow.ellipsis),
              if (streak != null) TodayStreakLine(text: streak),
            ],
          ),
        ),
        if (state.seasonVisible) ...[
          QRoundIconButton(icon: QIcons.moon, onTap: () => state.go(AppScreen.ramadan), label: state.isAr ? 'رمضان' : 'Ramadan', size: 44),
          if (state.showScore) const SizedBox(width: 4),
        ],
        // One Su display on Today, and it opens the wallet (O9). Level
        // lives in the wallet only.
        if (state.showScore) SuChip(state: state),
      ],
    );
  }
}

/// The greeting over the name, by the hour: morning until noon, afternoon
/// until six, evening after — where it said "Good morning" at midnight.
String greetingFor(DateTime now, {required bool ar}) {
  final h = now.hour;
  if (h >= 4 && h < 12) return ar ? 'صباح الخير،' : 'Good morning,';
  if (h >= 12 && h < 18) return ar ? 'نهارك سعيد،' : 'Good afternoon,';
  return ar ? 'مساء الخير،' : 'Good evening,';
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
      Text(text, style: QText.body(size: 13, color: QColors.accentInk));
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
        : (isAr ? 'أهم حاجة النهاردة: تسجّل أول وجبة. الباقي أنا هظبطه معاك.' : 'One thing today: log your first meal. I’ll handle the rest.'),
    fromNight: false,
  );
}

/// Qamar's card (O15): the day's sentence, and under it "Log a meal".
///
/// The button is Today's one primary action and it stays above the fold: it
/// goes straight to the meal question. The night note, which was a card of
/// its own, is the sentence here in the morning, with its link to today's
/// plan.
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
    // Qamar's voice, plainly: the sentence across the card and the one
    // burgundy button under it. No moon beside it — the header's face and
    // the orb in the bar are the moon — so the words get the whole width and
    // fewer lines.
    return Container(
      padding: const EdgeInsets.fromLTRB(18, 10, 18, 12),
      decoration: QDecor.card(),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(line.text, key: const ValueKey('today-sentence'), style: QText.body(size: 17, color: QColors.ink)),
          // The night note's way on: today's plan, or where the wall is. A
          // returning line has no plan behind it (plan_kcal 0, 0062), so
          // there is nothing to open and no link.
          if (line.fromNight && (state.nightNote?.planKcal ?? 0) > 0)
            Align(
              alignment: AlignmentDirectional.centerStart,
              child: QTapArea(
                key: offerWeek ? lockOfferKey : null,
                onTap: offerWeek ? state.acceptLockCardTrial : state.openNightNote,
                builder: (context, pressed) => qPressed(
                  context,
                  pressed: pressed,
                  child: SizedBox(
                    height: QLayout.minTap,
                    child: Row(mainAxisSize: MainAxisSize.min, children: [
                      QIcon(offerWeek ? QIcons.gift : (locked ? QIcons.locked : QIcons.external), size: 18, color: QColors.accentInk),
                      const SizedBox(width: 6),
                      Flexible(
                        child: Text(
                          offerWeek
                              ? (isAr
                                  ? TrialWords.lockLink(AppState.trialOfferDays, ar: true, iso: state.iso)
                                  : TrialWords.lockLink(AppState.trialOfferDays, ar: false, iso: state.iso))
                              : locked
                                  ? (isAr ? 'الخطة الكاملة في قمر+' : 'The full plan is Qamar+')
                                  : (isAr ? 'افتح خطة النهارده' : 'Open today’s plan'),
                          style: QText.body(size: 15, weight: FontWeight.w600, color: QColors.accentInk),
                        ),
                      ),
                    ]),
                  ),
                ),
              ),
            )
          else
            const SizedBox(height: 12),
          QPrimaryButton(key: logKey, label: state.t.logMeal, icon: QIcons.add, onTap: state.logFromToday),
        ],
      ),
    );
  }
}

/// The day's numbers, the kit's calorie card: on lavender, the gauge with
/// what is left in its middle, and the three macros under it as the kit's
/// nested tiles — protein on mint, carbs on lime, fat on coral. "Why?"
/// beside the card's name explains the figure.
class _NumbersCard extends StatelessWidget {
  final AppState state;
  const _NumbersCard({required this.state});

  @override
  Widget build(BuildContext context) {
    final t = state.t;
    final isAr = state.isAr;
    final tg = state.target();
    final con = state.consumed();
    final remaining = (tg.kcal - con.kcal).clamp(0, 1 << 30);
    double pct(int a, int b) => b == 0 ? 0 : (a / b).clamp(0, 1).toDouble();
    // In Arabic the slash keeps its spaces: joined to Arabic-Indic digits it
    // would make one number of the two, read target first
    // (iso_direction_test.dart).
    String grams(int a, int b) => isAr ? '${state.iso('$a / $b')} جم' : '$a/${b}g';
    // Within its budget above the fold (O15): the card's name, the gauge,
    // the three tiles, and under the card one line saying these are
    // estimates, in a colour that passes AA.
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // Its top is the "Why?" pill's touch band, which is air enough over
        // the name; the same inset either side, in either language.
        PastelCard(
          color: QColors.lavender,
          padding: const EdgeInsets.fromLTRB(14, 4, 14, 10),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(children: [
                Expanded(child: Text(isAr ? 'السعرات' : 'Calories', style: QText.body(size: 18, weight: FontWeight.w600, color: QColors.onPastel))),
                // Beside the figure it explains: one short word, "Why?".
                QPastelButton(label: t.whyCta, onTap: state.openWhy, height: 32),
              ]),
              Center(
                child: CalorieGauge(
                  width: 150,
                  eaten: pct(con.kcal, tg.kcal),
                  end: state.digits('${tg.kcal}'),
                  // The screen's one hero: what is left, in either digit set,
                  // its words under it. The explainable region is the figure
                  // and its words; its mark is on the words.
                  centre: Explainable(
                    id: 'kcal_remaining',
                    child: Column(mainAxisSize: MainAxisSize.min, children: [
                      HeroNumber(state.digits('$remaining'), size: 34, color: QColors.onPastel, semanticsLabel: '${state.digits('$remaining')} ${t.kcalRemaining}'),
                      ExplainMark(child: Text(isAr ? 'سعر فاضل' : 'kcal left', style: QText.body(size: 13, weight: FontWeight.w500, color: QColors.onPastelSecondary))),
                    ]),
                  ),
                ),
              ),
              const SizedBox(height: 4),
              Row(children: [
                Expanded(child: Explainable(id: 'protein', child: _MacroTile(color: QColors.mint, label: t.protein, text: grams(con.p, tg.protein), pct: pct(con.p, tg.protein)))),
                const SizedBox(width: 8),
                Expanded(child: Explainable(id: 'carbs', child: _MacroTile(color: QColors.lime, label: t.carbs, text: grams(con.c, tg.carbs), pct: pct(con.c, tg.carbs)))),
                const SizedBox(width: 8),
                Expanded(child: Explainable(id: 'fat', child: _MacroTile(color: QColors.coral, label: t.fat, text: grams(con.f, tg.fat), pct: pct(con.f, tg.fat)))),
              ]),
            ],
          ),
        ),
        const SizedBox(height: 4),
        Padding(
          padding: const EdgeInsetsDirectional.only(start: 4),
          child: Text(t.estimateNote, key: TodayScreen.estimateKey, maxLines: 1, overflow: TextOverflow.ellipsis, style: QText.body(size: 12, color: QColors.inkTertiary)),
        ),
      ],
    );
  }
}

/// A macro in the calorie card: its pastel, its name, its figures and a bar,
/// nested in the lavender as the kit nests its macro tiles.
class _MacroTile extends StatelessWidget {
  final Color color;
  final String label;
  final String text;
  final double pct;
  const _MacroTile({required this.color, required this.label, required this.text, required this.pct});

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.fromLTRB(10, 8, 10, 10),
        decoration: QDecor.pastel(color, radius: QRadii.inset),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(label, maxLines: 1, overflow: TextOverflow.ellipsis, style: QText.body(size: 13, weight: FontWeight.w600, color: QColors.onPastel)),
            ExplainMark(child: Text(text, maxLines: 1, softWrap: false, overflow: TextOverflow.visible, style: QText.number(size: 13, color: QColors.onPastel))),
            const SizedBox(height: 6),
            QBar(value: pct, height: 4, onPastel: true),
          ],
        ),
      );
}

/// The next planned meal, once a plan exists for this person.
class _NextMealCard extends StatelessWidget {
  final AppState state;
  final PlanMeal meal;
  const _NextMealCard({required this.state, required this.meal});

  @override
  Widget build(BuildContext context) {
    final t = state.t;
    final isAr = state.isAr;
    final nextMeal = meal;
    // The kit's "Diet Plan": the group's title over the meal's card, the
    // slot on a lime band at its top (the kit's photo, drawn as the plan's
    // own colour), its name and its figure under it. What the orb explains
    // is the meal and its figure.
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        QSectionTitle(t.nextMeal, isAr: isAr),
        Container(
          clipBehavior: Clip.antiAlias,
          decoration: QDecor.card(),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Container(
                color: QColors.lime,
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                child: Row(children: [
                  const QIcon(QIcons.plan, size: 20, color: QColors.onPastel),
                  const SizedBox(width: 8),
                  Text(isAr ? nextMeal.slotAr : nextMeal.slotEn, style: QText.body(size: 15, weight: FontWeight.w600, color: QColors.onPastel)),
                ]),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 14),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Explainable(
                      id: 'next_meal',
                      explanation: mealExplanation(nextMeal, iso: state.iso, digits: state.digits),
                      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        Text(isAr ? nextMeal.nameAr : nextMeal.nameEn, style: QText.body(size: 17, weight: FontWeight.w600, color: QColors.ink)),
                        const SizedBox(height: 2),
                        ExplainMark(
                          child: Text(
                            isAr ? 'حوالي ${state.iso('${mealKcal(nextMeal)}')} سعر' : 'About ${mealKcal(nextMeal)} kcal',
                            style: QText.body(size: 13, color: QColors.inkSecondary),
                          ),
                        ),
                      ]),
                    ),
                    const SizedBox(height: 12),
                    Row(children: [
                      // Only offered when the slot really has somewhere else to go.
                      if (state.slotHasAlternative(nextMeal.id)) ...[
                        QOutlineButton(label: t.swap, onTap: () => state.toggleSlotSwap(nextMeal.id), height: 36, icon: QIcons.swap),
                        const SizedBox(width: 8),
                      ],
                      QOutlineButton(label: t.openPlan, onTap: () => state.go(AppScreen.plan), height: 36),
                    ]),
                  ],
                ),
              ),
            ],
          ),
        ),
      ],
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
    final isAr = state.isAr;
    // One grouped list, the kit's: rows on one card, never a card per
    // meal, each meal's figure in the kit's meta row under its name.
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        QSectionTitle(t.loggedToday, isAr: isAr),
        QListGroup(rows: [
          for (final m in state.meals)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
              child: Row(
                children: [
                  Expanded(
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Text(m.name, style: QText.body(size: 16, weight: FontWeight.w500, color: QColors.ink)),
                      Text(
                        [
                          if (m.sub.isNotEmpty) m.sub,
                          isAr ? '${t.protein} ${state.iso('${m.p}')} جم' : '${t.protein} ${m.p}g',
                          isAr ? '${t.carbs} ${state.iso('${m.c}')} جم' : '${t.carbs} ${m.c}g',
                          isAr ? '${t.fat} ${state.iso('${m.f}')} جم' : '${t.fat} ${m.f}g',
                        ].join(isAr ? '، ' : ' | '),
                        style: QText.body(size: 13, color: QColors.inkSecondary),
                      ),
                    ]),
                  ),
                  const SizedBox(width: 12),
                  Text(isAr ? '${state.iso('${m.kcal}')} سعر' : '${m.kcal} kcal', style: QText.number(size: 15, weight: FontWeight.w600, color: QColors.ink, ar: isAr)),
                ],
              ),
            ),
        ]),
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

    // The card lines up with the others: the kit's grey card, its name with
    // its glyph, the figure, the bar; what the orb explains is the figure
    // row inside it.
    return Container(
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 16),
      decoration: QDecor.card(),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(children: [
            const QIcon(QIcons.water, size: 20, color: QColors.ink),
            const SizedBox(width: 8),
            Text(isAr ? 'الماء' : 'Water', style: QText.body(size: 16, weight: FontWeight.w600, color: QColors.ink)),
          ]),
          const SizedBox(height: 8),
          Explainable(
            id: 'water',
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.baseline,
              textBaseline: TextBaseline.alphabetic,
              children: [
                ExplainMark(
                  child: Text(isAr ? '${state.iso(litres)} لتر' : '$litres L', style: QText.number(size: 28, weight: FontWeight.w700, color: QColors.ink, ar: isAr)),
                ),
                const Spacer(),
                Text(
                  isAr ? '${state.iso(left)} لتر باقي' : '$left L left',
                  style: QText.body(size: 15, weight: FontWeight.w500, color: QColors.inkSecondary),
                ),
              ],
            ),
          ),
          if (state.fasting) ...[
            const SizedBox(height: 8),
            _HydrationLine(state: state),
          ],
          const SizedBox(height: 14),
          QBar(value: w.progress),
          const SizedBox(height: 16),
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
                style: TextButton.styleFrom(minimumSize: const Size(QLayout.minTap, QLayout.minTap)),
                child: Text(
                  isAr ? 'تراجع' : 'Undo',
                  style: QText.body(size: 15, weight: FontWeight.w500, color: QColors.accentInk),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _WaterAdd extends StatelessWidget {
  final String label;
  final VoidCallback onTap;
  const _WaterAdd({required this.label, required this.onTap});

  @override
  Widget build(BuildContext context) => QOutlineButton(
        label: label,
        icon: QIcons.add,
        height: 44,
        onTap: () {
          HapticFeedback.lightImpact();
          onTap();
        },
      );
}

/// Today's movement, as logged from the Log sheet: what, how long, and an
/// estimate of what it cost. Shown beside the food, never subtracted from it.
class _ActivityCard extends StatelessWidget {
  final AppState state;
  const _ActivityCard({required this.state});

  @override
  Widget build(BuildContext context) {
    final isAr = state.isAr;
    return Container(
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 16),
      decoration: QDecor.card(),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(children: [
            Expanded(
              child: Text(isAr ? 'حركة النهاردة' : 'Today’s movement', style: QText.body(size: 16, weight: FontWeight.w600, color: QColors.ink)),
            ),
            Text(
              isAr
                  // "،" where English has "·": beside Arabic digits a
                  // middle dot reads as a zero.
                  ? '${state.iso('${state.activityMinutesToday}')} د، حوالي ${state.iso('${state.activityKcalToday}')} سعرة'
                  : '${state.activityMinutesToday} min · ~${state.activityKcalToday} kcal',
              style: QText.number(size: 13, weight: FontWeight.w600, color: QColors.ink),
            ),
          ]),
          const SizedBox(height: 8),
          for (final a in state.activitiesToday)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 3),
              child: Row(children: [
                const QIcon(QIcons.run, size: 18, color: QColors.ink),
                const SizedBox(width: 8),
                Expanded(child: Text(a.label(ar: isAr), style: QText.body(size: 15, color: QColors.ink))),
                Text(isAr ? '${state.iso('${a.minutes}')} د' : '${a.minutes} min', style: QText.number(size: 13, color: QColors.inkSecondary)),
              ]),
            ),
          const SizedBox(height: 6),
          Text(
            isAr ? 'تقدير. بنسجّل الحركة جنب الأكل ومش بنزوّد سعرات عليها.' : 'An estimate. Movement is logged beside the food, not added to its budget.',
            style: QText.body(size: 12, color: QColors.inkTertiary),
          ),
        ],
      ),
    );
  }
}

/// The one question the season asks, once: fasting this year? Yes turns the
/// plan into iftar and suhoor and the water card into windows; no leaves the
/// day as it is. Either way Ramadan stays one tap away in season (the moon
/// by the header, and Me).
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
        return QStateLine(line: n.line, action: n.action, icon: QIcons.moon);
      }
    }
    final until = state.season.daysUntil(state.clockNow());
    final lead = until == null
        ? (isAr ? 'رمضان كريم.' : 'Ramadan Kareem.')
        : (isAr
            ? 'رمضان بعد ${Counted.day.of(until, ar: true, iso: state.iso)}.'
            : 'Ramadan is ${Counted.day.of(until, ar: false, iso: state.iso)} away.');
    // Within the slot's 120 points (O15), in both languages. The answers
    // are drawn 34 tall in a 48-point touch (O11), so the 7 points of touch
    // under each outline are the card's bottom margin, and the 7 above it
    // the gap to the line over them: 8 visible points on every side.
    // The season's own pastel: lavender, with the moon; the answers are the
    // kit's black buttons on it.
    return PastelCard(
      color: QColors.lavender,
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 1),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(children: [
            const QIcon(QIcons.moon, size: 18, color: QColors.onPastel),
            const SizedBox(width: 6),
            Expanded(
              child: Text('$lead ${isAr ? 'هتصوم؟' : 'Fasting?'}',
                  style: QText.body(size: 15, weight: FontWeight.w600, color: QColors.onPastel)),
            ),
          ]),
          const SizedBox(height: 2),
          Text(
            // A no-break space keeps the closing sentence whole, so the
            // Arabic never ends on "للكل." alone under "ببلاش".
            isAr
                ? 'لو أيوة، الوجبات تبقى إفطار وسحور. ببلاش\u00A0للكل.'
                : 'If yes, meals become iftar and suhoor. Free for\u00A0everyone.',
            style: QText.body(size: 12, height: 18, color: QColors.onPastelSecondary),
          ),
          Row(children: [
            QPastelButton(label: isAr ? 'أيوة، صايم' : 'Yes, fasting', height: 34, onTap: () => state.setFasting(true)),
            const SizedBox(width: 10),
            QPastelButton(label: isAr ? 'لا' : 'No', height: 34, onTap: () => state.setFasting(false)),
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
      const QIcon(QIcons.moon, size: 16, color: QColors.ink),
      const SizedBox(width: 6),
      Expanded(child: Text(text, style: QText.body(size: 13, color: QColors.ink))),
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
    // Days counted by the app's one rule: "1 day left", "باقي يومين".
    String days(int n) => Counted.day.of(n, ar: isAr, iso: state.iso);
    final body = granted
        ? (isAr ? 'سجّلت ${days(e.loggedDays)} من أول ${state.iso('${e.windowDays}')}. قمر+ شغال لحد $when.' : 'You logged ${e.loggedDays} of your first ${days(e.windowDays)}. Qamar+ runs until $when.')
        : (isAr
            ? 'سجّلت ${days(e.loggedDays)} من ${state.iso('${e.needed}')}، باقي ${days(e.daysLeft)}'
            : '${e.loggedDays} of ${days(e.needed)} logged · ${days(e.daysLeft)} left');
    final note = granted
        ? (isAr ? 'اضغط للإخفاء' : 'Tap to dismiss')
        : (isAr ? 'سجّل ${days(e.needed)} من أول ${state.iso('${e.windowDays}')} والشهر اللي بعده علينا.' : 'Log ${e.needed} of your first ${days(e.windowDays)} and the next month is free.');
    final pct = e.needed == 0 ? 1.0 : (e.loggedDays / e.needed).clamp(0.0, 1.0);
    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(QRadii.card),
        onTap: granted ? state.dismissEarnedMonthCard : null,
        // A gift, on the kit's lime.
        child: PastelCard(
          color: QColors.lime,
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(children: [
                const QIcon(QIcons.gift, size: 18, color: QColors.onPastel),
                const SizedBox(width: 6),
                Text(title, style: QText.body(size: 15, weight: FontWeight.w600, color: QColors.onPastel)),
              ]),
              const SizedBox(height: 4),
              Text(body, style: QText.body(size: 13, color: QColors.onPastel)),
              if (!granted) ...[
                const SizedBox(height: 8),
                QBar(value: pct, onPastel: true),
              ],
              const SizedBox(height: 4),
              Text(note, style: QText.body(size: 12, color: QColors.onPastelSecondary)),
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
              child: QSurface(
                shape: QSurfaceShape.capsule,
                height: 44,
                padding: const EdgeInsets.symmetric(horizontal: 14),
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
                      ExplainMark(child: Text(state.formatSu(state.suAvailable), key: SuChip.amountKey, style: QText.number(size: 15, weight: FontWeight.w600, color: QColors.ink))),
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
