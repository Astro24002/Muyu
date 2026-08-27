import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:muyu_client/models/task.dart';
import 'package:muyu_client/models/workspace_change.dart';
import 'package:muyu_client/models/workspace_snapshot.dart';
import 'package:muyu_client/screens/task_detail_screen.dart';
import 'package:muyu_client/sync/workspace_sync_controller.dart';
import 'package:muyu_client/sync/workspace_sync_repository.dart';

TaskItem detailTask() => TaskItem(
  id: 'task-1',
  parentTaskId: null,
  title: 'Original',
  description: 'Description',
  status: 'TODO',
  currentHandlerId: 'user-1',
  plannedStartAt: null,
  dueAt: null,
  estimatedMinutes: null,
  completedAt: null,
  createdBy: 'user-1',
  version: 3,
  statusVersion: 7,
  createdAt: DateTime.utc(2026, 8, 27),
  updatedAt: DateTime.utc(2026, 8, 27),
  assigneeIds: const ['user-1', 'user-2'],
  fieldVersions: const {'title': 3, 'description': 2},
);

class RecordingRepository implements WorkspaceSyncRepository {
  String? transitionedTo;
  int? transitionBaseVersion;
  String? comment;
  String? delayReason;
  String? resolvedConflict;

  @override
  Future<WorkspaceSnapshot> snapshot() async => WorkspaceSnapshot(
    workspaceId: 'w1',
    cursor: 1,
    tasks: [detailTask()],
    conflicts: const [
      {'id': 'conflict-1', 'task_id': 'task-1', 'status': 'OPEN'},
    ],
  );

  @override
  Future<WorkspaceChanges> changes({required int afterCursor}) async =>
      WorkspaceChanges(
        workspaceId: 'w1',
        cursor: afterCursor,
        changes: const [],
      );

  @override
  Future<TaskItem> create({
    required String title,
    String? description,
    String? dueAt,
    String? parentTaskId,
    List<String>? assigneeIds,
    String? plannedStartAt,
    int? estimatedMinutes,
    required String requestId,
  }) => throw UnimplementedError();

  @override
  Future<TaskItem?> update(
    String taskId, {
    required Map<String, Object?> fields,
    required Map<String, int> fieldVersions,
    required String requestId,
  }) async => detailTask();

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
    transitionedTo = targetStatus;
    transitionBaseVersion = baseStatusVersion;
    return detailTask().copyWith(status: targetStatus);
  }

  @override
  Future<Object?> addComment(
    String taskId, {
    required String body,
    required String requestId,
  }) async {
    comment = body;
    return null;
  }

  @override
  Future<Object?> addDelay(
    String taskId, {
    required String newDueAt,
    required String reason,
    String? note,
    required String requestId,
  }) async {
    delayReason = reason;
    return null;
  }

  @override
  Future<TaskItem> resolveConflict(
    String taskId,
    String conflictId, {
    required String resolution,
    required String requestId,
  }) async {
    resolvedConflict = resolution;
    return detailTask();
  }

  @override
  Stream<WorkspaceChanged> openWorkspaceHints() => const Stream.empty();
}

void main() {
  testWidgets(
    'detail actions use current status version and expose comment/conflict controls',
    (tester) async {
      final repository = RecordingRepository();
      final sync = WorkspaceSyncController(repository);
      await sync.refresh();
      await tester.pumpWidget(
        MaterialApp(
          home: TaskDetailScreen(task: detailTask(), sync: sync),
        ),
      );

      await tester.tap(find.byKey(const Key('task-status-done')));
      await tester.pumpAndSettle();
      expect(repository.transitionedTo, 'DONE');
      expect(repository.transitionBaseVersion, 7);

      await tester.enterText(
        find.byKey(const Key('task-comment-input')),
        'done',
      );
      await tester.tap(find.byKey(const Key('task-comment-submit')));
      await tester.pumpAndSettle();
      expect(repository.comment, 'done');

      expect(
        find.byKey(const Key('resolve-conflict-conflict-1')),
        findsOneWidget,
      );
    },
  );
}
