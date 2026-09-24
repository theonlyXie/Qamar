// The Arabic digit sweep (O8), reusable: any test can check that what a
// screen draws in Arabic carries no Latin digit. Arabic numbers go through
// state.iso() or the formatters, which draw Eastern digits; a raw int in an
// Arabic string shows up here as a 0-9.

import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

final _isolates = RegExp('[\u2066-\u2069]');
final _latinDigit = RegExp('[0-9]');

/// Every string drawn under [within] (the whole tree by default), with the
/// bidi isolates that state.iso() adds taken out.
List<String> drawnTexts(WidgetTester tester, {Finder? within}) {
  final texts = within == null ? find.byType(RichText) : find.descendant(of: within, matching: find.byType(RichText));
  return tester
      .widgetList<RichText>(texts)
      .map((r) => r.text.toPlainText().replaceAll(_isolates, ''))
      .where((t) => t.trim().isNotEmpty)
      .toList();
}

/// Fails, naming every offending string, if anything drawn under [within]
/// carries a Latin digit. Text the person typed is not drawn as a RichText
/// and is never checked. [allow] lets a test name a string that has a
/// reason to carry one (a code, a brand), matched by substring — use it
/// sparingly and say why at the call.
void expectNoLatinDigits(WidgetTester tester, {Finder? within, Iterable<Pattern> allow = const [], String where = ''}) {
  final offending = drawnTexts(tester, within: within)
      .where((t) => _latinDigit.hasMatch(t))
      .where((t) => !allow.any((a) => t.contains(a)))
      .toList();
  expect(offending, isEmpty, reason: 'Latin digits drawn in Arabic${where.isEmpty ? '' : ' on $where'}: $offending');
}
