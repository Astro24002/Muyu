import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;

import 'app.dart';
import 'auth/auth_repository.dart';
import 'auth/session_controller.dart';
import 'auth/token_store.dart';
import 'core/api_client.dart';
import 'core/config.dart';

void main() {
  final tokenStore = SecureTokenStore();
  final apiClient = ApiClient(
    baseUrl: AppConfig.apiBaseUrl,
    httpClient: http.Client(),
    tokenStore: tokenStore,
  );
  final repository = HttpAuthRepository(apiClient, tokenStore);
  runApp(MuyuApp(controller: SessionController(repository, tokenStore)));
}
