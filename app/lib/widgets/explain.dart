import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/plan.dart';
import '../state/app_state.dart';
import '../theme/app_theme.dart';
import '../theme/colors.dart';
import '../theme/text_styles.dart';
import 'common.dart';
import 'moon.dart';

/// What the orb says about one piece of data.
///
/// The whole point of the orb is that a number on its own teaches nobody
/// anything: "1,840 kcal" is only useful if you know where it came from, what
/// moving it does, and when to ignore it. Each entry answers those in plain
/// language rather than restating the label.
class Explanation {
  final String titleAr, titleEn;
  final String bodyAr, bodyEn;

  /// The concrete "so what" — what the user should actually do with it.
  final String soWhatAr, soWhatEn;

  const Explanation({
    required this.titleAr,
    required this.titleEn,
    required this.bodyAr,
    required this.bodyEn,
    required this.soWhatAr,
    required this.soWhatEn,
  });
}

/// Static copy for now. Once the AI gateway exists (lib/services/ai_gateway.dart)
/// these become the fallback, and the orb asks the model to explain the number
/// in the user's own context — "you're 300 under today because lunch was light".
const kExplanations = <String, Explanation>{
  'kcal_remaining': Explanation(
    titleAr: 'الباقي من السعرات',
    titleEn: 'Calories remaining',
    bodyAr:
        'ده هدفك اليومي ناقص اللي سجّلته لحد دلوقتي. مش عداد بيقفل عليك — دي مساحة لسه قدامك في اليوم.',
    bodyEn:
        'This is your daily target minus everything you have logged so far. It is not a countdown that locks you out — it is the room you still have in the day.',
    soWhatAr: 'لو الرقم قرّب يخلص بدري، خلّي الوجبة الجاية بروتين وخضار أكتر من نشويات.',
    soWhatEn: 'If it runs low early, make the next meal heavier on protein and vegetables than on starch.',
  ),
  'target_kcal': Explanation(
    titleAr: 'هدف السعرات اليومي',
    titleEn: 'Daily calorie target',
    bodyAr:
        'محسوب بمعادلة Mifflin-St Jeor: بتقدّر احتياجك وأنت مرتاح من الوزن والطول والسن والنوع، وبعدين بتتضرب في معامل نشاطك. لو هدفك تخس بنشيل حوالي ٤٥٠ سعر.',
    bodyEn:
        'Calculated with the Mifflin-St Jeor equation: it estimates what your body burns at rest from your weight, height, age and sex, then multiplies by your activity factor. If your goal is to lose, we take about 450 off.',
    soWhatAr: 'ده تقدير مش قياس. لو وزنك مش بيتحرك خالص بعد أسبوعين، الرقم محتاج تعديل مش أنت.',
    soWhatEn: 'It is an estimate, not a measurement. If your weight has not moved in two weeks, the number needs adjusting — not you.',
  ),
  'protein': Explanation(
    titleAr: 'البروتين',
    titleEn: 'Protein',
    bodyAr:
        'البروتين هو اللي بيحافظ على عضلاتك وأنت بتخس، وهو أكتر حاجة بتشبّعك. الرقم ده تقريباً ١.٨ جم لكل كيلو من وزنك.',
    bodyEn:
        'Protein is what protects your muscle while you lose weight, and it is the macro that keeps you full longest. This number is roughly 1.8 g per kilo of your body weight.',
    soWhatAr: 'لو بتوصله بصعوبة، ابدأ بيه في كل وجبة قبل ما تفكر في الباقي.',
    soWhatEn: 'If you struggle to hit it, start each meal with the protein before you think about anything else.',
  ),
  'carbs': Explanation(
    titleAr: 'الكربوهيدرات',
    titleEn: 'Carbs',
    bodyAr:
        'مصدر الطاقة الأساسي — العيش والرز والمكرونة والفاكهة. مش عدوك، بس الكمية هي اللي بتفرق.',
    bodyEn:
        'Your main energy source — bread, rice, pasta, fruit. Not the enemy; the amount is what matters.',
    soWhatAr: 'حطّهم حوالين حركتك: أكتر في اليوم اللي بتتمرن فيه، أقل في اليوم اللي قاعد فيه.',
    soWhatEn: 'Put them around your movement: more on days you train, less on days you sit.',
  ),
  'fat': Explanation(
    titleAr: 'الدهون',
    titleEn: 'Fat',
    bodyAr:
        'ضرورية للهرمونات وامتصاص الفيتامينات. بس هي أعلى حاجة في السعرات — ٩ سعرات في الجرام مقابل ٤ للبروتين والكربوهيدرات.',
    bodyEn:
        'Necessary for hormones and vitamin absorption. It is also the most calorie-dense — 9 kcal per gram against 4 for protein and carbs.',
    soWhatAr: 'الزيت والسمنة في الطبخ بيعدّوا. معلقة زيت زيتون لوحدها ١٢٥ سعر.',
    soWhatEn: 'Cooking oil and ghee count. A single tablespoon of olive oil is 125 kcal on its own.',
  ),
  'su_points': Explanation(
    titleAr: 'نقاط Su',
    titleEn: 'Su Points',
    bodyAr:
        'بتتكسب لما تعمل حاجة مفيدة لنفسك — تسجّل وجبة (+١٠٠، وأول وجبة +٥٠٠)، كوباية مياه (+٥، ومع قمر+ +١٠)، مهمة اليوم لما اللي بتطلبه يتسجّل (+٢٥٠، في حدود سقف اليوم)، أسبوع كامل في السلسلة (+١٠٠). بتتصرف على صورة زيادة أو تجميد السلسلة — ومرة في اليوم، عند حد الأسئلة، على السؤال ده بس. السؤال الرابع لسه بيفتح قمر+ الأول.',
    bodyEn:
        'Earned when you do something useful for yourself — logging a meal (+100, first meal +500), a glass of water (+5, +10 with Qamar+), the day’s quest, when what it asks is logged (+250, within the day’s cap), a full week of streak (+100). Spent on another photo or a streak freeze — and, once a day at the question limit, on that one question. The fourth question still opens Qamar+ first.',
    soWhatAr: 'النقط دي بتتكسب بس. مش بتتشترى بفلوس ومالهاش قيمة نقدية. لو مش عايز تشوفها، اقفل «النقاط والسلسلة» من أنا — بتستخبى بس، وبتفضل تتحسب.',
    soWhatEn: 'They are only ever earned. They cannot be bought with money and have no cash value. To stop seeing them, turn off Points and streaks in Me — they are only hidden, and still counted.',
  ),
  'streak': Explanation(
    titleAr: 'السلسلة',
    titleEn: 'Streak',
    bodyAr: 'أيام ورا بعض سجّلت فيها وجبة واحدة على الأقل. اليوم ميقطعش السلسلة قبل ما يخلص — بس لازم وجبة قبل نص الليل. الحلقة حوالين القمر هي السلسلة دي، ولما وجبة النهارده تكمّل يومين ورا بعض أو أكتر بقولها تحت اسمك في النهارده.',
    bodyEn: 'Days in a row with at least one logged meal. Today never breaks the streak before it ends — but it needs a meal before midnight. The ring around the moon is this streak, and once today’s meal makes a run of two days or more, Qamar says so under your name on Today.',
    soWhatAr: 'وجبة واحدة مسجلة بتكفي. وتجميد السلسلة من المحفظة بيغطي يوم واحد يفوت في الشهر، لو خدته قبله — مبيرجّعش يوم فات. لو مش عايز تشوف السلسلة، اقفل «النقاط والسلسلة» من أنا.',
    soWhatEn: 'One logged meal is enough. A streak freeze from the wallet covers one missed day a month, if you take it before — it never brings back a day already missed. To stop seeing the streak, turn off Points and streaks in Me.',
  ),
  'level': Explanation(
    titleAr: 'المستوى',
    titleEn: 'Level',
    bodyAr: 'بيتحرك مع إجمالي نقاط Su اللي كسبتها من أول ما بدأت — كل ١٬٠٠٠ نقطة Su مستوى. مقياس للاستمرارية مش للوزن، وهي الرقم اللي هيتقارن في لوحة المتصدرين.',
    bodyEn: 'Moves with the total Su Points you have earned since you started — 1,000 lifetime Su per level. A measure of consistency, not of weight, and the number a leaderboard will rank.',
    soWhatAr: 'الاستمرار أهم من الكمال. يوم واحد مضبوط أحسن من أسبوع مثالي وبعده انقطاع.',
    soWhatEn: 'Consistency beats perfection. One honest day beats a perfect week followed by quitting.',
  ),
  'quest': Explanation(
    titleAr: 'مهمة اليوم',
    titleEn: "Today's quest",
    bodyAr:
        'حاجة واحدة ناقصة النهارده، متختارة من اللي سجّلته: الغدا قبل ٤ العصر، أو بروتين في العشا، أو ٦ كوبايات مية. بتدي ٢٥٠ نقطة Su، في حدود سقف اليوم (١٬٥٠٠)، لما الوجبة أو الكوباية اللي بتعملها تتسجّل — مفيش حاجة تدوس عليها عشان تاخدها. وفي أيام مفيهاش مهمة: لما مفيش حاجة ناقصة، وأيام الصيام.',
    bodyEn:
        'One thing today is missing, chosen from what you have logged: lunch before 4pm, protein at dinner, or six glasses of water. It pays 250 Su, within the day’s 1,500 cap, when the meal or the glass that does it is logged — there is nothing to tap for it. Some days have none: when nothing is missing, and on fasting days.',
    soWhatAr: 'لو مش مناسبة لظروف يومك، اضغط «مش النهارده» وهتستنى لبكرة — ده مش فشل.',
    soWhatEn: 'If it does not fit your day, tap Not today and it waits until tomorrow — that is not a failure.',
  ),
  'water': Explanation(
    titleAr: 'الماء',
    titleEn: 'Water',
    bodyAr:
        'كوبتين لتلاتة لتر في اليوم بداية معقولة لشخص بالغ. الحر في مصر بيخلي الرقم أقرب للتلاتة. الكوباية ٢٥٠ مل، الزجاجة ٥٠٠ مل. الشاي والأكل فيه مية بتحسب، العصير المسكر لأ.',
    bodyEn:
        'Two to three litres a day is a reasonable start for an adult. Egyptian heat sits at the top of that range. A glass is 250 ml, a bottle is 500 ml. Tea and watery food count; sugary drinks do not.',
    soWhatAr: 'العطش دليل كويس. البول الفاتح أحسن. لو حر أو بتتحرك أكتر، زوّد من غير ما تستنى الرقم يوصل صفر.',
    soWhatEn: 'Thirst is a decent guide. Pale urine is a better one. In heat or on an active day, drink more — do not wait for the leftover to hit zero.',
  ),
  'plan_total': Explanation(
    titleAr: 'إجمالي الخطة',
    titleEn: 'Plan total',
    bodyAr: 'مجموع سعرات الوجبات المقترحة النهاردة، محسوب من المقادير نفسها مش مكتوب لوحده.',
    bodyEn: 'The calories of today’s suggested meals, summed from the portions themselves rather than written separately.',
    soWhatAr: 'لو مختلف عن هدفك بشوية، ده عادي — الخطة اقتراح مش أمر.',
    soWhatEn: 'A small gap from your target is fine — the plan is a suggestion, not an instruction.',
  ),
};

