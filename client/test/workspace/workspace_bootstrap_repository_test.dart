import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:muyu_client/auth/token_store.dart';
import 'package:muyu_client/core/api_client.dart';
import 'package:muyu_client/workspace/workspace_bootstrap_repository.dart';

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
  test('current workspace returns null for a new authenticated user', () async {
    late http.Request request;
    final repository = HttpWorkspaceBootstrapRepository(
      ApiClient(
        baseUrl: 'https://api.example',
        httpClient: MockClient((incoming) async {
          request = incoming;
          return http.Response('null', 200);
        }),
        tokenStore: StaticTokenStore(),
      ),
    );

    expect(await repository.currentWorkspace(), isNull);
    expect(request.method, 'GET');
    expect(request.url.path, '/api/v1/workspaces/current');
    expect(request.headers['authorization'], 'Bearer mobile-access');
  });

  test('create workspace posts an empty object and parses the authoritative result', () async {
    late http.Request request;
    final repository = HttpWorkspaceBootstrapRepository(
      ApiClient(
        baseUrl: 'https://api.example',
        httpClient: MockClient((incoming) async {
          request = incoming;
          return http.Response(
            '{"id":"workspace-1","name":null,"status":"ACTIVE"}',
            201,
          );
        }),
        tokenStore: StaticTokenStore(),
      ),
    );

    final workspace = await repository.createWorkspace();
    expect(request.method, 'POST');
    expect(request.url.path, '/api/v1/workspaces');
    expect(jsonDecode(request.body), <String, dynamic>{});
    expect(workspace.id, 'workspace-1');
    expect(workspace.name, isNull);
  });

  test(
    'workspace limit error remains distinguishable for race recovery',
    () async {
      final repository = HttpWorkspaceBootstrapRepository(
        ApiClient(
          baseUrl: 'https://api.example',
          httpClient: MockClient(
            (_) async => http.Response(
              '{"code":"workspace_limit_reached","message":"already joined"}',
              409,
            ),
          ),
        ),
      );

      await expectLater(
        repository.createWorkspace(),
        throwsA(
          isA<WorkspaceBootstrapFailure>().having(
            (error) => error.code,
            'code',
            'workspace_limit_reached',
          ),
        ),
      );
    },
  );
}
