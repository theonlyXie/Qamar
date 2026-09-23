import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:provider/provider.dart';

import '../l10n/strings.dart';
import '../services/repositories.dart';
import '../state/app_state.dart';
import '../theme/app_theme.dart';
import '../theme/colors.dart';
import '../theme/layout.dart';
import '../theme/text_styles.dart';
import '../services/config.dart';
import '../widgets/common.dart';
import '../widgets/explain.dart';
import '../widgets/review_card.dart';

/// Progress, drawn from what was actually logged.
///
/// Nothing on this screen is illustrative. A week with no meals in it shows
/// seven empty days and says the chart fills in as meals are logged; a weight
/// trend needs two real readings before a line is drawn at all. Showing a
/// convincing chart of a week that never happened is the one thing a progress
/// screen must never do.
class ProgressScreen extends StatelessWidget {
  const ProgressScreen({super.key});

  /// The streak card, found by tests: drawn only while the score is shown.
  static const streakKey = ValueKey('progress-streak');

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    final t = state.t;
    final isAr = state.isAr;

    final week = state.week();
    final target = state.target().kcal;
    final active = state.activeDays();
    final logged = state.mealsThisWeek();
    final inRange = state.daysInRange();
    final weights = state.weightHistory;
    final streak = state.streak();

    // The tallest bar is the biggest day, or the target if every day is under
    // it — so a normal week fills the chart instead of hugging the floor.
    final peak = [target.toDouble(), ...week.map((d) => d.kcal.toDouble())].reduce((a, b) => a > b ? a : b);