/// Builds the orb's answer for a planned meal from the meal itself, so hovering
/// a meal gives the portions and the reasoning without opening the Plan page —
/// which is the whole point of the orb.
///
/// Pass the state's [iso] and [digits] so the Arabic numbers are drawn the
/// way every other Arabic number is (Eastern digits, in bidi isolates);
/// without them the numbers are left as they are.
Explanation mealExplanation(PlanMeal m, {String Function(String) iso = _asIs, String Function(String) digits = _asIs}) {
  final kcal = mealKcal(m);
  final linesAr = m.portions.map((p) => '• ${p.ar} — ${digits(p.amountAr)} — ${iso('${p.kcal}')} سعر').join('\n');
  final linesEn = m.portions.map((p) => '• ${p.en} — ${p.amountEn} — ${p.kcal} kcal').join('\n');

  return Explanation(
    titleAr: '${m.slotAr}: ${m.nameAr}',
    titleEn: '${m.slotEn}: ${m.nameEn}',
    bodyAr: 'إجمالي ${iso('$kcal')} سعر، موزّعة كده:\n$linesAr',
    bodyEn: 'A total of $kcal kcal, made up of:\n$linesEn',
    soWhatAr: 'الكميات تقريبية — الأقرب أحسن من المضبوط. لو مكوّن مش متاح، اضغط «بديل» وهجيبلك واحد قريب منه في السعرات.',
    soWhatEn: 'Amounts are approximate — close is better than exact. If something is unavailable, tap Swap and I will offer a near-equivalent.',
  );
}

