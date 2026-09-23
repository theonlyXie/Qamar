// The share card's sign-off, seat 6's part (the scorecard's 08: "dr-qamar.com
// is an orphaned low-contrast watermark"). The link stays, since the card is
// shared as an image and this is where it came from, but as a sign-off:
// under a hairline, led by a crescent, from the start edge, in a colour
// that passes AA on the card; the run, when it is shown, takes the other
// end. Both languages.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:qamar/models/review.dart';
import 'package:qamar/models/streak.dart';
import 'package:qamar/services/repositories.dart';
import 'package:qamar/theme/colors.dart';
import 'package:qamar/widgets/moon.dart';
import 'package:qamar/widgets/review_card.dart';

import 'support/app_fonts.dart';
import 'support/contrast.dart';

WeekReview _review(Streak streak) {
  final monday = DateTime(2026, 9, 21);
  final week = [
    for (var i = 0; i < 7; i++) DayTotals(day: monday.add(Duration(days: i)), kcal: i.isEven ? 1900 : 0, meals: i.isEven ? 2 : 0),
  ];
  return WeekReview.build(week: week, lastWeek: const [], targetKcal: 2000, streak: streak, iso: (x) => x, hasTarget: true);
}

void main() {
  setUpAll(loadAppFonts);

  for (final ar in [false, true]) {
    for (final run in [0, 4]) {
      testWidgets('the link signs the card off from the start edge, the run at the other end (${ar ? 'ar' : 'en'}, run $run)', (tester) async {
        final streak = run == 0 ? Streak.none : Streak(current: run, best: run, todayCounted: true);
        await tester.pumpWidget(MaterialApp(
          home: Scaffold(body: Center(child: ReviewCard(review: _review(streak), isAr: ar, showNumbers: false, showStreak: true, footer: 'dr-qamar.com', iso: (x) => x))),
        ));
        final card = tester.getRect(find.byType(ReviewCard));
        final link = tester.getRect(find.byKey(ReviewCard.footerKey));
        final mark = tester.getRect(find.byKey(ReviewCard.markKey));
        final rule = tester.getRect(find.descendant(of: find.byType(ReviewCard), matching: find.byType(Divider)));
        expect(rule.bottom, lessThanOrEqualTo(mark.top), reason: 'under a hairline');
        expect((mark.center.dy - link.center.dy).abs(), lessThan(2), reason: 'the mark on the link’s line');
        if (ar) {
          expect(mark.left, greaterThan(link.right), reason: 'the crescent leads, from the right in Arabic');
          expect(card.right - mark.right, lessThan(30), reason: 'from the start edge, not stranded at the far end');
          expect(mark.left - link.right, lessThanOrEqualTo(12));
        } else {
          expect(mark.right, lessThan(link.left), reason: 'the crescent leads');
          expect(mark.left - card.left, lessThan(30), reason: 'from the start edge, not stranded at the far end');
          expect(link.left - mark.right, lessThanOrEqualTo(12));
        }
        final style = tester.widget<Text>(find.byKey(ReviewCard.footerKey)).style!;
        expect(contrastRatio(style.color!, QColors.cardMid), greaterThanOrEqualTo(4.5), reason: 'readable, not a watermark');
        final runText = find.textContaining(ar ? 'أيام ورا بعض' : 'days in a row');
        if (run >= 2) {
          final r = tester.getRect(runText);
          expect(ar ? r.left < link.left : r.left > link.right, isTrue, reason: 'the run at the other end');
        } else {
          expect(runText, findsNothing);
        }
        expect(find.byType(QamarMoon), findsNWidgets(7), reason: 'the mark is not an eighth day');
      });
    }
  }
}
