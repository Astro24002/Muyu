import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:muyu_client/auth/token_store.dart';
import 'package:muyu_client/core/api_client.dart';
import 'package:muyu_client/workspace/device_authorization_repository.dart';

class StaticTokenStore implements TokenStore {
  @override
  Future<String?> readAccessToken() async => 'mobile-access';

  @override
  Future<String?> readRefreshToken() async => null;

  @override
  Future<void> write({
    required String accessToken,
    required String refreshToken,
  }) async {}

  @override
  Future<void> clear() async {}
}

void main() {
  test('lists authorization requests with candidate metadata', () async {
    final requests = <http.Request>[];
    final repository = HttpDeviceAuthorizationRepository(
      ApiClient(
        baseUrl: 'https://api.example',
        httpClient: MockClient((incoming) async {
          requests.add(incoming);
          return http.Response(
            jsonEncode([
              {
                'id': 'request-1',
                'candidate_device_id': 'device-2',
                'candidate_device_label': 'Pixel 9',
                'candidate_platform': 'ANDROID',
                'candidate_user_id': 'user-2',
                'candidate_phone_masked': '+86******0169',
                'requester_user_id': 'user-2',
                'requester_phone_masked': '+86******0169',
                'is_incoming': true,
                'status': 'PENDING',
                'created_at': '2026-08-31T00:00:00Z',
                'expires_at': '2026-08-31T00:10:00Z',
              },
            ]),
            200,
          );
        }),
        tokenStore: StaticTokenStore(),
      ),
    );

    final result = await repository.listRequests();

    expect(requests.single.method, 'GET');
    expect(requests.single.url.path, '/api/v1/devices/authorization-requests');
    expect(result.single.candidateDeviceLabel, 'Pixel 9');
    expect(result.single.isIncoming, isTrue);
    expect(result.single.candidatePhoneMasked, '+86******0169');
  });

  test(
    'rejects an authorization request through the device endpoint',
    () async {
      late http.Request request;
      final repository = HttpDeviceAuthorizationRepository(
        ApiClient(
          baseUrl: 'https://api.example',
          httpClient: MockClient((incoming) async {
            request = incoming;
            return http.Response('{"id":"request-1","status":"REJECTED"}', 200);
          }),
          tokenStore: StaticTokenStore(),
        ),
      );

      await repository.reject('request-1');

      expect(request.method, 'POST');
      expect(
        request.url.path,
        '/api/v1/devices/authorization-requests/request-1/reject',
      );
    },
  );
}