String _asIs(String x) => x;

/// Where an explainable value currently sits on screen.
///
/// Kept as a plain global rather than an inherited widget because the orb is a
/// sibling of these values in the shell's Stack, not an ancestor, so it cannot
/// reach them through the tree.
class ExplainRegistry {
  ExplainRegistry._();
  static final ExplainRegistry instance = ExplainRegistry._();

  final Map<String, Rect> _spots = {};

  /// Explanations built from live data — a plan meal's actual portions, say —
  /// rather than looked up from [kExplanations]. Registered alongside the
  /// rect so the orb can read them without knowing which screen it is over.
  final Map<String, Explanation> _dynamic = {};

  void register(String id, Rect rect, [Explanation? explanation]) {
    _spots[id] = rect;
    if (explanation != null) _dynamic[id] = explanation;
  }

  void unregister(String id) {
    _spots.remove(id);
    _dynamic.remove(id);
  }

  /// Copy for [id]: whatever was registered with it, else the static table.
  Explanation? explanationFor(String id) => _dynamic[id] ?? kExplanations[id];

  /// The explainable value under [point], if any. Smallest match wins so a
  /// value nested inside a larger card resolves to the value.
  String? hitTest(Offset point) {
    String? best;
    var bestArea = double.infinity;
    for (final e in _spots.entries) {
      if (!e.value.contains(point)) continue;
      final area = e.value.width * e.value.height;
      if (area < bestArea) {
        bestArea = area;
        best = e.key;
      }
    }
    return best;
  }
}

