import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:http/http.dart' as http;
import 'package:muyu_client/core/api_client.dart';
import 'package:muyu_client/screens/cloud_workspace_screen.dart';
import 'package:muyu_client/sync/workspace_sync_controller.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('pending Android device is read-only in the workspace shell', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: CloudWorkspaceScreen(
          api: ApiClient(
            baseUrl: 'https://api.example',
            httpClient: http.Client(),
          ),
          syncController: WorkspaceSyncController.unavailable(),
          canWrite: false,
        ),
      ),
    );
    await tester.pump();

    expect(find.byKey(const Key('read-only-device-banner')), findsOneWidget);
    final title = tester.widget<TextField>(
      find.byKey(const Key('task-title-input')),
    );
    expect(title.enabled, isFalse);
    final create = tester.widget<IconButton>(
      find.byKey(const Key('create-task-button')),
    );
    expect(create.onPressed, isNull);
  });
}
