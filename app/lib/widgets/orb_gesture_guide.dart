import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../state/app_state.dart';
import '../theme/app_theme.dart';
import '../theme/colors.dart';
import '../theme/text_styles.dart';
import 'hold_coach_mark.dart';
import 'tree_overlay.dart';

/// The moon's three gestures, each ticked once the person has done it.
///
/// The same card in two places. On Today it is the tutorial: it holds the
/// one contextual slot until the first hold, and can be put away with "Got
/// it". There it keeps to the slot's 120 points (O15), so its last row never
/// reaches under the orb: a title row with "Got it", then the three gestures
/// side by side ([cellText]). In Me it is the help, and it stays for good, in
/// full, so a gesture forgotten after the tutorial is gone can always be
/// looked up again.
class OrbGestureGuide extends StatelessWidget {
  final AppState state;

  /// On Today, "Got it" puts it away; in Me there is nothing to put away.
  final bool dismissible;
  const OrbGestureGuide({super.key, required this.state, this.dismissible = true});

  /// The card's rows, in the order they are learned: tap, hold, drag. The
  /// hold row is the hold mark's own words (HoldCopy), so the two never
  /// drift apart.
  ///
  /// The tap row names the tree's own labels, read from the tree, so the
  /// words on the card are the words on the ring (they had drifted apart in
  /// Arabic: "مياه" and "حسابي" for a ring that says "الماء" and "أنا"). And
  /// it says what a tap does off Today too, since the card also lives in Me.
  static List<(OrbGesture, IconData, String, String, String, String)> rows() {
    final ar = kTreeNodes.map((n) => n.labelAr).join(' · ');
    final en = kTreeNodes.map((n) => n.labelEn).join(' · ');
    return [
        (OrbGesture.tap, Icons.touch_app_outlined, 'دوس على القمر', 'Tap the moon', 'تفتح الشجرة: $ar — ومن أي شاشة تانية ترجّعك للنهارده', 'opens the tree: $en — and from any other screen, it brings you back to Today'),
        (OrbGesture.hold, Icons.mic_none, HoldCopy.doAr, HoldCopy.doEn, HoldCopy.whatAr, HoldCopy.whatEn),
        // The explainable numbers carry a dotted line under them (ExplainMark).
        (OrbGesture.explain, Icons.open_with, 'اسحبه على رقم تحته نقط', 'Drag it onto a dotted number', 'يشرحه لك: من فين جه وإيه معناه', 'and it explains itself: where it came from, what it means'),
      ];
  }

  /// A gesture's words in its cell on Today, which has room for three short
  /// lines: what to do and what it does, in the rows' own words, shortened
  /// ("Tap it", as the card's title names the moon). The hold keeps its whole
  /// line, so the cell and the hold mark say exactly the same thing
  /// (HoldCopy.line).
  ///
  /// A no-break space holds each dash to the word before it, so a narrow
  /// cell never starts a line with one (and "يشرحه لك" stays together).
  static String cellText(OrbGesture g, bool isAr) => switch (g) {
        OrbGesture.tap => isAr ? 'دوس عليه\u00A0— تفتح الشجرة' : 'Tap it\u00A0— opens the tree',
        OrbGesture.hold => HoldCopy.line(isAr),
        OrbGesture.explain => isAr ? 'اسحبه على رقم تحته نقط\u00A0— يشرحه\u00A0لك' : 'Drag it onto a dotted number\u00A0— it explains itself',
      };

  static const cellKey = ValueKey('orb-gesture-cell');

  /// The glyph that leads a cell's words (13 points and a 4-point gap), and
  /// the cell's padding and the gap between cells.
  static const _glyph = Size(17, 13);
  static const _cellPad = 6.0;
  static const _gap = 5.0;

  /// The least share a cell's words are given, in letters, for [words] in
  /// [avail] points: each cell's share is its letter count, never under
  /// this floor, so a short cell is not squeezed. The floor is the smallest
  /// of 30 to 40 at which no cell needs more lines than the others must and
  /// none ends on a lone word (a last line under 40% of its width): at 30,
  /// the English "Tap it — opens the tree" left "tree" alone on a third
  /// line, while the Arabic fitted as it was.
  static int shareFloor(List<InlineSpan> words, List<int> letters, double avail, {required TextDirection direction, required TextScaler scaler}) {
    ({int lines, int lone}) layoutAt(int floor) {
      final shares = [for (final n in letters) math.max(n, floor)];
      final total = shares.fold(0, (a, b) => a + b);
      final inner = avail - _gap * (words.length - 1);
      var lines = 0, lone = 0;
      for (var i = 0; i < words.length; i++) {
        final width = inner * shares[i] / total - 2 * _cellPad;
        final p = TextPainter(text: words[i], textDirection: direction, textScaler: scaler)
          ..setPlaceholderDimensions(const [PlaceholderDimensions(size: _glyph, alignment: PlaceholderAlignment.middle)])
          ..layout(maxWidth: width);
        final metrics = p.computeLineMetrics();
        p.dispose();
        lines = math.max(lines, metrics.length);
        if (metrics.length > 1 && metrics.last.width < 0.4 * width) lone++;
      }
      return (lines: lines, lone: lone);
    }

    var best = 30;
    var bestAt = layoutAt(30);
    for (var floor = 32; floor <= 40; floor += 2) {
      final at = layoutAt(floor);
      if (at.lines < bestAt.lines || (at.lines == bestAt.lines && at.lone < bestAt.lone)) {
        best = floor;
        bestAt = at;
      }
    }
    return best;
  }

