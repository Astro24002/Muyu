import 'dart:typed_data';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:muyu_client/core/api_client.dart';
import 'package:muyu_client/platform/device_signing_key.dart';
import 'package:muyu_client/screens/cloud_workspace_screen.dart';
import 'package:muyu_client/screens/workspace_gate.dart';
import 'package:muyu_client/workspace/workspace_bootstrap_repository.dart';

class FakeWorkspaceBootstrapRepository
    implements
        WorkspaceBootstrapRepository,
        LegacyWorkspaceBootstrapRepository {
  WorkspaceSummary? currentResult;
  WorkspaceSummary? createResult;
  WorkspaceBootstrapPayload? bootstrapResult;
  WorkspaceBootstrapFailure? currentFailure;
  WorkspaceBootstrapFailure? createFailure;
  int currentCalls = 0;
  int createCalls = 0;

  @override
  Future<WorkspaceBootstrapPayload> loadBootstrap() async {
    final result = bootstrapResult;
    if (result == null) throw UnsupportedError('bootstrap API is not used');
    return result;
  }

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
    if (currentFailure != null) throw currentFailure!;
    return currentResult;
  }

  @override
  Future<WorkspaceSummary> createWorkspace() async {
    createCalls++;
    if (createFailure != null) throw createFailure!;
    return createResult!;
  }
}

class FakeDeviceSigningKey implements DeviceSigningKey {
  @override
  Future<String> getOrCreatePublicKey() async => 'public-key';

  @override
  Future<Uint8List> sign(Uint8List payload) async =>
      Uint8List.fromList(payload);

  @override
  Future<void> deleteKey() async {}
}

ApiClient testApiClient() => ApiClient(
  baseUrl: 'https://api.example',
  httpClient: MockClient((_) async {
    return http.Response(
      jsonEncode({
        'workspace_id': 'w1',
        'cursor': 1,
        'tasks': <Object?>[],
        'members': <Object?>[],
        'conflicts': <Object?>[],
      }),
      200,
    );
  }),
);

void main() {
  testWidgets(
    'new user sees create workspace and cannot reach the web scanner',
    (tester) async {
      final repository = FakeWorkspaceBootstrapRepository()
        ..currentResult = null;
      await tester.pumpWidget(
        MaterialApp(
          home: WorkspaceGate(
            api: testApiClient(),
            signingKey: FakeDeviceSigningKey(),
            repository: repository,
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.widgetWithText(FilledButton, '创建共享空间'), findsOneWidget);
      expect(find.byType(CloudWorkspaceScreen), findsNothing);
      expect(find.byTooltip('扫码登录 Web'), findsNothing);
    },
  );

  testWidgets('create action opens the task workspace only after 201 result', (
    tester,
  ) async {
    final repository = FakeWorkspaceBootstrapRepository()
      ..currentResult = null
      ..createResult = const WorkspaceSummary(
        id: 'w1',
        name: null,
        status: 'ACTIVE',
      );
    await tester.pumpWidget(
      MaterialApp(
        home: WorkspaceGate(
          api: testApiClient(),
          signingKey: FakeDeviceSigningKey(),
          repository: repository,
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.widgetWithText(FilledButton, '创建共享空间'));
    await tester.pumpAndSettle();

    expect(repository.createCalls, 1);
    expect(find.byType(CloudWorkspaceScreen), findsOneWidget);
  });

  testWidgets('failed loading offers retry without creating a workspace', (
    tester,
  ) async {
    final repository = FakeWorkspaceBootstrapRepository()
      ..currentFailure = const WorkspaceBootstrapFailure(
        code: 'network_error',
        statusCode: 503,
      );
    await tester.pumpWidget(
      MaterialApp(
        home: WorkspaceGate(
          api: testApiClient(),
          signingKey: FakeDeviceSigningKey(),
          repository: repository,
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('重试'), findsOneWidget);
    expect(repository.currentCalls, 1);
    repository.currentFailure = null;
    await tester.tap(find.widgetWithText(OutlinedButton, '重试'));
    await tester.pumpAndSettle();

    expect(repository.currentCalls, 2);
    expect(find.widgetWithText(FilledButton, '创建共享空间'), findsOneWidget);
  });

  testWidgets('failed creation keeps the creation action available', (
    tester,
  ) async {
    final repository = FakeWorkspaceBootstrapRepository()
      ..currentResult = null
      ..createFailure = const WorkspaceBootstrapFailure(
        code: 'server_error',
        statusCode: 500,
      );
    await tester.pumpWidget(
      MaterialApp(
        home: WorkspaceGate(
          api: testApiClient(),
          signingKey: FakeDeviceSigningKey(),
          repository: repository,
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.widgetWithText(FilledButton, '创建共享空间'));
    await tester.pumpAndSettle();

    expect(find.text('创建共享空间失败，请稍后重试'), findsOneWidget);
    expect(find.widgetWithText(FilledButton, '创建共享空间'), findsOneWidget);
  });

  testWidgets(
    'owner can use the workspace while waiting for the partner to join',
    (tester) async {
      final repository = FakeWorkspaceBootstrapRepository()
        ..bootstrapResult = WorkspaceBootstrapPayload.fromJson({
          'state': 'WAITING_FOR_PARTNER',
          'workspace': {'id': 'w1', 'name': '共同空间', 'member_count': 1},
          'invite': {
            'id': 'invite-1',
            'phone_masked': '+86******0169',
            'status': 'PENDING',
            'expires_at': '2026-08-29T00:00:00Z',
          },
          'device': {'status': 'VERIFIED', 'can_write': true},
        });

      await tester.pumpWidget(
        MaterialApp(
          home: WorkspaceGate(
            api: testApiClient(),
            signingKey: FakeDeviceSigningKey(),
            repository: repository,
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.byType(CloudWorkspaceScreen), findsOneWidget);
      expect(
        find.byKey(const Key('waiting-for-partner-banner')),
        findsOneWidget,
      );
      expect(find.text('创建共享空间'), findsNothing);
    },
  );
}
