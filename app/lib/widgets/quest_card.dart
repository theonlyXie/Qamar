import 'package:flutter/material.dart';

import '../state/app_state.dart';
import '../theme/app_theme.dart';
import '../theme/colors.dart';
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
        padding: const EdgeInsetsDirectional.fromSTEB(16, 6, 8, 10),
        decoration: QDecor.card(color: QColors.cardDeep, radius: QRadii.xl),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            // The label, the score, and the one control, on one line.
            SizedBox(
              height: 36,
              child: Row(
                children: [
                  Text(state.t.nextQuest, style: QText.body(size: 11, weight: FontWeight.w500, color: QColors.textMuted, letterSpacing: 0.4)),
                  if (state.showScore && q.amount > 0) ...[
                    const SizedBox(width: 8),
                    const SuCoinIcon(size: 14),
                    const SizedBox(width: 4),
                    ExplainMark(child: Text('+${state.formatSu(q.amount)}', style: QText.number(size: 12, weight: FontWeight.w600, color: QColors.gold))),
                  ],
                  const Spacer(),
                  if (q.done)
                    const Padding(
                      padding: EdgeInsetsDirectional.only(end: 8),
                      child: Icon(Icons.check_circle_outline, size: 22, color: QColors.green),
                    )
                  else
                    QOutlineButton(key: notTodayKey, label: isAr ? 'مش النهارده' : 'Not today', onTap: state.skipQuest, height: 34, color: QColors.textMuted),
                ],
              ),
            ),
            Text(q.kind.title(ar: isAr, iso: state.iso), style: QText.body(size: 16, height: 22, weight: FontWeight.w600, color: QColors.textPrimary)),
            const SizedBox(height: 2),
            Text(
              q.done ? (isAr ? 'خلصت النهارده، واتسجّلت.' : 'Done for today, and logged.') : q.kind.why(ar: isAr),
              style: QText.body(size: 13, height: 18, color: q.done ? QColors.green : QColors.textMuted),
            ),
          ],
        ),
      ),
    );
  }
}
