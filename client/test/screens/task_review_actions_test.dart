import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:muyu_client/models/task.dart';
import 'package:muyu_client/models/task_approval_request.dart';
import 'package:muyu_client/models/workspace_change.dart';
import 'package:muyu_client/models/workspace_snapshot.dart';
import 'package:muyu_client/screens/task_detail_screen.dart';
import 'package:muyu_client/sync/workspace_sync_controller.dart';
import 'package:muyu_client/sync/workspace_sync_repository.dart';

TaskItem reviewTask() => TaskItem(
  id: 'task-review',
  workspaceId: 'workspace-1',
  parentTaskId: null,
  title: 'Review task',
  description: '',
  status: 'REVIEW',
  currentHandlerId: 'owner',
  reviewerUserId: 'reviewer',
  quadrant: 'Q1',
  plannedStartAt: null,
  dueAt: null,
  estimatedMinutes: null,
  completedAt: null,
  createdBy: 'owner',
  version: 1,
  statusVersion: 3,
  createdAt: DateTime.utc(2026, 9, 3),
  updatedAt: DateTime.utc(2026, 9, 3),
  labels: const [],
);

WorkspaceSyncController syncFor(String viewerUserId, {TaskItem? task}) {
  final sync = WorkspaceSyncController.unavailable();
  sync.state = WorkspaceSyncState(
    snapshot: WorkspaceSnapshot(
      workspaceId: 'workspace-1',
      cursor: 3,
      viewerUserId: viewerUserId,
      tasks: [task ?? reviewTask()],
    ),
    isStale: false,
  );
  return sync;
}

TaskApprovalRequest handoffRequest() => TaskApprovalRequest(
  id: 'handoff-1',
  workspaceId: 'workspace-1',
  taskId: 'task-review',
  requesterId: 'owner',
  approverId: 'reviewer',
  requestType: 'HANDLER_TRANSFER',
  proposedChanges: const {
    'current_handler_id': 'reviewer',
    'transfer_note': '请接手后续安排',
  },
  baseFieldVersions: const {'current_handler_id': 1},
  requestId: 'request-handoff-1',
  status: 'PENDING',
  createdAt: DateTime.utc(2026, 9, 18),
);

class HandoffRepository implements WorkspaceSyncRepository {
  HandoffRepository(this.viewerUserId);

  final String viewerUserId;
  String? approvedId;
  String? rejectedId;
  TaskItem currentTask = reviewTask().copyWith(status: 'IN_PROGRESS');

  @override
  Future<WorkspaceSnapshot> snapshot() async => WorkspaceSnapshot(
    workspaceId: 'workspace-1',
    cursor: 1,
    viewerUserId: viewerUserId,
    tasks: [currentTask],
    approvalRequests: [handoffRequest()],
  );

  @override
  Future<WorkspaceChanges> changes({required int afterCursor}) async =>
      WorkspaceChanges(
        workspaceId: 'workspace-1',
        cursor: afterCursor,
        changes: const [],
      );

  @override
  Future<ApprovalActionResult> approveApproval(
    String approvalId, {
    String? workspaceId,
    required String requestId,
  }) async {
    approvedId = approvalId;
    currentTask = currentTask.copyWith(currentHandlerId: 'reviewer');
    return ApprovalActionResult(
      approvalRequest: handoffRequest().copyWith(status: 'APPROVED'),
      task: currentTask,
      cursor: 2,
    );
  }

  @override
  Future<ApprovalActionResult> rejectApproval(
    String approvalId, {
    String? workspaceId,
    required String requestId,
    String? reason,
  }) async {
    rejectedId = approvalId;
    return ApprovalActionResult(
      approvalRequest: handoffRequest().copyWith(status: 'REJECTED'),
      task: currentTask,
      cursor: 2,
    );
  }

