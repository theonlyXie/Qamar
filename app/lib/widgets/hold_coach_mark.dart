import 'package:flutter/material.dart';

import '../state/app_state.dart';
import '../theme/app_theme.dart';
import '../theme/colors.dart';
import '../theme/icons.dart';
import '../theme/text_styles.dart';

/// The words for the orb's hold, in one place: the Today tutorial card's
/// hold row and the coach mark above the orb say exactly the same thing.
abstract final class HoldCopy {
  static const doAr = 'استمر ضاغط عليه';
  static const doEn = 'Hold it';

  /// "تتكلم مع قمر بصوتك" is held together by no-break spaces, so where the
  /// line wraps (in the mark's two lines) it is never split from its verb,
  /// and "بصوتك" never ends a line alone.
  static const whatAr = 'تتكلم\u00A0مع\u00A0قمر\u00A0بصوتك';
  static const whatEn = 'talk to Qamar with your voice';

  /// The dash is held to the verb before it, so it never starts a line (or
  /// stands on one alone, as it did in the gesture guide's narrow cell).
  static String line(bool isAr) => isAr ? '$doAr\u00A0— $whatAr' : '$doEn\u00A0— $whatEn';
}

/// A one-time hint over the orb (O1): after the Log sheet has opened and
/// closed twice with no hold, the one gesture people have to learn is named
/// where it is done. It goes the moment they hold the moon or tap the hint,
/// and it never comes back ([AppState.holdCoachDue]).
///
/// The tab bar's layout places it over the middle of the bar, its [caret]
/// on the orb: a white bubble with black words, the kit's white on the dark.
class HoldCoachMark extends StatelessWidget {
  final AppState state;

  const HoldCoachMark({super.key, required this.state});

  static const double width = 240;
  static const _fill = QColors.white;
  static const _edge = QColors.white;

  /// The small point between the mark and the moon, its tip toward the moon:
  /// [up] when the mark sits below the orb.
  static Widget caret({required bool up}) => IgnorePointer(
        key: caretKey,
        child: CustomPaint(size: const Size(14, 7), painter: _CaretPainter(up: up)),
      );

  static const caretKey = ValueKey('hold_coach_caret');

  @override
  Widget build(BuildContext context) {
    final isAr = state.isAr;
    return Directionality(
      textDirection: isAr ? TextDirection.rtl : TextDirection.ltr,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(QRadii.control),
          onTap: state.dismissHoldCoach,
          child: Container(
            width: width,
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
            decoration: BoxDecoration(
              color: _fill,
              // It floats by its white on the dark; a black shadow has
              // nothing to darken on this ground.
              borderRadius: BorderRadius.circular(QRadii.control),
            ),
            child: Row(
              children: [
                const QIcon(QIcons.mic, size: 20, color: QColors.onInk),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(HoldCopy.line(isAr), style: QText.body(size: 15, weight: FontWeight.w500, color: QColors.onInk)),
                ),
                const SizedBox(width: 6),
                const QIcon(QIcons.close, size: 18, color: QColors.onPastelSecondary),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _CaretPainter extends CustomPainter {
  final bool up;
  const _CaretPainter({required this.up});

  @override
  void paint(Canvas canvas, Size box) {
    // The base lies a point into the bubble, so the fill opens its border
    // where the two meet and they read as one shape.
    final tip = up ? 0.0 : box.height;
    final base = up ? box.height : 0.0;
    final edges = Path()
      ..moveTo(0, base)
      ..lineTo(box.width / 2, tip)
      ..lineTo(box.width, base);
    canvas.drawPath(Path.from(edges)..close(), Paint()..color = HoldCoachMark._fill);
    canvas.drawPath(
      edges,
      Paint()
        ..color = HoldCoachMark._edge
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1,
    );
  }

  @override
  bool shouldRepaint(_CaretPainter old) => old.up != up;
}
