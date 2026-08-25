import 'package:flutter/material.dart';

import 'auth/mobile_login_controller.dart';
import 'core/api_client.dart';
import 'platform/device_signing_key.dart';
import 'screens/cloud_workspace_screen.dart';
import 'screens/mobile_phone_login_screen.dart';

class MuyuApp extends StatelessWidget {
  const MuyuApp({
    super.key,
    required this.apiClient,
    required this.deviceSigningKey,
    required this.mobileLoginController,
  });

  final ApiClient apiClient;
  final DeviceSigningKey deviceSigningKey;
  final MobileLoginController mobileLoginController;

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
    ),
  );
}

class _AndroidHome extends StatelessWidget {
  const _AndroidHome({
    required this.apiClient,
    required this.controller,
    required this.signingKey,
  });

  final ApiClient apiClient;
  final MobileLoginController controller;
  final DeviceSigningKey signingKey;

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: controller,
    builder: (context, _) => controller.status == MobileLoginStatus.signedIn
        ? CloudWorkspaceScreen(api: apiClient, signingKey: signingKey)
        : MobilePhoneLoginScreen(controller: controller),
  );
}
