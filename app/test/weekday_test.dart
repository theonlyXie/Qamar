// The week's row labels, seat 6's part (the scorecard's 08): one letter a
// day gave English two T's and two S's side by side, so Tuesday could not be
// told from Thursday, nor Saturday from Sunday. English takes two letters;
// the Arabic initials were each a different letter already and stay as
// they were. Both rows on Progress (the week's bars and the review card)
// read from the one list.

import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

import 'package:qamar/l10n/strings.dart';
import 'package:qamar/main.dart';
import 'package:qamar/models/meal.dart';
import 'package:qamar/state/app_state.dart';

import 'support/app_fonts.dart';

void main() {
  setUpAll(() async {
    await loadAppFonts();
    for (final name in const ['com.qamar.app/quick_events', 'com.qamar.app/quick_invoke']) {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(MethodChannel(name), (call) async => null);
    }
  });

  test('every day of the week has its own label, in both languages', () {
    expect(kWeekdayShortEn.toSet().length, 7);
    expect(kWeekdayShortAr.toSet().length, 7);
    expect(kWeekdayShortAr, ['ن', 'ث', 'ر', 'خ', 'ج', 'س', 'ح'], reason: 'the Arabic, unchanged');
    // Each English label is how its day's name begins, Monday first.
    const days = ['Monday', 'Tuesday', 'Wednesday', 'Thursday', 'Friday', 'Saturday', 'Sunday'];
    for (var i = 0; i < 7; i++) {
      expect(days[i].startsWith(kWeekdayShortEn[i]), isTrue, reason: days[i]);
    }
  });

  testWidgets('on Progress, the week’s labels are the seven days, whole', (tester) async {
    tester.view.devicePixelRatio = 3;
    tester.view.physicalSize = const Size(390, 2400) * 3;
    addTearDown(tester.view.reset);
    final s = AppState()..setLang(AppLang.en);
    s.meals.add(LoggedMeal(name: 'Koshary', sub: '', kcal: 640, p: 20, c: 100, f: 18, at: DateTime.now()));
    s.go(AppScreen.today);
    s.go(AppScreen.progress);
    await tester.pumpWidget(ChangeNotifierProvider.value(value: s, child: const QamarApp()));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    expect(tester.takeException(), isNull);
    for (final day in kWeekdayShortEn) {
      final labels = find.text(day);
      expect(labels, findsWidgets, reason: '$day is shown');
      for (final e in labels.evaluate()) {
        final p = e.findRenderObject()! as RenderParagraph;
        expect(p.didExceedMaxLines, isFalse);
        expect(p.size.width, greaterThanOrEqualTo(p.getMaxIntrinsicWidth(double.infinity) - 0.5), reason: '$day is not cut');
      }
    }
    for (final one in ['T', 'S']) {
      expect(find.text(one), findsNothing, reason: 'no lone $one');
    }
  });
}
