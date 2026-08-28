import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:muyu_client/auth/mobile_session_store.dart';
import 'package:muyu_client/core/api_client.dart';
import 'package:muyu_client/models/task.dart';
import 'package:muyu_client/models/user.dart';
import 'package:muyu_client/models/workspace_change.dart';
import 'package:muyu_client/models/workspace_snapshot.dart';
import 'package:muyu_client/screens/cloud_workspace_screen.dart';
import 'package:muyu_client/screens/my_profile_screen.dart';
import 'package:muyu_client/sync/workspace_sync_controller.dart';
import 'package:muyu_client/sync/workspace_sync_repository.dart';

TaskItem task(String id, String title) => TaskItem(
  id: id,
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
  createdAt: DateTime.utc(2026, 8, 27),
  updatedAt: DateTime.utc(2026, 8, 27),
  assigneeIds: const ['user-1'],
);

class FakeTaskRepository implements WorkspaceSyncRepository {
  FakeTaskRepository({this.failCreate = false, this.createCompleter});

  bool failCreate;
  final Completer<void>? createCompleter;
  final List<TaskItem> tasks = [];
  String? lastTitle;

  @override
  Future<WorkspaceSnapshot> snapshot() async => WorkspaceSnapshot(
    workspaceId: 'w1',
    cursor: 1,
    tasks: List.of(tasks),
    members: const [
      {'user_id': 'user-1'},
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
  }) async {
    lastTitle = title;
    if (createCompleter != null) await createCompleter!.future;
    if (failCreate) throw Exception('create failed');
    final created = task('task-${tasks.length + 1}', title);
    tasks.add(created);
    return created;
  }

  @override
  Future<TaskItem?> update(
    String taskId, {
    required Map<String, Object?> fields,
    required Map<String, int> fieldVersions,
    required String requestId,
  }) async => task(taskId, fields['title'] as String? ?? 'updated');

  @override
  Future<TaskItem> transition(
    String taskId, {
    required String targetStatus,
    required int baseStatusVersion,
    String? blockedReason,
    String? resumeHandlerId,
    String? waitingForUserId,
    required String requestId,
  }) async => task(taskId, targetStatus);

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
  Future<TaskItem> resolveConflict(
    String taskId,
    String conflictId, {
    required String resolution,
    required String requestId,
  }) async => task(taskId, 'resolved');

  @override
  Stream<WorkspaceChanged> openWorkspaceHints() => const Stream.empty();
}

ApiClient testApi() => ApiClient(
  baseUrl: 'https://api.example',
  httpClient: MockClient((_) async => http.Response(jsonEncode({}), 200)),
);

Future<WorkspaceSyncController> readyController(FakeTaskRepository repo) async {
  final controller = WorkspaceSyncController(repo);
  await controller.refresh();
  return controller;
}

void main() {
  const loggedInSession = MobileSession(
    accessToken: 'access',
    refreshToken: 'refresh',
    deviceId: 'device-1',
    user: User(
      id: 'user-1',
      phone: '+8613800138000',
      nickname: 'Muyu',
      avatarKey: '',
      role: 'member',
    ),
    expiresAt: null,
  );

  testWidgets('workspace opens the My page for a logged-in device', (
    tester,
  ) async {
    final sync = await readyController(FakeTaskRepository());
    await tester.pumpWidget(
      MaterialApp(
        home: CloudWorkspaceScreen(
          api: testApi(),
          syncController: sync,
          session: loggedInSession,
        ),
      ),
    );

    await tester.tap(find.byTooltip('我的'));
    await tester.pumpAndSettle();

    expect(find.byType(MyProfileScreen), findsOneWidget);
    expect(find.text('我的'), findsOneWidget);
  });

  testWidgets('title-only creation is available and successful task appears', (
    tester,
  ) async {
    final repo = FakeTaskRepository();
    final sync = await readyController(repo);
    await tester.pumpWidget(
      MaterialApp(
        home: CloudWorkspaceScreen(api: testApi(), syncController: sync),
      ),
    );
    await tester.enterText(
      find.byKey(const Key('task-title-input')),
      'Buy milk',
    );
    await tester.pump();
    await tester.tap(find.byKey(const Key('create-task-button')));
    await tester.pumpAndSettle();

    expect(repo.lastTitle, 'Buy milk');
    expect(find.text('Buy milk'), findsOneWidget);
  });

  testWidgets(
    'submit is disabled while creation is pending and errors retain input',
    (tester) async {
      final pending = Completer<void>();
      final repo = FakeTaskRepository(
        failCreate: true,
        createCompleter: pending,
      );
      final sync = await readyController(repo);
      await tester.pumpWidget(
        MaterialApp(
          home: CloudWorkspaceScreen(api: testApi(), syncController: sync),
        ),
      );
      await tester.enterText(
        find.byKey(const Key('task-title-input')),
        'Keep me',
      );
      await tester.pump();
      await tester.tap(find.byKey(const Key('create-task-button')));
      await tester.pump();
      expect(find.byKey(const Key('create-task-button')), findsOneWidget);
      expect(
        tester
            .widget<IconButton>(find.byKey(const Key('create-task-button')))
            .onPressed,
        isNull,
      );
      pending.complete();
      await tester.pumpAndSettle();

      expect(find.text('Keep me'), findsOneWidget);
      expect(find.textContaining('create failed'), findsAtLeastNWidgets(1));
    },
  );

  testWidgets('unverified device can read but cannot use task write controls', (
    tester,
  ) async {
    final repo = FakeTaskRepository()..tasks.add(task('task-1', 'Read only'));
    final sync = await readyController(repo);
    await tester.pumpWidget(
      MaterialApp(
        home: CloudWorkspaceScreen(
          api: testApi(),
          syncController: sync,
          canWrite: false,
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('read-only-device-banner')), findsOneWidget);
    expect(
      tester
          .widget<TextField>(find.byKey(const Key('task-title-input')))
          .enabled,
      isFalse,
    );
    expect(
      tester
          .widget<IconButton>(find.byKey(const Key('create-task-button')))
          .onPressed,
      isNull,
    );

    await tester.tap(find.text('Read only'));
    await tester.pumpAndSettle();

    expect(
      tester
          .widget<TextField>(find.byKey(const Key('task-detail-title')))
          .enabled,
      isFalse,
    );
    expect(
      tester
          .widget<IconButton>(find.byKey(const Key('task-save-button')))
          .onPressed,
      isNull,
    );
    await tester.drag(find.byType(ListView).last, const Offset(0, -500));
    await tester.pumpAndSettle();
    expect(
      tester
          .widget<TextField>(find.byKey(const Key('task-comment-input')))
          .enabled,
      isFalse,
    );
    expect(
      tester
          .widget<OutlinedButton>(find.byKey(const Key('task-delay-button')))
          .onPressed,
      isNull,
    );
  });
}
