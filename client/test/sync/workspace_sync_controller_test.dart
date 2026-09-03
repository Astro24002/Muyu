import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:muyu_client/core/api_client.dart';
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
  final queuedSnapshots = <WorkspaceSnapshot>[];
  Object? updateError;
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
  }) async {
    final error = updateError;
    if (error != null) throw error;
    return task(fields['title'] as String? ?? 'updated');
  }

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
    if (queuedSnapshots.isNotEmpty) return queuedSnapshots.removeAt(0);
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

  test(
    'recovers from a cursor gap, envelope mismatch, or empty-ahead response',
    () async {
      final invalidResponses = [
        WorkspaceChanges(
          workspaceId: 'w1',
          cursor: 8,
          changes: [
            WorkspaceChange.taskUpdated(
              cursor: 12,
              task: task('Skipped first'),
            ),
            WorkspaceChange.taskUpdated(
              cursor: 14,
              task: task('Skipped middle'),
            ),
          ],
        ),
        WorkspaceChanges(workspaceId: 'w1', cursor: 14, changes: const []),
        WorkspaceChanges(
          workspaceId: 'foreign',
          cursor: 12,
          changes: [
            WorkspaceChange.taskUpdated(cursor: 12, task: task('Foreign')),
          ],
        ),
      ];

      for (final invalid in invalidResponses) {
        final repository = FakeSyncRepository();
        repository.queuedSnapshots.addAll([
          WorkspaceSnapshot(
            workspaceId: 'w1',
            cursor: 11,
            tasks: [task('Initial')],
          ),
          WorkspaceSnapshot(
            workspaceId: 'w1',
            cursor: 12,
            tasks: [task('Recovered')],
          ),
        ]);
        repository.queuedChanges.add(invalid);
        final controller = WorkspaceSyncController(repository);

        await controller.refresh();
        await controller.pull();

        expect(repository.snapshotCalls, 2);
        expect(controller.state.cursor, 12);
        expect(controller.state.snapshot!.tasks.single.title, 'Recovered');
      }
    },
  );

  test(
    'recovers instead of applying a conflict resource from another workspace',
    () async {
      final repository = FakeSyncRepository();
      repository.queuedSnapshots.addAll([
        WorkspaceSnapshot(
          workspaceId: 'w1',
          cursor: 11,
          tasks: [task('Initial')],
        ),
        WorkspaceSnapshot(
          workspaceId: 'w1',
          cursor: 12,
          tasks: [task('Recovered')],
        ),
      ]);
      repository.queuedChanges.add(
        WorkspaceChanges(
          workspaceId: 'w1',
          cursor: 12,
          changes: [
            WorkspaceChange(
              cursor: 12,
              resourceType: 'task_conflict',
              resourceId: 'conflict-foreign',
              action: 'created',
              conflict: const {
                'id': 'conflict-foreign',
                'workspace_id': 'foreign',
                'task_id': 'task-1',
                'field': 'title',
                'status': 'OPEN',
              },
            ),
          ],
        ),
      );
      final controller = WorkspaceSyncController(repository);

      await controller.refresh();
      await controller.pull();

      expect(repository.snapshotCalls, 2);
      expect(controller.state.snapshot!.conflicts, isEmpty);
      expect(controller.state.cursor, 12);
    },
  );

  test('uses action-first conflict tombstone semantics for non-null deleted and null updates', () async {
    final openConflict = <String, dynamic>{
      'id': 'conflict-1',
      'workspace_id': 'w1',
      'task_id': 'task-1',
      'field': 'title',
      'status': 'OPEN',
      'current': 'Current',
      'proposed': 'Proposed',
    };
    final repository = FakeSyncRepository();
    repository.queuedSnapshots.add(
      WorkspaceSnapshot(
        workspaceId: 'w1',
        cursor: 11,
        tasks: [task('Initial')],
        conflicts: [openConflict],
      ),
    );
    repository.queuedChanges.addAll([
      WorkspaceChanges(
        workspaceId: 'w1',
        cursor: 12,
        changes: [
          WorkspaceChange(
            cursor: 12,
            resourceType: 'task_conflict',
            resourceId: 'conflict-1',
            action: 'deleted',
            conflict: openConflict,
          ),
        ],
      ),
      WorkspaceChanges(
        workspaceId: 'w1',
        cursor: 13,
        changes: [
          const WorkspaceChange(
            cursor: 13,
            resourceType: 'task_conflict',
            resourceId: 'conflict-1',
            action: 'updated',
            conflict: null,
          ),
        ],
      ),
    ]);
    final controller = WorkspaceSyncController(repository);

    await controller.refresh();
    expect(controller.state.snapshot!.conflicts, hasLength(1));
    await controller.pull();
    expect(controller.state.snapshot!.conflicts, isEmpty);
    await controller.pull();
    expect(controller.state.snapshot!.conflicts, isEmpty);
  });

  test(
    'merges a 409 conflict projection into state and reconciles its cursor',
    () async {
      final currentTask = task('Current title');
      final conflict = <String, dynamic>{
        'id': 'conflict-1',
        'workspace_id': 'w1',
        'task_id': currentTask.id,
        'field': 'title',
        'status': 'OPEN',
        'current': 'Current title',
        'proposed': 'Proposed title',
        'current_snapshot': currentTask.toJson()..['title'] = 'Current title',
      };
      final repository = FakeSyncRepository()
        ..updateError = ApiException(
          statusCode: 409,
          code: 'field_conflict',
          message: 'changed',
          details: {
            'cursor': 12,
            'conflicts': [conflict],
          },
        );
      final cache = MemoryWorkspaceCache(null);
      repository.queuedChanges.add(
        WorkspaceChanges(
          workspaceId: 'w1',
          cursor: 12,
          changes: [WorkspaceChange.taskUpdated(cursor: 12, task: currentTask)],
        ),
      );
      final controller = WorkspaceSyncController(
        repository,
        cache: cache,
        workspaceId: 'w1',
      );

      await controller.refresh();
      await controller.update('task-1', fields: {'title': 'Proposed title'});

      expect(controller.state.snapshot!.tasks.single.title, 'Current title');
      expect(controller.state.snapshot!.conflicts, hasLength(1));
      expect(controller.state.cursor, 12);
      expect(repository.requestedAfterCursors, [11]);
      expect(cache.cached?.cursor, 12);
      expect(cache.cached?.conflicts, hasLength(1));
    },
  );

  test(
    'recovers from a foreign 409 conflict projection without caching it',
    () async {
      final repository = FakeSyncRepository()
        ..updateError = ApiException(
          statusCode: 409,
          code: 'field_conflict',
          message: 'changed',
          details: {
            'cursor': 12,
            'conflicts': [
              {
                'id': 'foreign-conflict',
                'workspace_id': 'foreign-workspace',
                'task_id': 'task-1',
                'field': 'title',
                'status': 'OPEN',
              },
            ],
          },
        );
      repository.queuedSnapshots.addAll([
        WorkspaceSnapshot(
          workspaceId: 'w1',
          cursor: 11,
          tasks: [task('Initial')],
        ),
        WorkspaceSnapshot(
          workspaceId: 'w1',
          cursor: 12,
          tasks: [task('Recovered')],
        ),
      ]);
      final controller = WorkspaceSyncController(repository);

      await controller.refresh();
      await expectLater(
        controller.update('task-1', fields: {'title': 'Proposed'}),
        throwsA(isA<ApiException>()),
      );

      expect(repository.snapshotCalls, 2);
      expect(controller.state.snapshot!.tasks.single.title, 'Recovered');
      expect(controller.state.snapshot!.conflicts, isEmpty);
    },
  );

  test(
    'recovers instead of caching a conflict response with an invalid cursor',
    () async {
      final currentTask = task('Current title');
      final repository = FakeSyncRepository()
        ..updateError = ApiException(
          statusCode: 409,
          code: 'field_conflict',
          message: 'changed',
          details: {
            'cursor': 'not-a-cursor',
            'conflicts': [
              {
                'id': 'conflict-1',
                'workspace_id': 'w1',
                'task_id': currentTask.id,
                'field': 'title',
                'status': 'OPEN',
                'current_snapshot': currentTask.toJson(),
              },
            ],
          },
        );
      repository.queuedSnapshots.addAll([
        WorkspaceSnapshot(
          workspaceId: 'w1',
          cursor: 11,
          tasks: [task('Initial')],
        ),
        WorkspaceSnapshot(
          workspaceId: 'w1',
          cursor: 12,
          tasks: [task('Recovered')],
        ),
      ]);
      final controller = WorkspaceSyncController(repository);

      await controller.refresh();
      await expectLater(
        controller.update('task-1', fields: {'title': 'Proposed'}),
        throwsA(isA<ApiException>()),
      );

      expect(repository.snapshotCalls, 2);
      expect(controller.state.snapshot!.tasks.single.title, 'Recovered');
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
