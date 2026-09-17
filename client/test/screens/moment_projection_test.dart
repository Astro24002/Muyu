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
  testWidgets('renders the server moment counts and compact task groups', (
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
      ),
      isStale: false,
    );
    TaskItem? tapped;

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: TaskListView(
            sync: WorkspaceSyncController.unavailable(),
            state: state,
            canWrite: false,
            onTaskTap: (task) => tapped = task,
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
      tester.widget<Text>(find.byKey(const Key('moment-count-week-due'))).data,
      '2',
    );
    expect(find.text('卡住的事情'), findsOneWidget);
    expect(find.text('我在推进'), findsOneWidget);
    expect(find.text('TA 在推进'), findsOneWidget);
    expect(find.byKey(const Key('moment-summary')), findsOneWidget);
    expect(find.byKey(const Key('moment-view-all')), findsOneWidget);
    expect(find.byKey(const ValueKey('task-card-mine')), findsOneWidget);
    expect(find.byKey(const ValueKey('task-card-status-mine')), findsOneWidget);
    expect(find.byKey(const ValueKey('task-card-due-mine')), findsOneWidget);
    expect(
      find.byKey(const ValueKey('task-card-quadrant-mine')),
      findsOneWidget,
    );
    expect(find.byKey(const ValueKey('task-card-owner-mine')), findsOneWidget);
    expect(find.text('酒店'), findsOneWidget);
    expect(find.text('等待伙伴确认'), findsOneWidget);
    expect(find.text('收到确认后继续处理'), findsOneWidget);
    expect(find.byKey(const Key('task-section-header-upcoming')), findsNothing);

    await tester.tap(find.byKey(const ValueKey('task-card-mine')));
    expect(tapped, same(mine));

    await tester.tap(find.byKey(const Key('moment-view-all')));
    await tester.pumpAndSettle();
    expect(
      find.byKey(const Key('task-section-header-upcoming')),
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
            onTaskTap: (_) {},
          ),
        ),
      ),
    );

    expect(find.byKey(const ValueKey('moment-task-duplicate')), findsOneWidget);
  });
}
