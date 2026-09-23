// The SQL that meters the day's questions, photos and plan rewrites, held to
// what the app promises. The behaviour is checked in PGlite; these read the
// latest definitions across every migration, as the database ends up with
// them, so a later migration cannot quietly undo it.

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// The latest definition of [name] across every migration.
String latestFunction(String name) {
  final files = Directory('supabase/migrations').listSync().whereType<File>().where((f) => f.path.endsWith('.sql')).toList()
    ..sort((a, b) => a.path.compareTo(b.path));
  String? body;
  for (final f in files) {
    for (final m in RegExp('create or replace function public\\.$name\\(.*?\\n\\\$\\\$;', dotAll: true).allMatches(f.readAsStringSync())) {
      body = m.group(0);
    }
  }
  expect(body, isNotNull, reason: '$name is defined');
  return body!;
}

void main() {
  group('the day’s last use is answered (0065)', () {
    test('a use that was taken says allowed, so the gateway answers it', () {
      final body = latestFunction('qamar_ai_try_consume');
      // The last return is the one after the update that takes the use.
      final taken = body.substring(body.lastIndexOf('update public.ai_usage_days'));
      expect(taken, contains("'allowed', true"),
          reason: 'bucket_json says used < cap after the use, which is false for the third of three; the gateway refuses on it');
    });
  });
}
