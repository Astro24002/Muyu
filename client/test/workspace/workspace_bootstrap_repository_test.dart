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
  test('bootstrap endpoints parse state and normalize partner phone', () async {
    final requests = <http.Request>[];
    final repository = HttpWorkspaceBootstrapRepository(
      ApiClient(
        baseUrl: 'https://api.example',
        httpClient: MockClient((incoming) async {
          requests.add(incoming);
          if (incoming.method == 'GET') {
            return http.Response(
              jsonEncode({
                'state': 'NEEDS_PARTNER',
                'workspace': null,
                'invite': null,
                'device': {'status': 'VERIFIED', 'can_write': true},
              }),
              200,
            );
          }
          if (incoming.url.path.endsWith('bind-partner')) {
            return http.Response(
              jsonEncode({
                'state': 'WAITING_FOR_PARTNER',
                'workspace': {
                  'id': 'workspace-1',
                  'name': null,
                  'member_count': 1,
                },
                'invite': {
                  'id': 'invite-1',
                  'phone_masked': '+86******0169',
                  'status': 'PENDING',
                  'expires_at': '2026-08-29T00:00:00Z',
                },
                'device': {'status': 'VERIFIED', 'can_write': true},
              }),
              201,
            );
          }
          return http.Response(
            jsonEncode({
              'state': 'READY',
              'workspace': {
                'id': 'workspace-1',
                'name': null,
                'member_count': 2,
              },
              'invite': null,
              'device': {'status': 'VERIFIED', 'can_write': true},
            }),
            200,
          );
        }),
        tokenStore: StaticTokenStore(),
      ),
    );

    expect(
      (await repository.loadBootstrap()).state,
      WorkspaceBootstrapPhase.needsPartner,
    );
    await repository.bindPartner('15028180169', 'request-1');
    await repository.acceptInvite('invite-1', 'request-2');

    expect(requests[0].url.path, '/api/v1/workspaces/bootstrap');
    expect(jsonDecode(requests[1].body), {
      'phone': '+8615028180169',
      'request_id': 'request-1',
    });
    expect(requests[2].url.path, '/api/v1/workspace-invites/invite-1/accept');
    expect(jsonDecode(requests[2].body), {'request_id': 'request-2'});
  });

  test('bootstrap parses the two-person matching projection', () {
    final payload = WorkspaceBootstrapPayload.fromJson({
      'state': 'READY',
      'workspace': {
        'id': 'workspace-1',
        'name': '共同空间',
        'member_count': 2,
        'match_status': 'matched',
        'members': [
          {
            'user_id': 'user-a',
            'display_name': '我',
            'phone_masked': '+86******8726',
            'member_slot': 1,
            'membership_status': 'ACTIVE',
            'is_current': true,
          },
          {
            'user_id': 'user-b',
            'display_name': '对方',
            'phone_masked': '+86******0169',
            'member_slot': 2,
            'membership_status': 'ACTIVE',
            'is_current': false,
          },
        ],
      },
      'invite': null,
      'device': {'status': 'VERIFIED', 'can_write': true},
    });

    expect(payload.workspace!.matchStatus, WorkspaceMatchStatus.matched);
    expect(payload.workspace!.members, hasLength(2));
    expect(payload.workspace!.members[1].phoneMasked, '+86******0169');
    expect(payload.workspace!.members[0].isCurrent, isTrue);
  });

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
