import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:muyu_client/core/api_client.dart';
import 'package:muyu_client/task/home_entry_repository.dart';

void main() {
  test(
    'keeps approval identity and request without task in canonical action page',
    () async {
      final repository = HomeEntryRepository(
        ApiClient(
          baseUrl: 'https://api.example',
          httpClient: MockClient(
            (_) async => http.Response(
              jsonEncode({
                'count': 1,
                'items': [
                  {
                    'approval_request': {
                      'id': 'approval-1',
                      'workspace_id': 'workspace-1',
                      'task_id': null,
                      'requester_id': 'user-2',
                      'approver_id': 'user-1',
                      'request_type': 'CLASSIFICATION_CREATE',
                      'proposed_changes': {'name': '婚礼'},
                      'base_field_versions': {},
                      'request_id': 'request-1',
                      'status': 'PENDING',
                      'created_at': '2026-09-20T00:00:00Z',
                    },
                    'task': null,
                  },
                ],
                'has_more': false,
                'next_cursor': null,
              }),
              200,
              headers: {'content-type': 'application/json'},
            ),
          ),
        ),
      );
      final page = await repository.load(entry: 'needs_me');
      expect(page.approvals.single.approvalRequest.id, 'approval-1');
      expect(page.approvals.single.task, isNull);
      expect(page.tasks, isEmpty);
    },
  );

  test('loads a canonical home entry page with its opaque cursor', () async {
    late Uri requested;
    final repository = HomeEntryRepository(
      ApiClient(
        baseUrl: 'https://api.example',
        httpClient: MockClient((request) async {
          requested = request.url;
          return http.Response(
            jsonEncode({
              'count': 2,
              'items': [
                {
                  'id': 'task-1',
                  'parent_task_id': null,
                  'title': '即将到期事项',
                  'description': '',
                  'status': 'TODO',
                  'current_handler_id': 'user-1',
                  'quadrant': 'Q2',
                  'labels': [],
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
              'next_cursor': 'home-entry.v1',
            }),
            200,
            headers: {'content-type': 'application/json; charset=utf-8'},
          );
        }),
      ),
    );

    final page = await repository.load(
      entry: 'due_soon',
      afterCursor: 'previous.cursor',
    );
    expect(requested.path, '/api/v1/home/entries/due_soon');
    expect(requested.queryParameters['after_cursor'], 'previous.cursor');
    expect(page.tasks.single.title, '即将到期事项');
    expect(page.count, 2);
    expect(page.nextCursor, 'home-entry.v1');
  });
}
