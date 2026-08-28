import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:muyu_client/workspace/workspace_bootstrap_controller.dart';
import 'package:muyu_client/workspace/workspace_bootstrap_repository.dart';

class BootstrapFakeRepository
    implements
        WorkspaceBootstrapRepository,
        LegacyWorkspaceBootstrapRepository {
  BootstrapFakeRepository(this.payload);

  WorkspaceBootstrapPayload payload;
  WorkspaceBootstrapPayload? bindResult;
  String? boundPhone;
  String? acceptedInviteId;
  int loadCalls = 0;

  @override
  Future<WorkspaceBootstrapPayload> loadBootstrap() async {
    loadCalls++;
    return payload;
  }

  @override
  Future<WorkspaceBootstrapPayload> bindPartner(
    String phone,
    String requestId,
  ) async {
    boundPhone = phone;
    return bindResult ?? payload;
  }

  @override
  Future<WorkspaceBootstrapPayload> acceptInvite(
    String inviteId,
    String requestId,
  ) async {
    acceptedInviteId = inviteId;
    return payload;
  }

  @override
  Future<WorkspaceSummary?> currentWorkspace() =>
      throw UnsupportedError('legacy API is not used');

  @override
  Future<WorkspaceSummary> createWorkspace() =>
      throw UnsupportedError('legacy API is not used');
}

class FakeWorkspaceBootstrapRepository
    implements
        WorkspaceBootstrapRepository,
        LegacyWorkspaceBootstrapRepository {
  WorkspaceSummary? currentResult;
  List<WorkspaceSummary?> currentResults = [];
  WorkspaceBootstrapFailure? currentFailure;
  Future<WorkspaceSummary?>? currentFuture;
  WorkspaceSummary? createResult;
  WorkspaceBootstrapFailure? createFailure;
  Future<WorkspaceSummary>? createFuture;
  int currentCalls = 0;
  int createCalls = 0;

  @override
  Future<WorkspaceBootstrapPayload> loadBootstrap() =>
      throw UnsupportedError('bootstrap API is not used');

  @override
  Future<WorkspaceBootstrapPayload> bindPartner(
    String phone,
    String requestId,
  ) => throw UnsupportedError('bootstrap API is not used');

  @override
  Future<WorkspaceBootstrapPayload> acceptInvite(
    String inviteId,
    String requestId,
  ) => throw UnsupportedError('bootstrap API is not used');

  @override
  Future<WorkspaceSummary?> currentWorkspace() async {
    currentCalls++;
    final future = currentFuture;
    if (future != null) return future;
    final failure = currentFailure;
    if (failure != null) throw failure;
    if (currentResults.isNotEmpty) return currentResults.removeAt(0);
    return currentResult;
  }

  @override
  Future<WorkspaceSummary> createWorkspace() async {
    createCalls++;
    final future = createFuture;
    if (future != null) return future;
    final failure = createFailure;
    if (failure != null) throw failure;
    return createResult!;
  }
}

