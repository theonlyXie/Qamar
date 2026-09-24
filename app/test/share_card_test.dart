// The share card's sign-off, seat 6's part (the scorecard's 08: "dr-qamar.com
// is an orphaned low-contrast watermark"). The link stays, since the card is
// shared as an image and this is where it came from, but as a sign-off:
// under a hairline, led by the moon's mark, from the start edge, in a colour
// that passes AA on the card's lavender; the run, when it is shown, takes
// the other end. Both languages. And the mark — the mascot's face, the
// brand's own signature — is lit on the side the seven day moons are, the
// right in both languages, where a glyph was once lit on the left and read
// as their mirror (seat 3).

import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
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
        expect(contrastRatio(style.color!, QColors.lavender), greaterThanOrEqualTo(4.5), reason: 'readable on the card’s lavender, not a watermark');
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

  // The moons and the mark are painted: what is lit can be measured in the
  // pixels.
  for (final ar in [false, true]) {
    testWidgets('the moon’s mark is lit on the side the day moons are (${ar ? 'ar' : 'en'})', (tester) async {
      final monday = DateTime(2026, 9, 21);
      // A week of part-filled days, so every moon shows a lit side.
      final week = [for (var i = 0; i < 7; i++) DayTotals(day: monday.add(Duration(days: i)), kcal: const [400, 900, 1300, 1900, 700, 2600, 1500][i], meals: 2)];
      final review = WeekReview.build(week: week, lastWeek: const [], targetKcal: 2000, streak: Streak.none, iso: (x) => x, hasTarget: true);
      const shot = ValueKey('shot');
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(body: Center(child: RepaintBoundary(key: shot, child: ReviewCard(review: review, isAr: ar, showNumbers: false, showStreak: false, footer: 'dr-qamar.com', iso: (x) => x)))),
      ));
      final origin = tester.getRect(find.byKey(shot)).topLeft;
      final (width, pixels) = (await tester.runAsync(() async {
        final image = await tester.renderObject<RenderRepaintBoundary>(find.byKey(shot)).toImage(pixelRatio: 3);
        final bytes = await image.toByteData(format: ui.ImageByteFormat.rawRgba);
        return (image.width, bytes!);
      }))!;

      // Where the light is across [r]: the centre of what is lit — brighter
      // than the card's lavender — from the middle of the box, as a share of
      // its width. Right is positive.
      const ground = 0.2126 * 0xDD + 0.7152 * 0xC0 + 0.0722 * 0xFF;
      double litSide(Rect r) {
        final box = r.shift(-origin);
        double sum = 0, weight = 0;
        for (var y = (box.top * 3).floor(); y < (box.bottom * 3).ceil(); y++) {
          for (var x = (box.left * 3).floor(); x < (box.right * 3).ceil(); x++) {
            final i = (y * width + x) * 4;
            final luma = 0.2126 * pixels.getUint8(i) + 0.7152 * pixels.getUint8(i + 1) + 0.0722 * pixels.getUint8(i + 2);
            final w = (luma - ground - 12).clamp(0, 255).toDouble();
            sum += w * ((x + 0.5) / 3 - (box.center.dx));
            weight += w;
          }
        }
        return weight == 0 ? 0 : sum / weight / r.width;
      }

      final moons = [for (final e in find.byType(QamarMoon).evaluate()) litSide(tester.getRect(find.byWidget(e.widget)))];
      expect(moons, everyElement(greaterThan(0.03)), reason: 'the day moons are lit on the right: $moons');
      final mark = litSide(tester.getRect(find.byKey(ReviewCard.markKey)));
      expect(mark, greaterThan(0.03), reason: 'the mascot is lit on the right too, its shadow on the left: not their mirror ($mark)');
    });
  }
}
