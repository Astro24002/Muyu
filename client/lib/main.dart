import 'package:flutter/material.dart';

import 'app.dart';
import 'auth/mobile_auth_repository.dart';
import 'auth/mobile_login_controller.dart';
import 'auth/mobile_session_store.dart';
import 'core/api_client.dart';
import 'core/config.dart';
import 'platform/api_http_client.dart';
import 'platform/device_signing_key_android.dart';
import 'workspace/workspace_bootstrap_repository.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final sessionStore = SecureMobileSessionStore();
  final apiClient = ApiClient(
    baseUrl: AppConfig.apiBaseUrl,
    httpClient: createApiHttpClient(),
    tokenStore: MobileTokenStoreAdapter(sessionStore),
  );
  final mobileRepository = HttpMobileAuthRepository(apiClient, sessionStore);
  final signingKey = AndroidDeviceSigningKey();
  final loginController = MobileLoginController(
    mobileRepository,
    sessionStore,
    publicKey: signingKey.getOrCreatePublicKey,
  );
  await loginController.restore();
  final workspaceBootstrapRepository = HttpWorkspaceBootstrapRepository(
    apiClient,
  );
  runApp(
    MuyuApp(
      apiClient: apiClient,
      deviceSigningKey: signingKey,
      mobileLoginController: loginController,
      workspaceBootstrapRepository: workspaceBootstrapRepository,
    ),
  );
}
