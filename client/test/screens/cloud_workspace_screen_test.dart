import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:muyu_client/auth/mobile_session_store.dart';
import 'package:muyu_client/core/api_client.dart';
import 'package:muyu_client/models/task.dart';
import 'package:muyu_client/models/task_overview.dart';
import 'package:muyu_client/models/user.dart';
import 'package:muyu_client/models/workspace_change.dart';
import 'package:muyu_client/models/workspace_snapshot.dart';
import 'package:muyu_client/platform/device_signing_key.dart';
import 'package:muyu_client/screens/cloud_workspace_screen.dart';
import 'package:muyu_client/screens/my_profile_screen.dart';
import 'package:muyu_client/sync/workspace_sync_controller.dart';
import 'package:muyu_client/sync/workspace_sync_repository.dart';
import 'package:muyu_client/workspace/device_authorization_repository.dart';

TaskItem task(
  String id,
  String title, {
  String status = 'TODO',
  String currentHandlerId = 'user-1',
  DateTime? dueAt,
  List<String> labels = const [],
  String? parentTaskId,
  int delayCount = 0,
  int totalDelayMinutes = 0,
}) => TaskItem(
  id: id,
  parentTaskId: parentTaskId,
  title: title,
  description: '',
  status: status,
  currentHandlerId: currentHandlerId,
  quadrant: 'Q1',
  plannedStartAt: null,
  dueAt: dueAt,
  estimatedMinutes: null,
  completedAt: null,
  createdBy: 'user-1',
  version: 1,
  statusVersion: 1,
  createdAt: DateTime.utc(2026, 8, 27),
  updatedAt: DateTime.utc(2026, 8, 27),
  labels: labels,
  delayCount: delayCount,
  totalDelayMinutes: totalDelayMinutes,
);

class FakeTaskRepository implements WorkspaceSyncRepository {
  FakeTaskRepository({this.failCreate = false, this.createCompleter});

