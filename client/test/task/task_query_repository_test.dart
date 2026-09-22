import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:muyu_client/core/api_client.dart';
import 'package:muyu_client/task/task_query_repository.dart';

void main() {
  test(
    'queries canonical tasks with encoded filters and keeps the cursor',
    () async {
      late Uri requested;
      final repository = TaskQueryRepository(
        ApiClient(
          baseUrl: 'https://api.example',
          httpClient: MockClient((request) async {
            requested = request.url;
            return http.Response(
              jsonEncode({
                'items': [
                  {
                    'id': 'task-1',
                    'parent_task_id': null,
                    'title': '婚礼 歌单',
                    'description': '',
                    'status': 'REVIEW',
                    'current_handler_id': 'user-1',
                    'quadrant': 'Q2',
                    'labels': ['婚礼'],
                    'planned_start_at': null,
                    'due_at': null,
                    'estimated_minutes': null,
                    'completed_at': null,
                    'created_by': 'user-1',
                    'version': 1,
                    'status_version': 1,
                    'created_at': '2026-09-01T00:00:00Z',
                    'updated_at': '2026-09-01T00:00:00Z',
                  },
                ],
                'has_more': true,
                'next_cursor': 'cursor.v1',
                'query': {'status': 'review'},
              }),
              200,
              headers: {'content-type': 'application/json; charset=utf-8'},
            );
          }),
        ),
      );

      final page = await repository.query(
        text: '婚礼 歌单',
        status: 'review',
        after: 'previous.cursor',
      );
      expect(requested.path, '/api/v1/tasks');
      expect(requested.queryParameters['q'], '婚礼 歌单');
      expect(requested.queryParameters['status'], 'review');
      expect(requested.queryParameters['after'], 'previous.cursor');
      expect(page.items.single.title, '婚礼 歌单');
      expect(page.hasMore, isTrue);
      expect(page.nextCursor, 'cursor.v1');
    },
  );
}
