// A streak freeze is insurance, bought before the day it covers (O4, 0064):
// it covers the day it is taken on or a later one, never a day already
// missed. The blueprint (line 1267): "Streak freeze costs points; there is
// no 'restore my streak' purchase." The server decides (qamar_streak_snapshot);
// these hold its latest definition to that, and the words that describe the
// freeze to the same rule. The behaviour itself is checked in PGlite.

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:qamar/models/meal.dart';
import 'package:qamar/widgets/explain.dart';

/// The latest definition of qamar_streak_snapshot across every migration, as
/// the database ends up with it.
String _latestSnapshot() {
  final files = Directory('supabase/migrations').listSync().whereType<File>().where((f) => f.path.endsWith('.sql')).toList()
    ..sort((a, b) => a.path.compareTo(b.path));
  String? body;
  for (final f in files) {
    for (final m in RegExp(r'create or replace function public\.qamar_streak_snapshot\(.*?\n\$\$;', dotAll: true).allMatches(f.readAsStringSync())) {
      body = m.group(0);
    }
  }
  expect(body, isNotNull, reason: 'qamar_streak_snapshot is defined');
  return body!;
}

void main() {
  test('the server lets a token cover only the day it was taken on, or later', () {
    final body = _latestSnapshot();
    final rule = RegExp(r'and\s+redeemed_on\s*(.*?)\s*<=\s*v_cursor').firstMatch(body);
    expect(rule, isNotNull, reason: 'a token is matched to a day by its redemption date');
    expect(rule!.group(1), isEmpty, reason: 'redeemed_on <= v_cursor, never "redeemed_on - 1": that mended the day before it was bought');
  });

  test('the wallet says so, in both languages', () {
    final freeze = kSpendCatalog.singleWhere((i) => i.id == 'streak_freeze');
    expect(freeze.whatEn, contains('never to a day missed before you took it'));
    expect(freeze.whatAr, contains('مبيرجّعش يوم فات'));
  });

  test('and so does the streak’s explainer', () {
    final streak = kExplanations['streak']!;
    expect(streak.soWhatEn, contains('never brings back a day already missed'));
    expect(streak.soWhatAr, contains('مبيرجّعش يوم فات'));
  });
}