  bool failCreate;
  final Completer<void>? createCompleter;
  final List<TaskItem> tasks = [];
  String? lastTitle;
  String? lastQuadrant;
  List<String>? lastLabels;

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
    required String quadrant,
    List<String> labels = const [],
    String? description,
    String? dueAt,
    String? parentTaskId,
    String? plannedStartAt,
    int? estimatedMinutes,
    required String requestId,
  }) async {
    lastTitle = title;
    lastQuadrant = quadrant;
    lastLabels = List.of(labels);
    if (createCompleter != null) await createCompleter!.future;
    if (failCreate) throw Exception('create failed');
    final created = task(
      'task-${tasks.length + 1}',
      title,
    ).copyWith(quadrant: quadrant, labels: labels);
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

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class CountingAuthorizationRepository implements DeviceAuthorizationRepository {
  int createCalls = 0;

  @override
  Future<DeviceAuthorizationRequest> createDeviceRequest(
    String publicKey,
  ) async {
    createCalls++;
    return DeviceAuthorizationRequest(
      id: 'request-1',
      expiresAt: DateTime.utc(2099),
      status: 'PENDING',
      safetyCode: '123456',
    );
  }

  @override
  Future<List<DeviceAuthorizationRequest>> listRequests() async => const [];

  @override
  Future<DeviceAuthorizationRequest> beginApproval(String requestId) =>
      throw UnimplementedError();

  @override
  Future<void> approve(
    String requestId, {
    required DeviceSigningKey signingKey,
    required String signaturePayload,
  }) => throw UnimplementedError();

  @override
  Future<void> reject(String requestId) => throw UnimplementedError();

  @override
  Future<DeviceAuthorizationRequest> scanWebQr(String qrPayload) =>
      throw UnimplementedError();

  @override
  Future<void> approveWebLogin(
    DeviceAuthorizationRequest request, {
    required DeviceSigningKey signingKey,
  }) => throw UnimplementedError();
}

class FakeCloudSigningKey implements DeviceSigningKey {
  @override
  Future<String> getOrCreatePublicKey() async => 'cHVibGlj';

  @override
  Future<Uint8List> sign(Uint8List payload) async => Uint8List.fromList([1]);

  @override
  Future<void> deleteKey() async {}
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
  test(
    'Android profile overview counts owned parents and children independently',
    () {
      final overview = TaskOverview.fromTasks([
        task('parent', 'Parent', delayCount: 2, totalDelayMinutes: 90),
        task(
          'child',
          'Child',
          status: 'DONE',
          parentTaskId: 'parent',
          delayCount: 1,
          totalDelayMinutes: 60,
        ),
        task(
          'other-owner',
          'Other owner',
          currentHandlerId: 'user-2',
          delayCount: 8,
          totalDelayMinutes: 480,
        ),
      ], 'user-1');

      expect(overview.taskCount, 2);
      expect(overview.unfinishedCount, 1);
      expect(overview.completedCount, 1);
      expect(overview.delayCount, 3);
      expect(overview.totalDelayMinutes, 150);
    },
  );

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

    await tester.tap(find.byKey(const ValueKey('task-profile-destination')));
    await tester.pumpAndSettle();

    expect(find.byType(MyProfileScreen), findsOneWidget);
    expect(find.text('我的'), findsWidgets);
  });

  testWidgets('profile AppBar exposes approval center and Web QR actions', (
    tester,
  ) async {
    final sync = await readyController(FakeTaskRepository());
    await tester.pumpWidget(
      MaterialApp(
        home: CloudWorkspaceScreen(
          api: testApi(),
          syncController: sync,
          session: loggedInSession,
          signingKey: FakeCloudSigningKey(),
        ),
      ),
    );

    await tester.tap(find.byKey(const ValueKey('task-profile-destination')));
    await tester.pump();

    final approval = find.byKey(const Key('profile-approval-center'));
    final qr = find.byKey(const Key('profile-web-qr-login'));
    expect(approval, findsOneWidget);
    expect(qr, findsOneWidget);
    expect(tester.widget<IconButton>(approval).onPressed, isNotNull);
    expect(tester.widget<IconButton>(qr).onPressed, isNotNull);
    expect(
      find.ancestor(of: qr, matching: find.byType(ListTile)),
      findsNothing,
    );
  });

  testWidgets('profile hides Web QR login without a session', (tester) async {
    final sync = await readyController(FakeTaskRepository());
    await tester.pumpWidget(
      MaterialApp(
        home: CloudWorkspaceScreen(
          api: testApi(),
          syncController: sync,
          signingKey: FakeCloudSigningKey(),
        ),
      ),
    );

    await tester.tap(find.byKey(const ValueKey('task-profile-destination')));
    await tester.pump();

    expect(find.text('当前会话不可用'), findsOneWidget);
    expect(find.byKey(const Key('profile-web-qr-login')), findsNothing);
  });

  testWidgets('profile entry does not create device authorization requests', (
    tester,
  ) async {
    final authorization = CountingAuthorizationRepository();
    final sync = await readyController(FakeTaskRepository());
    await tester.pumpWidget(
      MaterialApp(
        home: CloudWorkspaceScreen(
          api: testApi(),
          syncController: sync,
          session: loggedInSession,
          canWrite: false,
          signingKey: FakeCloudSigningKey(),
          authorizationRepository: authorization,
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(authorization.createCalls, 0);
  });

  testWidgets('creation requires a quadrant and successful task appears', (
    tester,
  ) async {
    final repo = FakeTaskRepository();
    final sync = await readyController(repo);
    await tester.pumpWidget(
      MaterialApp(
        home: CloudWorkspaceScreen(api: testApi(), syncController: sync),
      ),
    );
    await tester.tap(find.byKey(const Key('create-task-fab')));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const Key('task-title-input')),
      'Buy milk',
    );
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
    await tester.pump();
    await tester.tap(find.byKey(const Key('create-task-button')));
    await tester.pumpAndSettle();

    expect(repo.lastTitle, 'Buy milk');
    expect(repo.lastQuadrant, 'Q2');
    expect(repo.lastLabels, isEmpty);
    expect(find.text('Buy milk'), findsOneWidget);
  });

  testWidgets('create FAB opens after the initial stale sync is refreshed', (
    tester,
  ) async {
    final sync = WorkspaceSyncController(FakeTaskRepository());
    await tester.pumpWidget(
      MaterialApp(
        home: CloudWorkspaceScreen(api: testApi(), syncController: sync),
      ),
    );

    expect(
      tester
          .widget<FloatingActionButton>(
            find.byKey(const Key('create-task-fab')),
          )
          .onPressed,
      isNotNull,
    );
    await tester.tap(find.byKey(const Key('create-task-fab')));
    await tester.pumpAndSettle();

    expect(find.text('新建任务'), findsOneWidget);
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
      await tester.tap(find.byKey(const Key('create-task-fab')));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byKey(const Key('task-title-input')),
        'Keep me',
      );
      await tester.pump();
      await tester.tap(find.byKey(const Key('task-create-quadrant-select')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Q1 重要且紧急').last);
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
          .widget<FloatingActionButton>(
            find.byKey(const Key('create-task-fab')),
          )
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

  testWidgets('bottom navigation exposes exactly the four task destinations', (
    tester,
  ) async {
    final sync = await readyController(FakeTaskRepository());
    await tester.pumpWidget(
      MaterialApp(
        home: CloudWorkspaceScreen(api: testApi(), syncController: sync),
      ),
    );

    expect(find.byType(NavigationBar), findsOneWidget);
    expect(find.text('清单'), findsWidgets);
    expect(find.text('四象限'), findsOneWidget);
    expect(find.text('日程'), findsOneWidget);
    expect(find.text('我的'), findsOneWidget);
    expect(find.text('看板'), findsNothing);

    await tester.tap(find.byKey(const ValueKey('task-quadrant-destination')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('task-quadrant-title-Q1')), findsOneWidget);
    expect(find.byKey(const Key('task-quadrant-title-Q2')), findsOneWidget);
    expect(find.byKey(const Key('task-quadrant-title-Q3')), findsOneWidget);
    expect(find.byKey(const Key('task-quadrant-title-Q4')), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('task-schedule-destination')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('task-schedule-scroll')), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('task-profile-destination')));
    await tester.pumpAndSettle();
    expect(find.text('当前会话不可用'), findsOneWidget);
  });

  testWidgets('hamburger opens a left drawer instead of a bottom sheet', (
    tester,
  ) async {
    final sync = await readyController(FakeTaskRepository());
    await tester.pumpWidget(
      MaterialApp(
        home: CloudWorkspaceScreen(api: testApi(), syncController: sync),
      ),
    );

    await tester.tap(find.byKey(const Key('task-list-menu-button')));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('task-list-drawer')), findsOneWidget);
    expect(find.byType(BottomSheet), findsNothing);
  });

  testWidgets(
    '清单 uses the top task category selector and counts unfinished work',
    (tester) async {
      final repo = FakeTaskRepository()
        ..tasks.addAll([
          task('work-1', 'Work', labels: const ['常规事项']),
          task('work-2', 'Work done', status: 'DONE', labels: const ['常规事项']),
          task('wedding', 'Wedding', labels: const ['婚礼']),
        ]);
      final sync = await readyController(repo);
      await tester.pumpWidget(
        MaterialApp(
          home: CloudWorkspaceScreen(api: testApi(), syncController: sync),
        ),
      );

      expect(find.byKey(const Key('task-category-selector')), findsOneWidget);
      expect(find.text('全部任务'), findsOneWidget);
      expect(find.byKey(const Key('task-list-label-filter')), findsNothing);

      await tester.tap(find.byKey(const Key('task-category-selector')));
      await tester.pumpAndSettle();

      expect(find.text('常规事项'), findsOneWidget);
      expect(find.text('婚礼'), findsOneWidget);
      expect(find.byKey(const Key('task-category-count-常规事项')), findsOneWidget);
      expect(find.text('1'), findsWidgets);
    },
  );

  testWidgets('清单 more menu exposes sorting and display controls only', (
    tester,
  ) async {
    final sync = await readyController(FakeTaskRepository());
    await tester.pumpWidget(
      MaterialApp(
        home: CloudWorkspaceScreen(api: testApi(), syncController: sync),
      ),
    );

    await tester.tap(find.byKey(const Key('task-list-more-button')));
    await tester.pumpAndSettle();

    expect(find.text('排序'), findsOneWidget);
    expect(find.text('截止时间'), findsOneWidget);
    expect(find.text('显示副标题'), findsOneWidget);
    expect(find.text('显示已完成任务'), findsOneWidget);
    expect(find.text('显示已失败任务'), findsOneWidget);
    expect(find.text('任务审批'), findsNothing);
    expect(find.text('批量编辑'), findsNothing);
    expect(find.text('刷新'), findsNothing);
    expect(find.text('扫码登录 Web'), findsNothing);
  });

  testWidgets(
    'task views use edge pull-to-refresh with always-scrollable lists',
    (tester) async {
      final sync = await readyController(FakeTaskRepository());
      await tester.pumpWidget(
        MaterialApp(
          home: CloudWorkspaceScreen(api: testApi(), syncController: sync),
        ),
      );

      expect(
        tester
            .widget<ListView>(find.byKey(const Key('task-list-scroll')))
            .physics,
        isA<AlwaysScrollableScrollPhysics>(),
      );
      await tester.tap(find.byKey(const ValueKey('task-quadrant-destination')));
      await tester.pumpAndSettle();
      expect(
        tester
            .widget<ListView>(find.byKey(const Key('task-quadrant-scroll')))
            .physics,
        isA<AlwaysScrollableScrollPhysics>(),
      );
      await tester.tap(find.byKey(const ValueKey('task-schedule-destination')));
      await tester.pumpAndSettle();
      expect(
        tester
            .widget<ListView>(find.byKey(const Key('task-schedule-scroll')))
            .physics,
        isA<AlwaysScrollableScrollPhysics>(),
      );
    },
  );

  testWidgets('清单 renders four groups and a floating create action', (
    tester,
  ) async {
    final repo = FakeTaskRepository()
      ..tasks.addAll([
        task('active', 'Active'),
        task('done', 'Done', status: 'DONE'),
      ]);
    final sync = await readyController(repo);
    await tester.pumpWidget(
      MaterialApp(
        home: CloudWorkspaceScreen(api: testApi(), syncController: sync),
      ),
    );

    expect(find.byKey(const Key('task-section-header-past')), findsOneWidget);
    expect(
      find.byKey(const Key('task-section-header-upcoming')),
      findsOneWidget,
    );
    expect(
      find.byKey(const Key('task-section-header-unscheduled')),
      findsOneWidget,
    );
    expect(
      find.byKey(const Key('task-section-header-terminal')),
      findsOneWidget,
    );
    expect(find.byKey(const Key('create-task-fab')), findsOneWidget);
  });
}
