import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;

import 'app.dart';
import 'auth/auth_repository.dart';
import 'auth/session_controller.dart';
import 'auth/token_store.dart';
import 'core/api_client.dart';
import 'core/config.dart';
import 'task/task_repository.dart';

void main() {
  final tokenStore = SecureTokenStore();
  final apiClient = ApiClient(
    baseUrl: AppConfig.apiBaseUrl,
    httpClient: http.Client(),
    tokenStore: tokenStore,
  );
  final authRepository = HttpAuthRepository(apiClient, tokenStore);
  final sessionController = SessionController(authRepository, tokenStore);
  final taskRepository = HttpTaskRepository(
    apiClient,
    refreshTokens: () async {
      try {
        await sessionController.refreshForApi();
      } on AuthFailure catch (error) {
        throw TaskFailure(error.message);
      }
    },
  );
  runApp(
    MuyuApp(controller: sessionController, taskRepository: taskRepository),
  );
}
