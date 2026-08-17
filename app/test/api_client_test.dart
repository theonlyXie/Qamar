import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'package:qamar/services/api_client.dart';

void main() {
  test('QamarApiClient unwraps data envelope', () async {
    final client = QamarApiClient(
      baseUrl: 'https://example.test/api',
      authTokenProvider: () => 'tok',
      client: MockClient((request) async {
        expect(request.url.path, '/api/bootstrap');
        expect(request.headers['Authorization'], 'Bearer tok');
        return http.Response(
          '{"data":{"server_time":"2026-01-01T00:00:00Z"},"request_id":"r1"}',
          200,
          headers: {'Content-Type': 'application/json'},
        );
      }),
    );

    final data = await client.bootstrap();
    expect(data['server_time'], '2026-01-01T00:00:00Z');
  });

  test('QamarApiClient maps typed errors', () async {
    final client = QamarApiClient(
      baseUrl: 'https://example.test/api',
      authTokenProvider: () => 'tok',
      client: MockClient((request) async {
        return http.Response(
          '{"error":{"code":"unauthorized","message_key":"error.unauthorized","retryable":false},"request_id":"r2"}',
          401,
          headers: {'Content-Type': 'application/json'},
        );
      }),
    );

    expect(
      () => client.getProfile(),
      throwsA(
        isA<QamarApiException>()
            .having((e) => e.status, 'status', 401)
            .having((e) => e.code, 'code', 'unauthorized'),
      ),
    );
  });

  test('walletRedeem sends Idempotency-Key', () async {
    final client = QamarApiClient(
      baseUrl: 'https://example.test/api',
      authTokenProvider: () => 'tok',
      client: MockClient((request) async {
        expect(request.headers['Idempotency-Key'], 'k-1');
        expect(request.method, 'POST');
        return http.Response(
          '{"data":{"result":{"balance_after":50}},"request_id":"r3"}',
          200,
          headers: {'Content-Type': 'application/json'},
        );
      }),
    );

    final data = await client.walletRedeem(catalogItemId: 'photo', idempotencyKey: 'k-1');
    expect(data['result']['balance_after'], 50);
  });
}
