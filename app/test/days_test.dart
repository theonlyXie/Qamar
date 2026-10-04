// Days are stepped and counted by the calendar (lib/models/days.dart), never
// by 24-hour durations: in Cairo a day can have 23 hours or 25. CI runs in
// UTC, where a Duration(days: 1) step never drifts and no behaviour test can
// see the difference, so this one reads lib/ itself and fails in any time
// zone if a Duration day step or an inDays count comes back outside the
// helper. The scenarios themselves run in Cairo time: cairo_days_test.dart,
// "Test in Cairo time" in checks.yml.

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:qamar/models/days.dart';

/// Day arithmetic by duration: a step of whole days, a count of them, or a
/// day spelled as 24 hours.
final _byDuration = [
  RegExp(r'Duration\(\s*days\s*:'),
  RegExp(r'\.inDays\b'),
  RegExp(r'Duration\(\s*hours\s*:\s*24\b'),
];

/// Every line of lib/ that does day arithmetic by duration, outside [Days],
/// as "path:line: code". Comments are not code.
List<String> dayArithmeticByDuration() {
  final found = <String>[];
  for (final f in Directory('lib').listSync(recursive: true).whereType<File>()) {
    if (!f.path.endsWith('.dart') || f.path.endsWith('models/days.dart')) continue;
    final lines = f.readAsLinesSync();
    for (var i = 0; i < lines.length; i++) {
      final code = lines[i].split('//').first;
      if (_byDuration.any((p) => p.hasMatch(code))) found.add('${f.path}:${i + 1}: ${lines[i].trim()}');
    }
  }
  return found;
}

void main() {
  test('no day in lib/ is stepped or counted as 24 hours, outside Days', () {
    expect(dayArithmeticByDuration(), isEmpty, reason: 'step and count days with Days (lib/models/days.dart)');
  });

  test('the guard sees the patterns it is there for', () {
    for (final line in [
      'final day = today.add(Duration(days: d));',
      'cursor = cursor.subtract(const Duration(days: 1));',
      'final n = to.difference(from).inDays;',
      'final next = day.add(const Duration(hours: 24));',
    ]) {
      expect(_byDuration.any((p) => p.hasMatch(line)), isTrue, reason: line);
    }
    expect(_byDuration.any((p) => p.hasMatch('left <= const Duration(hours: 48)')), isFalse, reason: 'an elapsed window is not a day');
  });

  group('Days', () {
    test('steps by the calendar, across months and years', () {
      expect(Days.add(DateTime(2026, 12, 30), 3), DateTime(2027, 1, 2));
      expect(Days.add(DateTime(2026, 3, 1, 15, 20), -1), DateTime(2026, 2, 28), reason: 'a day, at its start');
      expect(Days.add(DateTime(2028, 3, 1), -1), DateTime(2028, 2, 29), reason: 'a leap year');
      expect(Days.of(DateTime(2026, 9, 23, 23, 59)), DateTime(2026, 9, 23));
    });

    test('counts whole calendar days, whatever the hours', () {
      expect(Days.between(DateTime(2026, 4, 20), DateTime(2026, 4, 27)), 7);
      expect(Days.between(DateTime(2026, 4, 20, 23, 30), DateTime(2026, 4, 21, 0, 10)), 1, reason: 'forty minutes, across a midnight');
      expect(Days.between(DateTime(2026, 4, 21, 8), DateTime(2026, 4, 21, 22)), 0);
      expect(Days.between(DateTime(2026, 4, 27), DateTime(2026, 4, 20)), -7);
      expect(Days.between(DateTime(2026), DateTime(2026, 12, 31)), 364);
    });

    test('a time of day stays on the wall clock', () {
      final lunch = Days.at(DateTime(2026, 4, 24), 14 * 60);
      expect((lunch.year, lunch.month, lunch.day, lunch.hour, lunch.minute), (2026, 4, 24, 14, 0));
      final weekAgo = Days.ago(DateTime(2026, 5, 1, 13, 30), 7);
      expect((weekAgo.month, weekAgo.day, weekAgo.hour, weekAgo.minute), (4, 24, 13, 30));
    });

    test('a UTC date stays UTC', () {
      expect(Days.add(DateTime.utc(2026, 10, 29, 22), 1), DateTime.utc(2026, 10, 30));
      expect(Days.of(DateTime.utc(2026, 10, 29, 22)).isUtc, isTrue);
    });
  });
}