    return ListView(
      padding: const EdgeInsets.fromLTRB(20, QLayout.pageTop, 20, QLayout.pageBottom),
      children: [
        Row(children: [
          QBackButton(onTap: state.back, isAr: isAr),
          const SizedBox(width: 6),
          Expanded(child: Text(t.progress, style: QText.display(size: 30, ar: QText.arabic(t.progress), color: QColors.textPrimary))),
        ]),
        const SizedBox(height: 4),
        Text(t.progressSub, style: QText.body(size: 14, height: 22, color: QColors.textMuted)),
        const SizedBox(height: 14),
        // The streak keeps score, so it goes with "Points and streaks" (O4)
        // and the screen closes up behind it.
        if (state.showScore) ...[
          Explainable(
            key: ProgressScreen.streakKey,
            id: 'streak',
            child: Container(
              padding: const EdgeInsets.all(16),
              decoration: QDecor.card(
                gradient: const LinearGradient(colors: [QColors.cardMid, QColors.cardDeep]),
                // One edge for every card on the screen: state is said by the
                // eyebrow's colour, not by a third border colour.
                border: QColors.borderSoft,
                radius: QRadii.card,
              ),
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        ExplainMark(child: Text(isAr ? 'السلسلة' : 'Streak', style: QText.body(size: 11, weight: FontWeight.w500, color: QColors.textMuted))),
                        const SizedBox(height: 4),
                        Text(
                          streak.current == 0
                              ? (isAr ? 'سجّل وجبة النهاردة وتبدأ سلسلتك.' : 'Log a meal today and your streak begins.')
                              : streak.atRisk
                                  ? (isAr
                                      ? '${state.iso('${streak.current}')} ${streak.current == 1 ? 'يوم' : 'أيام'} · وجبة واحدة قبل نص الليل تكمّلها'
                                      : '${streak.current} ${streak.current == 1 ? 'day' : 'days'} · one meal before midnight keeps it')
                                  : (isAr
                                      ? '${state.iso('${streak.current}')} ${streak.current == 1 ? 'يوم' : 'أيام'} ورا بعض · النهاردة محسوب'
                                      : '${streak.current} ${streak.current == 1 ? 'day' : 'days'} in a row · today counted'),
                          style: QText.body(size: 14, height: 22, color: QColors.textHigh),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          isAr
                              ? 'أطول سلسلة ${state.iso('${streak.best}')} · تجميد متاح: ${state.iso('${streak.freezesAvailable}')}'
                              : 'best ${streak.best} · freezes available: ${streak.freezesAvailable}',
                          style: QText.number(size: 11, color: QColors.textMuted),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 12),
                  Text(
                    state.iso('${streak.current}'),
                    // A figure, in the figures' face: in the serif's old-style
                    // numerals a 1 read as a capital I.
                    style: QText.number(size: 28, weight: FontWeight.w600, color: streak.current > 0 ? QColors.textHigh : QColors.textMuted),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 14),
        ],
        _ShareableReview(state: state),
        const SizedBox(height: 14),
        Container(
          padding: const EdgeInsets.all(16),
          decoration: QDecor.card(
            color: QColors.cardDeep,
            border: QColors.borderSoft,
            radius: QRadii.card,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(t.thisWeek, style: QText.body(size: 11, weight: FontWeight.w500, color: active > 0 ? QColors.green : QColors.textMuted)),
              const SizedBox(height: 4),
              Text(
                active == 0
                    ? (isAr ? 'لسه مفيش وجبات مسجلة الأسبوع ده. أول ما تسجّل، الأرقام تظهر هنا.' : 'Nothing logged this week yet. The numbers appear here as soon as you log.')
                    : (isAr
                        ? '${state.iso('$active')} ${active == 1 ? 'يوم' : 'أيام'} نشاط · ${state.iso('$logged')} وجبة مسجلة${state.generalGuidance ? '' : ' · ${state.iso('$inRange')} من ${state.iso('$active')} داخل النطاق'}'
                        : '$active active ${active == 1 ? 'day' : 'days'} · $logged ${logged == 1 ? 'meal' : 'meals'} logged${state.generalGuidance ? '' : ' · $inRange of $active in target range'}'),
                style: QText.body(size: 14, height: 22, color: QColors.textHigh),
              ),
            ],
          ),
        ),
        const SizedBox(height: 14),
        Container(
          padding: const EdgeInsets.all(16),
          decoration: QDecor.card(gradient: const LinearGradient(colors: [QColors.cardMid, QColors.cardDeep]), radius: QRadii.card),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(t.activeDays, style: QText.body(size: 11, weight: FontWeight.w500, color: QColors.textMuted)),
                  // No target is set on the general-guidance route, so none is named.
                  if (!state.generalGuidance) Text(isAr ? 'الهدف ${state.iso('$target')}' : 'target $target', style: QText.number(size: 11, color: QColors.textMuted)),
                ],
              ),
              const SizedBox(height: 12),
              SizedBox(
                height: 110,
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    for (var i = 0; i < week.length; i++) ...[
                      if (i > 0) const SizedBox(width: 8),
                      Expanded(child: _DayBar(day: week[i], peak: peak, target: target, letter: (isAr ? kWeekdayShortAr : kWeekdayShortEn)[week[i].day.weekday - 1])),
                    ],
                  ],
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 14),
        Container(
          padding: const EdgeInsets.all(16),
          decoration: QDecor.card(gradient: const LinearGradient(colors: [QColors.cardMid, QColors.cardDeep]), radius: QRadii.card),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(t.weightTrend, style: QText.body(size: 11, weight: FontWeight.w500, color: QColors.textMuted)),
              const SizedBox(height: 10),
              if (weights.length < 2)
                SizedBox(
                  height: 90,
                  child: Center(
                    child: Text(
                      isAr ? 'محتاج قياسين على الأقل قبل ما أرسم اتجاه.' : 'A trend needs at least two readings.',
                      textAlign: TextAlign.center,
                      style: QText.body(size: 13, height: 20, color: QColors.textMuted),
                    ),
                  ),
                )
              else ...[
                SizedBox(width: double.infinity, height: 90, child: CustomPaint(painter: _WeightTrendPainter(weights))),
                const SizedBox(height: 10),
                Text(
                  _trendLine(isAr, weights),
                  style: QText.body(size: 13, color: QColors.textMuted),
                ),
              ],
            ],
          ),
        ),
        const SizedBox(height: 14),
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: QColors.blue.withValues(alpha: 0.1),
            border: Border.all(color: QColors.blue.withValues(alpha: 0.4)),
            borderRadius: BorderRadius.circular(QRadii.card),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(t.weeklyInsight, style: QText.body(size: 11, weight: FontWeight.w500, color: QColors.skyBlue)),
              const SizedBox(height: 4),
              // An insight is a claim about the person's week. Until there are
              // enough logged days to support one, this says what is missing
              // rather than asserting a pattern nobody measured.
              Text(
                active < 3
                    ? (isAr
                        ? 'رأي الأسبوع بيظهر بعد ٣ أيام مسجلة. لسه ${state.iso('${3 - active}')} ${3 - active == 1 ? 'يوم' : 'أيام'}.'
                        : 'The weekly insight appears after 3 logged days — ${3 - active} to go.')
                    : (isAr
                        ? 'من ${state.iso('$active')} أيام مسجلة، ${state.iso('$inRange')} قربوا من هدفك. المتوسط ${state.iso('${_average(week)}')} سعرة في اليوم المسجّل.'
                        : 'Across $active logged days, $inRange landed near your target. Your average on a logged day is ${_average(week)} kcal.'),
                style: QText.body(size: 14, height: 22, color: QColors.textHigh),
              ),
            ],
          ),
        ),
      ],
    );
  }

  static int _average(List<DayTotals> week) {
    final logged = week.where((d) => d.meals > 0).toList();
    if (logged.isEmpty) return 0;
    return (logged.fold(0, (s, d) => s + d.kcal) / logged.length).round();
  }

  static String _trendLine(bool isAr, List<WeightReading> w) {
    final delta = w.last.kg - w.first.kg;
    final days = w.last.at.difference(w.first.at).inDays;
    final span = isAr ? 'على مدى ${days} يوم' : 'over $days days';
    if (delta.abs() < 0.3) {
      return isAr ? 'وزنك ثابت تقريباً $span. قياس واحد مش دليل.' : 'Essentially level $span. A single reading is not evidence.';
    }
    final amount = delta.abs().toStringAsFixed(1);
    if (isAr) {
      return '${delta < 0 ? 'نزلت' : 'زدت'} $amount كجم $span. قياس واحد مش دليل.';
    }
    return '${delta < 0 ? 'Down' : 'Up'} $amount kg $span. A single reading is not evidence.';
  }
}

