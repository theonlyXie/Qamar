import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../l10n/words.dart';
import '../models/days.dart';
import '../services/config.dart';
import '../services/repositories.dart';
import '../state/app_state.dart';
import '../theme/app_theme.dart';
import '../theme/colors.dart';
import '../theme/icons.dart';
import '../theme/layout.dart';
import '../theme/text_styles.dart';
import '../widgets/common.dart';
import '../widgets/hero_number.dart';
import '../widgets/explain.dart';
import '../widgets/kit.dart';
import '../widgets/review_card.dart';

/// Progress (the kit's Analysis page): how the week is going, read at a
/// glance, and the card to share.
///
/// One figure, the days logged this week, large on the mint card; the run,
/// on lime, while the score is shown; the week's card (a moon a day, the
/// sentence the person did not expect, the one change) with the one way to
/// send it; and the weight's direction once there are two readings to draw
/// it from.
///
/// Nothing here is illustrative. A week with nothing logged says so in
/// words, not with a lonely zero; the moons of unlogged days rest; and no
/// weight line is drawn from fewer than two real readings.
class ProgressScreen extends StatelessWidget {
  const ProgressScreen({super.key});

  /// The streak card, found by tests: drawn only while the score is shown.
  static const streakKey = ValueKey('progress-streak');

  /// "Share the week", found by tests: it waits for three logged days.
  static const shareKey = ValueKey('progress-share-week');

  /// The week's figure, and the calories switch under the card, for tests.
  static const weekKey = ValueKey('progress-week');
  static const numbersKey = ValueKey('progress-numbers');

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    final weights = state.weightHistory;
    return ListView(
      padding: const EdgeInsets.fromLTRB(20, QLayout.pageTop, 20, QLayout.pageBottom),
      children: [
        // A tab's page: its name, and no way back (the tab bar is the way).
        QPageTitle(title: state.t.progress, isAr: state.isAr),
        const SizedBox(height: 16),
        _WeekFigure(state: state),
        const SizedBox(height: 14),
        // The streak keeps score, so it goes with "Points and streaks" (O4),
        // and the week's card moves up into its place.
        if (state.showScore) ...[
          _StreakCard(key: streakKey, state: state),
          const SizedBox(height: 14),
        ],
        _ShareableReview(state: state),
        // The weight's direction needs two readings; until then there is
        // nothing to draw, and the screen closes up.
        if (weights.length >= 2) ...[
          const SizedBox(height: 24),
          _WeightCard(state: state, readings: weights),
        ],
      ],
    );
  }

  /// The weight's direction over the readings, as a sentence: the change and
  /// the calendar days it took ([Days]), counted as each language counts
  /// ([Counted]), in the app's digits.
  static String trendLine(bool isAr, List<WeightReading> w, String Function(String) iso) {
    final delta = w.last.kg - w.first.kg;
    final span = Counted.day.of(Days.between(w.first.at, w.last.at), ar: isAr, iso: iso);
    if (delta.abs() < 0.3) return isAr ? 'وزنك ثابت تقريباً بقاله $span.' : 'Steady for $span.';
    final amount = delta.abs().toStringAsFixed(1);
    if (isAr) return '${delta < 0 ? 'نزلت' : 'زدت'} ${iso(amount)} كجم في $span.';
    return '${delta < 0 ? 'Down' : 'Up'} $amount kg in $span.';
  }
}

/// The screen's one figure: how many of the last seven days have a meal
/// logged, as the screen's large figure, with the meals under it. A week
/// with none says so.
class _WeekFigure extends StatelessWidget {
  final AppState state;
  const _WeekFigure({required this.state});

