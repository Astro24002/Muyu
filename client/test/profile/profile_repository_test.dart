import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:muyu_client/auth/token_store.dart';
import 'package:muyu_client/core/api_client.dart';
import 'package:muyu_client/profile/profile_repository.dart';

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

Map<String, dynamic> profileResponse({String displayName = 'Muyu'}) => {
  'id': 'user-1',
  'phone': '+8613800138000',
  'display_name': displayName,
  'workspace_id': null,
  'device_id': 'device-1',
  'device_status': 'VERIFIED',
  'can_write': true,
};

void main() {
  test(
    'updates the display name with the authenticated profile endpoint',
    () async {
      late http.Request request;
      final repository = HttpProfileRepository(
        ApiClient(
          baseUrl: 'https://api.example',
          httpClient: MockClient((incoming) async {
            request = incoming;
            return http.Response(jsonEncode(profileResponse()), 200);
          }),
          tokenStore: StaticTokenStore(),
        ),
      );

      final user = await repository.updateDisplayName('Muyu');

      expect(request.method, 'PATCH');
      expect(request.url.path, '/api/v1/me');
      expect(request.headers['authorization'], 'Bearer mobile-access');
      expect(jsonDecode(request.body), {'display_name': 'Muyu'});
      expect(user.id, 'user-1');
      expect(user.phone, '+8613800138000');
      expect(user.nickname, 'Muyu');
    },
  );

  test('propagates profile API errors with their code and status', () async {
    final repository = HttpProfileRepository(
      ApiClient(
        baseUrl: 'https://api.example',
        httpClient: MockClient(
          (_) async => http.Response(
            jsonEncode({
              'code': 'VALIDATION_ERROR',
              'message': 'request validation failed',
              'details': [
                {
                  'loc': ['body', 'display_name'],
                  'msg': 'String should have at most 120 characters',
                },
              ],
            }),
            422,
          ),
        ),
        tokenStore: StaticTokenStore(),
      ),
    );

    await expectLater(
      repository.updateDisplayName('x' * 121),
      throwsA(
        isA<ProfileRepositoryFailure>()
            .having((error) => error.code, 'code', 'VALIDATION_ERROR')
            .having((error) => error.statusCode, 'statusCode', 422),
      ),
    );
  });
}