class _DayBar extends StatelessWidget {
  final DayTotals day;
  final double peak;
  final int target;
  final String letter;
  const _DayBar({required this.day, required this.peak, required this.target, required this.letter});

  @override
  Widget build(BuildContext context) {
    final empty = day.meals == 0;
    // A minimum sliver keeps the day visible as a day; it is drawn faint so it
    // never reads as a small amount of food.
    final factor = empty ? 0.02 : (day.kcal / peak).clamp(0.06, 1.0);

    return Column(
      mainAxisAlignment: MainAxisAlignment.end,
      children: [
        Expanded(
          child: Align(
            alignment: Alignment.bottomCenter,
            child: FractionallySizedBox(
              heightFactor: factor,
              widthFactor: 1,
              child: Container(
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(QRadii.inset),
                  gradient: empty ? null : const LinearGradient(begin: Alignment.topCenter, end: Alignment.bottomCenter, colors: [QColors.cyan, QColors.blue]),
                  color: empty ? QColors.borderSoft : null,
                ),
              ),
            ),
          ),
        ),
        const SizedBox(height: 6),
        Text(letter, style: QText.number(size: 11, color: empty ? QColors.textMuted : QColors.textMid)),
      ],
    );
  }
}

class _WeightTrendPainter extends CustomPainter {
  final List<WeightReading> readings;
  const _WeightTrendPainter(this.readings);

