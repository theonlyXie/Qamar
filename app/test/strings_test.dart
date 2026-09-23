// The string table, seat 6's part: no line of copy is kept that nothing
// shows. "or type instead" was left behind when the scan's duplicate way to
// type went (e04b50b) and is gone. The table still holds 32 other strings
// nothing reads; they are listed here by name, owed to the seats whose
// screens they came from, so that this test holds the line: a string that
// stops being read is either used again or deleted, not kept.

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Unread before this test, left for their owners to use or retire.
const _owed = {
  'restart', 'startNow', 'guestNote', 'scanInbodySub', 'walletSub', 'priceLabel', 'limitLabel', 'barcode', 'barcodeSub',
  'labelSub', 'suEarned', 'namePlaceholder', 'accept', 'done2', 'logMeal', 'logSub', 'voiceSub', 'textSub', 'recent',
  'recentSub', 'describeMeal', 'mealPlaceholder', 'continueLabel', 'permissionNote', 'analyzing', 'sourcePreview',
  'uncertainNote', 'online', 'markEaten', 'sIdle', 'sAnswer', 'tapPrompt',
};

void main() {
  final table = File('lib/l10n/strings.dart').readAsStringSync();
  final fields = RegExp(r'class QStrings \{\s*final String (.*?);', dotAll: true)
      .firstMatch(table)!
      .group(1)!
      .split(',')
      .map((f) => f.trim())
      .where((f) => f.isNotEmpty)
      .toList();
  final elsewhere = Directory('lib')
      .listSync(recursive: true)
      .whereType<File>()
      .where((f) => f.path.endsWith('.dart') && !f.path.endsWith('l10n/strings.dart'))
      .map((f) => f.readAsStringSync())
      .join('\n');
  bool read(String f) => RegExp('\\.$f\\b').hasMatch(elsewhere);

  test('"or type instead" is gone from the table', () {
    expect(fields, isNot(contains('typeInstead')));
    expect(table, isNot(contains('or type instead')));
    expect(table, isNot(contains('أو اكتب بدل الكلام')));
  });

  test('every string in the table is read somewhere, but those owed to their seats', () {
    final unread = [for (final f in fields) if (!read(f) && !_owed.contains(f)) f];
    expect(unread, isEmpty, reason: 'kept, but nothing shows it: $unread');
    final nowRead = [for (final f in _owed) if (read(f)) f];
    expect(nowRead, isEmpty, reason: 'read again, so no longer owed: take it off the list: $nowRead');
  });
}
