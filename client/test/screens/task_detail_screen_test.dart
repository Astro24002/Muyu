import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:muyu_client/models/classification.dart';
import 'package:muyu_client/models/task.dart';
import 'package:muyu_client/models/workspace_change.dart';
import 'package:muyu_client/models/workspace_snapshot.dart';
import 'package:muyu_client/screens/task_detail_screen.dart';
import 'package:muyu_client/sync/workspace_sync_controller.dart';
import 'package:muyu_client/sync/workspace_sync_repository.dart';

const detailClassification = WorkspaceClassification(
  id: 'classification-work',
  workspaceId: 'w1',
  name: '工作',
  createdBy: 'user-1',
);

TaskItem detailTask({
  String status = 'TODO',
  String currentHandlerId = 'user-1',
  String? resumeHandlerId,
  DateTime? dueAt,
  List<String> labels = const ['工作'],
}) => TaskItem(
  id: 'task-1',
  parentTaskId: null,
  title: 'Original',
  description: 'Description',
  status: status,
  currentHandlerId: currentHandlerId,
  quadrant: 'Q1',
  plannedStartAt: null,
  dueAt: dueAt,
  estimatedMinutes: null,
  completedAt: null,
  createdBy: 'user-1',
  version: 3,
  statusVersion: 7,
  createdAt: DateTime.utc(2026, 8, 27),
  updatedAt: DateTime.utc(2026, 8, 27),
  labels: labels,
  fieldVersions: const {'title': 3, 'description': 2},
  resumeHandlerId: resumeHandlerId,
);

class RecordingRepository implements WorkspaceSyncRepository {
  String? transitionedTo;
  String? transitionReviewContent;
  String? transitionResumeHandlerId;
  int? transitionBaseVersion;
  String? comment;
  String? delayReason;
  String? resolvedConflict;
  Map<String, Object?>? updatedFields;
  List<TaskActivity> activityItems = const [];
  bool failActivity = false;

