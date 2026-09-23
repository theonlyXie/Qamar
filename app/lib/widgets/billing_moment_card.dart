import 'package:flutter/material.dart';

import '../models/billing.dart';
import '../state/app_state.dart';
import '../theme/app_theme.dart';
import '../theme/colors.dart';
import '../theme/text_styles.dart';

/// The billing moment on Today: the free week or the paid month in its last
/// 48 hours, carrying the same question its push asked.
///
/// Nothing renews on its own — the trial takes no card and a paid month is
/// paid for once — so this card and its push are the only word someone gets
/// before Qamar+ stops. It says so plainly, and it never says "cancel":
/// there is nothing to cancel.
///
/// Self-contained and at most [maxHeight] tall, so Today's one contextual
/// slot (`todayFocus`) can place it; [AppState.billingMoment] says whether
/// it is due. Renders nothing when it is not.
class BillingMomentCard extends StatelessWidget {
  final AppState state;
  const BillingMomentCard({super.key, required this.state});

  /// The slot's budget for any one card.
  static const double maxHeight = 120;

  @override
  Widget build(BuildContext context) {
    final moment = state.billingMoment;
    if (moment == BillingMoment.none) return const SizedBox.shrink();
    final isAr = state.isAr;
    final when = state.trialEndsIn();
    final price = formatEgp(state.displayPlusQuote.amountPounds, ar: isAr, eastern: state.easternDigits);
    final line = switch (moment) {
      BillingMoment.trialEnding =>
        isAr ? 'أسبوعك المجاني بيخلص $when. نكمّل الخطة؟' : 'Your free week ends $when. Keep the plan going?',
      _ => isAr ? 'شهرك مع قمر+ بيخلص $when. نكمّل شهر كمان؟' : 'Your Qamar+ month ends $when. Another month?',
    };
    final sub = isAr ? '$price في الشهر · مفيش حاجة بتتجدد لوحدها' : '$price a month · nothing renews on its own';

    return ConstrainedBox(
      constraints: const BoxConstraints(maxHeight: maxHeight),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(QRadii.card),
          onTap: state.openBillingMoment,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 13),
            decoration: BoxDecoration(
              color: QColors.ink.withValues(alpha: 0.08),
              border: Border.all(color: QColors.ink.withValues(alpha: 0.35)),
              borderRadius: BorderRadius.circular(QRadii.card),
            ),
            child: Row(
              children: [
                const Icon(Icons.hourglass_bottom_rounded, size: 18, color: QColors.ink),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(line,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: QText.body(size: 15, height: 21, color: QColors.ink)),
                      const SizedBox(height: 3),
                      Text(sub,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: QText.body(size: 12, color: QColors.inkTertiary)),
                    ],
                  ),
                ),
                const SizedBox(width: 6),
                // Points the way the line reads: up and to the end.
                Transform.flip(flipX: isAr, child: const Icon(Icons.arrow_outward, size: 14, color: QColors.inkTertiary)),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
