import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:muyu_client/core/api_client.dart';
import 'package:muyu_client/models/task.dart';
import 'package:muyu_client/models/task_approval_request.dart';
import 'package:muyu_client/models/workspace_change.dart';
import 'package:muyu_client/models/workspace_snapshot.dart';
import 'package:muyu_client/screens/cloud_workspace_screen.dart';
import 'package:muyu_client/screens/task_detail_screen.dart';
import 'package:muyu_client/sync/workspace_sync_controller.dart';
import 'package:muyu_client/sync/workspace_sync_repository.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

TaskItem sampleTask({String quadrant = 'Q1', List<String> labels = const []}) =>
    TaskItem(
      id: 'task-1',
      parentTaskId: null,
      title: 'Original',
      description: '',
      status: 'TODO',
      currentHandlerId: 'user-1',
      quadrant: quadrant,
      labels: labels,
      plannedStartAt: null,
      dueAt: null,
      estimatedMinutes: null,
      completedAt: null,
      createdBy: 'user-1',
      version: 1,
      statusVersion: 1,
      createdAt: DateTime.utc(2026, 8, 31),
      updatedAt: DateTime.utc(2026, 8, 31),
      assigneeIds: const ['user-1'],
    );

class LabelRecordingRepository implements WorkspaceSyncRepository {
  LabelRecordingRepository({this.tasks = const [], this.pendingUpdate = false});

  final List<TaskItem> tasks;
  final bool pendingUpdate;
  String? createdQuadrant;
  List<String>? createdLabels;
  Map<String, Object?>? updatedFields;

  @override
  Future<WorkspaceSnapshot> snapshot() async => WorkspaceSnapshot(
    workspaceId: 'workspace-1',
    cursor: 1,
    viewerUserId: 'user-1',
    tasks: tasks,
  );

  @override
  Future<WorkspaceChanges> changes({required int afterCursor}) async =>
      WorkspaceChanges(
        workspaceId: 'workspace-1',
        cursor: afterCursor,
        changes: const [],
      );

  @override
  Future<TaskItem> create({
    required String title,
    required String quadrant,
    List<String> labels = const [],
    String? description,
    String? dueAt,
    String? parentTaskId,
    List<String>? assigneeIds,
    String? plannedStartAt,
    int? estimatedMinutes,
    required String requestId,
  }) async {
    createdQuadrant = quadrant;
    createdLabels = labels;
    return sampleTask().copyWith(
      title: title,
      quadrant: quadrant,
      labels: labels,
    );
  }

  @override
  Future<TaskMutationResult?> update(
    String taskId, {
    required Map<String, Object?> fields,
    required Map<String, int> fieldVersions,
    required String requestId,
  }) async {
    updatedFields = fields;
    if (pendingUpdate) {
      return PendingApproval(
        approvalRequest: TaskApprovalRequest.fromJson({
          'id': 'approval-1',
          'workspace_id': 'workspace-1',
          'task_id': taskId,
          'comment_id': null,
          'requester_id': 'user-1',
          'approver_id': 'owner-1',
          'request_type': 'TASK_UPDATE',
          'proposed_changes': fields,
          'base_field_versions': fieldVersions,
          'request_id': requestId,
          'status': 'PENDING',
          'created_at': '2026-08-31T00:00:00Z',
          'reviewed_at': null,
          'reviewed_by': null,
          'rejection_reason': null,
          'resolved_cursor': null,
        }),
      );
    }
    return sampleTask(
      quadrant: fields['quadrant'] as String? ?? 'Q1',
      labels:
          (fields['labels'] as List<Object?>?)?.whereType<String>().toList() ??
          const [],
    );
  }

  @override
  Stream<WorkspaceChanged> openWorkspaceHints() => const Stream.empty();

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

ApiClient testApi() => ApiClient(
  baseUrl: 'https://api.example',
  httpClient: MockClient((_) async => http.Response('{}', 200)),
);

void main() {
  testWidgets('creation requires a quadrant and sends all labels', (
    tester,
  ) async {
    final repository = LabelRecordingRepository();
    final sync = WorkspaceSyncController(repository);
    await sync.refresh();
    await tester.pumpWidget(
      MaterialApp(
        home: CloudWorkspaceScreen(api: testApi(), syncController: sync),
      ),
    );

    await tester.enterText(find.byKey(const Key('task-title-input')), 'Plan');
    await tester.pump();
    expect(
      tester
          .widget<IconButton>(find.byKey(const Key('create-task-button')))
          .onPressed,
      isNull,
    );

    await tester.tap(find.byKey(const Key('task-create-quadrant-select')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Q2 重要不紧急').last);
    await tester.enterText(
      find.byKey(const Key('task-create-label-input')),
      '工作',
    );
    await tester.tap(find.byKey(const Key('task-create-label-add')));
    await tester.enterText(
      find.byKey(const Key('task-create-label-input')),
      '婚礼',
    );
    await tester.tap(find.byKey(const Key('task-create-label-add')));
    await tester.tap(find.byKey(const Key('create-task-button')));
    await tester.pumpAndSettle();

    expect(repository.createdQuadrant, 'Q2');
    expect(repository.createdLabels, ['工作', '婚礼']);
  });

  testWidgets('detail deduplicates labels and submits the complete remainder', (
    tester,
  ) async {
    final repository = LabelRecordingRepository(
      tasks: [
        sampleTask(labels: const ['工作', '工作', '婚礼']),
      ],
    );
    final sync = WorkspaceSyncController(repository);
    await sync.refresh();
    await tester.pumpWidget(
      MaterialApp(
        home: TaskDetailScreen(
          task: sampleTask(labels: const ['工作', '工作', '婚礼']),
          sync: sync,
        ),
      ),
    );

    expect(find.byKey(const Key('task-label-chip-工作')), findsOneWidget);
    expect(find.byKey(const Key('task-label-chip-婚礼')), findsOneWidget);
    await tester.tap(find.byKey(const Key('task-label-remove-工作')));
    await tester.enterText(
      find.byKey(const Key('task-detail-label-input')),
      '党员',
    );
    await tester.tap(find.byKey(const Key('task-detail-label-add')));
    await tester.tap(find.byKey(const Key('task-save-button')));
    await tester.pumpAndSettle();

    expect(repository.updatedFields?['labels'], ['婚礼', '党员']);
  });

  testWidgets('pending quadrant edit keeps the current task visible', (
    tester,
  ) async {
    final repository = LabelRecordingRepository(
      tasks: [sampleTask()],
      pendingUpdate: true,
    );
    final sync = WorkspaceSyncController(repository);
    await sync.refresh();
    await tester.pumpWidget(
      MaterialApp(
        home: TaskDetailScreen(task: sampleTask(), sync: sync),
      ),
    );

    await tester.tap(find.byKey(const Key('task-quadrant-select')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Q2 重要不紧急').last);
    await tester.pump();
    await tester.tap(find.byKey(const Key('task-save-button')));
    await tester.pumpAndSettle();

    expect(repository.updatedFields?['quadrant'], 'Q2');
    expect(sync.state.snapshot!.tasks.single.quadrant, 'Q1');
    expect(find.byKey(const Key('task-pending-approval')), findsOneWidget);
    expect(find.text('Original'), findsWidgets);
  });
}
