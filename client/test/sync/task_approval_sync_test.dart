import 'package:flutter_test/flutter_test.dart';
import 'package:muyu_client/models/task.dart';
import 'package:muyu_client/models/task_approval_request.dart';
import 'package:muyu_client/models/workspace_change.dart';
import 'package:muyu_client/models/workspace_snapshot.dart';
import 'package:muyu_client/sync/workspace_sync_controller.dart';
import 'package:muyu_client/sync/workspace_sync_repository.dart';

TaskItem localTask({String title = 'Original'}) => TaskItem(
  id: 'task-1',
  parentTaskId: null,
  taskNumber: '26080001',
  title: title,
  description: '',
  status: 'TODO',
  currentHandlerId: 'user-a',
  quadrant: 'Q1',
  plannedStartAt: null,
  dueAt: null,
  estimatedMinutes: null,
  completedAt: null,
  createdBy: 'user-a',
  version: 1,
  statusVersion: 1,
  createdAt: DateTime.utc(2026, 8, 28),
  updatedAt: DateTime.utc(2026, 8, 28),
  labels: const [],
  progress: 0,
);

TaskApprovalRequest pendingRequest() => TaskApprovalRequest.fromJson({
  'id': 'approval-1',
  'workspace_id': 'workspace-1',
  'task_id': 'task-1',
  'comment_id': null,
  'requester_id': 'user-b',
  'approver_id': 'user-a',
  'request_type': 'TASK_UPDATE',
  'proposed_changes': {'title': 'Pending title'},
  'base_field_versions': {'title': 1},
  'request_id': 'request-1',
  'status': 'PENDING',
  'created_at': '2026-08-28T00:00:00Z',
  'reviewed_at': null,
  'reviewed_by': null,
  'rejection_reason': null,
  'resolved_cursor': null,
});

class ApprovalSyncFake implements WorkspaceSyncRepository {
  final request = pendingRequest();
  final task = localTask();
  final List<int> requestedCursors = [];
  ApprovalActionResult? approvalResult;

  @override
  Future<WorkspaceSnapshot> snapshot() async => WorkspaceSnapshot(
    workspaceId: 'workspace-1',
    cursor: 4,
    viewerUserId: 'user-a',
    tasks: [task],
    approvalRequests: const [],
  );

  @override
  Future<WorkspaceChanges> changes({required int afterCursor}) async {
    requestedCursors.add(afterCursor);
    return WorkspaceChanges(
      workspaceId: 'workspace-1',
      cursor: afterCursor,
      changes: const [],
    );
  }

  @override
  Future<TaskMutationResult?> update(
    String taskId, {
    required Map<String, Object?> fields,
    required Map<String, int> fieldVersions,
    required String requestId,
  }) async => PendingApproval(approvalRequest: request);

  @override
  Future<TaskMutationResult> transition(
    String taskId, {
    required String targetStatus,
    required int baseStatusVersion,
    String? blockedReason,
    String? resumeHandlerId,
    String? waitingForUserId,
    String? reviewRejectionReason,
    String? reviewContent,
    required String requestId,
  }) async => PendingApproval(approvalRequest: request);

  @override
  Future<ApprovalActionResult> approveApproval(
    String approvalId, {
    String? workspaceId,
    required String requestId,
  }) async =>
      approvalResult ??
      ApprovalActionResult(
        approvalRequest: TaskApprovalRequest.fromJson({
          ...pendingRequest().toJson(),
          'status': 'APPROVED',
          'resolved_cursor': 5,
        }),
        task: localTask(title: 'Pending title'),
        cursor: 5,
      );

  @override
  Future<ApprovalActionResult> rejectApproval(
    String approvalId, {
    String? workspaceId,
    required String requestId,
    String? reason,
  }) async =>
      approvalResult ??
      ApprovalActionResult(
        approvalRequest: TaskApprovalRequest.fromJson({
          ...pendingRequest().toJson(),
          'status': 'REJECTED',
          'resolved_cursor': 5,
        }),
        cursor: 5,
      );

  @override
  Future<ApprovalActionResult> cancelApproval(
    String approvalId, {
    String? workspaceId,
    required String requestId,
  }) async =>
      approvalResult ??
      ApprovalActionResult(
        approvalRequest: TaskApprovalRequest.fromJson({
          ...pendingRequest().toJson(),
          'status': 'CANCELLED',
          'resolved_cursor': 5,
        }),
        cursor: 5,
      );

  @override
  Stream<WorkspaceChanged> openWorkspaceHints() => const Stream.empty();

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  test(
    '202 task update stores pending approval without changing task',
    () async {
      final repository = ApprovalSyncFake();
      final controller = WorkspaceSyncController(repository);
      await controller.refresh();

      final result = await controller.update(
        'task-1',
        fields: {'title': 'Pending title'},
      );

      expect(result, isA<PendingApproval>());
      expect(controller.state.snapshot!.tasks.single.title, 'Original');
      expect(controller.state.approvalRequests.single.id, 'approval-1');
    },
  );

