import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:muyu_client/models/task.dart';
import 'package:muyu_client/models/task_approval_request.dart';
import 'package:muyu_client/models/workspace_change.dart';
import 'package:muyu_client/models/workspace_snapshot.dart';
import 'package:muyu_client/screens/task_approval_screen.dart';
import 'package:muyu_client/sync/workspace_sync_controller.dart';
import 'package:muyu_client/sync/workspace_sync_repository.dart';

TaskItem task() => TaskItem(
  id: 'task-1',
  parentTaskId: null,
  taskNumber: '26080001',
  title: 'Prepare trip',
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
);

TaskApprovalRequest approval(
  String id,
  String requester,
  String approver, {
  String requestType = 'TASK_UPDATE',
}) => TaskApprovalRequest.fromJson({
  'id': id,
  'workspace_id': 'workspace-1',
  'task_id': 'task-1',
  'comment_id': null,
  'requester_id': requester,
  'approver_id': approver,
  'request_type': requestType,
  'proposed_changes': {'title': 'New title'},
  'base_field_versions': {'title': 1},
  'request_id': 'request-$id',
  'status': 'PENDING',
  'created_at': '2026-08-28T00:00:00Z',
  'reviewed_at': null,
  'reviewed_by': null,
  'rejection_reason': null,
  'resolved_cursor': null,
});

class ApprovalScreenRepository implements WorkspaceSyncRepository {
  ApprovalScreenRepository(this.approvals);

  final List<TaskApprovalRequest> approvals;
  String? approved;
  String? rejected;
  String? cancelled;

  @override
  Future<WorkspaceSnapshot> snapshot() async => WorkspaceSnapshot(
    workspaceId: 'workspace-1',
    cursor: 1,
    viewerUserId: 'user-a',
    tasks: [task()],
    approvalRequests: approvals,
  );

  @override
  Future<WorkspaceChanges> changes({required int afterCursor}) async =>
      WorkspaceChanges(
        workspaceId: 'workspace-1',
        cursor: afterCursor,
        changes: const [],
      );

  @override
  Future<TaskItem> create({
    required String title,
    required String quadrant,
    List<String> labels = const [],
    String? description,
    String? dueAt,
    String? parentTaskId,
    String? plannedStartAt,
    int? estimatedMinutes,
    required String requestId,
  }) => throw UnimplementedError();

  @override
  Future<TaskMutationResult?> update(
    String taskId, {
    required Map<String, Object?> fields,
    required Map<String, int> fieldVersions,
    required String requestId,
  }) => throw UnimplementedError();

  @override
  Future<TaskMutationResult> transition(
    String taskId, {
    required String targetStatus,
    required int baseStatusVersion,
    String? blockedReason,
    String? resumeHandlerId,
    String? waitingForUserId,
    required String requestId,
  }) => throw UnimplementedError();

  @override
  Future<Object?> addComment(
    String taskId, {
    required String body,
    required String requestId,
  }) => throw UnimplementedError();

  @override
  Future<Object?> addDelay(
    String taskId, {
    required String newDueAt,
    required String reason,
    String? note,
    required String requestId,
  }) => throw UnimplementedError();

  @override
  Future<TaskItem> resolveConflict(
    String taskId,
    String conflictId, {
    required String resolution,
    required String requestId,
  }) => throw UnimplementedError();

  @override
  Future<List<TaskApprovalRequest>> listApprovalRequests({
    String? workspaceId,
    String? box,
  }) async => approvals;

  @override
  Future<TaskApprovalRequest> createApprovalRequest({
    String? workspaceId,
    required String taskId,
    String? commentId,
    required String requestType,
    required Map<String, Object?> proposedChanges,
    required Map<String, int> baseFieldVersions,
    required String requestId,
  }) => throw UnimplementedError();

  @override
  Future<ApprovalActionResult> approveApproval(
    String approvalId, {
    String? workspaceId,
    required String requestId,
  }) async {
    approved = approvalId;
    return ApprovalActionResult(
      approvalRequest: approvals.firstWhere((item) => item.id == approvalId),
    );
  }

  @override
  Future<ApprovalActionResult> rejectApproval(
    String approvalId, {
    String? workspaceId,
    required String requestId,
    String? reason,
  }) async {
    rejected = approvalId;
    return ApprovalActionResult(
      approvalRequest: approvals.firstWhere((item) => item.id == approvalId),
    );
  }

  @override
  Future<ApprovalActionResult> cancelApproval(
    String approvalId, {
    String? workspaceId,
    required String requestId,
  }) async {
    cancelled = approvalId;
    return ApprovalActionResult(
      approvalRequest: approvals.firstWhere((item) => item.id == approvalId),
    );
  }

  @override
  Future<TaskMutationResult?> deleteComment(
    String taskId,
    String commentId, {
    required int baseVersion,
    String? requestId,
  }) => throw UnimplementedError();

  @override
  Stream<WorkspaceChanged> openWorkspaceHints() => const Stream.empty();

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  testWidgets('incoming and outgoing requests expose the right actions', (
    tester,
  ) async {
    final repository = ApprovalScreenRepository([
      approval('incoming', 'user-b', 'user-a'),
      approval('outgoing', 'user-a', 'user-b'),
    ]);
    final sync = WorkspaceSyncController(repository);
    await sync.refresh();
    await tester.pumpWidget(
      MaterialApp(
        home: TaskApprovalScreen(sync: sync, currentUserId: 'user-a'),
      ),
    );

    expect(find.text('待我审批'), findsOneWidget);
    expect(find.byKey(const Key('approval-approve-incoming')), findsOneWidget);
    await tester.tap(find.byKey(const Key('approval-approve-incoming')));
    await tester.pump();
    expect(repository.approved, 'incoming');

    await tester.tap(find.text('我发起的请求'));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('approval-cancel-outgoing')), findsOneWidget);
    await tester.tap(find.byKey(const Key('approval-cancel-outgoing')));
    await tester.pump();
    expect(repository.cancelled, 'outgoing');
  });

  testWidgets('unverified device can inspect but cannot act', (tester) async {
    final repository = ApprovalScreenRepository([
      approval('incoming', 'user-b', 'user-a'),
    ]);
    final sync = WorkspaceSyncController(repository);
    await sync.refresh();
    await tester.pumpWidget(
      MaterialApp(
        home: TaskApprovalScreen(
          sync: sync,
          currentUserId: 'user-a',
          canWrite: false,
        ),
      ),
    );
    expect(find.byKey(const Key('approval-read-only-banner')), findsOneWidget);
    expect(find.byKey(const Key('approval-approve-incoming')), findsNothing);
  });

  testWidgets('retired participant approval types are not given a label', (
    tester,
  ) async {
    final repository = ApprovalScreenRepository([
      approval('legacy', 'user-b', 'user-a', requestType: 'ASSIGNEE_UPDATE'),
    ]);
    final sync = WorkspaceSyncController(repository);
    await sync.refresh();
    await tester.pumpWidget(
      MaterialApp(
        home: TaskApprovalScreen(sync: sync, currentUserId: 'user-a'),
      ),
    );

    expect(find.text('ASSIGNEE_UPDATE · PENDING'), findsOneWidget);
    expect(find.textContaining('协作者'), findsNothing);
  });
}
