import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:muyu_client/models/home.dart';
import 'package:muyu_client/models/task.dart';
import 'package:muyu_client/models/workspace_snapshot.dart';
import 'package:muyu_client/screens/task_list_view.dart';
import 'package:muyu_client/sync/workspace_sync_controller.dart';

TaskItem momentTask(
  String id, {
  required String status,
  required String handler,
  List<String> labels = const [],
  DateTime? dueAt,
  String? blockedReason,
  MomentNextStep? nextStep,
}) => TaskItem(
  id: id,
  workspaceId: 'workspace-1',
  parentTaskId: null,
  title: '$id title',
  description: '',
  status: status,
  currentHandlerId: handler,
  quadrant: 'Q1',
  labels: labels,
  progress: status == 'IN_PROGRESS' ? 35 : null,
  blockedReason: blockedReason,
  nextStep: nextStep,
  plannedStartAt: null,
  dueAt: dueAt,
  estimatedMinutes: null,
  completedAt: null,
  createdBy: 'user-1',
  version: 1,
  statusVersion: 1,
  createdAt: DateTime.utc(2026, 9, 3),
  updatedAt: DateTime.utc(2026, 9, 3),
);

void main() {
  testWidgets(
    'default moment hides open groups and shows completed archive rows',
    (tester) async {
      final mine = momentTask(
        'active',
        status: 'IN_PROGRESS',
        handler: 'user-1',
      );
      final done = momentTask('done', status: 'DONE', handler: 'user-2');
      final cancelled = momentTask(
        'cancelled',
        status: 'CANCELLED',
        handler: 'user-1',
      );
      final state = WorkspaceSyncState(
        snapshot: WorkspaceSnapshot(
          workspaceId: 'workspace-1',
          cursor: 1,
          viewerUserId: 'user-1',
          tasks: [mine, done, cancelled],
        ),
        home: HomeResponse(
          currentTasks: HomeTaskSection(items: [mine]),
          blockedTasks: HomeTaskSection(items: const []),
          reviewTasks: HomeTaskSection(items: const []),
          pendingApprovalCount: 0,
          moment: MomentProjection(
            blocked: HomeTaskSection(items: const []),
            mine: HomeTaskSection(items: [mine]),
            other: HomeTaskSection(items: const []),
          ),
        ),
      );
      TaskItem? tapped;
      Widget page({bool showCompleted = true}) => MaterialApp(
        home: Scaffold(
          body: TaskListView(
            sync: WorkspaceSyncController.unavailable(),
            state: state,
            canWrite: false,
            showMomentMetrics: false,
            showCompleted: showCompleted,
            onTaskTap: (task) => tapped = task,
          ),
        ),
      );

      await tester.pumpWidget(page());
      expect(find.byKey(const ValueKey('task-card-active')), findsNothing);
      await tester.scrollUntilVisible(
        find.byKey(const ValueKey('task-list-row-done')),
        200,
      );
      expect(find.text('已完成/已归档'), findsOneWidget);
      expect(find.byKey(const ValueKey('task-list-row-done')), findsOneWidget);
      expect(find.byKey(const ValueKey('task-card-done')), findsNothing);
      expect(
        find.byKey(const ValueKey('task-list-row-cancelled')),
        findsNothing,
      );
      await tester.tap(find.byKey(const ValueKey('task-list-row-done')));
      expect(tapped, same(done));

      await tester.pumpWidget(page(showCompleted: false));
      await tester.pumpAndSettle();
      expect(
        find.byKey(const Key('task-section-header-terminal')),
        findsNothing,
      );
      expect(find.byKey(const ValueKey('task-list-row-done')), findsNothing);
    },
  );

  testWidgets('renders the server moment counts without the task groups', (
    tester,
  ) async {
    final blocked = momentTask(
      'blocked',
      status: 'BLOCKED',
      handler: 'user-2',
      labels: const ['酒店'],
      dueAt: DateTime.utc(2026, 9, 20),
      blockedReason: '等待伙伴确认',
      nextStep: const MomentNextStep(
        kind: 'RESUME_TASK',
        label: '收到确认后继续处理',
        canAct: false,
        actions: [],
      ),
    );
    final mine = momentTask(
      'mine',
      status: 'IN_PROGRESS',
      handler: 'user-1',
      labels: const ['工作'],
      dueAt: DateTime.utc(2026, 9, 18),
    );
    final other = momentTask(
      'other',
      status: 'TODO',
      handler: 'user-2',
      dueAt: DateTime.utc(2026, 9, 21),
    );
    final state = WorkspaceSyncState(
      snapshot: WorkspaceSnapshot(
        workspaceId: 'workspace-1',
        cursor: 1,
        viewerUserId: 'user-1',
        tasks: [blocked, mine, other],
        members: const [
          {'user_id': 'user-1', 'display_name': '我'},
          {'user_id': 'user-2', 'display_name': '对方'},
        ],
      ),
      home: HomeResponse(
        currentTasks: HomeTaskSection(items: [mine]),
        blockedTasks: HomeTaskSection(items: [blocked]),
        reviewTasks: HomeTaskSection(items: const []),
        pendingApprovalCount: 3,
        moment: MomentProjection(
          blockedTasks: HomeTaskSection(items: [blocked]),
          myTasks: HomeTaskSection(items: [mine]),
          otherTasks: HomeTaskSection(items: [other]),
        ),
        needsActionCount: 3,
        waitingOnOtherCount: 1,
        weekDueCount: 2,
        dueSoonCount: 2,
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

    expect(
      tester
          .widget<Text>(find.byKey(const Key('moment-count-needs-action')))
          .data,
      '3',
    );
    expect(
      tester
          .widget<Text>(find.byKey(const Key('moment-count-waiting-on-other')))
          .data,
      '1',
    );
    expect(
      tester.widget<Text>(find.byKey(const Key('moment-count-due-soon'))).data,
      '2',
    );
    expect(find.text('即将到期'), findsOneWidget);
    expect(find.text('本周到期'), findsNothing);
    expect(find.text('卡住的事情'), findsNothing);
    expect(find.text('我在推进'), findsNothing);
    expect(find.text('TA 在推进'), findsNothing);
    expect(find.byKey(const Key('moment-summary')), findsOneWidget);
    expect(find.byKey(const Key('moment-greeting')), findsOneWidget);
    expect(find.byKey(const Key('moment-view-all')), findsNothing);
    expect(find.byKey(const ValueKey('task-card-mine')), findsNothing);
    expect(find.text('酒店'), findsNothing);
    expect(find.text('等待伙伴确认'), findsNothing);
    expect(find.text('收到确认后继续处理'), findsNothing);
    expect(find.byKey(const Key('task-section-header-upcoming')), findsNothing);
    expect(
      find.byKey(const Key('task-section-header-terminal')),
      findsOneWidget,
    );
  });

  testWidgets('renders a projected task once when sections overlap', (
    tester,
  ) async {
    final duplicate = momentTask(
      'duplicate',
      status: 'BLOCKED',
      handler: 'user-2',
    );
    final state = WorkspaceSyncState(
      snapshot: WorkspaceSnapshot(
        workspaceId: 'workspace-1',
        cursor: 1,
        viewerUserId: 'user-1',
        tasks: [duplicate],
      ),
      home: HomeResponse(
        currentTasks: HomeTaskSection(items: const []),
        blockedTasks: HomeTaskSection(items: [duplicate]),
        reviewTasks: HomeTaskSection(items: const []),
        pendingApprovalCount: 0,
        moment: MomentProjection(
          blocked: HomeTaskSection(items: [duplicate]),
          mine: HomeTaskSection(items: [duplicate]),
          other: HomeTaskSection(items: const []),
        ),
      ),
    );

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: TaskListView(
            sync: WorkspaceSyncController.unavailable(),
            state: state,
            canWrite: false,
            showMomentMetrics: false,
            showMomentTaskSections: true,
            onTaskTap: (_) {},
          ),
        ),
      ),
    );

    expect(find.byKey(const ValueKey('moment-task-duplicate')), findsOneWidget);
  });
}
