// The type scale (the qamar-design skill, the Nutri AI kit's): text is set
// at a size on the kit's scale and nowhere between (six steps for reading
// and controls, nothing under 12; four title sizes, each with its own line
// height; six for figures); nothing is tracked, in either language — Space
// Grotesk is set as drawn, and Arabic must never be, where space between
// joined letters broke the word (the eyebrow labels were once set at +0.4 in
// both languages). Swept over every screen, the Log sheet and the
// conversation, in both languages.

import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

import 'package:qamar/l10n/strings.dart';
import 'package:qamar/main.dart';
import 'package:qamar/models/meal.dart';
import 'package:qamar/state/app_state.dart';
import 'package:qamar/theme/text_styles.dart';

import 'support/app_fonts.dart';

final _onScale = {...QText.textSizes, ...QText.displaySizes.keys, ...QText.figureSizes};

/// Each run of text on screen, with the style it is drawn in.
Iterable<(String, TextStyle)> _runs(WidgetTester tester) sync* {
  for (final p in tester.allRenderObjects.whereType<RenderParagraph>()) {
    final out = <(String, TextStyle)>[];
    void walk(InlineSpan span, TextStyle? inherited) {
      final style = inherited == null ? span.style : inherited.merge(span.style);
      if (span is TextSpan) {
        // Icons are glyphs of an icon font, sized as icons, not type.
        final icon = style?.fontFamily?.contains('Icons') ?? false;
        if (span.text != null && span.text!.trim().isNotEmpty && style != null && !icon) out.add((span.text!, style));
        for (final c in span.children ?? const <InlineSpan>[]) {
          walk(c, style);
        }
      }
    }

    walk(p.text, null);
    yield* out;
  }
}

void main() {
  setUpAll(() async {
    await loadAppFonts();
    for (final name in const ['com.qamar.app/quick_events', 'com.qamar.app/quick_invoke']) {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(MethodChannel(name), (call) async => null);
    }
  });

  group('the scale', () {
    test('six steps for reading, nothing under 12; four title sizes, each with its line height', () {
      // The kit's styles: badge, footnote, body 2, callout, body, headline;
      // title 3, title 2, title 1, large title — each at one and a half.
      expect(QText.textSizes, [12, 13, 15, 16, 17, 18]);
      expect(QText.displaySizes, {20: 30, 24: 36, 28: 42, 34: 51});
      expect(QText.figureSizes, [20, 24, 28, 34, 48, 56]);
      for (final e in QText.displaySizes.entries) {
        expect(QText.display(size: e.key, ar: false).height! * e.key, moreOrLessEquals(e.value));
      }
    });

    test('a size off the scale does not draw', () {
      expect(() => QText.body(size: 11), throwsAssertionError);
      expect(() => QText.body(size: 14), throwsAssertionError);
      expect(() => QText.number(size: 38), throwsAssertionError);
      expect(() => QText.display(size: 22, ar: false), throwsAssertionError);
    });

    test('nothing is tracked, at any size, nor left to inherit a tracking', () {
      for (final s in [...QText.textSizes, ...QText.displaySizes.keys, ...QText.figureSizes]) {
        expect(QText.tracking(s), 0, reason: '$s');
      }
      for (final s in QText.textSizes) {
        expect(QText.body(size: s).letterSpacing, 0, reason: 'zero, not null: null inherits Material’s +0.25');
        expect(QText.number(size: s).letterSpacing, 0);
      }
      for (final s in QText.displaySizes.keys) {
        expect(QText.display(size: s, ar: false).letterSpacing, 0);
      }
      expect(QText.eyebrow(ar: false).letterSpacing, 0);
    });

    test('Arabic is never tracked', () {
      for (final s in QText.displaySizes.keys) {
        expect(QText.display(size: s, ar: true).letterSpacing, 0);
      }
      expect(QText.arabic('قمر'), isTrue);
      expect(QText.arabic('Basel باسل'), isTrue);
      expect(QText.arabic('Basel'), isFalse);
      expect(QText.arabic('٣٠'), isFalse, reason: 'digits do not join');
    });
  });

  for (final lang in AppLang.values) {
    testWidgets('on every screen, the Log sheet and the conversation: every size on the scale, nothing tracked (${lang.name})', (tester) async {
      tester.view.devicePixelRatio = 3;
      tester.view.physicalSize = const Size(390, 2400) * 3;
      addTearDown(tester.view.reset);
      final state = AppState()..setLang(lang);
      state.profile = state.profile.copyWith(name: 'باسل');
      state.meals.add(LoggedMeal(name: lang == AppLang.ar ? 'كشري' : 'Koshary', sub: '', kcal: 640, p: 20, c: 100, f: 18, at: DateTime.now()));
      await tester.pumpWidget(ChangeNotifierProvider.value(value: state, child: const QamarApp()));

      var arabicRuns = 0;
      void check(String where) {
        expect(tester.takeException(), isNull, reason: where);
        for (final (text, style) in _runs(tester)) {
          expect(_onScale, contains(style.fontSize ?? 14), reason: '"$text" on $where is set at ${style.fontSize}');
          final spacing = style.letterSpacing ?? 0;
          if (QText.arabic(text)) arabicRuns++;
          expect(spacing, 0, reason: '"$text" on $where is tracked at $spacing');
        }
      }

      Future<void> settle() async {
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 400));
      }

      for (final screen in AppScreen.values) {
        state.go(screen);
        await settle();
        check('$screen');
      }
      state.go(AppScreen.today);
      state.orbTap();
      await settle();
      check('the Log sheet');
      state.closeLog();
      state.openChat();
      await settle();
      check('the conversation');
      state.closeChat();

      expect(arabicRuns, greaterThan(lang == AppLang.ar ? 50 : 0), reason: 'the sweep read the Arabic it was meant to');
    });
  }
}
