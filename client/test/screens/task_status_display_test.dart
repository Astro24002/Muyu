import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:muyu_client/models/home.dart';
import 'package:muyu_client/models/task.dart';
import 'package:muyu_client/models/workspace_snapshot.dart';
import 'package:muyu_client/screens/task_list_view.dart';
import 'package:muyu_client/sync/workspace_sync_controller.dart';

TaskItem displayTask(String id, String status) => TaskItem(
  id: id,
  parentTaskId: null,
  title: id,
  description: '',
  status: status,
  currentHandlerId: 'user-1',
  quadrant: 'Q1',
  plannedStartAt: null,
  dueAt: null,
  estimatedMinutes: null,
  completedAt: null,
  createdBy: 'user-1',
  version: 1,
  statusVersion: 1,
  createdAt: DateTime.utc(2026, 9, 3),
  updatedAt: DateTime.utc(2026, 9, 3),
);

void main() {
  testWidgets('uses distinct Chinese status semantics for blocked and review', (
    tester,
  ) async {
    final semantics = tester.ensureSemantics();
    final sync = WorkspaceSyncController.unavailable();
    final state = WorkspaceSyncState(
      snapshot: WorkspaceSnapshot(
        workspaceId: 'workspace-1',
        cursor: 1,
        viewerUserId: 'user-1',
        tasks: [
          displayTask('blocked', 'BLOCKED'),
          displayTask('review', 'REVIEW'),
          displayTask('cancelled', 'CANCELLED'),
        ],
      ),
      isStale: false,
    );

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: TaskListView(
            sync: sync,
            state: state,
            canWrite: false,
            onTaskTap: (_) {},
          ),
        ),
      ),
    );

    expect(find.byIcon(Icons.pause_circle_outline), findsOneWidget);
    expect(find.byIcon(Icons.fact_check_outlined), findsOneWidget);
    expect(
      tester.getSemantics(find.byIcon(Icons.pause_circle_outline)).label,
      startsWith('阻塞中'),
    );
    expect(
      tester.getSemantics(find.byIcon(Icons.fact_check_outlined)).label,
      startsWith('待验收'),
    );
    expect(
      tester.getSemantics(find.byIcon(Icons.cancel)).label,
      startsWith('已取消'),
    );
    semantics.dispose();
  });

  testWidgets('renders server action sections inside the existing task list tab', (
    tester,
  ) async {
    final current = displayTask('current', 'TODO');
    final blocked = displayTask('blocked', 'BLOCKED');
    final review = displayTask('review', 'REVIEW');
    final sync = WorkspaceSyncController.unavailable();
    final state = WorkspaceSyncState(
      snapshot: WorkspaceSnapshot(
        workspaceId: 'workspace-1',
        cursor: 1,
        viewerUserId: 'user-1',
        tasks: [current, blocked, review],
      ),
      home: HomeResponse(
        currentTasks: HomeTaskSection(items: [current]),
        blockedTasks: HomeTaskSection(items: [blocked]),
        reviewTasks: HomeTaskSection(items: [review]),
        pendingApprovalCount: 0,
      ),
      isStale: false,
    );

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: TaskListView(
            sync: sync,
            state: state,
            canWrite: false,
            onTaskTap: (_) {},
          ),
        ),
      ),
    );

    expect(find.text('当前任务 1'), findsOneWidget);
    expect(find.text('当前阻塞 1'), findsOneWidget);
    expect(find.text('待我验收 1'), findsOneWidget);
  });
}
