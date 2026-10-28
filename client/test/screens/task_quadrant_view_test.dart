import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:muyu_client/models/task.dart';
import 'package:muyu_client/models/workspace_snapshot.dart';
import 'package:muyu_client/screens/task_quadrant_view.dart';
import 'package:muyu_client/sync/workspace_sync_controller.dart';
import 'package:muyu_client/theme/muyu_theme.dart';

TaskItem quadrantTask(
  String id,
  String title, {
  String quadrant = 'Q1',
  List<String> labels = const ['工作'],
  DateTime? dueAt,
}) => TaskItem(
  id: id,
  parentTaskId: null,
  title: title,
  description: '',
  status: 'TODO',
  currentHandlerId: 'user-1',
  quadrant: quadrant,
  labels: labels,
  plannedStartAt: null,
  dueAt: dueAt,
  estimatedMinutes: null,
  completedAt: null,
  createdBy: 'user-1',
  version: 1,
  statusVersion: 1,
  createdAt: DateTime.utc(2026, 9, 1),
  updatedAt: DateTime.utc(2026, 9, 1),
);

WorkspaceSyncState quadrantState(
  List<TaskItem> tasks, {
  List<Map<String, dynamic>> members = const [],
}) => WorkspaceSyncState(
  snapshot: WorkspaceSnapshot(
    workspaceId: 'workspace-1',
    cursor: 1,
    tasks: tasks,
    viewerUserId: 'user-1',
    members: members,
  ),
  isStale: false,
);

Widget quadrantApp(TaskQuadrantView view) => MaterialApp(
  theme: muyuLightTheme(),
  home: Scaffold(body: view),
);

