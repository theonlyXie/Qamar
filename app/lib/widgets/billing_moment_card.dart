import 'package:flutter/material.dart';

import '../models/billing.dart';
import '../state/app_state.dart';
import '../theme/app_theme.dart';
import '../theme/colors.dart';
import '../theme/icons.dart';
import '../theme/text_styles.dart';
import 'common.dart';

/// The billing moment on Today: the free week or the paid month in its last
/// 48 hours, carrying the same question its push asked.
///
/// Nothing renews on its own — the trial takes no card and a paid month is
/// paid for once — so this card and its push are the only word someone gets
/// before Qamar+ stops. It says so plainly, and it never says "cancel":
/// there is nothing to cancel. The whole card is the way to Qamar+, one tap.
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
    // Arabic takes its own comma: a "·" beside its numbers reads as a zero.
    final sub = isAr ? '$price في الشهر، ومفيش حاجة بتتجدد لوحدها' : '$price a month · nothing renews on its own';

    return ConstrainedBox(
      constraints: const BoxConstraints(maxHeight: maxHeight),
      child: QTapArea(
        onTap: state.openBillingMoment,
        builder: (context, pressed) => qPressed(
          context,
          pressed: pressed,
          child: Container(
            padding: const EdgeInsetsDirectional.fromSTEB(16, 14, 12, 14),
            // A strong edge: the one card whose moment runs out.
            decoration: QDecor.card(color: pressed ? QColors.surfaceRaised : QColors.surface, border: QColors.hairlineStrong),
            child: Row(
              children: [
                const Icon(QIcons.limit, size: 20, color: QColors.ink),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(line, maxLines: 2, overflow: TextOverflow.ellipsis, style: QText.body(size: 15, weight: FontWeight.w500, color: QColors.ink)),
                      const SizedBox(height: 2),
                      Text(sub, maxLines: 1, overflow: TextOverflow.ellipsis, style: QText.body(size: 13, color: QColors.inkTertiary)),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                // It opens Qamar+ in the app: the chevron points the way
                // the line reads, and turns in Arabic.
                const Icon(QIcons.forward, size: 16, color: QColors.inkTertiary),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