  @override
  Widget build(BuildContext context) {
    final isAr = state.isAr;
    final days = state.activeDays();
    final meals = Counted.meal.of(state.mealsThisWeek(), ar: isAr, iso: state.iso);
    // "of 7 days": the noun agrees with the seven, so it reads right beside
    // any figure, one or six.
    final ofSeven = isAr ? 'من ${state.iso('7')} أيام متسجّلة' : 'of 7 days logged';
    // The kit's mint header card, the week's one figure on it.
    return PastelCard(
      key: ProgressScreen.weekKey,
      color: QColors.mint,
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(children: [
            Expanded(child: Text(state.t.thisWeek, style: QText.body(size: 18, weight: FontWeight.w600, color: QColors.onPastel))),
            const PastelGlyph(QIcons.calendar, size: 36),
          ]),
          const SizedBox(height: 8),
          if (days == 0)
            Text(
              isAr ? 'لسه مفيش أكل متسجّل الأسبوع ده. أول وجبة تسجّلها هتبان هنا.' : 'Nothing logged this week yet. Your first meal shows up here.',
              style: QText.body(size: 17, color: QColors.onPastel),
            )
          else ...[
            HeroNumber(
              state.digits('$days'),
              color: QColors.onPastel,
              semanticsLabel: isAr ? '${state.iso('$days')} $ofSeven' : '$days $ofSeven',
            ),
            const SizedBox(height: 8),
            // Arabic takes its own comma: beside Arabic-Indic digits a "·"
            // reads as a zero.
            Text(isAr ? '$ofSeven، $meals' : '$ofSeven · $meals', style: QText.body(size: 15, weight: FontWeight.w500, color: QColors.onPastelSecondary)),
          ],
        ],
      ),
    );
  }
}

/// The run of days with a meal: its length, and one line when there is
/// something to say about it (today still open, or a longer run behind it).
class _StreakCard extends StatelessWidget {
  final AppState state;
  const _StreakCard({super.key, required this.state});

  @override
  Widget build(BuildContext context) {
    final isAr = state.isAr;
    final streak = state.streak();
    String days(int n) => Counted.day.of(n, ar: isAr, iso: state.iso);
    final String? note = streak.current == 0
        ? (isAr ? 'سجّل وجبة النهارده وتبدأ سلسلتك.' : 'Log a meal today to start one.')
        : streak.atRisk
            ? (isAr ? 'وجبة واحدة قبل نص الليل تكمّلها.' : 'One meal before midnight keeps it going.')
            : streak.best > streak.current
                ? (isAr ? 'أطول سلسلة: ${days(streak.best)}' : 'Best: ${days(streak.best)}')
                : null;
    final value = streak.current == 0
        ? (isAr ? 'لسه' : 'Not yet')
        : streak.atRisk
            ? days(streak.current)
            : (isAr ? '${days(streak.current)} ورا بعض' : '${days(streak.current)} in a row');
    // On the kit's lime. The value's explainable inset (Explainable's own)
    // takes the last of the end padding, so the run ends where the card's
    // content does.
    return PastelCard(
      color: QColors.lime,
      padding: const EdgeInsetsDirectional.fromSTEB(16, 14, 15, 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(children: [
            const PastelGlyph(QIcons.flame, size: 36),
            const SizedBox(width: 10),
            Text(isAr ? 'السلسلة' : 'Streak', style: QText.body(size: 17, weight: FontWeight.w600, color: QColors.onPastel)),
            const Spacer(),
            // The run is what the orb explains: the dotted value.
            Explainable(
              id: 'streak',
              child: ExplainMark(child: Text(value, style: QText.number(size: 15, weight: FontWeight.w600, color: QColors.onPastel, ar: isAr))),
            ),
          ]),
          if (note != null) ...[
            const SizedBox(height: 4),
            Padding(
              padding: const EdgeInsetsDirectional.only(start: 46),
              child: Text(note, style: QText.body(size: 13, color: QColors.onPastelSecondary)),
            ),
          ],
        ],
      ),
    );
  }
}

/// The weight's direction: the sentence, and the line through the readings,
/// drawn from the start edge as the week's moons are.
class _WeightCard extends StatelessWidget {
  final AppState state;
  final List<WeightReading> readings;
  const _WeightCard({required this.state, required this.readings});

  @override
  Widget build(BuildContext context) {
    final isAr = state.isAr;
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: QDecor.card(),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(state.t.weightTrend, style: QText.body(size: 16, weight: FontWeight.w600, color: QColors.ink)),
          const SizedBox(height: 6),
          Text(ProgressScreen.trendLine(isAr, readings, state.iso), style: QText.body(size: 17, color: QColors.ink)),
          const SizedBox(height: 16),
          ExcludeSemantics(
            child: SizedBox(
              width: double.infinity,
              height: 72,
              child: CustomPaint(painter: _WeightTrendPainter(readings, rtl: isAr)),
            ),
          ),
          const SizedBox(height: 12),
          Text(isAr ? 'قياس واحد مش اتجاه.' : 'One reading is not a trend.', style: QText.body(size: 13, color: QColors.inkTertiary)),
        ],
      ),
    );
  }
}

