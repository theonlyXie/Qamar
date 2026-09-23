import 'package:flutter/material.dart';

import '../state/app_state.dart';
import '../theme/app_theme.dart';
import '../theme/colors.dart';
import '../theme/layout.dart';
import '../theme/text_styles.dart';
import 'common.dart';
import 'explain.dart';

/// The day's quest in Today's slot (O2, O15): what the day lacks, in one
/// line, and why. There is no Accept and no Replace: the meal or glass that
/// does what it asks pays it, on the server. The person can put it away for
/// the day ("not today"), and once it is met it shows done. Its coin shows
/// what it would pay, or did pay, within the day's cap, and no coin at 0.
/// It is part of the score, so it is drawn only while the score is shown.
class QuestCard extends StatelessWidget {
  final AppState state;
  const QuestCard({super.key, required this.state});

  static const notTodayKey = ValueKey('quest-not-today');

  @override
  Widget build(BuildContext context) {
    final q = state.quest;
    if (q == null) return const SizedBox.shrink();
    final isAr = state.isAr;
    return Explainable(
      id: 'quest',
      child: Container(
        padding: const EdgeInsetsDirectional.fromSTEB(16, 0, 8, 10),
        decoration: QDecor.card(color: QColors.surface, radius: QRadii.card),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            // The label, the score, and the one control, on one line: at least
            // as tall as the control's whole touch (48pt, O11), so the touch
            // around its 34pt outline is never cut, and the same height when
            // done, so the card does not change shape.
            ConstrainedBox(
              constraints: const BoxConstraints(minHeight: QLayout.minTap),
              child: Row(
                children: [
                  Text(state.t.nextQuest, style: QText.body(size: 11, weight: FontWeight.w500, color: QColors.inkTertiary)),
                  if (state.showScore && q.amount > 0) ...[
                    const SizedBox(width: 8),
                    const SuCoinIcon(size: 14),
                    const SizedBox(width: 4),
                    ExplainMark(child: Text('+${state.formatSu(q.amount)}', style: QText.number(size: 12, weight: FontWeight.w600, color: QColors.ink))),
                  ],
                  const Spacer(),
                  if (q.done)
                    const Padding(
                      padding: EdgeInsetsDirectional.only(end: 8),
                      child: Icon(Icons.check_circle_outline, size: 22, color: QColors.ink),
                    )
                  else
                    QOutlineButton(key: notTodayKey, label: isAr ? 'مش النهارده' : 'Not today', onTap: state.skipQuest, height: 34, color: QColors.inkTertiary),
                ],
              ),
            ),
            Text(q.kind.title(ar: isAr, iso: state.iso), style: QText.body(size: 15, height: 22, weight: FontWeight.w600, color: QColors.ink)),
            const SizedBox(height: 2),
            Text(
              q.done ? (isAr ? 'خلصت النهارده، واتسجّلت.' : 'Done for today, and logged.') : q.kind.why(ar: isAr),
              style: QText.body(size: 13, height: 18, color: q.done ? QColors.ink : QColors.inkTertiary),
            ),
          ],
        ),
      ),
    );
  }
}
