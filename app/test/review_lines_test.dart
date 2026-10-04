// The week's card in words, seat 3's part. On the card's width the line for
// a week of under three logged days left "go." alone on a third line, and
// the change under it left "rest."; in Arabic "لسه ٢ أيام" and "لسه ١ يوم"
// were counted wrong. The count now goes by the app's one rule (Counted:
// يوم واحد, يومين, ٣ أيام, ١١ يوم), and the closing count and phrase wrap as
// one. Here: every wrapped paragraph on the card ends on two words or more,
// for every line the week can say, in both languages; and the counts.

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:qamar/l10n/strings.dart';
import 'package:qamar/l10n/words.dart';
import 'package:qamar/models/review.dart';
import 'package:qamar/models/streak.dart';
import 'package:qamar/screens/you_screen.dart';
import 'package:qamar/services/repositories.dart';
import 'package:qamar/state/app_state.dart';
import 'package:qamar/widgets/review_card.dart';

import 'support/app_fonts.dart';

/// Saturday 19 to Friday 25 September 2026, with these calories.
List<DayTotals> _days(List<int> kcal, {int from = 19}) => [
      for (var i = 0; i < 7; i++) DayTotals(day: DateTime(2026, 9, from + i), kcal: kcal[i], meals: kcal[i] > 0 ? 2 : 0),
    ];

/// Every line the week can say: each insight and each change.
final _weeks = <String, ({List<int> week, List<int> last, bool target})>{
  'nothing logged': (week: [0, 0, 0, 0, 0, 0, 0], last: [0, 0, 0, 0, 0, 0, 0], target: true),
  'one day logged': (week: [0, 0, 0, 0, 0, 0, 1900], last: [0, 0, 0, 0, 0, 0, 0], target: true),
  'two days logged': (week: [0, 0, 0, 0, 0, 1900, 2000], last: [0, 0, 0, 0, 0, 0, 0], target: true),
  'a heavy Thursday': (week: [1800, 1800, 1800, 1800, 1800, 2900, 0], last: [0, 0, 0, 0, 0, 0, 0], target: true),
  'above last week': (week: [2200, 2200, 2200, 2200, 2200, 0, 0], last: [2000, 2000, 2000, 2000, 2000, 0, 0], target: true),
  'below last week': (week: [1800, 1800, 1800, 1800, 1800, 0, 0], last: [2000, 2000, 2000, 2000, 2000, 0, 0], target: true),
  'the same rhythm': (week: [2000, 2000, 2000, 2000, 2000, 0, 0], last: [2020, 2020, 2020, 2020, 2020, 0, 0], target: true),
  'inside the range': (week: [2000, 2050, 1950, 2100, 1900, 0, 0], last: [0, 0, 0, 0, 0, 0, 0], target: true),
  'mostly out of range': (week: [1500, 1500, 1500, 1500, 1500, 0, 0], last: [0, 0, 0, 0, 0, 0, 0], target: true),
  'guidance, a heavy Thursday': (week: [1800, 1800, 1800, 1800, 1800, 2900, 0], last: [0, 0, 0, 0, 0, 0, 0], target: false),
  'guidance, three days': (week: [1500, 1500, 1500, 0, 0, 0, 0], last: [0, 0, 0, 0, 0, 0, 0], target: false),
};

/// The words on [p]'s last line, or null when it holds one line.
List<String>? _lastLine(RenderParagraph p) {
  final text = p.text.toPlainText(includeSemanticsLabels: false);
  final painter = TextPainter(text: p.text, textDirection: p.textDirection, textScaler: p.textScaler)..layout(maxWidth: p.size.width);
  if (painter.computeLineMetrics().length < 2) return null;
  final range = painter.getLineBoundary(TextPosition(offset: text.length - 1));
  return text.substring(range.start, range.end).trim().split(RegExp('[ \u00A0]+')).where((w) => w.isNotEmpty).toList();
}

String _plain(String s) => s.replaceAll('\u00A0', ' ').replaceAll(RegExp('[\u2066-\u2069]'), '');

void main() {
  setUpAll(loadAppFonts);

  final ar = AppState()..setLang(AppLang.ar);
  final en = AppState()..setLang(AppLang.en);

  for (final lang in AppLang.values) {
    final s = lang == AppLang.ar ? ar : en;
    testWidgets('no paragraph on the card ends on one word alone, whatever the week says (${lang.name})', (tester) async {
      final alone = <String>[];
      var wrapped = 0;
      for (final MapEntry(key: name, value: w) in _weeks.entries) {
        final review = WeekReview.build(
          week: _days(w.week),
          lastWeek: _days(w.last, from: 12),
          targetKcal: 2000,
          hasTarget: w.target,
          streak: const Streak(current: 12, best: 12, todayCounted: true),
          iso: s.iso,
        );
        await tester.pumpWidget(MaterialApp(
          key: ValueKey(name),
          home: Scaffold(
            body: Center(child: ReviewCard(review: review, isAr: s.isAr, showNumbers: true, showStreak: true, footer: 'dr-qamar.com', iso: s.iso)),
          ),
        ));
        for (final e in find.descendant(of: find.byType(ReviewCard), matching: find.byType(RichText)).evaluate()) {
          final p = e.renderObject! as RenderParagraph;
          final last = _lastLine(p);
          if (last == null) continue;
          wrapped++;
          if (last.length < 2) alone.add('$name: "${p.text.toPlainText()}" ends on "${last.join(' ')}"');
        }
      }
      expect(alone, isEmpty);
      expect(wrapped, greaterThan(0), reason: 'the card has wrapped words to check');
    });
  }

  test('the under-three line counts its days in Arabic as they are said', () {
    String line(int logged) => _plain(WeekReview.build(
          week: _days([for (var i = 0; i < 7; i++) i < logged ? 1900 : 0]),
          lastWeek: const [],
          targetKcal: 2000,
          streak: Streak.none,
          iso: ar.iso,
        ).insight.ar);
    expect(line(0), startsWith('سجّل ٣ أيام على الأقل'));
    expect(line(0), endsWith('لسه ٣ أيام.'));
    expect(line(1), endsWith('لسه يومين.'));
    expect(line(2), endsWith('لسه يوم واحد.'));
    final en = WeekReview.build(week: _days([0, 0, 0, 0, 0, 1900, 1900]), lastWeek: const [], targetKcal: 2000, streak: Streak.none, iso: (x) => x).insight.en;
    expect(_plain(en), 'Log at least 3 days and I can tell you something you did not expect — 1 to go.');
    expect(en, endsWith('1\u00A0to\u00A0go.'), reason: 'the count and its words wrap as one');
  });

  test('one count rule: one, the dual, three to ten, eleven on, by the last two digits', () {
    String day(int n) => _plain(Counted.day.of(n, ar: true, iso: ar.iso));
    expect([for (final n in [1, 2, 3, 10, 11, 100, 103]) day(n)], ['يوم واحد', 'يومين', '٣ أيام', '١٠ أيام', '١١ يوم', '١٠٠ يوم', '١٠٣ أيام']);
    expect([for (final n in [1, 2, 11]) Counted.day.of(n, ar: false, iso: en.iso)], ['1 day', '2 days', '11 days']);
    // You's memory line and the streak's sentence say it by the same rule.
    for (var n = 0; n <= 120; n++) {
      expect(YouScreen.itemsLine(n, isAr: true, iso: ar.iso), Counted.item.of(n, ar: true, iso: ar.iso));
    }
    expect(_plain(streakSentence(const Streak(current: 105, best: 105, todayCounted: true), ar: true, iso: ar.iso)!), '١٠٥ أيام ورا بعض.');
  });
}