class _WeightTrendPainter extends CustomPainter {
  final List<WeightReading> readings;
  final bool rtl;
  const _WeightTrendPainter(this.readings, {required this.rtl});

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
      final along = 6 + (r.at.millisecondsSinceEpoch - first) / span * (size.width - 12);
      final y = size.height - 6 - (r.kg - lo) / (hi - lo) * (size.height - 12);
      // Time runs the way the page reads: from the right in Arabic.
      return Offset(rtl ? size.width - along : along, y);
    }

    final path = Path();
    for (var i = 0; i < readings.length; i++) {
      final p = at(readings[i]);
      i == 0 ? path.moveTo(p.dx, p.dy) : path.lineTo(p.dx, p.dy);
    }
    canvas.drawPath(
      path,
      Paint()
        ..color = QColors.inkSecondary
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round,
    );
    for (final r in readings) {
      canvas.drawCircle(at(r), 2.5, Paint()..color = QColors.inkSecondary);
    }
    // The latest reading, where the line ends: the one lit dot, in the
    // kit's lavender.
    canvas.drawCircle(at(readings.last), 5, Paint()..color = QColors.lavender);
  }

  @override
  bool shouldRepaint(covariant _WeightTrendPainter old) => old.readings != readings || old.rtl != rtl;
}

/// The week's card, exactly as it will be shared, and under it the two
/// controls that are not part of the picture: send it, and whether the
/// calories go with it.
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
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // As wide as the page's cards, so its edges line up with theirs; the
        // picture shared is the card as it is seen.
        LayoutBuilder(
          builder: (context, box) => Center(
            child: RepaintBoundary(
              key: _cardKey,
              child: ReviewCard(
                review: review,
                isAr: isAr,
                showNumbers: state.reviewShowNumbers,
                showStreak: state.showScore,
                footer: QamarConfig.site.replaceFirst('https://', ''),
                iso: state.iso,
                width: math.min(box.maxWidth, 420),
              ),
            ),
          ),
        ),
        const SizedBox(height: 12),
        // It waits for three logged days, as the week card on Today does:
        // before then the card's sentence is what is still missing, said to
        // the person, and that sentence is the reason it waits.
        QOutlineButton(
          key: ProgressScreen.shareKey,
          icon: QIcons.share,
          label: _busy ? (isAr ? 'بجهّز الكارت…' : 'Getting the card ready…') : (isAr ? 'شارك الأسبوع' : 'Share the week'),
          onTap: _busy || !review.enough ? null : _share,
        ),
        const SizedBox(height: 4),
        _SwitchRow(
          key: ProgressScreen.numbersKey,
          label: isAr ? 'السعرات على الكارت' : 'Calories on the card',
          note: isAr ? 'وزنك عمره ما بيظهر عليه.' : 'Your weight never goes on it.',
          value: state.reviewShowNumbers,
          onChanged: state.setReviewShowNumbers,
        ),
      ],
    );
  }
}

/// A setting on a row: its words, and the switch at the end. The whole row
/// is the control, and one control to a screen reader.
class _SwitchRow extends StatelessWidget {
  final String label;
  final String? note;
  final bool value;
  final ValueChanged<bool> onChanged;
  const _SwitchRow({super.key, required this.label, this.note, required this.value, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    return MergeSemantics(
      child: QTapArea(
        onTap: () {
          HapticFeedback.selectionClick();
          onChanged(!value);
        },
        builder: (context, pressed) => Padding(
          padding: const EdgeInsets.symmetric(vertical: 4),
          child: Row(children: [
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
                Text(label, style: QText.body(size: 15, weight: FontWeight.w500, color: QColors.ink)),
                if (note != null) Text(note!, style: QText.body(size: 13, color: QColors.inkSecondary)),
              ]),
            ),
            const SizedBox(width: 12),
            Switch.adaptive(value: value, onChanged: onChanged),
          ]),
        ),
      ),
    );
  }
}
