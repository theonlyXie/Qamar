import 'package:flutter/material.dart';

import '../state/app_state.dart';
import '../theme/app_theme.dart';
import '../theme/colors.dart';
import '../theme/text_styles.dart';

/// The words for the orb's hold, in one place: the Today tutorial card's
/// hold row and the coach mark above the orb say exactly the same thing.
abstract final class HoldCopy {
  static const doAr = 'استمر ضاغط عليه';
  static const doEn = 'Hold it';

  /// "تتكلم مع قمر" is held together by no-break spaces, so where the line
  /// wraps (in the mark's two lines) it is never split from its verb.
  static const whatAr = 'تتكلم\u00A0مع\u00A0قمر — بصوتك';
  static const whatEn = 'talk to Qamar — with your voice';

  static String line(bool isAr) => isAr ? '$doAr — $whatAr' : '$doEn — $whatEn';
}

/// A one-time hint by the orb (O1): after the tree has opened and closed
/// twice with no hold, the one gesture people have to learn is named where
/// it is done. It goes the moment they hold the moon or tap the hint, and it
/// never comes back ([AppState.holdCoachDue]).
///
/// The orb's layout places it, from the orb's own rect: centred on the moon,
/// kept inside the screen, with its [caret] on the moon's centre.
class HoldCoachMark extends StatelessWidget {
  final AppState state;

  const HoldCoachMark({super.key, required this.state});

  static const double width = 230;
  static const _fill = QColors.glass;
  static final _edge = QColors.violet.withValues(alpha: 0.55);

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
              border: Border.all(color: _edge),
              // It floats by its lighter fill and edge; a black shadow has
              // nothing to darken on this ground.
              borderRadius: BorderRadius.circular(QRadii.control),
            ),
            child: Row(
              children: [
                const Icon(Icons.mic_none, size: 16, color: QColors.violetSoft),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(HoldCopy.line(isAr), style: QText.body(size: 13, height: 18, color: QColors.textHigh)),
                ),
                const SizedBox(width: 6),
                const Icon(Icons.close, size: 14, color: QColors.textMuted),
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
