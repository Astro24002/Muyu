import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:muyu_client/core/api_client.dart';
import 'package:muyu_client/models/task_approval_request.dart';
import 'package:muyu_client/task/cloud_task_repository.dart';

void main() {
  final taskJson = <String, dynamic>{
    'id': 'task-1',
    'parent_task_id': null,
    'title': 'New title',
    'description': '',
    'status': 'TODO',
    'current_handler_id': 'user-1',
    'quadrant': 'Q2',
    'labels': ['工作'],
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
      expect(body, isNot(contains('assignee_ids')));
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
            return http.Response(
              jsonEncode(taskJson),
              201,
              headers: {'content-type': 'application/json; charset=utf-8'},
            );
          }),
        ),
      );

      final result = await repository.create(
        title: ' New title ',
        quadrant: 'Q2',
        labels: const ['工作', '重要'],
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
      expect(body['quadrant'], 'Q2');
      expect(body['labels'], ['工作', '重要']);
      expect(body['planned_start_at'], '2026-08-24T00:00:00Z');
      expect(body['estimated_minutes'], 30);
      expect(body, isNot(contains('assignee_ids')));
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

  test('202 task update returns a pending approval without a task', () async {
    late http.Request request;
    final repository = CloudTaskRepository(
      ApiClient(
        baseUrl: 'https://api.example',
        httpClient: MockClient((incoming) async {
          request = incoming;
          return http.Response(
            jsonEncode({
              'pending': true,
              'cursor': 7,
              'approval_request': {
                'id': 'approval-1',
                'workspace_id': 'workspace-1',
                'task_id': 'task-1',
                'comment_id': null,
                'requester_id': 'user-b',
                'approver_id': 'user-a',
                'request_type': 'TASK_UPDATE',
                'proposed_changes': {'title': 'Pending'},
                'base_field_versions': {'title': 1},
                'request_id': 'request-1',
                'status': 'PENDING',
                'created_at': '2026-08-28T00:00:00Z',
                'reviewed_at': null,
                'reviewed_by': null,
                'rejection_reason': null,
                'resolved_cursor': null,
              },
            }),
            202,
          );
        }),
      ),
    );

    final result = await repository.update(
      'task-1',
      fields: {'title': 'Pending'},
      fieldVersions: {'title': 1},
      requestId: 'request-1',
    );

    expect(result, isA<PendingApproval>());
    expect((result! as PendingApproval).approvalRequest.id, 'approval-1');
    expect(request.headers['x-request-id'], 'request-1');
  });

  test(
    'approval methods use workspace paths and exact snake_case bodies',
    () async {
      final requests = <http.Request>[];
      final repository = CloudTaskRepository(
        ApiClient(
          baseUrl: 'https://api.example',
          httpClient: MockClient((incoming) async {
            requests.add(incoming);
            final approval = {
              'id': 'approval-1',
              'workspace_id': 'workspace-1',
              'task_id': 'task-1',
              'comment_id': null,
              'requester_id': 'user-b',
              'approver_id': 'user-a',
              'request_type': 'TASK_UPDATE',
              'proposed_changes': {'title': 'New'},
              'base_field_versions': {'title': 1},
              'request_id': 'request-1',
              'status': 'APPROVED',
              'created_at': '2026-08-28T00:00:00Z',
              'reviewed_at': null,
              'reviewed_by': 'user-a',
              'rejection_reason': null,
              'resolved_cursor': 8,
            };
            if (incoming.url.path.endsWith('/approve')) {
              return http.Response(
                jsonEncode({'approval_request': approval}),
                200,
              );
            }
            return http.Response(jsonEncode(approval), 201);
          }),
        ),
      );

      final created = await repository.createApprovalRequest(
        workspaceId: 'workspace-1',
        taskId: 'task-1',
        requestType: 'TASK_UPDATE',
        proposedChanges: {'title': 'New'},
        baseFieldVersions: {'title': 1},
        requestId: 'request-1',
      );
      final approved = await repository.approveApproval(
        'approval-1',
        workspaceId: 'workspace-1',
        requestId: 'action-1',
      );

      final createBody = jsonDecode(requests[0].body) as Map<String, dynamic>;
      expect(
        requests[0].url.path,
        '/api/v1/workspaces/workspace-1/approval-requests',
      );
      expect(createBody, {
        'request_id': 'request-1',
        'task_id': 'task-1',
        'request_type': 'TASK_UPDATE',
        'proposed_changes': {'title': 'New'},
        'base_field_versions': {'title': 1},
      });
      expect(created.id, 'approval-1');
      expect(
        requests[1].url.path,
        '/api/v1/workspaces/workspace-1/approval-requests/approval-1/approve',
      );
      expect(jsonDecode(requests[1].body), {'request_id': 'action-1'});
      expect(requests[1].headers['x-request-id'], 'action-1');
      expect(approved.approvalRequest.status, 'APPROVED');
    },
  );
}
