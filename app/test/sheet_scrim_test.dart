// The sheets' scrims, seat 6's part (seat 2's review): the layer that
// closes a sheet was an unnamed button the size of the screen under
// TalkBack. It is named Close (إغلاق) inside QSheetScrim, for all four
// sheets; a tap on it closes the sheet, and a tap inside the sheet does
// not, now that nothing inside has to swallow taps. The guideline sweep in
// widget_test.dart runs with each sheet open, in both languages.

import 'dart:ui' show SemanticsAction;

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

import 'package:qamar/l10n/strings.dart';
import 'package:qamar/main.dart';
import 'package:qamar/models/activity.dart';
import 'package:qamar/state/app_state.dart';
import 'package:qamar/widgets/common.dart';
import 'package:qamar/widgets/explain.dart';

import 'support/app_fonts.dart';

typedef _Sheet = ({String name, void Function(AppState) open, bool Function(AppState) isOpen});

final _sheets = <_Sheet>[
  (name: 'Why', open: (s) => s.openWhy(), isOpen: (s) => s.whyOpen),
  (name: 'an explanation', open: (s) => s.openExplain(kExplanations['kcal_remaining']!), isOpen: (s) => s.explainOpen != null),
  (name: 'the account sheet', open: (s) => s.openLinkAccount(), isOpen: (s) => s.authOpen),
  (name: 'the activity sheet', open: (s) => s.chooseActivity(ActivityKind.walk), isOpen: (s) => s.pendingActivity != null),
];

void main() {
  setUpAll(() async {
    await loadAppFonts();
    for (final name in const ['com.qamar.app/quick_events', 'com.qamar.app/quick_invoke']) {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(MethodChannel(name), (call) async => null);
    }
  });

  for (final lang in AppLang.values) {
    for (final sheet in _sheets) {
      testWidgets('${sheet.name}: its scrim is a button named ${lang == AppLang.ar ? 'إغلاق' : 'Close'}, and closes it; inside, a tap stays (${lang.name})', (tester) async {
        tester.view.devicePixelRatio = 3;
        tester.view.physicalSize = const Size(390, 844) * 3;
        addTearDown(tester.view.reset);
        final handle = tester.ensureSemantics();
        final s = AppState()..setLang(lang);
        s.dismissOrbTutorial();
        s.go(AppScreen.today);
        await tester.pumpWidget(ChangeNotifierProvider.value(value: s, child: const QamarApp()));
        await tester.pump();
        sheet.open(s);
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 700));
        expect(sheet.isOpen(s), isTrue);

        final dismiss = find.byKey(QSheetScrim.dismissKey);
        expect(dismiss, findsOneWidget);
        final node = tester.getSemantics(dismiss);
        expect(node.label, lang == AppLang.ar ? 'إغلاق' : 'Close');
        expect(node.flagsCollection.isButton, isTrue);
        expect(node.getSemanticsData().hasAction(SemanticsAction.tap), isTrue);

        // Inside the sheet: its own surface, away from any control and clear
        // of its rounded corner (outside the curve is the scrim).
        final panel = tester.getRect(find.byKey(QSheetScrim.panelKey));
        await tester.tapAt(Offset(panel.left + 40, panel.top + 10));
        await tester.pump();
        expect(sheet.isOpen(s), isTrue, reason: 'a tap on the sheet itself does not close it');

        await tester.tapAt(const Offset(195, 60)); // the scrim, above the sheet
        await tester.pump();
        expect(sheet.isOpen(s), isFalse, reason: 'a tap on the scrim closes it');
        handle.dispose();
      });
    }
  }
}
