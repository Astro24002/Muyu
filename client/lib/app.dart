import 'package:flutter/material.dart';

import 'auth/mobile_login_controller.dart';
import 'auth/mobile_session_store.dart';
import 'core/api_client.dart';
import 'platform/device_signing_key.dart';
import 'screens/mobile_phone_login_screen.dart';
import 'screens/workspace_gate.dart';
import 'sync/workspace_cache.dart';
import 'theme/muyu_theme.dart';
import 'workspace/workspace_bootstrap_repository.dart';

class MuyuApp extends StatelessWidget {
  const MuyuApp({
    super.key,
    required this.apiClient,
    required this.deviceSigningKey,
    required this.mobileLoginController,
    required this.workspaceBootstrapRepository,
    this.sessionStore,
    this.workspaceCache,
  });

  final ApiClient apiClient;
  final DeviceSigningKey deviceSigningKey;
  final MobileLoginController mobileLoginController;
  final WorkspaceBootstrapRepository workspaceBootstrapRepository;
  final MobileSessionStore? sessionStore;
  final WorkspaceCache? workspaceCache;

  @override
  Widget build(BuildContext context) => MaterialApp(
    title: 'Muyu',
    debugShowCheckedModeBanner: false,
    theme: muyuLightTheme(),
    home: _AndroidHome(
      apiClient: apiClient,
      controller: mobileLoginController,
      signingKey: deviceSigningKey,
      workspaceBootstrapRepository: workspaceBootstrapRepository,
      sessionStore: sessionStore,
      workspaceCache: workspaceCache,
    ),
  );
}

class _AndroidHome extends StatelessWidget {
  const _AndroidHome({
    required this.apiClient,
    required this.controller,
    required this.signingKey,
    required this.workspaceBootstrapRepository,
    this.sessionStore,
    this.workspaceCache,
  });

  final ApiClient apiClient;
  final MobileLoginController controller;
  final DeviceSigningKey signingKey;
  final WorkspaceBootstrapRepository workspaceBootstrapRepository;
  final MobileSessionStore? sessionStore;
  final WorkspaceCache? workspaceCache;

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: controller,
    builder: (context, _) => controller.status == MobileLoginStatus.signedIn
        ? WorkspaceGate(
            key: ValueKey(controller.currentSession!.user.id),
            api: apiClient,
            signingKey: signingKey,
            repository: workspaceBootstrapRepository,
            session: controller.currentSession,
            sessionStore: sessionStore,
            workspaceCache: workspaceCache,
          )
        : MobilePhoneLoginScreen(controller: controller),
  );
}
