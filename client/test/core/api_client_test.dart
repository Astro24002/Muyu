import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:muyu_client/auth/auth_repository.dart';
import 'package:muyu_client/auth/token_store.dart';
import 'package:muyu_client/core/api_client.dart';

class MemoryTokenStore implements TokenStore {
  String? access;
  String? refresh;

  @override
  Future<String?> readAccessToken() async => access;

  @override
  Future<String?> readRefreshToken() async => refresh;

  @override
  Future<void> write({
    required String accessToken,
    required String refreshToken,
  }) async {
    access = accessToken;
    refresh = refreshToken;
  }

  @override
  Future<void> clear() async {
    access = null;
    refresh = null;
  }
}

const userJson = {
  'id': '1',
  'phone': '15028180169',
  'nickname': '用户一',
  'avatar_key': 'avatar-1',
  'role': '成员',
};

void main() {
  test(
    'authenticated request refreshes once and retries with the new token',
    () async {
      final store = MemoryTokenStore()
        ..access = 'expired-access'
        ..refresh = 'valid-refresh';
      final requests = <http.Request>[];
      final httpClient = MockClient((request) async {
        requests.add(request);
        if (request.url.path == '/api/me' && requests.length == 1) {
          return http.Response(
            jsonEncode({
              'code': 'UNAUTHORIZED',
              'message': 'expired',
              'details': {},
            }),
            401,
            headers: {'content-type': 'application/json'},
          );
        }
        if (request.url.path == '/api/auth/refresh') {
          return http.Response(
            jsonEncode({
              'user': userJson,
              'access_token': 'new-access',
              'refresh_token': 'new-refresh',
              'token_type': 'bearer',
            }),
            200,
            headers: {'content-type': 'application/json'},
          );
        }
        return http.Response(
          jsonEncode(userJson),
          200,
          headers: {'content-type': 'application/json'},
        );
      });
      final repository = HttpAuthRepository(
        ApiClient(
          baseUrl: 'http://example.test',
          httpClient: httpClient,
          tokenStore: store,
        ),
        store,
      );

      final result = await repository.me();

      expect(result.nickname, '用户一');
      expect(requests.map((request) => request.url.path), [
        '/api/me',
        '/api/auth/refresh',
        '/api/me',
      ]);
      expect(requests.first.headers['authorization'], 'Bearer expired-access');
      expect(requests.last.headers['authorization'], 'Bearer new-access');
      expect(store.refresh, 'new-refresh');
    },
  );

  test(
    'failed refresh clears tokens and does not retry indefinitely',
    () async {
      final store = MemoryTokenStore()
        ..access = 'expired-access'
        ..refresh = 'invalid-refresh';
      var requestCount = 0;
      final httpClient = MockClient((request) async {
        requestCount++;
        return http.Response(
          jsonEncode({
            'code': 'UNAUTHORIZED',
            'message': 'session expired',
            'details': {},
          }),
          401,
          headers: {'content-type': 'application/json'},
        );
      });
      final repository = HttpAuthRepository(
        ApiClient(
          baseUrl: 'http://example.test',
          httpClient: httpClient,
          tokenStore: store,
        ),
        store,
      );

      await expectLater(repository.me(), throwsA(isA<AuthFailure>()));

      expect(requestCount, 2);
      expect(store.access, isNull);
      expect(store.refresh, isNull);
    },
  );

  test('network failures are exposed as authentication failures', () async {
    final store = MemoryTokenStore();
    final httpClient = MockClient(
      (request) => throw http.ClientException('offline'),
    );
    final repository = HttpAuthRepository(
      ApiClient(
        baseUrl: 'http://example.test',
        httpClient: httpClient,
        tokenStore: store,
      ),
      store,
    );

    await expectLater(
      repository.login('15028180169', 'password'),
      throwsA(
        isA<AuthFailure>().having(
          (failure) => failure.message,
          'message',
          '网络连接失败，请稍后重试',
        ),
      ),
    );
  });
}
