import 'package:flutter_test/flutter_test.dart';
import 'package:muyu_client/models/task.dart';
import 'package:muyu_client/models/task_approval_request.dart';
import 'package:muyu_client/models/workspace_snapshot.dart';

Map<String, dynamic> taskJson() => {
  'id': 'task-1',
  'parent_task_id': null,
  'task_number': '26080001',
  'title': 'Prepare trip',
  'description': 'Book the train',
  'status': 'IN_PROGRESS',
  'quadrant': 'Q1',
  'progress': 40,
  'current_handler_id': 'user-a',
  'blocked_reason': null,
  'blocked_since': null,
  'resume_handler_id': null,
  'waiting_for_user_id': null,
  'planned_start_at': null,
  'due_at': null,
  'estimated_minutes': 30,
  'completed_at': null,
  'created_by': 'user-a',
  'version': 2,
  'status_version': 1,
  'created_at': '2026-08-28T00:00:00Z',
  'updated_at': '2026-08-28T00:00:00Z',
  'delay_count': 0,
  'total_delay_minutes': 0,
  'field_versions': {'title': 2, 'progress': 1},
  'lifecycle_version': 1,
  'deleted_at': null,
};

Map<String, dynamic> approvalJson() => {
  'id': 'approval-1',
  'workspace_id': 'workspace-1',
  'task_id': 'task-1',
  'comment_id': null,
  'requester_id': 'user-b',
  'approver_id': 'user-a',
  'request_type': 'TASK_UPDATE',
  'proposed_changes': {'title': 'New title'},
  'base_field_versions': {'title': 2},
  'request_id': 'request-1',
  'status': 'PENDING',
  'created_at': '2026-08-28T01:00:00Z',
  'reviewed_at': null,
  'reviewed_by': null,
  'rejection_reason': null,
  'resolved_cursor': null,
};

void main() {
  test('TaskItem parses task number, quadrant and public progress', () {
    final task = TaskItem.fromJson(taskJson());

    expect(task.taskNumber, '26080001');
    expect(task.quadrant, 'Q1');
    expect(task.progress, 40);
  });

  test('TaskItem derives terminal progress when the wire field is absent', () {
    final todo = TaskItem.fromJson(
      {...taskJson(), 'status': 'TODO'}..remove('progress'),
    );
    final done = TaskItem.fromJson(
      {...taskJson(), 'status': 'DONE'}..remove('progress'),
    );

    expect(todo.progress, 0);
    expect(done.progress, 100);
  });

  test('TaskApprovalRequest parses its wire contract and filters by actor', () {
    final request = TaskApprovalRequest.fromJson(approvalJson());

    expect(request.id, 'approval-1');
    expect(request.requestType, 'TASK_UPDATE');
    expect(request.proposedChanges, {'title': 'New title'});
    expect(request.baseFieldVersions, {'title': 2});
    expect(request.isIncoming('user-a'), isTrue);
    expect(request.isIncoming('user-b'), isFalse);
    expect(request.isOutgoing('user-b'), isTrue);
    expect(request.isOutgoing('user-a'), isFalse);
  });

  test(
    'snapshot cache JSON round-trips viewer, approvals and comment tombstones',
    () {
      final snapshot = WorkspaceSnapshot(
        workspaceId: 'workspace-1',
        cursor: 9,
        viewerUserId: 'user-a',
        tasks: [TaskItem.fromJson(taskJson())],
        approvalRequests: [TaskApprovalRequest.fromJson(approvalJson())],
        comments: [
          TaskComment(
            id: 'comment-1',
            workspaceId: 'workspace-1',
            taskId: 'task-1',
            authorUserId: 'user-b',
            body: 'Removed comment',
            version: 2,
            deletedAt: DateTime.utc(2026, 8, 28, 2),
            deletedBy: 'user-a',
            createdAt: DateTime.utc(2026, 8, 28, 1),
          ),
        ],
      );

      final restored = WorkspaceSnapshot.fromJson(
        Map<String, dynamic>.from(snapshot.toJson()),
      );

      expect(restored.viewerUserId, 'user-a');
      expect(restored.approvalRequests.single.id, 'approval-1');
      expect(restored.tasks.single.taskNumber, '26080001');
      expect(restored.comments.single.deletedBy, 'user-a');
      expect(restored.comments.single.deletedAt, DateTime.utc(2026, 8, 28, 2));
    },
  );
}
