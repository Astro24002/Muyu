import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:muyu_client/core/api_client.dart';
import 'package:muyu_client/screens/cloud_workspace_screen.dart';
import 'package:muyu_client/sync/workspace_sync_controller.dart';
import 'package:muyu_client/theme/muyu_theme.dart';

ApiClient shellTestApi() => ApiClient(
  baseUrl: 'https://api.example',
  httpClient: MockClient((_) async => http.Response('{}', 200)),
);

void main() {
  testWidgets('renders the 390px list shell with stable Android chrome', (
    tester,
  ) async {
    final view = tester.view;
    view.physicalSize = const Size(390, 844);
    view.devicePixelRatio = 1;
    addTearDown(() {
      view.resetPhysicalSize();
      view.resetDevicePixelRatio();
    });

    await tester.pumpWidget(
      MaterialApp(
        theme: muyuLightTheme(),
        home: CloudWorkspaceScreen(
          api: shellTestApi(),
          syncController: WorkspaceSyncController.unavailable(),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('task-system-app-bar')), findsOneWidget);
    expect(find.byKey(const Key('workspace-brand-mark')), findsOneWidget);
    expect(find.byKey(const Key('workspace-brand-title')), findsOneWidget);
    expect(find.byKey(const Key('workspace-actor-strip')), findsOneWidget);
    expect(find.byKey(const Key('workspace-summary-grid')), findsOneWidget);
    expect(
      find.byKey(const Key('workspace-summary-needs-action')),
      findsOneWidget,
    );
    expect(
      find.byKey(const Key('workspace-summary-waiting-on-other')),
      findsOneWidget,
    );
    expect(find.byKey(const Key('workspace-summary-week-due')), findsOneWidget);
    expect(find.byKey(const Key('workspace-navigation-shell')), findsOneWidget);
    expect(find.byKey(const Key('create-task-fab')), findsOneWidget);
    expect(find.byType(NavigationDestination), findsNWidgets(4));
  });

  testWidgets('summary cards and the drawer retain explicit actions', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: muyuLightTheme(),
        home: CloudWorkspaceScreen(
          api: shellTestApi(),
          syncController: WorkspaceSyncController.unavailable(),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('workspace-summary-needs-action')));
    await tester.pumpAndSettle();
    expect(find.text('待处理的交接和验收，会随着当前视角变化。'), findsOneWidget);
    await tester.tap(find.byKey(const Key('workspace-summary-close')));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('task-list-menu-button')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('task-list-drawer')), findsOneWidget);
    expect(
      find.descendant(
        of: find.byKey(const Key('task-list-drawer')),
        matching: find.text('清单→此刻'),
      ),
      findsOneWidget,
    );
    expect(find.text('刷新'), findsOneWidget);
  });
}
