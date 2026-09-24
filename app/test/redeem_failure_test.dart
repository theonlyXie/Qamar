// What a failed Su redemption means (O13, 0067). Only the redeem function's
// own RAISE (SQLSTATE P0001) is a refusal whose transaction rolled back, and
// so the only failure the app may call "no points were spent". A 5xx also
// arrives as a PostgrestException, with the status as its code, and the
// purchase may have committed before it.

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:qamar/services/repositories.dart';
import 'package:qamar/services/supabase_repositories.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

void main() {
  test('the redeem function’s own refusal is a refusal', () {
    final e = SupabaseWalletRepository.redeemFailure(const PostgrestException(message: 'insufficient balance', code: 'P0001'));
    expect(e, isA<RedeemRefused>());
    expect((e as RedeemRefused).message, 'insufficient balance');
  });

  test('a 5xx, a timeout or no connection stays unknown', () {
    for (final raw in <Object>[
      const PostgrestException(message: '<html>Bad Gateway</html>', code: '502', details: 'Bad Gateway'),
      const PostgrestException(message: 'upstream timed out', code: '504'),
      const SocketException('Failed host lookup'),
      Exception('anything else'),
    ]) {
      expect(SupabaseWalletRepository.redeemFailure(raw), same(raw), reason: '$raw');
    }
  });
}
