import 'package:flutter/material.dart';

import '../state/app_state.dart';
import '../theme/app_theme.dart';
import '../theme/colors.dart';
import '../theme/icons.dart';
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
    return Container(
      // The lines get the width they need to stay one line each, so every
      // kind keeps to the slot's 120 points in both languages.
      padding: const EdgeInsetsDirectional.fromSTEB(16, 0, 8, 12),
      decoration: QDecor.card(),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          // The label, the score, and the one way out, on one line: at
          // least as tall as that control's whole touch (48pt, O11), and
          // the same height when done, so the card does not change shape.
          ConstrainedBox(
            constraints: const BoxConstraints(minHeight: QLayout.minTap),
            child: Row(
              children: [
                Text(QText.eyebrowText(state.t.nextQuest, ar: isAr), style: QText.eyebrow(ar: isAr)),
                // What it pays is what the orb explains: the dotted value.
                if (state.showScore && q.amount > 0) ...[
                  const SizedBox(width: 4),
                  Explainable(
                    id: 'quest',
                    child: Row(mainAxisSize: MainAxisSize.min, children: [
                      const SuCoinIcon(size: 14),
                      const SizedBox(width: 4),
                      ExplainMark(child: Text('+${state.formatSu(q.amount)}', style: QText.number(size: 13, weight: FontWeight.w600, color: QColors.ink))),
                    ]),
                  ),
                ],
                const Spacer(),
                if (q.done)
                  const Padding(
                    padding: EdgeInsetsDirectional.only(end: 8),
                    child: Icon(QIcons.done, size: 20, color: QColors.ink),
                  )
                else
                  // A quiet way out: putting it away is not the day's
                  // thing to do, so it is words, not a button's outline;
                  // they end where the card's start inset mirrors them.
                  QTapArea(
                    key: notTodayKey,
                    onTap: state.skipQuest,
                    builder: (context, pressed) => Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 8),
                      child: Text(
                        isAr ? 'مش النهارده' : 'Not today',
                        style: QText.body(size: 13, weight: FontWeight.w500, color: pressed ? QColors.ink : QColors.inkSecondary),
                      ),
                    ),
                  ),
              ],
            ),
          ),
          Text(q.kind.title(ar: isAr, iso: state.iso), style: QText.body(size: 15, weight: FontWeight.w600, color: QColors.ink)),
          const SizedBox(height: 2),
          Text(
            q.done ? (isAr ? 'خلصت النهارده، واتسجّلت.' : 'Done for today, and logged.') : q.kind.why(ar: isAr),
            style: QText.body(size: 13, color: q.done ? QColors.ink : QColors.inkSecondary),
          ),
        ],
      ),
    );
  }
}
