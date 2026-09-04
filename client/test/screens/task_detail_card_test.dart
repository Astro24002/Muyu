import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:muyu_client/models/task.dart';
import 'package:muyu_client/models/workspace_snapshot.dart';
import 'package:muyu_client/screens/task_detail_screen.dart';
import 'package:muyu_client/sync/workspace_sync_controller.dart';
import 'package:muyu_client/theme/muyu_theme.dart';

TaskItem cardTask({
  required String id,
  required String title,
  String? parentTaskId,
  DateTime? dueAt,
}) => TaskItem(
  id: id,
  workspaceId: 'workspace-1',
  parentTaskId: parentTaskId,
  taskNumber: id,
  title: title,
  description: '任务说明',
  status: 'TODO',
  currentHandlerId: 'user-1',
  quadrant: 'Q2',
  labels: const ['工作'],
  plannedStartAt: null,
  dueAt: dueAt ?? DateTime.utc(2026, 9, 3, 10, 30),
  estimatedMinutes: 30,
  completedAt: null,
  createdBy: 'user-1',
  version: 1,
  statusVersion: 1,
  createdAt: DateTime.utc(2026, 8, 27),
  updatedAt: DateTime.utc(2026, 8, 27),
);

WorkspaceSyncController cardSync(List<TaskItem> tasks) {
  final sync = WorkspaceSyncController.unavailable();
  sync.state = WorkspaceSyncState(
    snapshot: WorkspaceSnapshot(
      workspaceId: 'workspace-1',
      cursor: 1,
      viewerUserId: 'user-1',
      tasks: tasks,
      members: const [
        {'user_id': 'user-1', 'display_name': '我'},
      ],
    ),
    isStale: false,
  );
  return sync;
}

void main() {
  testWidgets('opens as a read-only card and enters edit mode explicitly', (
    tester,
  ) async {
    final task = cardTask(id: 'task-1', title: '准备发布');
    final sync = cardSync([task]);
    await tester.pumpWidget(
      MaterialApp(
        theme: muyuLightTheme(),
        home: TaskDetailScreen(task: task, sync: sync),
      ),
    );

    expect(find.byKey(const Key('task-detail-card')), findsOneWidget);
    expect(find.byKey(const Key('task-detail-title')), findsOneWidget);
    expect(
      tester.widget<Text>(find.byKey(const Key('task-detail-title'))).data,
      '准备发布',
    );
    expect(find.byKey(const Key('task-detail-due-at')), findsNothing);

    await tester.tap(find.byKey(const Key('task-save-button')));
    await tester.pump();

    expect(find.byKey(const Key('task-detail-title')), findsOneWidget);
    expect(
      tester.widget<TextField>(find.byKey(const Key('task-detail-title'))),
      isNotNull,
    );
    expect(find.byKey(const Key('task-detail-due-at')), findsOneWidget);
    expect(find.text('09月03日 周四 10:30'), findsOneWidget);
  });

  testWidgets(
    'shows one-level child tasks and hides child creation on a child',
    (tester) async {
      final parent = cardTask(id: 'parent', title: '发布版本');
      final child = cardTask(
        id: 'child',
        title: '完成发布检查',
        parentTaskId: parent.id,
      );
      final sync = cardSync([parent, child]);
      await tester.pumpWidget(
        MaterialApp(
          theme: muyuLightTheme(),
          home: TaskDetailScreen(task: parent, sync: sync),
        ),
      );

      expect(find.text('子任务'), findsOneWidget);
      expect(find.text('child  完成发布检查'), findsOneWidget);
      expect(find.byKey(const Key('task-add-subtask')), findsOneWidget);

      await tester.drag(find.byType(ListView), const Offset(0, -180));
      await tester.pump();
      final childRow = find.ancestor(
        of: find.text('child  完成发布检查'),
        matching: find.byType(InkWell),
      );
      await tester.ensureVisible(childRow);
      await tester.tap(childRow);
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('task-parent')), findsOneWidget);
      expect(find.byKey(const Key('task-add-subtask')), findsNothing);
    },
  );
}
