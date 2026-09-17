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
  fieldVersions: const {'title': 1},
);

TaskApprovalRequest approval(
  String id,
  String requester,
  String approver, {
  String? taskId = 'task-1',
  String requestType = 'TASK_UPDATE',
  Map<String, dynamic>? proposedChanges,
}) => TaskApprovalRequest.fromJson({
  'id': id,
  'workspace_id': 'workspace-1',
  'task_id': taskId,
  'comment_id': null,
  'requester_id': requester,
  'approver_id': approver,
  'request_type': requestType,
  'proposed_changes': proposedChanges ?? {'title': 'New title'},
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
  ApprovalScreenRepository(this.approvals, {this.members = const []});

  final List<TaskApprovalRequest> approvals;
  final List<Map<String, dynamic>> members;
  String? approved;
  String? rejected;
  String? cancelled;

  @override
  Future<WorkspaceSnapshot> snapshot() async => WorkspaceSnapshot(
    workspaceId: 'workspace-1',
    cursor: 1,
    viewerUserId: 'user-a',
    members: members,
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
    String? nextStepText,
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
    String? reviewRejectionReason,
    String? reviewContent,
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
      approvalRequest: approvals
          .firstWhere((item) => item.id == approvalId)
          .copyWith(status: 'APPROVED'),
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
      approvalRequest: approvals
          .firstWhere((item) => item.id == approvalId)
          .copyWith(status: 'REJECTED'),
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
      approvalRequest: approvals
          .firstWhere((item) => item.id == approvalId)
          .copyWith(status: 'CANCELLED'),
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
    expect(find.byKey(const Key('approval-card-incoming')), findsNothing);
    expect(find.byKey(const Key('approval-approve-incoming')), findsNothing);
    await tester.tap(find.text('审批记录'));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('approval-card-incoming')), findsOneWidget);

    await tester.tap(find.text('我发起的请求'));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('approval-cancel-outgoing')), findsOneWidget);
    await tester.tap(find.byKey(const Key('approval-cancel-outgoing')));
    await tester.pump();
    expect(find.text('撤回审批请求？'), findsOneWidget);
    expect(repository.cancelled, isNull);
    await tester.tap(find.text('确认撤回'));
    await tester.pumpAndSettle();
    expect(repository.cancelled, 'outgoing');
    expect(find.byKey(const Key('approval-card-outgoing')), findsNothing);
    expect(find.byKey(const Key('approval-cancel-outgoing')), findsNothing);
    await tester.tap(find.text('审批记录'));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('approval-card-outgoing')), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('resolved requests remain history without pending actions', (
    tester,
  ) async {
    final repository = ApprovalScreenRepository([
      approval('resolved', 'user-b', 'user-a').copyWith(
        status: 'CANCELLED',
        rejectionReason: 'cancelled by requester',
      ),
    ]);
    final sync = WorkspaceSyncController(repository);
    await sync.refresh();
    await tester.pumpWidget(
      MaterialApp(
        home: TaskApprovalScreen(sync: sync, currentUserId: 'user-a'),
      ),
    );

    expect(find.byKey(const Key('approval-card-resolved')), findsNothing);
    expect(find.byKey(const Key('approval-approve-resolved')), findsNothing);
    expect(find.text('审批记录'), findsOneWidget);
    await tester.tap(find.text('审批记录'));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('approval-approve-resolved')), findsNothing);
    expect(find.byKey(const Key('approval-cancel-resolved')), findsNothing);
    expect(find.text('对方 · 发起'), findsOneWidget);
    expect(find.text('已撤回'), findsOneWidget);
    expect(find.text('任务修改'), findsOneWidget);
    expect(find.text('任务标题：原内容未记录 → New title'), findsOneWidget);
    expect(find.text('说明'), findsOneWidget);
    expect(find.text('请求方已撤回请求'), findsOneWidget);
  });

  testWidgets('request details use readable two-person and change semantics', (
    tester,
  ) async {
    final repository = ApprovalScreenRepository(
      [
        approval(
          'incoming',
          'user-b',
          'user-a',
          proposedChanges: {
            'title': 'Finish release checklist',
            'due_at': '2026-09-11T10:00:00Z',
            'quadrant': 'Q1',
            'labels': ['工作'],
            'current_handler_id': 'user-b',
          },
        ),
        approval(
          'outgoing',
          'user-a',
          'user-b',
          proposedChanges: {'target_status': 'REVIEW'},
        ),
      ],
      members: const [
        {'user_id': 'user-a', 'display_name': '我'},
        {'user_id': 'user-b', 'display_name': '溪岸'},
      ],
    );
    final sync = WorkspaceSyncController(repository);
    await sync.refresh();
    await tester.pumpWidget(
      MaterialApp(
        home: TaskApprovalScreen(sync: sync, currentUserId: 'user-a'),
      ),
    );

    expect(find.text('26080001 · Prepare trip'), findsNothing);
    expect(find.text('审批事项'), findsOneWidget);
    expect(find.text('溪岸 · 发起'), findsOneWidget);
    expect(find.text('2026年08月28日 00:00'), findsOneWidget);
    expect(find.text('任务修改'), findsOneWidget);
    expect(find.text('变更内容'), findsOneWidget);
    expect(
      find.text('任务标题：Prepare trip → Finish release checklist'),
      findsOneWidget,
    );
    expect(find.text('截止时间：原内容未记录 → 2026年09月11日 10:00'), findsOneWidget);
    expect(find.byKey(const Key('approval-change-value')), findsOneWidget);
    expect(find.byKey(const Key('approval-change-row-title')), findsOneWidget);
    expect(find.byKey(const Key('approval-change-row-due_at')), findsOneWidget);
    expect(
      find.byKey(const Key('approval-change-row-quadrant')),
      findsOneWidget,
    );
    expect(find.byKey(const Key('approval-change-row-labels')), findsOneWidget);
    expect(
      find.byKey(const Key('approval-change-row-current_handler_id')),
      findsOneWidget,
    );
    expect(find.text('user-a'), findsNothing);
    expect(find.text('user-b'), findsNothing);

    await tester.tap(find.text('我发起的请求'));
    await tester.pumpAndSettle();
    expect(find.text('我 · 发起'), findsOneWidget);
    expect(find.text('任务修改'), findsOneWidget);
    expect(find.text('任务状态：原内容未记录 → 待验收'), findsOneWidget);
  });

  testWidgets('classification approval uses the explicit empty-to-new diff', (
    tester,
  ) async {
    final repository = ApprovalScreenRepository(
      [
        approval(
          'classification',
          'user-b',
          'user-a',
          taskId: null,
          requestType: 'CLASSIFICATION_CREATE',
          proposedChanges: {'name': '测试分类'},
        ),
      ],
      members: const [
        {'user_id': 'user-b', 'display_name': '溪岸'},
      ],
    );
    final sync = WorkspaceSyncController(repository);
    await sync.refresh();
    await tester.pumpWidget(
      MaterialApp(
        home: TaskApprovalScreen(sync: sync, currentUserId: 'user-a'),
      ),
    );

    expect(find.text('审批类别'), findsOneWidget);
    expect(find.text('新建分类'), findsOneWidget);
    expect(find.text('分类名称：无 → 测试分类'), findsOneWidget);

    final categoryLabel = tester.widget<Text>(
      find.byKey(const Key('approval-category-label')),
    );
    final changeLabel = tester.widget<Text>(
      find.byKey(const Key('approval-change-label')),
    );
    expect(categoryLabel.style?.fontSize, changeLabel.style?.fontSize);
    expect(categoryLabel.style?.fontWeight, changeLabel.style?.fontWeight);
    expect(
      tester.getRect(find.byKey(const Key('approval-category-label'))).width,
      tester.getRect(find.byKey(const Key('approval-change-label'))).width,
    );
  });

  testWidgets('separates pending tabs from approval history', (tester) async {
    final repository = ApprovalScreenRepository([
      approval('pending', 'user-b', 'user-a'),
      approval('approved', 'user-b', 'user-a').copyWith(status: 'APPROVED'),
    ]);
    final sync = WorkspaceSyncController(repository);
    await sync.refresh();
    await tester.pumpWidget(
      MaterialApp(
        home: TaskApprovalScreen(sync: sync, currentUserId: 'user-a'),
      ),
    );

    expect(find.byKey(const Key('approval-card-pending')), findsOneWidget);
    expect(find.byKey(const Key('approval-card-approved')), findsNothing);

    expect(find.text('审批记录'), findsOneWidget);
    await tester.tap(find.text('审批记录'));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('approval-card-approved')), findsOneWidget);
    expect(find.byKey(const Key('approval-approve-approved')), findsNothing);
    expect(find.byKey(const Key('approval-cancel-approved')), findsNothing);
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

    expect(find.text('其他审批事项'), findsOneWidget);
    expect(find.text('user-b'), findsNothing);
    expect(find.textContaining('协作者'), findsNothing);
  });
}