  @override
  Stream<WorkspaceChanged> openWorkspaceHints() => const Stream.empty();

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  testWidgets('the current handler can submit in-progress work for review', (
    tester,
  ) async {
    final task = reviewTask().copyWith(
      status: 'IN_PROGRESS',
      reviewerUserId: 'reviewer',
    );
    final sync = syncFor('owner', task: task);
    await tester.pumpWidget(
      MaterialApp(
        home: TaskDetailScreen(task: task, sync: sync),
      ),
    );
    await tester.drag(find.byType(ListView), const Offset(0, -600));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('task-status-review')), findsOneWidget);
    expect(find.byKey(const Key('task-status-done')), findsNothing);
  });

  testWidgets(
    'review content opens as a bottom sheet and preserves its draft',
    (tester) async {
      final task = reviewTask().copyWith(status: 'IN_PROGRESS');
      final sync = syncFor('owner', task: task);
      await tester.pumpWidget(
        MaterialApp(
          home: TaskDetailScreen(task: task, sync: sync, inSheet: true),
        ),
      );
      await tester.drag(find.byType(ListView), const Offset(0, -600));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('task-status-review')));
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('review-submit-sheet')), findsOneWidget);
      await tester.tap(find.byKey(const Key('review-submit-confirm')));
      await tester.pumpAndSettle();
      expect(find.text('请填写验收内容'), findsOneWidget);
      await tester.enterText(
        find.byKey(const Key('review-content-input')),
        '歌单已整理',
      );
      expect(find.text('歌单已整理'), findsOneWidget);
    },
  );

  testWidgets(
    'only the server-provided reviewer sees REVIEW decision actions',
    (tester) async {
      final ownerSync = syncFor('owner');
      await tester.pumpWidget(
        MaterialApp(
          home: TaskDetailScreen(task: reviewTask(), sync: ownerSync),
        ),
      );
      await tester.drag(find.byType(ListView), const Offset(0, -600));
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('task-status-done')), findsNothing);
      expect(find.byKey(const Key('task-status-in_progress')), findsNothing);
      expect(find.byKey(const Key('task-status-cancelled')), findsOneWidget);

      final reviewerSync = syncFor('reviewer');
      await tester.pumpWidget(
        MaterialApp(
          home: TaskDetailScreen(task: reviewTask(), sync: reviewerSync),
        ),
      );
      await tester.drag(find.byType(ListView), const Offset(0, -600));
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('task-status-done')), findsOneWidget);
      expect(find.byKey(const Key('task-status-in_progress')), findsOneWidget);
      expect(find.widgetWithText(OutlinedButton, '通过验收'), findsOneWidget);
      expect(find.widgetWithText(OutlinedButton, '退回修改'), findsOneWidget);
      expect(find.text('验收人：reviewer'), findsOneWidget);
      expect(find.text('已完成'), findsNothing);
      expect(find.text('进行中'), findsNothing);
    },
  );

  testWidgets('handoff target can accept from task detail', (tester) async {
    final repository = HandoffRepository('reviewer');
    final sync = WorkspaceSyncController(repository);
    await sync.refresh();

    await tester.pumpWidget(
      MaterialApp(
        home: TaskDetailScreen(task: repository.currentTask, sync: sync),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('task-handoff-accept')), findsOneWidget);
    expect(find.byKey(const Key('task-handoff-decline')), findsOneWidget);
    expect(sync.state.snapshot!.tasks.single.currentHandlerId, 'owner');

    await tester.tap(find.byKey(const Key('task-handoff-accept')));
    await tester.pumpAndSettle();

    expect(repository.approvedId, 'handoff-1');
    expect(sync.state.snapshot!.tasks.single.currentHandlerId, 'reviewer');
    expect(find.byKey(const Key('task-handoff-accept')), findsNothing);
  });

  testWidgets('handoff actions are hidden from the requester', (tester) async {
    final repository = HandoffRepository('owner');
    final sync = WorkspaceSyncController(repository);
    await sync.refresh();

    await tester.pumpWidget(
      MaterialApp(
        home: TaskDetailScreen(task: repository.currentTask, sync: sync),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('task-handoff-accept')), findsNothing);
    expect(find.byKey(const Key('task-handoff-decline')), findsNothing);
    expect(find.text('等待对方接受交接'), findsOneWidget);
  });

  testWidgets('handoff target can decline without changing the owner', (
    tester,
  ) async {
    final repository = HandoffRepository('reviewer');
    final sync = WorkspaceSyncController(repository);
    await sync.refresh();

    await tester.pumpWidget(
      MaterialApp(
        home: TaskDetailScreen(task: repository.currentTask, sync: sync),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('等待你确认接棒'), findsOneWidget);
    await tester.ensureVisible(find.byKey(const Key('task-handoff-decline')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('task-handoff-decline')));
    await tester.pumpAndSettle();

    expect(repository.rejectedId, 'handoff-1');
    expect(sync.state.snapshot!.tasks.single.currentHandlerId, 'owner');
    expect(find.byKey(const Key('task-handoff-actions')), findsNothing);
  });

  testWidgets('read-only detail does not expose handoff decisions', (
    tester,
  ) async {
    final repository = HandoffRepository('reviewer');
    final sync = WorkspaceSyncController(repository);
    await sync.refresh();

    await tester.pumpWidget(
      MaterialApp(
        home: TaskDetailScreen(
          task: repository.currentTask,
          sync: sync,
          canWrite: false,
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('task-handoff-actions')), findsNothing);
  });
}
