import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:muyu_client/auth/token_store.dart';
import 'package:muyu_client/core/api_client.dart';
import 'package:muyu_client/models/task.dart';
import 'package:muyu_client/task/task_repository.dart';

class MemoryTokenStore implements TokenStore {
  @override
  Future<void> clear() async {}

  @override
  Future<String?> readAccessToken() async => 'access';

  @override
  Future<String?> readRefreshToken() async => 'refresh';

  @override
  Future<void> write({
    required String accessToken,
    required String refreshToken,
  }) async {}
}

Map<String, dynamic> taskJson() => {
  'id': 'task-1',
  'parent_task_id': null,
  'title': '整理旅行计划',
  'description': '',
  'status': 'TODO',
  'current_handler_id': 'user-a',
  'planned_start_at': null,
  'due_at': null,
  'estimated_minutes': null,
  'completed_at': null,
  'created_by': 'user-a',
  'version': 1,
  'status_version': 1,
  'created_at': '2026-08-17T00:00:00Z',
  'updated_at': '2026-08-17T00:00:00Z',
  'assignee_ids': ['user-a'],
};

void main() {
  test(
    'repository creates a task and sends the authenticated JSON contract',
    () async {
      late http.Request request;
      final repository = HttpTaskRepository(
        ApiClient(
          baseUrl: 'http://example.test',
          httpClient: MockClient((incoming) async {
            request = incoming;
            return http.Response(
              jsonEncode(taskJson()),
              201,
              headers: {'content-type': 'application/json; charset=utf-8'},
            );
          }),
          tokenStore: MemoryTokenStore(),
        ),
      );

      final task = await repository.create(
        title: '整理旅行计划',
        description: '确定交通',
        assigneeIds: const ['user-a'],
        currentHandlerId: 'user-a',
      );

      expect(task, isA<TaskItem>());
      expect(request.method, 'POST');
      expect(request.url.path, '/api/tasks');
      expect(request.headers['authorization'], 'Bearer access');
      expect(jsonDecode(request.body)['title'], '整理旅行计划');
    },
  );

  test('repository exposes state actions and maps API errors', () async {
    var calls = 0;
    final repository = HttpTaskRepository(
      ApiClient(
        baseUrl: 'http://example.test',
        httpClient: MockClient((incoming) async {
          calls++;
          if (calls == 1) {
            return http.Response(
              jsonEncode(taskJson()),
              200,
              headers: {'content-type': 'application/json; charset=utf-8'},
            );
          }
          return http.Response(
            jsonEncode({
              'code': 'INVALID_TASK_TRANSITION',
              'message': '状态不允许',
              'details': {},
            }),
            409,
            headers: {'content-type': 'application/json'},
          );
        }),
        tokenStore: MemoryTokenStore(),
      ),
    );

    expect((await repository.start('task-1')).status, 'TODO');
    await expectLater(
      repository.complete('task-1'),
      throwsA(
        isA<TaskFailure>().having((error) => error.message, 'message', '状态不允许'),
      ),
    );
  });
}
