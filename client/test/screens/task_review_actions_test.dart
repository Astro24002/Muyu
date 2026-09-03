import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:muyu_client/models/task.dart';
import 'package:muyu_client/models/workspace_snapshot.dart';
import 'package:muyu_client/screens/task_detail_screen.dart';
import 'package:muyu_client/sync/workspace_sync_controller.dart';

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
}