  @override
  Future<WorkspaceSnapshot> snapshot() async => WorkspaceSnapshot(
    workspaceId: 'w1',
    cursor: 1,
    tasks: [detailTask()],
    members: const [
      {'user_id': 'user-1', 'display_name': '15028180169'},
      {'user_id': 'user-2', 'display_name': '小雨'},
    ],
    classifications: const [detailClassification],
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
    required String quadrant,
    List<String> labels = const [],
    String? description,
    String? nextStepText,
    String? dueAt,
    String? parentTaskId,
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
  }) async {
    updatedFields = fields;
    return detailTask();
  }

  @override
  Future<TaskItem> transition(
    String taskId, {
    required String targetStatus,
    required int baseStatusVersion,
    String? blockedReason,
    String? resumeHandlerId,
    String? waitingForUserId,
    String? reviewRejectionReason,
    String? reviewContent,
    required String requestId,
  }) async {
    transitionedTo = targetStatus;
    transitionReviewContent = reviewContent;
    transitionBaseVersion = baseStatusVersion;
    transitionResumeHandlerId = resumeHandlerId;
    return detailTask(status: targetStatus);
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
  Future<List<TaskActivity>> activity(String taskId) async {
    if (failActivity) throw StateError('activity unavailable');
    return activityItems;
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

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  testWidgets('shows member usernames in the handler selector', (tester) async {
    final repository = RecordingRepository();
    final sync = WorkspaceSyncController(repository);
    await sync.refresh();

    await tester.pumpWidget(
      MaterialApp(
        home: TaskDetailScreen(task: detailTask(), sync: sync),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('task-save-button')));
    await tester.pump();

    final listState = tester.state<ScrollableState>(
      find.byType(Scrollable).first,
    );
    listState.position.jumpTo(listState.position.maxScrollExtent);
    await tester.pump();
    await tester.ensureVisible(find.byKey(const Key('task-handler-select')));
    await tester.pump();
    await tester.tap(find.byKey(const Key('task-handler-select')));
    await tester.pumpAndSettle();

    expect(find.text('15028180169'), findsWidgets);
    expect(find.text('小雨'), findsOneWidget);
    expect(find.text('user-1'), findsNothing);
  });

  testWidgets(
    'shows the server-provided next step in the compact detail block',
    (tester) async {
      final task = detailTask().copyWith(
        nextStep: const MomentNextStep(
          kind: 'CONTINUE_TASK',
          label: '继续处理任务',
          canAct: true,
          actions: ['SUBMIT_REVIEW'],
        ),
      );
      final sync = WorkspaceSyncController.unavailable();
      sync.state = WorkspaceSyncState(
        snapshot: WorkspaceSnapshot(
          workspaceId: 'w1',
          cursor: 1,
          viewerUserId: 'user-1',
          tasks: [task],
        ),
        isStale: false,
      );

      await tester.pumpWidget(
        MaterialApp(
          home: TaskDetailScreen(task: task, sync: sync),
        ),
      );

      expect(find.byKey(const Key('task-next-step')), findsOneWidget);
      expect(find.byKey(const Key('task-next-step-label')), findsOneWidget);
      expect(find.text('继续处理任务'), findsOneWidget);
    },
  );

  testWidgets('requires a transfer note before changing the handler', (
    tester,
  ) async {
    final repository = RecordingRepository();
    final sync = WorkspaceSyncController(repository);
    await sync.refresh();
    await tester.pumpWidget(
      MaterialApp(
        home: TaskDetailScreen(task: detailTask(), sync: sync),
      ),
    );
    await tester.tap(find.byKey(const Key('task-save-button')));
    await tester.pump();
    final listState = tester.state<ScrollableState>(
      find.byType(Scrollable).first,
    );
    listState.position.jumpTo(listState.position.maxScrollExtent);
    await tester.pump();
    await tester.ensureVisible(find.byKey(const Key('task-handler-select')));
    await tester.pump();
    await tester.tap(find.byKey(const Key('task-handler-select')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('小雨').last);
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('transfer-note-input')), findsOneWidget);
    await tester.tap(find.byKey(const Key('transfer-note-submit')));
    await tester.pump();
    expect(find.text('请填写交接说明'), findsOneWidget);

    await tester.enterText(
      find.byKey(const Key('transfer-note-input')),
      '请继续跟进合同',
    );
    await tester.tap(find.byKey(const Key('transfer-note-submit')));
    await tester.pumpAndSettle();

    expect(repository.updatedFields, {
      'current_handler_id': 'user-2',
      'transfer_note': '请继续跟进合同',
    });
  });

  testWidgets('shows activity evidence with operator and timestamp', (
    tester,
  ) async {
    final repository = RecordingRepository();
    repository.activityItems = [
      TaskActivity(
        id: 'activity-1',
        action: 'APPROVAL_REJECTED',
        eventType: 'APPROVAL_REJECTED',
        actorUserId: 'user-2',
        before: null,
        after: null,
        payload: const {
          'approval_request': {
            'proposed_changes': {
              'transfer_note': '请继续跟进客户',
              'review_content': '已完成验收清单',
            },
            'rejection_reason': '请补充截图',
          },
          'reason': '请补充截图',
        },
        createdAt: DateTime.utc(2026, 9, 1, 2, 3),
      ),
    ];
    final task = detailTask();
    final sync = WorkspaceSyncController(repository);
    sync.state = WorkspaceSyncState(
      snapshot: WorkspaceSnapshot(
        workspaceId: 'w1',
        cursor: 1,
        viewerUserId: 'user-1',
        tasks: [task],
        members: const [
          {'user_id': 'user-1', 'display_name': '我'},
          {'user_id': 'user-2', 'display_name': '小雨'},
        ],
      ),
      isStale: false,
    );

    await tester.pumpWidget(
      MaterialApp(
        home: TaskDetailScreen(task: task, sync: sync),
      ),
    );
    await tester.pumpAndSettle();
    await tester.ensureVisible(
      find.byKey(const Key('task-activity-activity-1')),
    );

    expect(find.byKey(const Key('task-activity-section')), findsOneWidget);
    expect(find.text('负责人变更被拒绝'), findsOneWidget);
    expect(find.text('小雨'), findsOneWidget);
    expect(find.text('交接说明：请继续跟进客户'), findsOneWidget);
    expect(find.text('验收内容：已完成验收清单'), findsOneWidget);
    expect(find.text('退回原因：请补充截图'), findsOneWidget);
  });

  testWidgets('keeps task details when activity loading fails', (tester) async {
    final repository = RecordingRepository()..failActivity = true;
    final task = detailTask();
    final sync = WorkspaceSyncController(repository);
    sync.state = WorkspaceSyncState(
      snapshot: WorkspaceSnapshot(
        workspaceId: 'w1',
        cursor: 1,
        viewerUserId: 'user-1',
        tasks: [task],
      ),
      isStale: false,
    );

    await tester.pumpWidget(
      MaterialApp(
        home: TaskDetailScreen(task: task, sync: sync),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('task-detail-card')), findsOneWidget);
    expect(find.text('Original'), findsOneWidget);
    expect(find.byKey(const Key('task-activity-section')), findsOneWidget);
  });

  testWidgets('submits review content through the compatible transition path', (
    tester,
  ) async {
    final task = detailTask(status: 'IN_PROGRESS');
    final repository = RecordingRepository();
    final sync = WorkspaceSyncController(repository);
    sync.state = WorkspaceSyncState(
      snapshot: WorkspaceSnapshot(
        workspaceId: 'w1',
        cursor: 1,
        viewerUserId: 'user-1',
        tasks: [task],
        members: const [
          {'user_id': 'user-1', 'display_name': '我'},
          {'user_id': 'user-2', 'display_name': '小雨'},
        ],
      ),
      isStale: false,
    );

    await tester.pumpWidget(
      MaterialApp(
        home: TaskDetailScreen(task: task, sync: sync),
      ),
    );
    await tester.drag(find.byType(ListView), const Offset(0, -260));
    await tester.pump();
    await tester.ensureVisible(find.byKey(const Key('task-status-review')));
    await tester.tap(find.byKey(const Key('task-status-review')));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('review-content-input')), findsOneWidget);
    await tester.tap(find.byKey(const Key('review-submit-confirm')));
    await tester.pump();
    expect(find.text('请填写验收内容'), findsOneWidget);

    await tester.enterText(
      find.byKey(const Key('review-content-input')),
      '已完成清单并附上截图',
    );
    await tester.tap(find.byKey(const Key('review-submit-confirm')));
    await tester.pumpAndSettle();

    expect(repository.transitionedTo, 'REVIEW');
    expect(repository.transitionReviewContent, '已完成清单并附上截图');
  });

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
      await tester.tap(find.byKey(const Key('task-save-button')));
      await tester.pump();

      await tester.drag(find.byType(ListView), const Offset(0, -500));
      await tester.pump();
      await tester.ensureVisible(
        find.byKey(const Key('task-status-in_progress')),
      );
      await tester.pump();
      await tester.ensureVisible(
        find.byKey(const Key('task-status-in_progress')),
      );
      await tester.tap(find.byKey(const Key('task-status-in_progress')));
      await tester.pumpAndSettle();
      expect(repository.transitionedTo, 'IN_PROGRESS');
      expect(repository.transitionBaseVersion, 7);

      await tester.ensureVisible(find.byKey(const Key('task-comment-input')));
      await tester.enterText(
        find.byKey(const Key('task-comment-input')),
        'done',
      );
      await tester.tap(find.byKey(const Key('task-comment-submit')));
      await tester.pumpAndSettle();
      expect(repository.comment, 'done');

      await tester.ensureVisible(
        find.byKey(const Key('task-detail-estimated-minutes')),
      );
      await tester.enterText(
        find.byKey(const Key('task-detail-estimated-minutes')),
        '45',
      );
      expect(find.byType(FilterChip), findsNothing);
      await tester.ensureVisible(find.byKey(const Key('task-save-button')));
      await tester.tap(find.byKey(const Key('task-save-button')));
      await tester.pumpAndSettle();
      expect(repository.updatedFields?['estimated_minutes'], 45);
      expect(repository.updatedFields, isNot(contains('assignee_ids')));

      expect(
        find.byKey(const Key('resolve-conflict-conflict-1')),
        findsOneWidget,
      );
    },
  );

  testWidgets('does not allow an existing task deadline to be cleared', (
    tester,
  ) async {
    final task = detailTask(dueAt: DateTime.utc(2026, 9, 10, 18));
    final repository = RecordingRepository();
    final sync = WorkspaceSyncController(repository);
    sync.state = WorkspaceSyncState(
      snapshot: WorkspaceSnapshot(
        workspaceId: 'w1',
        cursor: 1,
        viewerUserId: 'user-1',
        tasks: [task],
        members: const [
          {'user_id': 'user-1'},
          {'user_id': 'user-2'},
        ],
        classifications: const [detailClassification],
      ),
      isStale: false,
    );

    await tester.pumpWidget(
      MaterialApp(
        home: TaskDetailScreen(task: task, sync: sync),
      ),
    );
    await tester.tap(find.byKey(const Key('task-save-button')));
    await tester.pump();
    await tester.ensureVisible(find.byKey(const Key('task-detail-due-at')));
    await tester.enterText(find.byKey(const Key('task-detail-due-at')), '');
    await tester.ensureVisible(find.byKey(const Key('task-save-button')));
    await tester.tap(find.byKey(const Key('task-save-button')));
    await tester.pumpAndSettle();

    expect(repository.updatedFields, isNull);
    expect(
      find.byKey(const Key('task-form-error'), skipOffstage: false),
      findsOneWidget,
    );
    expect(
      tester
          .widget<Text>(
            find.byKey(const Key('task-form-error'), skipOffstage: false),
          )
          .data,
      '截止时间不能为空，请选择截止时间',
    );
  });

  testWidgets('allows a legacy unclassified task to edit an unrelated field', (
    tester,
  ) async {
    final task = detailTask(labels: const []);
    final repository = RecordingRepository();
    final sync = WorkspaceSyncController(repository);
    sync.state = WorkspaceSyncState(
      snapshot: WorkspaceSnapshot(
        workspaceId: 'w1',
        cursor: 1,
        viewerUserId: 'user-1',
        tasks: [task],
        members: const [
          {'user_id': 'user-1'},
          {'user_id': 'user-2'},
        ],
      ),
      isStale: false,
    );

    await tester.pumpWidget(
      MaterialApp(
        home: TaskDetailScreen(task: task, sync: sync),
      ),
    );
    await tester.tap(find.byKey(const Key('task-save-button')));
    await tester.pump();
    await tester.enterText(
      find.byKey(const Key('task-detail-title')),
      'Legacy title',
    );
    await tester.tap(find.byKey(const Key('task-save-button')));
    await tester.pumpAndSettle();

    expect(repository.updatedFields?['title'], 'Legacy title');
    expect(repository.updatedFields, isNot(contains('labels')));
  });

  testWidgets('keeps a revoked current handler visible but disabled', (
    tester,
  ) async {
    final task = detailTask(currentHandlerId: 'revoked-user');
    final sync = WorkspaceSyncController.unavailable();
    sync.state = WorkspaceSyncState(
      snapshot: WorkspaceSnapshot(
        workspaceId: 'w1',
        cursor: 1,
        viewerUserId: 'user-1',
        tasks: [task],
        members: const [
          {'user_id': 'user-1'},
          {'user_id': 'user-2'},
          {'user_id': 'revoked-user', 'membership_status': 'REVOKED'},
        ],
        classifications: const [detailClassification],
      ),
      isStale: false,
    );

    await tester.pumpWidget(
      MaterialApp(
        home: TaskDetailScreen(task: task, sync: sync),
      ),
    );
    await tester.tap(find.byKey(const Key('task-save-button')));
    await tester.pump();
    final listState = tester.state<ScrollableState>(
      find.byType(Scrollable).first,
    );
    listState.position.jumpTo(listState.position.maxScrollExtent);
    await tester.pump();
    await tester.ensureVisible(find.byKey(const Key('task-handler-select')));
    await tester.pump();

    final select = tester.widget<DropdownButton<String>>(
      find.descendant(
        of: find.byKey(const Key('task-handler-select')),
        matching: find.byType(DropdownButton<String>),
      ),
    );
    final revoked = select.items!.singleWhere(
      (item) => item.value == 'revoked-user',
    );
    expect(revoked.enabled, isFalse);
    expect(find.text('协作成员'), findsOneWidget);
  });

  testWidgets('does not submit a stale resume handler during recovery', (
    tester,
  ) async {
    final task = detailTask(status: 'BLOCKED', resumeHandlerId: 'revoked-user');
    final repository = RecordingRepository();
    final sync = WorkspaceSyncController(repository);
    sync.state = WorkspaceSyncState(
      snapshot: WorkspaceSnapshot(
        workspaceId: 'w1',
        cursor: 1,
        viewerUserId: 'user-1',
        tasks: [task],
        members: const [
          {'user_id': 'user-1'},
          {'user_id': 'user-2'},
          {'user_id': 'revoked-user', 'membership_status': 'REVOKED'},
        ],
        classifications: const [detailClassification],
      ),
      isStale: false,
    );

    await tester.pumpWidget(
      MaterialApp(
        home: TaskDetailScreen(task: task, sync: sync),
      ),
    );
    await tester.drag(find.byType(ListView), const Offset(0, -500));
    await tester.pump();
    await tester.ensureVisible(
      find.byKey(const Key('task-status-in_progress')),
    );
    await tester.tap(find.byKey(const Key('task-status-in_progress')));
    await tester.pump();
    await tester.drag(find.byType(ListView), const Offset(0, 500));
    await tester.pump();

    expect(repository.transitionedTo, isNull);
    expect(find.text('恢复负责人已不可用，请选择有效成员'), findsOneWidget);
  });
}
