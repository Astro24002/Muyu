import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:muyu_client/core/api_client.dart';
import 'package:muyu_client/task/cloud_task_repository.dart';

void main() {
  final taskJson = <String, dynamic>{
    'id': 'task-1',
    'parent_task_id': null,
    'title': 'New title',
    'description': '',
    'status': 'TODO',
    'current_handler_id': 'user-1',
    'planned_start_at': null,
    'due_at': null,
    'estimated_minutes': null,
    'completed_at': null,
    'created_by': 'user-1',
    'version': 1,
    'status_version': 1,
    'lifecycle_version': 1,
    'created_at': '2026-08-24T00:00:00Z',
    'updated_at': '2026-08-24T00:00:00Z',
    'assignee_ids': ['user-1'],
    'field_versions': {'title': 1},
  };

  test(
    'mutation sends request id and field versions to authoritative API',
    () async {
      late http.Request request;
      final repository = CloudTaskRepository(
        ApiClient(
          baseUrl: 'https://api.example',
          httpClient: MockClient((incoming) async {
            request = incoming;
            return http.Response(jsonEncode({'id': 'task-1'}), 200);
          }),
        ),
      );

      await repository.update(
        'task-1',
        fields: {'title': 'New title'},
        fieldVersions: {'title': 4},
        requestId: 'request-1',
      );

      final body = jsonDecode(request.body) as Map<String, dynamic>;
      expect(request.url.path, '/api/v1/tasks/task-1');
      expect(request.headers['x-request-id'], 'request-1');
      expect(body['base_field_versions'], {'title': 4});
      expect(body['changes'], {'title': 'New title'});
    },
  );

  test(
    'create sends snake_case fields and generates a UUID request id',
    () async {
      late http.Request request;
      final repository = CloudTaskRepository(
        ApiClient(
          baseUrl: 'https://api.example',
          httpClient: MockClient((incoming) async {
            request = incoming;
            return http.Response(jsonEncode(taskJson), 201);
          }),
        ),
      );

      final result = await repository.create(
        title: ' New title ',
        description: 'details',
        dueAt: '2026-08-25T00:00:00Z',
        plannedStartAt: '2026-08-24T00:00:00Z',
        estimatedMinutes: 30,
      );

      final body = jsonDecode(request.body) as Map<String, dynamic>;
      expect(request.url.path, '/api/v1/tasks');
      expect(request.headers['x-request-id'], isNotEmpty);
      expect(
        request.headers['x-request-id'],
        matches(RegExp(r'^[0-9a-f-]{36}$')),
      );
      expect(body['request_id'], request.headers['x-request-id']);
      expect(body['title'], ' New title ');
      expect(body['planned_start_at'], '2026-08-24T00:00:00Z');
      expect(body['estimated_minutes'], 30);
      expect(result.title, 'New title');
    },
  );

  test('409 preserves conflict details as CloudTaskFailure', () async {
    final repository = CloudTaskRepository(
      ApiClient(
        baseUrl: 'https://api.example',
        httpClient: MockClient(
          (_) async => http.Response(
            jsonEncode({
              'code': 'field_conflict',
              'message': 'stale task',
              'details': {
                'conflicts': [
                  {'field': 'title'},
                ],
              },
            }),
            409,
          ),
        ),
      ),
    );

    expect(
      () => repository.update(
        'task-1',
        fields: {'title': 'changed'},
        fieldVersions: {'title': 1},
        requestId: 'request-1',
      ),
      throwsA(
        isA<CloudTaskFailure>()
            .having((error) => error.statusCode, 'status', 409)
            .having((error) => error.code, 'code', 'field_conflict')
            .having((error) => error.details, 'details', isNotNull),
      ),
    );
  });
}
