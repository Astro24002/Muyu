import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import 'app.dart';
import 'auth/mobile_auth_repository.dart';
import 'auth/mobile_login_controller.dart';
import 'auth/mobile_session_store.dart';
import 'auth/web_login_repository.dart';
import 'auth/web_session_controller.dart';
import 'core/api_client.dart';
import 'core/config.dart';
import 'platform/device_signing_key.dart';

void main() {
  if (kIsWeb) {
    final apiClient = ApiClient(
      baseUrl: AppConfig.apiBaseUrl,
      httpClient: http.Client(),
    );
    runApp(
      MuyuApp(
        platform: AppPlatform.web,
        webSessionController: WebSessionController(
          WebLoginRepository(apiClient),
        ),
      ),
    );
    return;
  }

  final sessionStore = SecureMobileSessionStore();
  final apiClient = ApiClient(
    baseUrl: AppConfig.apiBaseUrl,
    httpClient: http.Client(),
    tokenStore: MobileTokenStoreAdapter(sessionStore),
  );
  final mobileRepository = HttpMobileAuthRepository(apiClient, sessionStore);
  final signingKey = createDeviceSigningKey();
  final loginController = MobileLoginController(
    mobileRepository,
    sessionStore,
    publicKey: signingKey.getOrCreatePublicKey,
  );
  runApp(
    MuyuApp(
      platform: AppPlatform.android,
      mobileLoginController: loginController,
    ),
  );
}
