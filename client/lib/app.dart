import 'package:flutter/material.dart';

import 'auth/mobile_login_controller.dart';
import 'core/api_client.dart';
import 'platform/device_signing_key.dart';
import 'screens/mobile_phone_login_screen.dart';
import 'screens/workspace_gate.dart';
import 'workspace/workspace_bootstrap_repository.dart';

class MuyuApp extends StatelessWidget {
  const MuyuApp({
    super.key,
    required this.apiClient,
    required this.deviceSigningKey,
    required this.mobileLoginController,
    required this.workspaceBootstrapRepository,
  });

  final ApiClient apiClient;
  final DeviceSigningKey deviceSigningKey;
  final MobileLoginController mobileLoginController;
  final WorkspaceBootstrapRepository workspaceBootstrapRepository;

  @override
  Widget build(BuildContext context) => MaterialApp(
    title: 'Muyu',
    debugShowCheckedModeBanner: false,
    theme: ThemeData(
      colorScheme: ColorScheme.fromSeed(
        seedColor: const Color(0xff087f73),
        brightness: Brightness.light,
      ),
      scaffoldBackgroundColor: const Color(0xfff7f8f6),
      inputDecorationTheme: const InputDecorationTheme(
        border: OutlineInputBorder(),
        filled: true,
        fillColor: Colors.white,
      ),
      cardTheme: const CardThemeData(
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.all(Radius.circular(6)),
          side: BorderSide(color: Color(0xffd9dedb)),
        ),
      ),
      useMaterial3: true,
    ),
    home: _AndroidHome(
      apiClient: apiClient,
      controller: mobileLoginController,
      signingKey: deviceSigningKey,
      workspaceBootstrapRepository: workspaceBootstrapRepository,
    ),
  );
}

class _AndroidHome extends StatelessWidget {
  const _AndroidHome({
    required this.apiClient,
    required this.controller,
    required this.signingKey,
    required this.workspaceBootstrapRepository,
  });

  final ApiClient apiClient;
  final MobileLoginController controller;
  final DeviceSigningKey signingKey;
  final WorkspaceBootstrapRepository workspaceBootstrapRepository;

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: controller,
    builder: (context, _) => controller.status == MobileLoginStatus.signedIn
        ? WorkspaceGate(
            key: ValueKey(controller.currentSession!.user.id),
            api: apiClient,
            signingKey: signingKey,
            repository: workspaceBootstrapRepository,
          )
        : MobilePhoneLoginScreen(controller: controller),
  );
}