  @override
  Widget build(BuildContext context) => dismissible ? _today(context) : _help(context);

  /// Today's tutorial, within the slot: the title row carries "Got it", and
  /// the three gestures sit in one row of three cells, each at least 48
  /// points, ticked as they are done.
  Widget _today(BuildContext context) {
    final isAr = state.isAr;
    final learned = state.gesturesLearned;
    return Container(
      padding: const EdgeInsets.fromLTRB(8, 0, 8, 8),
      decoration: BoxDecoration(
        color: QColors.violet.withValues(alpha: 0.08),
        border: Border.all(color: QColors.violet.withValues(alpha: 0.3)),
        borderRadius: BorderRadius.circular(QRadii.card),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _titleRow(isAr),
          LayoutBuilder(builder: (context, box) {
            final gestures = rows();
            final words = [
              for (final (g, icon, _, _, _, _) in gestures)
                TextSpan(
                  children: [
                    WidgetSpan(
                      alignment: PlaceholderAlignment.middle,
                      child: Padding(
                        padding: const EdgeInsetsDirectional.only(end: 4),
                        child: Icon(
                          learned.contains(g) ? Icons.check_circle : icon,
                          size: 13,
                          color: learned.contains(g) ? QColors.green : QColors.violetSoft,
                        ),
                      ),
                    ),
                    TextSpan(text: cellText(g, isAr)),
                  ],
                  style: QText.body(size: 11, height: 15, color: learned.contains(g) ? QColors.textMuted : QColors.textMid),
                ),
            ];
            final letters = [for (final (g, _, _, _, _, _) in gestures) cellText(g, isAr).length];
            final floor = shareFloor(words, letters, box.maxWidth, direction: Directionality.of(context), scaler: MediaQuery.textScalerOf(context));
            return IntrinsicHeight(
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  for (var i = 0; i < gestures.length; i++) ...[
                    if (i > 0) const SizedBox(width: _gap),
                    // Each cell as wide as its words need, and never too
                    // narrow for a short line ([shareFloor]).
                    Expanded(
                      flex: math.max(letters[i], floor),
                      child: Container(
                        key: cellKey,
                        constraints: const BoxConstraints(minHeight: 48),
                        padding: const EdgeInsets.all(_cellPad),
                        decoration: BoxDecoration(
                          color: QColors.violet.withValues(alpha: learned.contains(gestures[i].$1) ? 0.04 : 0.1),
                          borderRadius: BorderRadius.circular(QRadii.inset),
                        ),
                        child: Text.rich(words[i]),
                      ),
                    ),
                  ],
                ],
              ),
            );
          }),
        ],
      ),
    );
  }

  Widget _titleRow(bool isAr) => Row(
        children: [
          Expanded(
            child: Text(
              isAr ? 'القمر بيفهم تلات حركات' : 'The moon knows three gestures',
              style: QText.body(size: 12, weight: FontWeight.w600, color: QColors.violetSoft),
            ),
          ),
          if (dismissible)
            // Small words, a full 48-point touch.
            Semantics(
              button: true,
              child: InkWell(
                borderRadius: BorderRadius.circular(QRadii.control),
                onTap: state.dismissOrbTutorial,
                child: ConstrainedBox(
                  constraints: const BoxConstraints(minWidth: 48, minHeight: 48),
                  child: Center(
                    widthFactor: 1,
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 6),
                      child: Text(isAr ? 'عارف' : 'Got it', style: QText.body(size: 12, color: QColors.textMuted)),
                    ),
                  ),
                ),
              ),
            ),
        ],
      );

  /// The help in Me: every row in full, and the day's free allowance.
  Widget _help(BuildContext context) {
    final isAr = state.isAr;
    final learned = state.gesturesLearned;
    final photos = state.photoQuota.limit;
    return Container(
      padding: const EdgeInsets.fromLTRB(14, 4, 14, 11),
      decoration: BoxDecoration(
        color: QColors.violet.withValues(alpha: 0.08),
        border: Border.all(color: QColors.violet.withValues(alpha: 0.3)),
        borderRadius: BorderRadius.circular(QRadii.card),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _titleRow(isAr),
          const SizedBox(height: 8),
          for (final (g, icon, doAr, doEn, whatAr, whatEn) in rows()) ...[
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 2),
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
                      '${isAr ? doAr : doEn} — ${isAr ? whatAr : whatEn}',
                      style: QText.body(size: 12, height: 18, color: learned.contains(g) ? QColors.textMuted : QColors.textMid),
                    ),
                  ),
                ],
              ),
            ),
          ],
          const SizedBox(height: 4),
          Text(
            isAr
                ? 'الكتابة والصوت ببلاش على طول. الصور ${state.iso('$photos')} في اليوم.'
                : 'Typing and speaking are always free. Photos, $photos a day.',
            style: QText.body(size: 11, height: 16, color: QColors.textMuted),
          ),
        ],
      ),
    );
  }
}
