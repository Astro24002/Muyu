import 'package:flutter/material.dart';

import 'auth/mobile_login_controller.dart';
import 'auth/web_login_repository.dart';
import 'auth/web_session_controller.dart';
import 'core/api_client.dart';
import 'screens/cloud_workspace_screen.dart';
import 'screens/mobile_phone_login_screen.dart';
import 'screens/web_qr_login_screen.dart';

class MuyuApp extends StatelessWidget {
  const MuyuApp({
    super.key,
    required this.platform,
    required this.apiClient,
    this.webSessionController,
    this.mobileLoginController,
  });

  final AppPlatform platform;
  final ApiClient apiClient;
  final WebSessionController? webSessionController;
  final MobileLoginController? mobileLoginController;

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
    home: platform == AppPlatform.web
        ? _WebHome(
            apiClient: apiClient,
            controller:
                webSessionController ??
                WebSessionController(_UnavailableWebLoginApi()),
          )
        : _AndroidHome(apiClient: apiClient, controller: mobileLoginController),
  );
}

enum AppPlatform { android, web }

class _AndroidHome extends StatelessWidget {
  const _AndroidHome({required this.apiClient, required this.controller});

  final ApiClient apiClient;
  final MobileLoginController? controller;

  @override
  Widget build(BuildContext context) {
    if (controller == null) {
      return const Scaffold(body: Center(child: Text('移动端登录未配置')));
    }
    return AnimatedBuilder(
      animation: controller!,
      builder: (context, _) => controller!.status == MobileLoginStatus.signedIn
          ? CloudWorkspaceScreen(api: apiClient)
          : MobilePhoneLoginScreen(controller: controller!),
    );
  }
}

class _WebHome extends StatelessWidget {
  const _WebHome({required this.apiClient, required this.controller});

  final ApiClient apiClient;
  final WebSessionController controller;

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: controller,
    builder: (context, _) => controller.status == WebSessionStatus.signedIn
        ? CloudWorkspaceScreen(api: apiClient)
        : WebQrLoginScreen(controller: controller),
  );
}

class _UnavailableWebLoginApi implements WebLoginApi {
  @override
  Future<WebLoginChallenge> createChallenge(String browserProof) =>
      throw const WebQrPayloadFailure('Web API 未配置');

  @override
  Future<String> status(String challengeId) =>
      throw const WebQrPayloadFailure('Web API 未配置');

  @override
  Future<void> exchange(String challengeId, String browserProof) =>
      throw const WebQrPayloadFailure('Web API 未配置');
}