/// Marks its child as something the orb can explain. Drag the orb over it and
/// it lights up; drop the orb and the explanation opens.
class Explainable extends StatefulWidget {
  final String id;

  /// Built from live data. Omit to use the static entry for [id].
  final Explanation? explanation;
  final Widget child;
  const Explainable({super.key, required this.id, this.explanation, required this.child});

  @override
  State<Explainable> createState() => _ExplainableState();
}

class _ExplainableState extends State<Explainable> {
  final GlobalKey _key = GlobalKey();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _sync());
  }

  @override
  void didUpdateWidget(covariant Explainable old) {
    super.didUpdateWidget(old);
    WidgetsBinding.instance.addPostFrameCallback((_) => _sync());
  }

  /// Re-reads the child's position after layout. Cheap, and it keeps the
  /// registry honest while lists scroll.
  void _sync() {
    if (!mounted) return;
    final box = _key.currentContext?.findRenderObject() as RenderBox?;
    if (box == null || !box.hasSize) return;
    ExplainRegistry.instance.register(
      widget.id,
      box.localToGlobal(Offset.zero) & box.size,
      widget.explanation,
    );
  }

  @override
  void dispose() {
    ExplainRegistry.instance.unregister(widget.id);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // Position can change without this widget rebuilding (an ancestor scrolls),
    // so refresh on every frame this widget is laid out in.
    WidgetsBinding.instance.addPostFrameCallback((_) => _sync());

    final hovered = context.select<AppState, bool>((s) => s.explainHoverId == widget.id);

    return AnimatedContainer(
      key: _key,
      duration: const Duration(milliseconds: 160),
      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(QRadii.inset),
        color: hovered ? QColors.violet.withValues(alpha: 0.16) : Colors.transparent,
        border: Border.all(
          color: hovered ? QColors.violet.withValues(alpha: 0.85) : Colors.transparent,
        ),
        boxShadow: hovered ? [BoxShadow(color: QColors.violet.withValues(alpha: 0.35), blurRadius: 18)] : null,
      ),
      child: widget.child,
    );
  }
}

