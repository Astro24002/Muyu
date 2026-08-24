import 'package:flutter/material.dart';

import 'auth/web_session_controller.dart';
import 'auth/web_login_repository.dart';
import 'auth/mobile_login_controller.dart';
import 'auth/session_controller.dart';
import 'screens/login_screen.dart';
import 'screens/main_shell.dart';
import 'screens/mobile_phone_login_screen.dart';
import 'screens/web_qr_login_screen.dart';
import 'task/task_repository.dart';

class MuyuApp extends StatefulWidget {
  const MuyuApp({
    super.key,
    this.controller,
    this.taskRepository,
    this.platform = AppPlatform.legacy,
    this.webSessionController,
    this.mobileLoginController,
    this.initializeSession = true,
  });

  final SessionController? controller;
  final TaskRepository? taskRepository;
  final AppPlatform platform;
  final WebSessionController? webSessionController;
  final MobileLoginController? mobileLoginController;
  final bool initializeSession;

  @override
  State<MuyuApp> createState() => _MuyuAppState();
}

class _MuyuAppState extends State<MuyuApp> {
  @override
  void initState() {
    super.initState();
    if (widget.initializeSession && widget.controller != null) {
      widget.controller!.restore();
    }
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
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
      home: widget.platform == AppPlatform.web
          ? WebQrLoginScreen(
              controller:
                  widget.webSessionController ??
                  WebSessionController(_UnavailableWebLoginApi()),
            )
          : widget.platform == AppPlatform.android &&
                widget.mobileLoginController != null
          ? MobilePhoneLoginScreen(controller: widget.mobileLoginController!)
          : AnimatedBuilder(
              animation: widget.controller!,
              builder: (context, _) => switch (widget.controller!.status) {
                SessionStatus.loading => const _LoadingScreen(),
                SessionStatus.signedIn => MainShell(
                  sessionController: widget.controller!,
                  taskRepository: widget.taskRepository!,
                ),
                SessionStatus.signedOut || SessionStatus.failure => LoginScreen(
                  controller: widget.controller!,
                ),
              },
            ),
    );
  }
}

enum AppPlatform { legacy, android, web }

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

class _LoadingScreen extends StatelessWidget {
  const _LoadingScreen();

  @override
  Widget build(BuildContext context) =>
      const Scaffold(body: Center(child: CircularProgressIndicator()));
}
