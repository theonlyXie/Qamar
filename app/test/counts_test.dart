// A count agrees with its noun, seat 6's part: You's "Qamar memory" said
// "1 items" in English and "١ عناصر" in Arabic, the plural for every number.
// English: one item, n items. Arabic, as it is said: one (عنصر واحد), two
// (the dual, عنصرين), three to ten (the plural, عناصر), eleven on (the
// singular, عنصر), in the app's digits.

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

import 'package:qamar/l10n/strings.dart';
import 'package:qamar/main.dart';
import 'package:qamar/screens/you_screen.dart';
import 'package:qamar/state/app_state.dart';

import 'support/app_fonts.dart';

String _eastern(String s) => s.replaceAllMapped(RegExp('[0-9]'), (m) => '٠١٢٣٤٥٦٧٨٩'[int.parse(m.group(0)!)]);

void main() {
  setUpAll(() async {
    await loadAppFonts();
    for (final name in const ['com.qamar.app/quick_events', 'com.qamar.app/quick_invoke']) {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(MethodChannel(name), (call) async => null);
    }
  });

  test('English: one item, n items', () {
    expect(YouScreen.itemsLine(1, isAr: false, iso: (s) => s), '1 item');
    expect(YouScreen.itemsLine(2, isAr: false, iso: (s) => s), '2 items');
    expect(YouScreen.itemsLine(11, isAr: false, iso: (s) => s), '11 items');
  });

  test('Arabic: one, the dual, three to ten, eleven on', () {
    String ar(int n) => YouScreen.itemsLine(n, isAr: true, iso: _eastern);
    expect(ar(1), 'عنصر واحد');
    expect(ar(2), 'عنصرين');
    expect(ar(3), '٣ عناصر');
    expect(ar(10), '١٠ عناصر');
    expect(ar(11), '١١ عنصر');
    expect(ar(100), '١٠٠ عنصر');
    expect(ar(103), '١٠٣ عناصر');
  });

  for (final lang in AppLang.values) {
    testWidgets('on You, a memory of one thing says one (${lang.name})', (tester) async {
      tester.view.devicePixelRatio = 3;
      tester.view.physicalSize = const Size(390, 2600) * 3;
      addTearDown(tester.view.reset);
      final s = AppState()..setLang(lang);
      s.profile = s.profile.copyWith(name: 'Basel');
      s.dismissOrbTutorial();
      s.go(AppScreen.today);
      s.go(AppScreen.you);
      expect(s.rememberedCount(), 1, reason: 'the name, and nothing else');
      await tester.pumpWidget(ChangeNotifierProvider.value(value: s, child: const QamarApp()));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
      expect(find.text(lang == AppLang.ar ? 'عنصر واحد' : '1 item'), findsOneWidget);
      expect(find.text('1 items'), findsNothing);
      expect(find.textContaining('عناصر'), findsNothing);
    });
  }
}