void main() {
  testWidgets('omits completed tasks from the active quadrant view', (
    tester,
  ) async {
    final active = quadrantTask('active', '正在推进');
    final done = quadrantTask('done', '已经完成').copyWith(status: 'DONE');
    await tester.pumpWidget(
      quadrantApp(
        TaskQuadrantView(
          sync: WorkspaceSyncController.unavailable(),
          state: quadrantState([active, done]),
          canWrite: true,
          onTaskTap: (_) {},
        ),
      ),
    );
    expect(find.text('正在推进'), findsOneWidget);
    expect(find.text('已经完成'), findsNothing);
  });

  testWidgets('filters the same quadrant tasks by the current handler', (
    tester,
  ) async {
    final mine = quadrantTask('mine', '我负责的事');
    final other = quadrantTask(
      'other',
      'TA 负责的事',
    ).copyWith(currentHandlerId: 'user-2');
    await tester.pumpWidget(
      quadrantApp(
        TaskQuadrantView(
          sync: WorkspaceSyncController.unavailable(),
          state: quadrantState([mine, other]),
          canWrite: true,
          onTaskTap: (_) {},
        ),
      ),
    );
    expect(find.text('我负责的事'), findsOneWidget);
    expect(find.text('TA 负责的事'), findsOneWidget);
    await tester.tap(find.byKey(const Key('quadrant-owner-mine')));
    await tester.pumpAndSettle();
    expect(find.text('我负责的事'), findsOneWidget);
    expect(find.text('TA 负责的事'), findsNothing);
    await tester.tap(find.byKey(const Key('quadrant-owner-other')));
    await tester.pumpAndSettle();
    expect(find.text('我负责的事'), findsNothing);
    expect(find.text('TA 负责的事'), findsOneWidget);
    await tester.tap(find.byKey(const Key('quadrant-owner-all')));
    await tester.pumpAndSettle();
    expect(find.text('我负责的事'), findsOneWidget);
    expect(find.text('TA 负责的事'), findsOneWidget);
  });

  testWidgets('renders a two-column grid with tinted quadrant headers', (
    tester,
  ) async {
    final task = quadrantTask('q1-1', 'Q1 task');
    await tester.pumpWidget(
      quadrantApp(
        TaskQuadrantView(
          sync: WorkspaceSyncController.unavailable(),
          state: quadrantState([task]),
          canWrite: true,
          onTaskTap: (_) {},
        ),
      ),
    );

    expect(find.byKey(const Key('task-quadrant-grid')), findsOneWidget);
    expect(find.byKey(const Key('task-quadrant-title-Q1')), findsOneWidget);
    expect(find.byKey(const Key('task-quadrant-title-Q2')), findsOneWidget);
    expect(find.byKey(const Key('task-quadrant-title-Q3')), findsOneWidget);
    expect(find.byKey(const Key('task-quadrant-title-Q4')), findsOneWidget);
    expect(find.byKey(const Key('task-quadrant-label-filter')), findsNothing);
    expect(find.text('Q1 重要且紧急'), findsOneWidget);
    expect(find.text('Q1 task'), findsOneWidget);
    expect(find.text('按重要性和紧急程度查看未完成事项。'), findsOneWidget);
    expect(find.text('让重要的事，有它的位置。'), findsNothing);

    final header = tester.widget<Container>(
      find.byKey(const Key('task-quadrant-title-Q1')),
    );
    expect(header.color, isNot(muyuLightTheme().colorScheme.surface));
    final panel = tester.widget<DecoratedBox>(
      find.byKey(const Key('task-quadrant-surface-Q1')),
    );
    expect(
      (panel.decoration as BoxDecoration).color,
      muyuLightTheme().scaffoldBackgroundColor,
    );
    expect(
      tester
          .widget<Material>(find.byKey(ValueKey('task-card-${task.id}')))
          .color,
      muyuLightTheme().scaffoldBackgroundColor,
    );
  });

  testWidgets(
    'shows the task title instead of the task number in a compact quadrant row',
    (tester) async {
      final task = quadrantTask(
        'task-1',
        '准备发布',
      ).copyWith(taskNumber: '26080001');

      await tester.pumpWidget(
        quadrantApp(
          TaskQuadrantView(
            sync: WorkspaceSyncController.unavailable(),
            state: quadrantState([task]),
            canWrite: true,
            onTaskTap: (_) {},
          ),
        ),
      );

      expect(find.text('准备发布'), findsOneWidget);
      expect(find.text('26080001'), findsNothing);
      expect(find.byKey(const ValueKey('task-card-task-1')), findsOneWidget);
      expect(
        tester.getSize(find.byKey(const ValueKey('task-card-task-1'))).height,
        lessThan(48),
      );
    },
  );

  testWidgets('keeps compact quadrant rows dense when a due date is present', (
    tester,
  ) async {
    final task = quadrantTask(
      'task-dense',
      '准备发布生产环境检查清单',
      dueAt: DateTime.utc(2026, 9, 3, 18, 30),
    );

    await tester.pumpWidget(
      quadrantApp(
        TaskQuadrantView(
          sync: WorkspaceSyncController.unavailable(),
          state: quadrantState([task]),
          canWrite: true,
          onTaskTap: (_) {},
        ),
      ),
    );

    final title = tester.widget<Text>(
      find.byKey(const ValueKey('task-card-title-task-dense')),
    );
    expect(title.maxLines, 1);
    expect(title.style?.fontSize, 12);
    expect(
      find.byKey(const ValueKey('task-card-metadata-task-dense')),
      findsOneWidget,
    );
    expect(
      tester.getSize(find.byKey(const ValueKey('task-card-task-dense'))).height,
      lessThan(48),
    );
    expect(
      tester
          .getSize(find.byKey(const ValueKey('task-card-title-task-dense')))
          .width,
      greaterThan(100),
    );
  });

  testWidgets('renders compact owner, status, and classification pills', (
    tester,
  ) async {
    final task = quadrantTask('task-pills', '准备婚礼物料', labels: const ['婚礼101']);

    await tester.pumpWidget(
      quadrantApp(
        TaskQuadrantView(
          sync: WorkspaceSyncController.unavailable(),
          state: quadrantState(
            [task],
            members: const [
              {'user_id': 'user-1', 'display_name': 'Bokang'},
            ],
          ),
          canWrite: true,
          onTaskTap: (_) {},
        ),
      ),
    );

    expect(find.text('Bokang'), findsOneWidget);
    expect(find.text('待进行'), findsOneWidget);
    expect(find.text('婚礼101'), findsOneWidget);
    for (final key in [
      'task-card-owner-task-pills',
      'task-card-status-task-pills',
      'task-card-label-task-pills',
    ]) {
      final pill = find.byKey(ValueKey(key));
      expect(pill, findsOneWidget);
      expect(tester.getSize(pill).height, 20);
      final container = tester.widget<Container>(
        find.descendant(of: pill, matching: find.byType(Container)),
      );
      expect(container.alignment, Alignment.center);
      expect(
        (container.decoration! as BoxDecoration).borderRadius,
        const BorderRadius.all(Radius.circular(999)),
      );
    }
  });

  testWidgets('previews four tasks and expands only the selected quadrant', (
    tester,
  ) async {
    final tasks = [
      for (var index = 1; index <= 5; index++)
        quadrantTask('q1-$index', 'Q1 task $index'),
      quadrantTask('q2-1', 'Q2 task', quadrant: 'Q2'),
    ];
    await tester.pumpWidget(
      quadrantApp(
        TaskQuadrantView(
          sync: WorkspaceSyncController.unavailable(),
          state: quadrantState(tasks),
          canWrite: true,
          onTaskTap: (_) {},
        ),
      ),
    );

    expect(find.text('Q1 task 1'), findsOneWidget);
    expect(find.text('Q1 task 4'), findsOneWidget);
    expect(find.text('Q1 task 5'), findsNothing);
    expect(find.text('更多任务'), findsOneWidget);
    expect(find.text('更多任务 · 1项'), findsNothing);

    await tester.tap(find.byKey(const Key('task-quadrant-more-Q1')));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('task-quadrant-title-Q1')), findsOneWidget);
    expect(find.byKey(const Key('task-quadrant-title-Q2')), findsNothing);
    expect(find.text('Q1 task 5'), findsOneWidget);
    expect(find.byKey(const Key('task-quadrant-collapse')), findsOneWidget);

    await tester.tap(find.byKey(const Key('task-quadrant-collapse')));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('task-quadrant-title-Q2')), findsOneWidget);
    expect(find.text('Q1 task 5'), findsNothing);
  });

  testWidgets('uses the selected category supplied by the parent app bar', (
    tester,
  ) async {
    await tester.pumpWidget(
      quadrantApp(
        TaskQuadrantView(
          sync: WorkspaceSyncController.unavailable(),
          state: quadrantState([
            quadrantTask('work', 'Work task'),
            quadrantTask('wedding', 'Wedding task', labels: const ['婚礼']),
          ]),
          canWrite: true,
          selectedLabel: '工作',
          onTaskTap: (_) {},
        ),
      ),
    );

    expect(find.text('Work task'), findsOneWidget);
    expect(find.text('Wedding task'), findsNothing);
  });

  testWidgets('can be removed by a tab host while expansion is running', (
    tester,
  ) async {
    final tasks = [
      for (var index = 1; index <= 5; index++)
        quadrantTask('dispose-$index', 'Disposable task $index'),
    ];
    var showQuadrant = true;
    late StateSetter updateHost;
    await tester.pumpWidget(
      MaterialApp(
        theme: muyuLightTheme(),
        home: StatefulBuilder(
          builder: (context, setState) {
            updateHost = setState;
            return Scaffold(
              body: showQuadrant
                  ? TaskQuadrantView(
                      sync: WorkspaceSyncController.unavailable(),
                      state: quadrantState(tasks),
                      canWrite: true,
                      onTaskTap: (_) {},
                    )
                  : const SizedBox.shrink(),
            );
          },
        ),
      ),
    );

    await tester.tap(find.byKey(const Key('task-quadrant-more-Q1')));
    await tester.pump(const Duration(milliseconds: 80));
    updateHost(() => showQuadrant = false);
    await tester.pumpAndSettle();
  });
}
