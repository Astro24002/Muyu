import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:muyu_client/auth/token_store.dart';
import 'package:muyu_client/core/api_client.dart';
import 'package:muyu_client/workspace/device_repository.dart';

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
  test('lists the authenticated user devices without exposing public keys', () async {
    late http.Request request;
    final repository = HttpDeviceRepository(
      ApiClient(
        baseUrl: 'https://api.example',
        httpClient: MockClient((incoming) async {
          request = incoming;
          return http.Response(
            jsonEncode([
              {
                'id': 'device-1',
                'platform': 'ANDROID',
                'label': 'Pixel',
                'status': 'ACTIVE',
                'is_current': true,
                'created_at': '2026-08-27T00:00:00Z',
                'enrolled_at': '2026-08-27T00:00:00Z',
                'revoked_at': null,
              },
            ]),
            200,
          );
        }),
        tokenStore: StaticTokenStore(),
      ),
    );

    final devices = await repository.listDevices();

    expect(request.method, 'GET');
    expect(request.url.path, '/api/v1/devices');
    expect(request.headers['authorization'], 'Bearer mobile-access');
    expect(devices, hasLength(1));
    expect(devices.single.id, 'device-1');
    expect(devices.single.label, 'Pixel');
    expect(devices.single.isCurrent, isTrue);
    expect(devices.single.enrolledAt, DateTime.utc(2026, 8, 27));
  });
}
