import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../models/plan.dart';
import '../models/su_economy.dart';
import '../models/water.dart';
import '../state/app_state.dart';
import '../theme/app_theme.dart';
import '../theme/colors.dart';
import '../theme/text_styles.dart';
import '../widgets/common.dart';
import '../widgets/explain.dart';
import '../widgets/moon.dart';

class TodayScreen extends StatefulWidget {
  const TodayScreen({super.key});

  @override
  State<TodayScreen> createState() => _TodayScreenState();
}

class _TodayScreenState extends State<TodayScreen> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) context.read<AppState>().ensurePlan();
    });
  }

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    final t = state.t;
    final tg = state.target();
    final con = state.consumed();
    final remaining = (tg.kcal - con.kcal).clamp(0, 1 << 30);
    final nameOr = state.profile.name.isNotEmpty ? state.profile.name : (state.isAr ? 'يا صاحبي' : 'friend');
    // Null until a plan has been generated for this person. The card is then
    // hidden entirely rather than showing a meal nobody chose for them.
    final nextMeal = state.nextMeal();

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
                      child: Explainable(
                        id: 'su_points',
                        child: Row(mainAxisSize: MainAxisSize.min, children: [
                          const SuCoinIcon(size: 16),
                          const SizedBox(width: 6),
                          Text('${state.formatSu(state.suAvailable)}', style: QText.number(size: 11, weight: FontWeight.w600, color: QColors.gold)),
                        ]),
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                  decoration: BoxDecoration(border: Border.all(color: QColors.borderSoft), borderRadius: BorderRadius.circular(999), color: QColors.cardDeep),
                  child: Explainable(
                    id: 'level',
                    child: Row(mainAxisSize: MainAxisSize.min, children: [
                      Container(width: 8, height: 8, decoration: const BoxDecoration(shape: BoxShape.circle, color: QColors.green)),
                      const SizedBox(width: 8),
                      Text(state.isAr ? 'المستوى ${state.iso('${state.level()}')}' : 'Level ${state.level()}', style: QText.number(size: 11, weight: FontWeight.w500, color: QColors.textMid)),
                    ]),
                  ),
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
              const QamarMoon(size: 40),
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
        if (state.nightNote != null) ...[
          _NightCard(state: state),
          const SizedBox(height: 14),
        ],
        Container(
          padding: const EdgeInsets.all(20),
          decoration: QDecor.card(gradient: const LinearGradient(colors: [QColors.cardMid, QColors.cardSlate]), border: QColors.borderStrong, radius: QRadii.xxxl,
              shadow: [BoxShadow(color: QColors.blue.withOpacity(0.12), blurRadius: 40)]),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(crossAxisAlignment: CrossAxisAlignment.baseline, textBaseline: TextBaseline.alphabetic, children: [
                Explainable(
                  id: 'kcal_remaining',
                  child: ShaderMask(
                    shaderCallback: (r) => QColors.cyanVioletGradient.createShader(r),
                    child: Text(state.digits('$remaining'), style: QText.number(size: 38, weight: FontWeight.w600, color: Colors.white)),
                  ),
                ),
                const SizedBox(width: 8),
                Text(t.kcalRemaining, style: QText.body(size: 13, weight: FontWeight.w500, color: QColors.textMuted)),
              ]),
              const SizedBox(height: 16),
              Explainable(id: 'protein', child: _MacroRow(label: t.protein, text: state.isAr ? '${state.iso('${con.p} / ${tg.protein}')} جم' : '${con.p} / ${tg.protein} g', pct: pct(con.p, tg.protein))),
              const SizedBox(height: 12),
              Explainable(id: 'carbs', child: _MacroRow(label: t.carbs, text: state.isAr ? '${state.iso('${con.c} / ${tg.carbs}')} جم' : '${con.c} / ${tg.carbs} g', pct: pct(con.c, tg.carbs))),
              const SizedBox(height: 12),
              Explainable(id: 'fat', child: _MacroRow(label: t.fat, text: state.isAr ? '${state.iso('${con.f} / ${tg.fat}')} جم' : '${con.f} / ${tg.fat} g', pct: pct(con.f, tg.fat))),
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
        const _WaterCard(),
        const SizedBox(height: 14),
        if (nextMeal != null)
          Explainable(
            id: 'next_meal',
            explanation: mealExplanation(nextMeal),
            child: Container(
              padding: const EdgeInsets.all(16),
              decoration: QDecor.card(color: QColors.cardDeep, border: QColors.green.withOpacity(0.4), radius: QRadii.xl),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(t.nextMeal, style: QText.body(size: 11, weight: FontWeight.w500, color: QColors.green, letterSpacing: 0.4)),
                  Text(state.isAr ? nextMeal.nameAr : nextMeal.nameEn,
                      style: QText.body(size: 17, weight: FontWeight.w600, color: QColors.textPrimary)),
                  Text(
                    state.isAr
                        ? 'حوالي ${state.iso('${mealKcal(nextMeal)}')} سعر'
                        : 'About ${mealKcal(nextMeal)} kcal',
                    style: QText.body(size: 13, color: QColors.textMuted),
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
          ),
        const SizedBox(height: 14),
        Explainable(
          id: 'quest',
          child: Container(
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
                    Text('+${state.formatSu(SuEconomy.dailyQuest)}', style: QText.number(size: 12, weight: FontWeight.w600, color: QColors.gold)),
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
        ),
        const SizedBox(height: 14),
        // No "log a meal" button: hold the orb and pick speak / type (free)
        // or photo (Qamar+).
        _OrbLogHint(state: state),
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
                  Text(state.isAr ? '${state.iso('${m.kcal}')} سعر' : '${m.kcal} kcal', style: QText.number(size: 15, weight: FontWeight.w600, color: QColors.cyan)),
                ],
              ),
            ),
          ],
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
          radius: QRadii.xl,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(isAr ? 'الماء' : 'Water',
                style: QText.body(size: 11, weight: FontWeight.w500, color: QColors.textMuted, letterSpacing: 0.4)),
            const SizedBox(height: 8),
            Row(
              crossAxisAlignment: CrossAxisAlignment.baseline,
              textBaseline: TextBaseline.alphabetic,
              children: [
                ShaderMask(
                  shaderCallback: (r) => QColors.blueCyanGradient.createShader(r),
                  child: Text(
                    isAr ? '${state.iso(litres)} لتر' : '$litres L',
                    style: QText.number(size: 28, weight: FontWeight.w600, color: Colors.white),
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
            const SizedBox(height: 12),
            ClipRRect(
              borderRadius: BorderRadius.circular(999),
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
                    style: QText.body(size: 12, weight: FontWeight.w500, color: QColors.textFaint),
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
      height: 44,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(QRadii.md),
          onTap: () {
            HapticFeedback.lightImpact();
            onTap();
          },
          child: Ink(
            decoration: BoxDecoration(
              color: QColors.cyan.withValues(alpha: 0.10),
              border: Border.all(color: QColors.cyan.withValues(alpha: 0.35)),
              borderRadius: BorderRadius.circular(QRadii.md),
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


/// Replaces the old "log a meal" button. The action itself lives in the orb —
/// tap it, choose Log, pick speak, type or photo — so this only has to teach
/// the two gestures once.
/// Last night's sentence about today — the plan's one line, read in the
/// morning. On Qamar+ it opens the plan; on the free tier the plan behind it
/// is locked, and this card is where the wall stands.
class _NightCard extends StatelessWidget {
  final AppState state;
  const _NightCard({required this.state});

  @override
  Widget build(BuildContext context) {
    final isAr = state.isAr;
    final locked = state.nightPlanLocked;
    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(QRadii.xl),
        onTap: state.openNightNote,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 13),
          decoration: BoxDecoration(
            color: QColors.violet.withValues(alpha: 0.08),
            border: Border.all(color: QColors.violet.withValues(alpha: 0.3)),
            borderRadius: BorderRadius.circular(QRadii.xl),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(children: [
                const Icon(Icons.nightlight_round, size: 14, color: QColors.violetSoft),
                const SizedBox(width: 6),
                Text(
                  isAr ? 'من الليل' : 'From last night',
                  style: QText.body(size: 12, weight: FontWeight.w600, color: QColors.violetSoft, letterSpacing: 0.3),
                ),
              ]),
              const SizedBox(height: 8),
              Text(state.nightSentence ?? '', style: QText.body(size: 14, height: 21, color: QColors.textHigh)),
              const SizedBox(height: 8),
              Row(children: [
                Icon(
                  locked ? Icons.lock_outline : Icons.arrow_outward,
                  size: 14,
                  color: locked ? QColors.gold : QColors.textMuted,
                ),
                const SizedBox(width: 6),
                Text(
                  locked
                      ? (isAr ? 'الخطة الكاملة في قمر+' : 'The full plan is Qamar+')
                      : (isAr ? 'افتح خطة النهارده' : 'Open today’s plan'),
                  style: QText.body(size: 12, color: locked ? QColors.gold : QColors.textMuted),
                ),
              ]),
            ],
          ),
        ),
      ),
    );
  }
}

class _OrbLogHint extends StatelessWidget {
  final AppState state;
  const _OrbLogHint({required this.state});

  @override
  Widget build(BuildContext context) {
    final isAr = state.isAr;
    if (state.orbTutorialDone) return const SizedBox.shrink();
    final learned = state.gesturesLearned;
    final rows = <(OrbGesture, IconData, String, String)>[
      (OrbGesture.tap, Icons.touch_app_outlined, 'دوس على القمر', 'Tap the moon'),
      (OrbGesture.hold, Icons.mic_none, 'استمر ضاغط عليه', 'Hold it'),
      (OrbGesture.explain, Icons.open_with, 'اسحبه على أي رقم', 'Drag it onto any number'),
    ];
    final what = <OrbGesture, (String, String)>{
      OrbGesture.tap: ('تفتح الشجرة: سجّل · الخطة · مياه · المراجعة · حسابي', 'opens the tree: Log · Plan · Water · Review · Me'),
      OrbGesture.hold: ('تتكلم مع قمر — بصوتك', 'talk to Qamar — with your voice'),
      OrbGesture.explain: ('يشرحه لك: من فين جه وإيه معناه', 'and it explains itself: where it came from, what it means'),
    };
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 13),
      decoration: BoxDecoration(
        color: QColors.violet.withValues(alpha: 0.08),
        border: Border.all(color: QColors.violet.withValues(alpha: 0.3)),
        borderRadius: BorderRadius.circular(QRadii.xl),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  isAr ? 'القمر بيفهم تلات حركات' : 'The moon knows three gestures',
                  style: QText.body(size: 12, weight: FontWeight.w600, color: QColors.violetSoft, letterSpacing: 0.3),
                ),
              ),
              GestureDetector(
                onTap: state.dismissOrbTutorial,
                child: Padding(
                  padding: const EdgeInsets.all(4),
                  child: Text(isAr ? 'عارف' : 'Got it', style: QText.body(size: 12, color: QColors.textMuted)),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          for (final (g, icon, ar, en) in rows) ...[
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 3),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(
                    learned.contains(g) ? Icons.check_circle : icon,
                    size: 16,
                    color: learned.contains(g) ? QColors.green : QColors.violetSoft,
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      '${isAr ? ar : en} — ${isAr ? what[g]!.$1 : what[g]!.$2}',
                      style: QText.body(
                        size: 12,
                        height: 18,
                        color: learned.contains(g) ? QColors.textMuted : QColors.textMid,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
          const SizedBox(height: 4),
          Text(
            isAr ? 'الكتابة والصوت ببلاش على طول. الصور تلاتة في اليوم.' : 'Typing and speaking are always free. Photos, three a day.',
            style: QText.body(size: 11, height: 16, color: QColors.textFaint),
          ),
        ],
      ),
    );
  }
}
