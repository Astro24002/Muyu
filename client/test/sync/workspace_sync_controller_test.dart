import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:muyu_client/models/task.dart';
import 'package:muyu_client/models/workspace_change.dart';
import 'package:muyu_client/models/workspace_snapshot.dart';
import 'package:muyu_client/sync/workspace_cache.dart';
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
  final queuedChanges = <WorkspaceChanges>[];
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
    if (queuedChanges.isNotEmpty) return queuedChanges.removeAt(0);
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

class MemoryWorkspaceCache implements WorkspaceCache {
  MemoryWorkspaceCache(this.cached);

  WorkspaceSnapshot? cached;
  final writes = <WorkspaceSnapshot>[];
  String? readWorkspaceId;

  @override
  Future<WorkspaceSnapshot?> read(String workspaceId) async {
    readWorkspaceId = workspaceId;
    return cached;
  }

  @override
  Future<void> write(WorkspaceSnapshot snapshot) async {
    writes.add(snapshot);
    cached = snapshot;
  }

  @override
  Future<void> clear(String workspaceId) async {
    cached = null;
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

  test(
    'cursor changes merge task conflicts and remove resolved conflicts',
    () async {
      final repository = FakeSyncRepository();
      final controller = WorkspaceSyncController(repository);
      await controller.refresh();

      final openConflict = <String, dynamic>{
        'id': 'conflict-1',
        'task_id': 'task-1',
        'field': 'status',
        'base': 'TODO',
        'current': 'IN_PROGRESS',
        'proposed_payload': {
          'target_status': 'BLOCKED',
          'blocked_reason': '等待资料',
        },
        'status': 'OPEN',
        'base_version': 1,
        'current_version': 2,
        'current_snapshot': {
          ...task('Blocked').toJson(),
          'status': 'BLOCKED',
          'blocked_reason': '等待资料',
          'status_version': 2,
          'lifecycle_version': 2,
        },
        'field_versions': {'title': 1},
        'status_version': 2,
        'lifecycle_version': 2,
      };
      repository.queuedChanges.add(
        WorkspaceChanges(
          workspaceId: 'w1',
          cursor: 12,
          changes: [
            WorkspaceChange.taskConflict(
              cursor: 12,
              conflict: openConflict,
              action: 'created',
            ),
          ],
        ),
      );

      await controller.pull();

      expect(controller.state.cursor, 12);
      expect(controller.state.snapshot!.conflicts, hasLength(1));
      expect(controller.state.snapshot!.conflicts.single['status'], 'OPEN');
      expect(
        controller.state.snapshot!.conflicts.single['current_snapshot'],
        isA<Map<String, dynamic>>(),
      );

      repository.queuedChanges.add(
        WorkspaceChanges(
          workspaceId: 'w1',
          cursor: 13,
          changes: [
            WorkspaceChange.taskConflict(
              cursor: 13,
              conflict: {...openConflict, 'status': 'RESOLVED'},
              action: 'updated',
            ),
          ],
        ),
      );

      await controller.pull();

      expect(controller.state.cursor, 13);
      expect(controller.state.snapshot!.conflicts, isEmpty);
    },
  );

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

  test(
    'start restores a cached snapshot before replacing it with network data',
    () async {
      final cache = MemoryWorkspaceCache(
        WorkspaceSnapshot(
          workspaceId: 'w1',
          cursor: 7,
          tasks: [task('Cached title')],
        ),
      );
      final repository = FakeSyncRepository()
        ..snapshotCompleter = Completer<WorkspaceSnapshot>();
      final controller = WorkspaceSyncController(
        repository,
        cache: cache,
        workspaceId: 'w1',
      );

      final start = controller.start();
      await Future<void>.delayed(Duration.zero);

      expect(cache.readWorkspaceId, 'w1');
      expect(controller.state.snapshot?.tasks.single.title, 'Cached title');
      expect(controller.state.isStale, isTrue);
      expect(repository.snapshotCalls, 1);

      repository.snapshotCompleter!.complete(
        WorkspaceSnapshot(
          workspaceId: 'w1',
          cursor: 11,
          tasks: [task('Fresh title')],
        ),
      );
      await start;

      expect(controller.state.snapshot?.tasks.single.title, 'Fresh title');
      expect(controller.state.isStale, isFalse);
      expect(cache.writes.single.cursor, 11);
    },
  );

  test(
    'cached snapshot remains last known good when startup refresh fails',
    () async {
      final cached = WorkspaceSnapshot(
        workspaceId: 'w1',
        cursor: 7,
        tasks: [task('Last known good')],
      );
      final cache = MemoryWorkspaceCache(cached);
      final repository = FakeSyncRepository()..failSnapshots = true;
      final controller = WorkspaceSyncController(
        repository,
        cache: cache,
        workspaceId: 'w1',
      );

      await controller.start();

      expect(controller.state.snapshot?.tasks.single.title, 'Last known good');
      expect(controller.state.isStale, isTrue);
      expect(controller.state.errorMessage, contains('snapshot unavailable'));
      expect(cache.writes, isEmpty);
    },
  );
}
