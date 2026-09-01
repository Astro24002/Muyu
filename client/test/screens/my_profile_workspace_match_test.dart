import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:muyu_client/auth/mobile_session_store.dart';
import 'package:muyu_client/models/task.dart';
import 'package:muyu_client/models/workspace_snapshot.dart';
import 'package:muyu_client/models/user.dart';
import 'package:muyu_client/platform/device_signing_key.dart';
import 'package:muyu_client/screens/my_profile_screen.dart';
import 'package:muyu_client/sync/workspace_sync_controller.dart';
import 'package:muyu_client/workspace/device_authorization_repository.dart';
import 'package:muyu_client/workspace/device_repository.dart';
import 'package:muyu_client/workspace/workspace_bootstrap_repository.dart';

const _session = MobileSession(
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

class FakeDeviceRepository implements DeviceRepository {
  @override
  Future<List<DeviceSummary>> listDevices() async => [
    DeviceSummary(
      id: 'device-1',
      platform: 'ANDROID',
      label: 'Pixel 8',
      status: 'VERIFIED',
      isCurrent: true,
      createdAt: DateTime.utc(2026, 8, 31),
      enrolledAt: DateTime.utc(2026, 8, 31),
      revokedAt: null,
    ),
  ];
}

class FakeWorkspaceRepository implements WorkspaceBootstrapRepository {
  @override
  Future<WorkspaceBootstrapPayload> loadBootstrap() async =>
      WorkspaceBootstrapPayload.fromJson({
        'state': 'READY',
        'workspace': {
          'id': 'workspace-1',
          'name': '共同空间',
          'member_count': 2,
          'match_status': 'matched',
          'members': [
            {
              'user_id': 'user-1',
              'display_name': '我',
              'phone_masked': '+86******0000',
              'member_slot': 1,
              'membership_status': 'ACTIVE',
              'is_current': true,
            },
            {
              'user_id': 'user-2',
              'display_name': '对方',
              'phone_masked': '+86******0169',
              'member_slot': 2,
              'membership_status': 'ACTIVE',
              'is_current': false,
            },
          ],
        },
        'invite': null,
        'device': {'status': 'VERIFIED', 'can_write': true},
      });

  @override
  Future<WorkspaceBootstrapPayload> bindPartner(
    String phone,
    String requestId,
  ) => throw UnimplementedError();

  @override
  Future<WorkspaceBootstrapPayload> acceptInvite(
    String inviteId,
    String requestId,
  ) => throw UnimplementedError();
}

class FakeAuthorizationRepository implements DeviceAuthorizationRepository {
  final request = DeviceAuthorizationRequest(
    id: 'request-1',
    expiresAt: DateTime.utc(2026, 8, 31, 12),
    status: 'PENDING',
    candidateDeviceId: 'device-2',
    candidateDeviceLabel: 'Pixel 9',
    candidatePlatform: 'ANDROID',
    candidateUserId: 'user-2',
    candidatePhoneMasked: '+86******0169',
    requesterUserId: 'user-2',
    requesterPhoneMasked: '+86******0169',
    isIncoming: true,
  );

  bool began = false;
  bool approved = false;
  bool rejected = false;

  @override
  Future<DeviceAuthorizationRequest> createDeviceRequest(String publicKey) =>
      throw UnimplementedError();

  @override
  Future<List<DeviceAuthorizationRequest>> listRequests() async => [request];

  @override
  Future<DeviceAuthorizationRequest> beginApproval(String requestId) async {
    began = true;
    return DeviceAuthorizationRequest(
      id: requestId,
      expiresAt: request.expiresAt,
      status: 'PENDING',
      signaturePayload: 'c2lnbmF0dXJl',
    );
  }

  @override
  Future<void> approve(
    String requestId, {
    required DeviceSigningKey signingKey,
    required String signaturePayload,
  }) async {
    approved = true;
  }

  @override
  Future<void> reject(String requestId) async {
    rejected = true;
  }

  @override
  Future<DeviceAuthorizationRequest> scanWebQr(String qrPayload) =>
      throw UnimplementedError();

  @override
  Future<void> approveWebLogin(
    DeviceAuthorizationRequest request, {
    required DeviceSigningKey signingKey,
  }) => throw UnimplementedError();
}

class FakeSigningKey implements DeviceSigningKey {
  @override
  Future<String> getOrCreatePublicKey() async => 'cHVibGlj';

  @override
  Future<Uint8List> sign(Uint8List payload) async => Uint8List.fromList([1]);

  @override
  Future<void> deleteKey() async {}
}

TaskItem profileTask(
  String id, {
  String status = 'TODO',
  String currentHandlerId = 'user-1',
  String? parentTaskId,
  int delayCount = 0,
  int totalDelayMinutes = 0,
}) => TaskItem(
  id: id,
  parentTaskId: parentTaskId,
  title: id,
  description: '',
  status: status,
  currentHandlerId: currentHandlerId,
  quadrant: 'Q1',
  plannedStartAt: null,
  dueAt: null,
  estimatedMinutes: null,
  completedAt: status == 'DONE' ? DateTime.utc(2026, 9, 1) : null,
  createdBy: 'user-1',
  version: 1,
  statusVersion: 1,
  createdAt: DateTime.utc(2026, 9, 1),
  updatedAt: DateTime.utc(2026, 9, 1),
  delayCount: delayCount,
  totalDelayMinutes: totalDelayMinutes,
);

WorkspaceSyncController profileSync() {
  final controller = WorkspaceSyncController.unavailable();
  controller.state = WorkspaceSyncState(
    snapshot: WorkspaceSnapshot(
      workspaceId: 'workspace-1',
      cursor: 1,
      viewerUserId: 'user-1',
      tasks: [
        profileTask('mine', delayCount: 2, totalDelayMinutes: 90),
        profileTask(
          'mine-child',
          status: 'DONE',
          parentTaskId: 'mine',
          delayCount: 1,
          totalDelayMinutes: 60,
        ),
        profileTask(
          'partner-task',
          currentHandlerId: 'user-2',
          delayCount: 4,
          totalDelayMinutes: 240,
        ),
      ],
    ),
    isStale: false,
  );
  return controller;
}

void main() {
  testWidgets('updates the overview from successful snapshots only', (
    tester,
  ) async {
    final sync = profileSync();
    await tester.pumpWidget(
      MaterialApp(
        home: MyProfileScreen(
          session: _session,
          repository: FakeDeviceRepository(),
          workspaceRepository: FakeWorkspaceRepository(),
          sync: sync,
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(
      tester
          .widget<Text>(find.byKey(const Key('profile-overview-task-count')))
          .data,
      '2',
    );

    sync.state = WorkspaceSyncState(
      snapshot: WorkspaceSnapshot(
        workspaceId: 'workspace-1',
        cursor: 2,
        viewerUserId: 'user-1',
        tasks: [profileTask('new-mine')],
      ),
      isStale: false,
    );
    sync.notifyListeners();
    await tester.pump();

    expect(
      tester
          .widget<Text>(find.byKey(const Key('profile-overview-task-count')))
          .data,
      '1',
    );

    final lastKnownGood = sync.state.snapshot;
    sync.state = WorkspaceSyncState(
      snapshot: lastKnownGood,
      isStale: true,
      errorMessage: 'snapshot unavailable',
    );
    sync.notifyListeners();
    await tester.pump();

    expect(
      tester
          .widget<Text>(find.byKey(const Key('profile-overview-task-count')))
          .data,
      '1',
    );
  });

  testWidgets('shows a compact matched account and partner overview sheet', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: MyProfileScreen(
          session: _session,
          repository: FakeDeviceRepository(),
          workspaceRepository: FakeWorkspaceRepository(),
          sync: profileSync(),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('profile-account-card')), findsOneWidget);
    expect(find.text('Muyu'), findsOneWidget);
    expect(
      tester.widget<Text>(find.byKey(const Key('profile-current-phone'))).data,
      '+86******0000',
    );
    expect(find.textContaining('已匹配'), findsOneWidget);
    expect(
      find.byKey(const Key('profile-overview-task-count')),
      findsOneWidget,
    );
    expect(find.text('2'), findsWidgets);
    expect(find.byKey(const Key('profile-partner-avatar')), findsOneWidget);

    await tester.tap(find.byKey(const Key('profile-partner-avatar')));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('profile-partner-sheet')), findsOneWidget);
    expect(find.text('对方'), findsWidgets);
    expect(
      find.descendant(
        of: find.byKey(const Key('profile-partner-sheet')),
        matching: find.text('已加入'),
      ),
      findsOneWidget,
    );
    expect(
      find.byKey(const Key('profile-partner-overview-task-count')),
      findsOneWidget,
    );
  });

  testWidgets('shows workspace matching and approves an incoming device', (
    tester,
  ) async {
    final authorization = FakeAuthorizationRepository();
    await tester.pumpWidget(
      MaterialApp(
        home: MyProfileScreen(
          session: _session,
          repository: FakeDeviceRepository(),
          workspaceRepository: FakeWorkspaceRepository(),
          authorizationRepository: authorization,
          signingKey: FakeSigningKey(),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('共享空间'), findsOneWidget);
    expect(find.text('已匹配 · 2/2 位成员'), findsOneWidget);
    expect(find.textContaining('+86******0169'), findsWidgets);
    expect(find.text('待处理的设备验证'), findsOneWidget);
    expect(find.text('Pixel 9'), findsOneWidget);
    expect(
      find.byKey(const Key('profile-approve-device-request')),
      findsOneWidget,
    );

    await tester.tap(find.byKey(const Key('profile-approve-device-request')));
    await tester.pumpAndSettle();

    expect(authorization.began, isTrue);
    expect(authorization.approved, isTrue);
  });

  testWidgets('rejects an incoming device request from the profile page', (
    tester,
  ) async {
    final authorization = FakeAuthorizationRepository();
    await tester.pumpWidget(
      MaterialApp(
        home: MyProfileScreen(
          session: _session,
          repository: FakeDeviceRepository(),
          workspaceRepository: FakeWorkspaceRepository(),
          authorizationRepository: authorization,
          signingKey: FakeSigningKey(),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('profile-reject-device-request')));
    await tester.pumpAndSettle();

    expect(authorization.rejected, isTrue);
  });
}
