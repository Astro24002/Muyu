import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:muyu_client/screens/workspace_bootstrap_screen.dart';
import 'package:muyu_client/workspace/workspace_bootstrap_controller.dart';
import 'package:muyu_client/workspace/workspace_bootstrap_repository.dart';

WorkspaceBootstrapPayload payload(String state) =>
    WorkspaceBootstrapPayload.fromJson({
      'state': state,
      'workspace': state == 'NEEDS_PARTNER'
          ? null
          : {'id': 'w1', 'name': null, 'member_count': 1},
      'invite': state == 'INVITED' || state == 'WAITING_FOR_PARTNER'
          ? {
              'id': 'invite-1',
              'phone_masked': '+86******0169',
              'status': 'PENDING',
              'expires_at': '2026-08-29T00:00:00Z',
            }
          : null,
      'device': {'status': 'VERIFIED', 'can_write': true},
    });

void main() {
  testWidgets('needs partner accepts a Chinese 11 digit phone', (tester) async {
    String? phone;
    final state = WorkspaceBootstrapState(
      status: WorkspaceBootstrapStatus.needsPartner,
      payload: payload('NEEDS_PARTNER'),
    );
    await tester.pumpWidget(
      MaterialApp(
        home: WorkspaceBootstrapScreen(
          state: state,
          onBindPartner: (value) async => phone = value,
          onRetry: () async {},
        ),
      ),
    );

    await tester.enterText(
      find.byKey(const Key('partner-phone-input')),
      '15028180169',
    );
    await tester.tap(find.byKey(const Key('bind-partner-button')));
    await tester.pump();

    expect(phone, '+8615028180169');
  });

  testWidgets('waiting and invited states show the masked invitation', (
    tester,
  ) async {
    final waitingState = WorkspaceBootstrapState(
      status: WorkspaceBootstrapStatus.waitingForPartner,
      payload: payload('WAITING_FOR_PARTNER'),
    );
    await tester.pumpWidget(
      MaterialApp(
        home: WorkspaceBootstrapScreen(
          state: waitingState,
          onRetry: () async {},
        ),
      ),
    );
    expect(find.textContaining('+86******0169'), findsOneWidget);

    final invitedState = WorkspaceBootstrapState(
      status: WorkspaceBootstrapStatus.invited,
      payload: payload('INVITED'),
    );
    await tester.pumpWidget(
      MaterialApp(
        home: WorkspaceBootstrapScreen(
          state: invitedState,
          onAcceptInvite: () async {},
          onRetry: () async {},
        ),
      ),
    );
    expect(find.byKey(const Key('accept-invite-button')), findsOneWidget);
  });
}
