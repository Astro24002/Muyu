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
  'blocked_reason': null,
  'blocked_since': null,
  'resume_handler_id': null,
  'waiting_for_user_id': null,
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
  'delay_count': 0,
  'total_delay_minutes': 0,
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

  test('repository exposes delay history and blocking actions', () async {
    final requests = <http.Request>[];
    var calls = 0;
    final repository = HttpTaskRepository(
      ApiClient(
        baseUrl: 'http://example.test',
        httpClient: MockClient((incoming) async {
          requests.add(incoming);
          calls++;
          final body = switch (calls) {
            1 => {
              ...taskJson(),
              'due_at': '2026-09-04T01:00:00Z',
              'delay_count': 1,
              'total_delay_minutes': 1440,
            },
            2 => [
              {
                'id': 'delay-1',
                'task_id': 'task-1',
                'user_id': 'user-a',
                'original_due_at': '2026-09-03T01:00:00Z',
                'new_due_at': '2026-09-04T01:00:00Z',
                'delayed_at': '2026-09-01T02:00:00Z',
                'delay_duration_minutes': 1440,
                'reason': 'NO_TIME',
                'note': null,
                'created_at': '2026-09-01T02:00:00Z',
              },
            ],
            3 => {
              ...taskJson(),
              'status': 'WAITING',
              'blocked_reason': '等待确认',
              'blocked_since': '2026-09-01T02:00:00Z',
              'resume_handler_id': 'user-b',
              'waiting_for_user_id': 'user-b',
            },
            _ => {...taskJson(), 'status': 'IN_PROGRESS'},
          };
          return http.Response(
            jsonEncode(body),
            200,
            headers: {'content-type': 'application/json; charset=utf-8'},
          );
        }),
        tokenStore: MemoryTokenStore(),
      ),
    );

    final delayed = await repository.delay(
      'task-1',
      newDueAt: DateTime.parse('2026-09-04T09:00:00+08:00'),
      reason: 'NO_TIME',
      note: '当天没有时间',
    );
    final records = await repository.delays('task-1');
    final blocked = await repository.block(
      'task-1',
      blockedReason: '等待确认',
      resumeHandlerId: 'user-b',
      waitingForUserId: 'user-b',
    );
    final resumed = await repository.unblock('task-1');

    expect(delayed.delayCount, 1);
    expect(records.single.reason, 'NO_TIME');
    expect(blocked.status, 'WAITING');
    expect(resumed.status, 'IN_PROGRESS');
    expect(requests.map((request) => request.url.path), [
      '/api/tasks/task-1/delay',
      '/api/tasks/task-1/delays',
      '/api/tasks/task-1/block',
      '/api/tasks/task-1/unblock',
    ]);
    expect(jsonDecode(requests[0].body), {
      'new_due_at': '2026-09-04T01:00:00.000Z',
      'reason': 'NO_TIME',
      'note': '当天没有时间',
    });
    expect(jsonDecode(requests[2].body), {
      'blocked_reason': '等待确认',
      'resume_handler_id': 'user-b',
      'waiting_for_user_id': 'user-b',
    });
  });
}
