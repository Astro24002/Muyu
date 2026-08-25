import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:muyu_client/auth/web_login_repository.dart';
import 'package:muyu_client/core/api_client.dart';

void main() {
  test('parses and validates an HTTPS QR payload before API use', () {
    final payload = WebQrPayload.parse(
      jsonEncode({
        'version': 1,
        'challenge_id': 'challenge-1',
        'scan_nonce': 'nonce-1',
        'origin': 'https://muyu.example',
        'expires_at': '2026-08-24T12:02:00Z',
      }),
      now: DateTime.utc(2026, 8, 24, 12),
    );

    expect(payload.challengeId, 'challenge-1');
    expect(payload.origin, 'https://muyu.example');
  });

  test('rejects malformed, expired, or non-HTTPS QR payloads', () {
    expect(
      () => WebQrPayload.parse('{"version":1}'),
      throwsA(isA<WebQrPayloadFailure>()),
    );
    expect(
      () => WebQrPayload.parse(
        jsonEncode({
          'version': 1,
          'challenge_id': 'c',
          'scan_nonce': 'n',
          'origin': 'http://muyu.example',
          'expires_at': '2026-08-24T12:02:00Z',
        }),
        now: DateTime.utc(2026, 8, 24, 12),
      ),
      throwsA(isA<WebQrPayloadFailure>()),
    );
  });

  test(
    'creates a browser challenge with a proof hash and no raw proof',
    () async {
      late http.Request request;
      final repository = WebLoginRepository(
        ApiClient(
          baseUrl: 'https://muyu.example',
          httpClient: MockClient((incoming) async {
            request = incoming;
            return http.Response(
              jsonEncode({
                'challenge_id': 'challenge-1',
                'qr_payload': '{}',
                'origin': 'https://muyu.example',
                'safety_code': '123456',
                'expires_at': '2026-08-24T12:02:00Z',
              }),
              201,
            );
          }),
        ),
      );

      await repository.createChallenge('browser-proof');

      expect(request.body, isNot(contains('browser-proof')));
      expect(jsonDecode(request.body)['browser_proof_hash'], isNotEmpty);
    },
  );
}