void main() {
  test(
    'bootstrap maps each server state and preserves device capability',
    () async {
      final repository = BootstrapFakeRepository(
        WorkspaceBootstrapPayload.fromJson({
          'state': 'READY',
          'workspace': {'id': 'w1', 'name': '共同空间', 'member_count': 2},
          'invite': null,
          'device': {'status': 'UNVERIFIED', 'can_write': false},
        }),
      );
      final controller = WorkspaceBootstrapController(repository);

      await controller.load();

      expect(controller.state.status, WorkspaceBootstrapStatus.readOnlyDevice);
      expect(controller.state.workspace!.id, 'w1');
      expect(controller.state.canWrite, isFalse);
      expect(
        controller.state.payload!.device.status,
        WorkspaceDeviceStatus.unverified,
      );
    },
  );

  test(
    'bind partner normalizes an 11 digit phone at the controller boundary',
    () async {
      final repository = BootstrapFakeRepository(
        WorkspaceBootstrapPayload.fromJson({
          'state': 'NEEDS_PARTNER',
          'workspace': null,
          'invite': null,
          'device': {'status': 'VERIFIED', 'can_write': true},
        }),
      );
      repository.bindResult = WorkspaceBootstrapPayload.fromJson({
        'state': 'WAITING_FOR_PARTNER',
        'workspace': {'id': 'w1', 'name': null, 'member_count': 1},
        'invite': {
          'id': 'invite-1',
          'phone_masked': '+86******0169',
          'status': 'PENDING',
          'expires_at': '2026-08-29T00:00:00Z',
        },
        'device': {'status': 'VERIFIED', 'can_write': true},
      });
      final controller = WorkspaceBootstrapController(repository);
      await controller.load();

      await controller.bindPartner('15028180169');

      expect(repository.boundPhone, '+8615028180169');
      expect(
        controller.state.status,
        WorkspaceBootstrapStatus.waitingForPartner,
      );
    },
  );

  test('invited user can accept the invitation and reach ready', () async {
    final repository = BootstrapFakeRepository(
      WorkspaceBootstrapPayload.fromJson({
        'state': 'READY',
        'workspace': {'id': 'w1', 'name': null, 'member_count': 2},
        'invite': null,
        'device': {'status': 'VERIFIED', 'can_write': true},
      }),
    );
    final controller = WorkspaceBootstrapController(repository);
    controller.state = WorkspaceBootstrapState(
      status: WorkspaceBootstrapStatus.invited,
      payload: WorkspaceBootstrapPayload.fromJson({
        'state': 'INVITED',
        'workspace': {'id': 'w1', 'name': null, 'member_count': 1},
        'invite': {
          'id': 'invite-1',
          'phone_masked': '+86******0169',
          'status': 'PENDING',
          'expires_at': '2026-08-29T00:00:00Z',
        },
        'device': {'status': 'VERIFIED', 'can_write': true},
      }),
    );

    await controller.acceptInvite();

    expect(repository.acceptedInviteId, 'invite-1');
    expect(controller.state.status, WorkspaceBootstrapStatus.ready);
  });

  test('no current workspace enters the explicit creation state', () async {
    final repository = FakeWorkspaceBootstrapRepository()..currentResult = null;
    final controller = WorkspaceBootstrapController(repository);

    await controller.load();

    expect(controller.state.status, WorkspaceBootstrapStatus.needsWorkspace);
    expect(controller.state.workspace, isNull);
  });

  test(
    'create transitions to ready exactly once while request is pending',
    () async {
      final pending = Completer<WorkspaceSummary>();
      final repository = FakeWorkspaceBootstrapRepository()
        ..currentResult = null
        ..createFuture = pending.future;
      final controller = WorkspaceBootstrapController(repository);
      await controller.load();

      final first = controller.createWorkspace();
      final second = controller.createWorkspace();
      expect(repository.createCalls, 1);
      expect(
        controller.state.status,
        WorkspaceBootstrapStatus.creatingWorkspace,
      );

      pending.complete(
        const WorkspaceSummary(id: 'w1', name: null, status: 'ACTIVE'),
      );
      await Future.wait([first, second]);
      expect(controller.state.status, WorkspaceBootstrapStatus.ready);
      expect(controller.state.workspace!.id, 'w1');
    },
  );

  test(
    'workspace limit race reloads and enters the workspace created elsewhere',
    () async {
      final repository = FakeWorkspaceBootstrapRepository()
        ..currentResults = [
          null,
          const WorkspaceSummary(id: 'w2', name: null, status: 'ACTIVE'),
        ]
        ..createFailure = const WorkspaceBootstrapFailure(
          code: 'workspace_limit_reached',
          statusCode: 409,
        );
      final controller = WorkspaceBootstrapController(repository);
      await controller.load();
      await controller.createWorkspace();

      expect(repository.currentCalls, 2);
      expect(controller.state.status, WorkspaceBootstrapStatus.ready);
      expect(controller.state.workspace!.id, 'w2');
    },
  );

  test(
    'current workspace failure enters failure with stable message',
    () async {
      final repository = FakeWorkspaceBootstrapRepository()
        ..currentFailure = const WorkspaceBootstrapFailure(
          code: 'network_error',
          statusCode: 503,
        );
      final controller = WorkspaceBootstrapController(repository);

      await controller.load();

      expect(controller.state.status, WorkspaceBootstrapStatus.failure);
      expect(controller.state.errorMessage, '无法加载共享空间，请检查网络后重试');
    },
  );

  test(
    'ordinary create failure returns to needsWorkspace and can be retried',
    () async {
      final repository = FakeWorkspaceBootstrapRepository()
        ..currentResult = null
        ..createFailure = const WorkspaceBootstrapFailure(
          code: 'server_error',
          statusCode: 500,
        );
      final controller = WorkspaceBootstrapController(repository);
      await controller.load();

      await controller.createWorkspace();

      expect(controller.state.status, WorkspaceBootstrapStatus.needsWorkspace);
      expect(controller.state.errorMessage, '创建共享空间失败，请稍后重试');

      repository.createFailure = null;
      repository.createResult = const WorkspaceSummary(
        id: 'w3',
        name: null,
        status: 'ACTIVE',
      );
      await controller.createWorkspace();

      expect(repository.createCalls, 2);
      expect(controller.state.status, WorkspaceBootstrapStatus.ready);
      expect(controller.state.workspace!.id, 'w3');
    },
  );
}
