import 'package:flutter/material.dart';

import 'auth/session_controller.dart';
import 'screens/login_screen.dart';
import 'screens/main_shell.dart';
import 'task/task_repository.dart';

class MuyuApp extends StatefulWidget {
  const MuyuApp({
    super.key,
    required this.controller,
    required this.taskRepository,
    this.initializeSession = true,
  });

  final SessionController controller;
  final TaskRepository taskRepository;
  final bool initializeSession;

  @override
  State<MuyuApp> createState() => _MuyuAppState();
}

class _MuyuAppState extends State<MuyuApp> {
  @override
  void initState() {
    super.initState();
    if (widget.initializeSession) widget.controller.restore();
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
      home: AnimatedBuilder(
        animation: widget.controller,
        builder: (context, _) => switch (widget.controller.status) {
          SessionStatus.loading => const _LoadingScreen(),
          SessionStatus.signedIn => MainShell(
            sessionController: widget.controller,
            taskRepository: widget.taskRepository,
          ),
          SessionStatus.signedOut ||
          SessionStatus.failure => LoginScreen(controller: widget.controller),
        },
      ),
    );
  }
}

class _LoadingScreen extends StatelessWidget {
  const _LoadingScreen();

  @override
  Widget build(BuildContext context) =>
      const Scaffold(body: Center(child: CircularProgressIndicator()));
}
