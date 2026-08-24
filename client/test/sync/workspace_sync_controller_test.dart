import 'package:flutter_test/flutter_test.dart';
import 'package:muyu_client/models/task.dart';
import 'package:muyu_client/models/workspace_change.dart';
import 'package:muyu_client/models/workspace_snapshot.dart';
import 'package:muyu_client/sync/workspace_sync_controller.dart';
import 'package:muyu_client/sync/workspace_sync_repository.dart';

TaskItem task(String title) => TaskItem(
  id: 'task-1',
  parentTaskId: null,
  title: title,
  description: '',
  status: 'TODO',
  currentHandlerId: 'user-1',
  plannedStartAt: null,
  dueAt: null,
  estimatedMinutes: null,
  completedAt: null,
  createdBy: 'user-1',
  version: 1,
  statusVersion: 1,
  createdAt: DateTime.utc(2026, 8, 24),
  updatedAt: DateTime.utc(2026, 8, 24),
  assigneeIds: const ['user-1'],
);

class FakeSyncRepository implements WorkspaceSyncRepository {
  final hints = <WorkspaceChanged>[];
  int snapshotCalls = 0;
  final requestedAfterCursors = <int>[];

  @override
  Stream<WorkspaceChanged> openWorkspaceHints() => Stream.fromIterable(hints);

  @override
  Future<WorkspaceSnapshot> snapshot() async {
    snapshotCalls++;
    return WorkspaceSnapshot(
      workspaceId: 'w1',
      cursor: 11,
      tasks: [task('Server title')],
    );
  }

  @override
  Future<WorkspaceChanges> changes({required int afterCursor}) async {
    requestedAfterCursors.add(afterCursor);
    return WorkspaceChanges(
      workspaceId: 'w1',
      cursor: 12,
      changes: [
        WorkspaceChange.taskUpdated(cursor: 12, task: task('Changed title')),
      ],
    );
  }
}

void main() {
  test(
    'a workspace hint pulls REST changes instead of applying hint data',
    () async {
      final repository = FakeSyncRepository();
      final controller = WorkspaceSyncController(repository);

      await controller.start();
      repository.hints.add(
        const WorkspaceChanged(workspaceId: 'w1', cursor: 12),
      );
      await controller.pull();

      expect(repository.requestedAfterCursors, [11]);
      expect(controller.state.snapshot!.tasks.single.title, 'Changed title');
      expect(controller.state.cursor, 12);
    },
  );

  test('manual refresh uses the same authoritative snapshot routine', () async {
    final repository = FakeSyncRepository();
    final controller = WorkspaceSyncController(repository);

    await controller.refresh();

    expect(repository.snapshotCalls, 1);
    expect(controller.state.isStale, isFalse);
  });
}
