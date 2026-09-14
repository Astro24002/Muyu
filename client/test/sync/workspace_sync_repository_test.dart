import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:muyu_client/core/api_client.dart';
import 'package:muyu_client/sync/workspace_sync_repository.dart';

void main() {
  test('HttpWorkspaceSyncRepository parses task activity events', () async {
    late http.Request request;
    final repository = HttpWorkspaceSyncRepository(
      ApiClient(
        baseUrl: 'https://api.example',
        httpClient: MockClient((incoming) async {
          request = incoming;
          return http.Response(
            jsonEncode([
              {
                'kind': 'activity',
                'id': 'activity-1',
                'event_type': 'TASK_REVIEW_SUBMITTED',
                'actor_user_id': 'user-1',
                'payload': {'review_content': '已完成验收清单'},
                'created_at': '2026-09-01T02:03:04Z',
              },
              {
                'kind': 'comment',
                'id': 'comment-1',
                'author_user_id': 'user-2',
                'body': '请补充截图',
                'created_at': '2026-09-01T03:00:00Z',
              },
            ]),
            200,
            headers: {'content-type': 'application/json; charset=utf-8'},
          );
        }),
      ),
    );

    final activities = await repository.activity('task-1');

    expect(request.method, 'GET');
    expect(request.url.path, '/api/v1/tasks/task-1/activity');
    expect(activities, hasLength(2));
    expect(activities.first.reviewContent, '已完成验收清单');
    expect(activities.last.body, '请补充截图');
  });
}
