import 'package:flutter/material.dart';

import '../state/app_state.dart';
import '../theme/colors.dart';
import '../theme/icons.dart';
import '../theme/text_styles.dart';
import 'common.dart';
import 'kit.dart';
import 'review_card.dart';

/// The week, in Today's slot on review day (O15): the one line from the
/// week's card the person did not expect ("You ate 24% more on Thursday than
/// the rest of the week."). The whole card is the way to that card on
/// Progress, one tap, and says so.
class WeekGlanceCard extends StatelessWidget {
  final AppState state;
  const WeekGlanceCard({super.key, required this.state});

  /// The card itself, which is the control, for tests.
  static const openKey = ValueKey('week-card-open');

  @override
  Widget build(BuildContext context) {
    final isAr = state.isAr;
    final review = state.weekReview();
    return QTapArea(
      key: openKey,
      onTap: state.openWeekCard,
      builder: (context, pressed) => qPressed(
        context,
        pressed: pressed,
        // The week's own lavender, as its card on Progress.
        child: PastelCard(
          color: QColors.lavender,
          padding: const EdgeInsets.fromLTRB(16, 14, 16, 16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(children: [
                Expanded(child: Text(QText.eyebrowText(isAr ? 'أسبوعك' : 'Your week', ar: isAr), style: QText.eyebrow(ar: isAr, color: QColors.onPastel))),
                Text(isAr ? 'شوف الأسبوع' : 'See the week', style: QText.body(size: 13, weight: FontWeight.w600, color: QColors.onPastel)),
                const SizedBox(width: 2),
                const QIcon(QIcons.forward, size: 18, color: QColors.onPastel),
              ]),
              const SizedBox(height: 8),
              // Wrapped to even lines, as on the week's card: never one word
              // alone on the last line.
              BalancedStartText(isAr ? review.insight.ar : review.insight.en, style: QText.body(size: 17, weight: FontWeight.w600, color: QColors.onPastel)),
            ],
          ),
        ),
      ),
    );
  }
}
