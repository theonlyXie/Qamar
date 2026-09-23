import 'package:flutter/material.dart';

import '../l10n/strings.dart';
import '../l10n/words.dart';
import '../models/review.dart';
import '../models/streak.dart';
import '../theme/app_theme.dart';
import '../theme/colors.dart';
import '../theme/text_styles.dart';
import 'moon.dart';

/// The one thing in the product designed to be shared.
///
/// A moon for each day of the week, brightened from the resting crescent as
/// far as that day's intake reached the target (a day with nothing logged is
/// the resting moon, faint, never dark); the sentence the person did not
/// expect; the one change for next week. No weight, ever. Calories only when
/// [showNumbers]. The sign-off carries the link the card travels with.
class ReviewCard extends StatelessWidget {
  final WeekReview review;
  final bool isAr;
  final bool showNumbers;

  /// The run under the week, when "Points and streaks" is on (O4). Off, the
  /// card and what it shares carry no streak.
  final bool showStreak;
  final String footer;
  final String Function(String) iso;

  const ReviewCard({
    super.key,
    required this.review,
    required this.isAr,
    required this.showNumbers,
    required this.showStreak,
    required this.footer,
    required this.iso,
  });

  /// The sign-off row and the link in it, for tests.
  static const signOffKey = ValueKey('review-sign-off');
  static const footerKey = ValueKey('review-footer');
  static const markKey = ValueKey('review-mark');

  @override
  Widget build(BuildContext context) {
    final fills = review.fills;
    final letters = isAr ? kWeekdayShortAr : kWeekdayShortEn;
    return Directionality(
      textDirection: isAr ? TextDirection.rtl : TextDirection.ltr,
      child: Container(
        width: 340,
        padding: const EdgeInsets.fromLTRB(22, 22, 22, 18),
        decoration: BoxDecoration(
          gradient: const LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [QColors.cardMid, QColors.cardDeep],
          ),
          borderRadius: BorderRadius.circular(QRadii.card),
          border: Border.all(color: QColors.violet.withValues(alpha: 0.35)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              isAr ? 'أسبوعي مع قمر' : 'My week with Qamar',
              style: QText.body(size: 12, weight: FontWeight.w600, color: QColors.violetSoft),
            ),
            const SizedBox(height: 16),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                for (var i = 0; i < review.days.length; i++)
                  Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      // An unknown day (nothing logged, or no target) is the
                      // moon at rest, faint: no reading, and never dark.
                      Opacity(
                        opacity: fills[i] == null ? 0.35 : 1,
                        child: QamarMoon(
                          size: 30,
                          staticPhase: fills[i] == null ? OrbState.restPhase : OrbState.phaseForFill(fills[i]!),
                        ),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        letters[review.days[i].day.weekday - 1],
                        style: QText.number(size: 11, color: fills[i] == null ? QColors.textMuted : QColors.textMid),
                      ),
                    ],
                  ),
              ],
            ),
            const SizedBox(height: 18),
            Text(
              isAr ? review.insight.ar : review.insight.en,
              style: QText.body(size: 15, height: 23, weight: FontWeight.w600, color: QColors.textPrimary),
            ),
            const SizedBox(height: 8),
            Text(
              isAr ? review.change.ar : review.change.en,
              style: QText.body(size: 13, height: 20, color: QColors.textMid),
            ),
            if (showNumbers && review.avgKcal != null) ...[
              const SizedBox(height: 12),
              Text(
                isAr
                    ? 'متوسط ${iso('${review.avgKcal}')} سعرة في اليوم المسجّل · ${iso('${review.inRange}')} من ${iso('${review.loggedDays}')} داخل النطاق'
                    : 'Average ${review.avgKcal} kcal on a logged day · ${review.inRange} of ${review.loggedDays} in range',
                style: QText.number(size: 11, color: QColors.textMuted),
              ),
            ],
            const SizedBox(height: 14),
            // The card's sign-off: the link it travels with, under a hairline,
            // led by a crescent, from the start edge. It used to
            // stand alone at the far end of an empty row, which read as a
            // stray watermark rather than as where the card came from. The
            // run, when it is shown, takes the other end.
            const Divider(color: QColors.borderSoft, height: 1),
            const SizedBox(height: 12),
            Row(
              key: ReviewCard.signOffKey,
              children: [
                // A mark, not an eighth day: the day moons are the only
                // QamarMoons on the card (seat 4's orb_day_test counts them).
                const Icon(Icons.nightlight_round, key: ReviewCard.markKey, size: 14, color: QColors.moonbeam),
                const SizedBox(width: 8),
                Text(footer, key: ReviewCard.footerKey, textDirection: TextDirection.ltr, style: QText.number(size: 11, weight: FontWeight.w500, color: QColors.textMuted)),
                const Spacer(),
                if (showStreak && review.streak.current >= 2)
                  Text(
                    // Counted as each language counts: يومين, not ٢ أيام.
                    '${Counted.day.of(review.streak.current, ar: isAr, iso: iso)} ${isAr ? 'ورا بعض' : 'in a row'}',
                    style: QText.body(size: 11, color: QColors.cyan),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
