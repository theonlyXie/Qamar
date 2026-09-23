import 'package:flutter/material.dart';

import '../l10n/strings.dart';
import '../l10n/words.dart';
import '../models/review.dart';
import '../models/streak.dart';
import '../theme/app_theme.dart';
import '../theme/colors.dart';
import '../theme/icons.dart';
import '../theme/text_styles.dart';
import 'common.dart';
import 'moon.dart';

/// The one thing in the product designed to be shared, and it leaves the
/// phone as a picture: so it is drawn in black and white only, on the solid
/// card surface, with nothing that needs the app around it to be read.
///
/// A moon for each day of the week, in greys, brightened from the resting
/// crescent as far as that day's intake reached the target (a day with
/// nothing logged is the resting moon, faint, never dark); the sentence the
/// person did not expect; the one change for next week. No weight, ever.
/// Calories only when [showNumbers]. The sign-off carries the link the card
/// travels with.
class ReviewCard extends StatelessWidget {
  final WeekReview review;
  final bool isAr;
  final bool showNumbers;

  /// The run under the week, when "Points and streaks" is on (O4). Off, the
  /// card and what it shares carry no streak.
  final bool showStreak;
  final String footer;
  final String Function(String) iso;

  /// How wide the picture is: the page's width where it is shown, so it
  /// lines up with the cards around it, and what is shared is what was seen.
  final double width;

  const ReviewCard({
    super.key,
    required this.review,
    required this.isAr,
    required this.showNumbers,
    required this.showStreak,
    required this.footer,
    required this.iso,
    this.width = defaultWidth,
  });

  static const defaultWidth = 340.0;

  /// The sign-off row and the link in it, for tests.
  static const signOffKey = ValueKey('review-sign-off');
  static const footerKey = ValueKey('review-footer');
  static const markKey = ValueKey('review-mark');

  @override
  Widget build(BuildContext context) {
    final fills = review.fills;
    final letters = isAr ? kWeekdayShortAr : kWeekdayShortEn;
    final numbers = showNumbers ? _numbers() : const <String>[];
    return Directionality(
      textDirection: isAr ? TextDirection.rtl : TextDirection.ltr,
      child: Container(
        width: width,
        padding: const EdgeInsets.fromLTRB(20, 20, 20, 16),
        decoration: QDecor.card(),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(QText.eyebrowText(isAr ? 'أسبوعي مع قمر' : 'My week with Qamar', ar: isAr), style: QText.eyebrow(ar: isAr)),
            const SizedBox(height: 16),
            // The week from its first day at the start edge, as it is read;
            // heard as one sentence rather than seven initials.
            Semantics(
              label: _heard(),
              child: ExcludeSemantics(
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    for (var i = 0; i < review.days.length; i++)
                      _DayMoon(fill: fills[i], letter: letters[review.days[i].day.weekday - 1]),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 20),
            // The picture's words wrap to even lines, so none ends on one
            // word alone, whatever the week says.
            BalancedStartText(isAr ? review.insight.ar : review.insight.en, style: QText.body(size: 17, weight: FontWeight.w600, color: QColors.ink)),
            const SizedBox(height: 6),
            BalancedStartText(isAr ? review.change.ar : review.change.en, style: QText.body(size: 15, color: QColors.inkSecondary)),
            if (numbers.isNotEmpty) ...[
              const SizedBox(height: 12),
              for (final line in numbers) BalancedStartText(line, style: QText.number(size: 13, color: QColors.inkTertiary, ar: isAr)),
            ],
            const SizedBox(height: 16),
            const Divider(color: QColors.hairline, height: 1, thickness: 1),
            const SizedBox(height: 12),
            // The sign-off: where the card came from, led by the crescent
            // from the start edge; the run, when it is shown, at the other.
            Row(
              key: ReviewCard.signOffKey,
              children: [
                // The moon's mark, not an eighth day: the day moons are the
                // only QamarMoons on the card. Filled, since it is a mark and
                // not a control, and turned to be lit on the right, as the
                // seven moons above it are in both languages; the glyph
                // itself is lit on the left.
                Transform.flip(
                  flipX: true,
                  child: const Icon(QIcons.moonFull, key: ReviewCard.markKey, size: 14, color: QColors.inkSecondary),
                ),
                const SizedBox(width: 8),
                Text(footer, key: ReviewCard.footerKey, textDirection: TextDirection.ltr, style: QText.body(size: 13, weight: FontWeight.w500, color: QColors.inkTertiary)),
                const Spacer(),
                if (showStreak && review.streak.current >= 2)
                  Text(
                    // Counted as each language counts: يومين, not ٢ أيام.
                    '${Counted.day.of(review.streak.current, ar: isAr, iso: iso)} ${isAr ? 'ورا بعض' : 'in a row'}',
                    style: QText.body(size: 13, weight: FontWeight.w500, color: QColors.inkSecondary),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  /// What the seven moons say, for a screen reader.
  String _heard() {
    final n = review.loggedDays;
    if (n == 0) return isAr ? 'مفيش تسجيل في آخر ${iso('7')} أيام' : 'Nothing logged in the last 7 days';
    return isAr ? 'سجّلت في ${iso('$n')} من آخر ${iso('7')} أيام' : 'Logged on $n of the last 7 days';
  }

  /// The calories, in plain words and a line each, once there are enough
  /// days to average; how many days were near the target only where there
  /// is a target. No "·" between them: beside Arabic-Indic digits it reads
  /// as a zero.
  List<String> _numbers() {
    final avg = review.avgKcal;
    if (avg == null) return const [];
    return [
      isAr ? 'حوالي ${iso('$avg')} سعرة في اليوم المسجّل' : 'About $avg kcal on a logged day',
      if (review.hasTarget)
        isAr
            ? '${iso('${review.inRange}')} من ${iso('${review.loggedDays}')} أيام قريبة من هدفك'
            : '${review.inRange} of ${review.loggedDays} days near your target',
    ];
  }
}

/// A paragraph set from the start edge and wrapped to even lines, the way
/// [QBalancedText] wraps a centred one: at the narrowest width that keeps
/// the same number of lines, so the last line is never one word alone. The
/// week's words use it wherever they are shown: on this card and in Today's
/// slot (WeekGlanceCard).
class BalancedStartText extends StatelessWidget {
  final String text;
  final TextStyle style;
  const BalancedStartText(this.text, {super.key, required this.style});

  @override
  Widget build(BuildContext context) => LayoutBuilder(builder: (context, box) {
        final width = QBalancedText.balancedWidth(
          text,
          DefaultTextStyle.of(context).style.merge(style),
          box.maxWidth,
          Directionality.of(context),
          MediaQuery.textScalerOf(context),
        );
        return SizedBox(width: width, child: Text(text, style: style));
      });
}

/// One day of the card's week: its moon, and its initial under it. A day
/// with nothing logged is the moon at rest, faint: no reading, never dark.
class _DayMoon extends StatelessWidget {
  final double? fill;
  final String letter;
  const _DayMoon({required this.fill, required this.letter});

  @override
  Widget build(BuildContext context) {
    final known = fill != null;
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Opacity(
          opacity: known ? 1 : 0.35,
          child: QamarMoon(size: 32, staticPhase: known ? OrbState.phaseForFill(fill!) : OrbState.restPhase),
        ),
        const SizedBox(height: 8),
        Text(letter, style: QText.body(size: 11, weight: FontWeight.w500, color: known ? QColors.inkSecondary : QColors.inkTertiary)),
      ],
    );
  }
}
