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

TaskItem blockedDisplayTask() => TaskItem(
  id: 'blocked-summary',
  parentTaskId: null,
  title: '等待确认出行日期',
  description: '',
  status: 'BLOCKED',
  currentHandlerId: 'user-2',
  quadrant: 'Q1',
  blockedReason: '等待对方确认最终日期',
  blockedSince: DateTime.now().subtract(const Duration(hours: 2, minutes: 4)),
  plannedStartAt: null,
  dueAt: DateTime.now().add(const Duration(days: 1)),
  estimatedMinutes: null,
  completedAt: null,
  createdBy: 'user-1',
  version: 1,
  statusVersion: 1,
  createdAt: DateTime.utc(2026, 9, 3),
  updatedAt: DateTime.utc(2026, 9, 3),
);

void main() {
  testWidgets('uses Chinese status semantics for blocked and cancelled rows', (
    tester,
  ) async {
    final semantics = tester.ensureSemantics();
    final blocked = blockedDisplayTask();
    final cancelled = displayTask('cancelled', 'CANCELLED');
    final state = WorkspaceSyncState(
      snapshot: WorkspaceSnapshot(
        workspaceId: 'workspace-1',
        cursor: 1,
        viewerUserId: 'user-1',
        tasks: [blocked, cancelled],
        members: const [
          {'user_id': 'user-1', 'display_name': '我'},
          {'user_id': 'user-2', 'display_name': '李四'},
        ],
      ),
      isStale: false,
    );

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Column(
            children: [
              TaskListRow(
                task: blocked,
                state: state,
                showSubtitle: true,
                subtasks: const [],
                onTap: () {},
              ),
              TaskListRow(
                task: cancelled,
                state: state,
                showSubtitle: true,
                subtasks: const [],
                onTap: () {},
              ),
            ],
          ),
        ),
      ),
    );

    expect(find.byIcon(Icons.pause_circle_outline), findsOneWidget);
    expect(find.byIcon(Icons.fact_check_outlined), findsNothing);
    expect(
      tester.getSemantics(find.byIcon(Icons.pause_circle_outline)).label,
      startsWith('阻塞中'),
    );
    expect(
      tester.getSemantics(find.byIcon(Icons.cancel)).label,
      startsWith('已取消'),
    );
    semantics.dispose();
  });

  testWidgets(
    'renders server action sections inside the existing task list tab',
    (tester) async {
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

      expect(find.text('当前任务 1'), findsNothing);
      expect(find.text('当前阻塞'), findsOneWidget);
      expect(
        find.byKey(const Key('home-action-count-blocked')),
        findsOneWidget,
      );
      expect(find.text('待我验收'), findsNothing);
      expect(find.text('待处理审批'), findsNothing);
    },
  );

  testWidgets('blocked summary keeps owner and duration in compact pills', (
    tester,
  ) async {
    final blocked = blockedDisplayTask();
    final state = WorkspaceSyncState(
      snapshot: WorkspaceSnapshot(
        workspaceId: 'workspace-1',
        cursor: 1,
        viewerUserId: 'user-1',
        tasks: [blocked],
        members: const [
          {'user_id': 'user-1', 'display_name': '我'},
          {'user_id': 'user-2', 'display_name': '李四'},
        ],
      ),
      home: HomeResponse(
        currentTasks: HomeTaskSection(items: const []),
        blockedTasks: HomeTaskSection(items: [blocked]),
        reviewTasks: HomeTaskSection(items: const []),
        pendingApprovalCount: 0,
      ),
      isStale: false,
    );

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: TaskListView(
            sync: WorkspaceSyncController.unavailable(),
            state: state,
            canWrite: false,
            onTaskTap: (_) {},
          ),
        ),
      ),
    );

    expect(find.text('李四'), findsOneWidget);
    expect(find.text('等待对方确认最终日期'), findsOneWidget);
    expect(
      find.byKey(const Key('home-action-duration-blocked-summary')),
      findsOneWidget,
    );
    expect(find.byType(ActionChip), findsNothing);
  });
}
