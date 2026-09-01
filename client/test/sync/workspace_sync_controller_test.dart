import 'dart:async';

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
  quadrant: 'Q1',
  plannedStartAt: null,
  dueAt: null,
  estimatedMinutes: null,
  completedAt: null,
  createdBy: 'user-1',
  version: 1,
  statusVersion: 1,
  createdAt: DateTime.utc(2026, 8, 24),
  updatedAt: DateTime.utc(2026, 8, 24),
  labels: const [],
);

class FakeSyncRepository implements WorkspaceSyncRepository {
  final hints = <WorkspaceChanged>[];
  int snapshotCalls = 0;
  bool failSnapshots = false;
  Completer<WorkspaceSnapshot>? snapshotCompleter;
  final requestedAfterCursors = <int>[];
  String? lastRequestId;
  String? createRequestId;

  @override
  Future<TaskItem> create({
    required String title,
    required String quadrant,
    List<String> labels = const [],
    String? description,
    String? dueAt,
    String? parentTaskId,
    String? plannedStartAt,
    int? estimatedMinutes,
    required String requestId,
  }) async {
    createRequestId = requestId;
    return task(title);
  }

  @override
  Future<TaskItem?> update(
    String taskId, {
    required Map<String, Object?> fields,
    required Map<String, int> fieldVersions,
    required String requestId,
  }) async => task(fields['title'] as String? ?? 'updated');

  @override
  Future<TaskItem> resolveConflict(
    String taskId,
    String conflictId, {
    required String resolution,
    required String requestId,
  }) async => task('resolved');

  @override
  Stream<WorkspaceChanged> openWorkspaceHints() => Stream.fromIterable(hints);

  @override
  Future<WorkspaceSnapshot> snapshot() async {
    snapshotCalls++;
    final completer = snapshotCompleter;
    if (completer != null) return completer.future;
    if (failSnapshots) throw StateError('snapshot unavailable');
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

  @override
  Future<TaskItem> transition(
    String taskId, {
    required String targetStatus,
    required int baseStatusVersion,
    String? blockedReason,
    String? resumeHandlerId,
    String? waitingForUserId,
    required String requestId,
  }) async {
    lastRequestId = requestId;
    return task(targetStatus);
  }

  @override
  Future<Object?> addComment(
    String taskId, {
    required String body,
    required String requestId,
  }) async => null;

  @override
  Future<Object?> addDelay(
    String taskId, {
    required String newDueAt,
    required String reason,
    String? note,
    required String requestId,
  }) async => null;

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
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

  test('concurrent refresh requests share one snapshot call', () async {
    final repository = FakeSyncRepository()
      ..snapshotCompleter = Completer<WorkspaceSnapshot>();
    final controller = WorkspaceSyncController(repository);

    final first = controller.refresh();
    final second = controller.refresh();
    expect(identical(first, second), isTrue);
    expect(repository.snapshotCalls, 1);

    repository.snapshotCompleter!.complete(
      WorkspaceSnapshot(workspaceId: 'w1', cursor: 11, tasks: [task('title')]),
    );
    await Future.wait([first, second]);
    expect(controller.state.isStale, isFalse);
  });

  test('refresh failure keeps the last known good snapshot', () async {
    final repository = FakeSyncRepository();
    final controller = WorkspaceSyncController(repository);

    await controller.refresh();
    final lastKnownGood = controller.state.snapshot;
    repository.failSnapshots = true;

    await controller.refresh();

    expect(controller.state.snapshot, same(lastKnownGood));
    expect(controller.state.isStale, isTrue);
  });

  test('transition generates a UUID request id', () async {
    final repository = FakeSyncRepository();
    final controller = WorkspaceSyncController(repository);
    await controller.refresh();
    await controller.transition('task-1', 'DONE');
    expect(
      repository.lastRequestId,
      matches(
        RegExp(
          r'^[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$',
        ),
      ),
    );
  });

  test('transition refreshes the authoritative cursor after a write', () async {
    final repository = FakeSyncRepository();
    final controller = WorkspaceSyncController(repository);
    await controller.refresh();

    await controller.transition('task-1', 'DONE');

    expect(repository.requestedAfterCursors, [11]);
    expect(controller.state.cursor, 12);
    expect(controller.state.snapshot!.tasks.single.title, 'Changed title');
  });

  test('create inserts the server task then reconciles its cursor', () async {
    final repository = FakeSyncRepository();
    final controller = WorkspaceSyncController(repository);
    await controller.refresh();

    final created = await controller.create('Created title', quadrant: 'Q1');

    expect(created!.title, 'Created title');
    expect(
      repository.createRequestId,
      matches(
        RegExp(
          r'^[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$',
        ),
      ),
    );
    expect(repository.requestedAfterCursors, [11]);
    expect(controller.state.cursor, 12);
    expect(controller.state.snapshot!.tasks.single.title, 'Changed title');
    expect(controller.inFlightMutations, isEmpty);
  });
}
