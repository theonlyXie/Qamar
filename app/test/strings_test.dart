// The string table, seat 6's part: no line of copy is kept that nothing
// shows. "or type instead" was left behind when the scan's duplicate way to
// type went (e04b50b) and is gone. So are the quest's Accept, Replace and
// Completed, which O2 took away (the meal or glass pays the quest, not a
// tap), and the plan's Mark eaten, which only opened the old Log page
// before logging moved to the orb (seat 3). And the welcome's old "Start
// now", the name step's "First name" hint (the question is on screen), the
// old typed log's "Continue", and "Done", which only looked read through a
// quest's `q.done` (seat 1). And the old log sheet's words (its inputs,
// "Recent", "Describe the meal", "Analyzing", "Source preview", "Confirm
// meal", the portion note the confirm card's badges now carry), the barcode
// and nutrition-label scans that were never built, the old tab bar's "Log",
// and the conversation's superseded states ("Online", "Tap the moon and
// speak", "What's on your mind?"), with the camera-and-mic note that the
// permission problems now say where it happens (seat 2). And the wallet's
// old subtitle, "Never purchased, never cash", whose cue the wallet's terms
// now carry, where it is drawn (seat 4). The table still holds 5 other
// strings nothing reads; they are listed here by name, owed
// to the seats whose screens they came from, so that this test holds the
// line: a string that stops being read is either used again or deleted,
// not kept.

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Unread before this test, left for their owners to use or retire.
const _owed = {
  'restart', 'guestNote', 'priceLabel', 'limitLabel', 'suEarned',
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

  test('the quest\'s Accept, Replace and Completed, and the plan\'s Mark eaten, are gone from the table', () {
    for (final name in const ['accept', 'replace', 'done2', 'markEaten']) {
      expect(fields, isNot(contains(name)), reason: name);
    }
    for (final words in const ["'Accept'", "'Replace'", "'Completed'", "'Mark eaten'", "'موافق'", "'غيّرها'", "'اتعملت'", "'اتاكلت'"]) {
      expect(table, isNot(contains(words)), reason: words);
    }
  });

  test('seat 1’s retired strings are gone from the table, "Done" with them', () {
    for (final f in const ['startNow', 'namePlaceholder', 'continueLabel', 'done']) {
      expect(fields, isNot(contains(f)), reason: '$f is not read anywhere');
    }
    for (final words in const ['Start now', 'ابدأ دلوقتي', 'First name', 'اسمك الأول']) {
      expect(table, isNot(contains(words)));
    }
  });

  test('the wallet\'s old subtitle is gone from the table; its cue is in the terms the wallet draws', () {
    expect(fields, isNot(contains('walletSub')));
    for (final words in const ['Never purchased', 'Earned through useful actions', 'بتتكسب بالأفعال المفيدة']) {
      expect(table, isNot(contains(words)), reason: words);
    }
  });

  test('every string in the table is read somewhere, but those owed to their seats', () {
    final unread = [for (final f in fields) if (!read(f) && !_owed.contains(f)) f];
    expect(unread, isEmpty, reason: 'kept, but nothing shows it: $unread');
    final nowRead = [for (final f in _owed) if (read(f)) f];
    expect(nowRead, isEmpty, reason: 'read again, so no longer owed: take it off the list: $nowRead');
  });
}
