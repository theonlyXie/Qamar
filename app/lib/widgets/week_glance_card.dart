import 'package:flutter/material.dart';

import '../state/app_state.dart';
import '../theme/app_theme.dart';
import '../theme/colors.dart';
import '../theme/layout.dart';
import '../theme/text_styles.dart';
import 'common.dart';

/// The week, on Today's slot on review day (O15): the one line from the
/// week's card the person did not expect ("You ate 24% more on Thursday than
/// the rest of the week."), and the way to the whole card on Progress.
class WeekGlanceCard extends StatelessWidget {
  final AppState state;
  const WeekGlanceCard({super.key, required this.state});

  static const openKey = ValueKey('week-card-open');

  @override
  Widget build(BuildContext context) {
    final isAr = state.isAr;
    final review = state.weekReview();
    return Container(
      padding: const EdgeInsetsDirectional.fromSTEB(16, 0, 8, 12),
      decoration: QDecor.card(
        gradient: const LinearGradient(colors: [QColors.cardMid, QColors.cardDeep]),
        border: QColors.violet.withValues(alpha: 0.35),
        radius: QRadii.card,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          // At least as tall as the control's whole touch (48pt, O11), so the
          // touch around its 34pt outline is never cut.
          ConstrainedBox(
            constraints: const BoxConstraints(minHeight: QLayout.minTap),
            child: Row(
              children: [
                Text(isAr ? 'أسبوعك مع قمر' : 'Your week with Qamar', style: QText.body(size: 11, weight: FontWeight.w600, color: QColors.violetSoft)),
                const Spacer(),
                QOutlineButton(key: openKey, label: isAr ? 'شوف الأسبوع' : 'See the week', onTap: state.openWeekCard, height: 34, color: QColors.textMid),
              ],
            ),
          ),
          Text(isAr ? review.insight.ar : review.insight.en, style: QText.body(size: 15, height: 21, weight: FontWeight.w600, color: QColors.textPrimary)),
        ],
      ),
    );
  }
}