  test('approval action merges approved task and request state', () async {
    final repository = ApprovalSyncFake();
    final controller = WorkspaceSyncController(repository);
    await controller.refresh();
    await controller.update('task-1', fields: {'title': 'Pending title'});

    final result = await controller.approveApproval('approval-1');

    expect(result.approvalRequest.status, 'APPROVED');
    expect(controller.state.snapshot!.tasks.single.title, 'Pending title');
    expect(controller.state.approvalRequests.single.status, 'APPROVED');
    expect(controller.state.cursor, 5);
  });

  test('all approval actions reject comments not bound to the request before cursor reconciliation', () async {
    final malformedComments = <Map<String, String?>>[
      {'workspaceId': null, 'commentId': 'comment-1'},
      {'workspaceId': 'workspace-foreign', 'commentId': 'comment-1'},
      {'workspaceId': 'workspace-1', 'commentId': 'comment-1'},
      {'workspaceId': 'workspace-1', 'commentId': 'comment-other'},
    ];
    for (final action in ['approve', 'reject', 'cancel']) {
      for (final malformed in malformedComments) {
        final approvalCommentId = malformed['commentId'] == 'comment-other'
            ? 'comment-expected'
            : null;
        final repository = ApprovalSyncFake()
          ..approvalResult = ApprovalActionResult(
            approvalRequest: TaskApprovalRequest.fromJson({
              ...pendingRequest().toJson(),
              'comment_id': approvalCommentId,
              'status': action == 'approve'
                  ? 'APPROVED'
                  : action == 'reject'
                  ? 'REJECTED'
                  : 'CANCELLED',
              'resolved_cursor': 9,
            }),
            comment: TaskComment(
              id: malformed['commentId']!,
              workspaceId: malformed['workspaceId'],
              taskId: 'task-1',
              authorUserId: 'user-b',
              body: 'deleted',
              version: 2,
            ),
            cursor: 9,
          );
        final controller = WorkspaceSyncController(repository);
        await controller.refresh();

        Future<ApprovalActionResult> invoke() => switch (action) {
          'approve' => controller.approveApproval('approval-1'),
          'reject' => controller.rejectApproval('approval-1'),
          _ => controller.cancelApproval('approval-1'),
        };
        await expectLater(invoke(), throwsA(isA<FormatException>()));

        expect(repository.requestedCursors, isEmpty);
        expect(controller.state.cursor, 4);
        expect(controller.state.approvalRequests, isEmpty);
      }
    }
  });

  test('approval and comment changes parse as typed resources', () {
    final approval = pendingRequest();
    final approvalChange = WorkspaceChange.fromJson({
      'cursor': 2,
      'resource_type': 'approval_request',
      'resource_id': approval.id,
      'action': 'updated',
      'resource': approval.toJson(),
    });
    final commentChange = WorkspaceChange.fromJson({
      'cursor': 3,
      'resource_type': 'comment',
      'resource_id': 'comment-1',
      'action': 'updated',
      'resource': {
        'id': 'comment-1',
        'workspace_id': 'workspace-1',
        'task_id': 'task-1',
        'author_user_id': 'user-b',
        'body': 'Deleted',
        'version': 2,
        'deleted_at': '2026-08-28T00:00:00Z',
        'deleted_by': 'user-a',
        'created_at': '2026-08-27T00:00:00Z',
      },
    });

    expect(approvalChange.approvalRequest!.id, approval.id);
    expect(commentChange.comment!.deletedBy, 'user-a');
  });

  test('comment changes must carry the requested workspace identity', () {
    final missingWorkspace = {
      'workspace_id': 'workspace-1',
      'cursor': 3,
      'changes': [
        {
          'cursor': 3,
          'resource_type': 'comment',
          'resource_id': 'comment-1',
          'action': 'updated',
          'resource': {
            'id': 'comment-1',
            'task_id': 'task-1',
            'author_user_id': 'user-b',
            'body': 'Foreign',
            'version': 1,
            'deleted_at': null,
            'deleted_by': null,
            'created_at': '2026-08-27T00:00:00Z',
          },
        },
      ],
    };
    expect(
      () => WorkspaceChanges.fromJson(missingWorkspace),
      throwsA(isA<FormatException>()),
    );

    final foreignWorkspace = WorkspaceChanges.fromJson({
      'workspace_id': 'workspace-1',
      'cursor': 3,
      'changes': [
        {
          'cursor': 3,
          'resource_type': 'comment',
          'resource_id': 'comment-1',
          'action': 'updated',
          'resource': {
            'id': 'comment-1',
            'workspace_id': 'workspace-foreign',
            'task_id': 'task-1',
            'author_user_id': 'user-b',
            'body': 'Foreign',
            'version': 1,
            'deleted_at': null,
            'deleted_by': null,
            'created_at': '2026-08-27T00:00:00Z',
          },
        },
      ],
    });
    expect(
      foreignWorkspace.isValidFor(workspaceId: 'workspace-1', afterCursor: 2),
      isFalse,
    );
  });
}