/// The mark that says "the orb explains this": a quiet dotted violet line
/// under a value, the way a dotted underline marks a term with a definition.
/// Drag-to-explain had no signifier at all — nothing on screen told the
/// explainable numbers from the rest — so the gesture could only be learned
/// from the tutorial. The tutorial now says "a dotted number".
///
/// It belongs inside an [Explainable] and nowhere else: a mark on a value
/// the orb cannot explain would be a false promise, so that is asserted.
class ExplainMark extends StatelessWidget {
  final Widget child;
  const ExplainMark({super.key, required this.child});

  static final color = QColors.violetSoft.withValues(alpha: 0.7);

  @override
  Widget build(BuildContext context) {
    assert(
      context.findAncestorWidgetOfExactType<Explainable>() != null,
      'An ExplainMark says the orb explains this value: put it inside an Explainable.',
    );
    return CustomPaint(foregroundPainter: const _DottedUnderline(), child: child);
  }
}

class _DottedUnderline extends CustomPainter {
  const _DottedUnderline();

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()..color = ExplainMark.color;
    const r = 1.0, step = 4.0;
    final y = size.height - r;
    for (var x = r; x <= size.width - r; x += step) {
      canvas.drawCircle(Offset(x, y), r, paint);
    }
  }

  @override
  bool shouldRepaint(covariant _DottedUnderline oldDelegate) => false;
}

/// The sheet the orb opens when it is dropped on a value.
class ExplainSheet extends StatelessWidget {
  const ExplainSheet({super.key});

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    final ex = state.explainOpen;
    if (ex == null) return const SizedBox.shrink();

    final isAr = state.isAr;

    return Positioned.fill(
      child: GestureDetector(
        onTap: state.closeExplain,
        child: Container(
          color: QColors.scrim,
          alignment: Alignment.bottomCenter,
          child: GestureDetector(
            onTap: () {},
            child: Container(
              width: double.infinity,
              padding: const EdgeInsets.fromLTRB(20, 18, 20, 34),
              decoration: const BoxDecoration(
                color: QColors.cardSlate,
                border: Border(top: BorderSide(color: QColors.borderStrong)),
                borderRadius: BorderRadius.vertical(top: Radius.circular(QRadii.sheet)),
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Center(
                    child: Container(
                      width: 38,
                      height: 4,
                      decoration: BoxDecoration(color: QColors.borderStrong, borderRadius: BorderRadius.circular(QRadii.pill)),
                    ),
                  ),
                  const SizedBox(height: 16),
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const QamarMoon(size: 40),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(isAr ? ex.titleAr : ex.titleEn,
                                style: QText.display(size: 24, ar: isAr, color: QColors.textPrimary)),
                            const SizedBox(height: 6),
                            Text(isAr ? ex.bodyAr : ex.bodyEn,
                                style: QText.body(size: 14, height: 22, color: QColors.textHigh)),
                          ],
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 14),
                  Container(
                    padding: const EdgeInsets.all(13),
                    decoration: BoxDecoration(
                      color: QColors.violet.withValues(alpha: 0.10),
                      border: Border.all(color: QColors.violet.withValues(alpha: 0.35)),
                      borderRadius: BorderRadius.circular(QRadii.control),
                    ),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Icon(Icons.lightbulb_outline, size: 16, color: QColors.violetSoft),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(isAr ? ex.soWhatAr : ex.soWhatEn,
                              style: QText.body(size: 13, height: 20, color: QColors.textMid)),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 14),
                  Row(
                    children: [
                      Expanded(
                        child: QOutlineButton(
                          label: isAr ? 'اسأل قمر عن ده' : 'Ask Qamar about this',
                          onTap: () {
                            state.closeExplain();
                            state.openChat();
                          },
                          height: 46,
                          color: QColors.textMid,
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: QPrimaryButton(
                          label: isAr ? 'فهمت' : 'Got it',
                          onTap: state.closeExplain,
                          height: 46,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
