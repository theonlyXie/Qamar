// The SQL that meters the day's questions, photos and plan rewrites, held to
// what the app promises. The behaviour is checked in PGlite; these read the
// latest definitions across every migration, as the database ends up with
// them, so a later migration cannot quietly undo it.

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:qamar/models/su_economy.dart';

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

  group('the fourth question, bought with Su (0066)', () {
    test('the chat bucket counts the questions bought today, not a hardcoded 0', () {
      for (final name in ['qamar_ai_try_consume', 'qamar_ai_quota_snapshot']) {
        expect(latestFunction(name), contains('chat_extra'), reason: '$name reads the bought questions');
      }
      expect(latestFunction('qamar_ai_try_consume'), contains("when 'chat' then chat_extra"));
    });

    test('the price is charged from config, and the phone’s first guess is the price the server seeds', () {
      expect(latestFunction('qamar_wallet_redeem'), contains('qamar_su_value(v_price_key)'));
      final seed = File('supabase/migrations/0066_question_with_su.sql').readAsStringSync();
      expect(seed, contains("('question_extra', ${SuEconomy.extraQuestion})"));
      expect(seed, contains("('question_extra_daily', 1)"), reason: 'at most once a Cairo day');
    });
  });
}
