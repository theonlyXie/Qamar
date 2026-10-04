import 'package:flutter/material.dart';

import '../models/billing.dart';
import '../state/app_state.dart';
import '../theme/colors.dart';
import '../theme/icons.dart';
import '../theme/text_styles.dart';
import 'common.dart';
import 'kit.dart';

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
          // The kit's coral: the one card whose moment runs out.
          child: PastelCard(
            color: QColors.coral,
            padding: const EdgeInsetsDirectional.fromSTEB(14, 14, 12, 14),
            child: Row(
              children: [
                const PastelGlyph(QIcons.limit, size: 36),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(line, maxLines: 2, overflow: TextOverflow.ellipsis, style: QText.body(size: 15, weight: FontWeight.w600, color: QColors.onPastel)),
                      const SizedBox(height: 2),
                      Text(sub, maxLines: 1, overflow: TextOverflow.ellipsis, style: QText.body(size: 13, color: QColors.onPastel)),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                // It opens Qamar+ in the app: the chevron points the way
                // the line reads, and turns in Arabic.
                const QIcon(QIcons.forward, size: 20, color: QColors.onPastel),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