  @override
  void paint(Canvas canvas, Size size) {
    if (readings.length < 2) return;

    final first = readings.first.at.millisecondsSinceEpoch.toDouble();
    final last = readings.last.at.millisecondsSinceEpoch.toDouble();
    final span = (last - first).abs() < 1 ? 1.0 : last - first;

    var lo = readings.first.kg, hi = readings.first.kg;
    for (final r in readings) {
      if (r.kg < lo) lo = r.kg;
      if (r.kg > hi) hi = r.kg;
    }
    // A flat series would otherwise divide by zero and a 0.2 kg wobble would
    // fill the whole card; both are handled by a minimum 2 kg window.
    final mid = (lo + hi) / 2;
    if (hi - lo < 2) {
      lo = mid - 1;
      hi = mid + 1;
    }

    Offset at(WeightReading r) {
      final x = 8 + (r.at.millisecondsSinceEpoch - first) / span * (size.width - 16);
      final y = size.height - 12 - (r.kg - lo) / (hi - lo) * (size.height - 24);
      return Offset(x, y);
    }

    final path = Path();
    for (var i = 0; i < readings.length; i++) {
      final p = at(readings[i]);
      i == 0 ? path.moveTo(p.dx, p.dy) : path.lineTo(p.dx, p.dy);
    }

    canvas.drawPath(
      path,
      Paint()
        ..color = QColors.violet
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2.5
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round,
    );
    for (final r in readings) {
      canvas.drawCircle(at(r), 2.5, Paint()..color = QColors.violet.withValues(alpha: 0.6));
    }
    canvas.drawCircle(at(readings.last), 5, Paint()..color = QColors.cyan);
  }

  @override
  bool shouldRepaint(covariant _WeightTrendPainter old) => old.readings != readings;
}

/// The week's card, exactly as it will be shared, with the two controls
/// that are not part of the picture: share it, show numbers.
class _ShareableReview extends StatefulWidget {
  final AppState state;
  const _ShareableReview({required this.state});

  @override
  State<_ShareableReview> createState() => _ShareableReviewState();
}

class _ShareableReviewState extends State<_ShareableReview> {
  final _cardKey = GlobalKey();
  bool _busy = false;

  Future<void> _share() async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      final boundary = _cardKey.currentContext?.findRenderObject() as RenderRepaintBoundary?;
      if (boundary == null) return;
      final image = await boundary.toImage(pixelRatio: 3);
      final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
      if (bytes == null) return;
      await widget.state.shareReview(bytes.buffer.asUint8List());
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final state = widget.state;
    final isAr = state.isAr;
    final review = state.weekReview();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Center(
          child: RepaintBoundary(
            key: _cardKey,
            child: ReviewCard(
              review: review,
              isAr: isAr,
              showNumbers: state.reviewShowNumbers,
              showStreak: state.showScore,
              footer: QamarConfig.site.replaceFirst('https://', ''),
              iso: state.iso,
            ),
          ),
        ),
        const SizedBox(height: 10),
        Row(
          children: [
            Expanded(
              child: QOutlineButton(
                label: _busy ? (isAr ? 'لحظة…' : 'One moment…') : (isAr ? 'شارك كارت الأسبوع' : 'Share the week'),
                onTap: _busy ? null : _share,
                height: 40,
                color: QColors.violetSoft,
              ),
            ),
            const SizedBox(width: 12),
            Text(isAr ? 'الأرقام' : 'Numbers', style: QText.body(size: 12, color: QColors.textMuted)),
            const SizedBox(width: 4),
            Switch.adaptive(
              value: state.reviewShowNumbers,
              onChanged: state.setReviewShowNumbers,
            ),
          ],
        ),
        Text(
          isAr ? 'الكارت من غير وزن أبداً، ومن غير سعرات إلا لو فتحت الأرقام.' : 'Never your weight; calories only if you turn numbers on.',
          style: QText.body(size: 11, color: QColors.textMuted),
        ),
      ],
    );
  }
}
