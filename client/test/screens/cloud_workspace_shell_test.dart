import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
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

Widget shell() => MaterialApp(
  theme: muyuLightTheme(),
  home: CloudWorkspaceScreen(
    api: shellTestApi(),
    syncController: WorkspaceSyncController.unavailable(),
  ),
);

void main() {
  testWidgets('renders the v1 four-tab shell at a narrow phone width', (
    tester,
  ) async {
    final view = tester.view;
    view.physicalSize = const Size(390, 844);
    view.devicePixelRatio = 1;
    addTearDown(() {
      view.resetPhysicalSize();
      view.resetDevicePixelRatio();
    });

    await tester.pumpWidget(shell());
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('workspace-navigation-shell')), findsOneWidget);
    expect(find.byType(NavigationDestination), findsNWidgets(4));
    expect(find.text('事项'), findsWidgets);
    expect(find.text('记账'), findsOneWidget);
    expect(find.text('打卡'), findsOneWidget);
    expect(find.text('我的'), findsOneWidget);
    expect(find.byKey(const Key('matter-view-menu')), findsOneWidget);
    expect(find.text('此刻'), findsWidgets);
    expect(find.byKey(const Key('workspace-brand-mark')), findsNothing);
    expect(find.byKey(const Key('task-list-drawer')), findsNothing);
    expect(find.byKey(const Key('create-task-fab')), findsOneWidget);
  });

  testWidgets('app chrome shares one page surface without separator bands', (
    tester,
  ) async {
    await tester.pumpWidget(shell());
    await tester.pumpAndSettle();

    final pageColor = muyuLightTheme().scaffoldBackgroundColor;
    final appBar = tester.widget<AppBar>(
      find.byKey(const Key('task-system-app-bar')),
    );
    final navigationShell = tester.widget<DecoratedBox>(
      find.byKey(const Key('workspace-navigation-shell')),
    );
    final navigationDecoration = navigationShell.decoration as BoxDecoration;
    final systemOverlay = tester.widget<AnnotatedRegion<SystemUiOverlayStyle>>(
      find.byKey(const Key('workspace-system-ui-overlay')),
    );

    expect(appBar.backgroundColor, pageColor);
    expect(appBar.bottom, isNull);
    expect(navigationDecoration.color, pageColor);
    expect(navigationDecoration.border, isNull);
    expect(systemOverlay.value.statusBarColor, pageColor);
    expect(systemOverlay.value.systemNavigationBarColor, pageColor);
  });

  testWidgets(
    'title menu switches the three matter views and keeps the shell',
    (tester) async {
      await tester.pumpWidget(shell());
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const Key('matter-view-menu')));
      await tester.pumpAndSettle();
      expect(find.text('清单'), findsOneWidget);
      expect(find.text('四象限'), findsOneWidget);
      expect(find.text('日程'), findsOneWidget);

      await tester.tap(find.byKey(const Key('matter-view-item-quadrant')));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('task-quadrant-scroll')), findsOneWidget);
      expect(find.byKey(const Key('create-task-fab')), findsNothing);

      await tester.tap(find.byKey(const Key('matter-view-menu')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('matter-view-item-schedule')));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('task-schedule-scroll')), findsOneWidget);
    },
  );

  testWidgets('ledger and checkins show their real domain controls', (
    tester,
  ) async {
    await tester.pumpWidget(shell());
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const ValueKey('ledger-destination')));
    await tester.pumpAndSettle();
    expect(find.text('共同支出'), findsOneWidget);
    expect(find.byTooltip('记一笔'), findsOneWidget);
    expect(find.byKey(const Key('ledger-monthly-summary')), findsOneWidget);
    expect(
      find.byKey(const Key('ledger-category-distribution')),
      findsOneWidget,
    );
    expect(find.byKey(const Key('task-list-scroll')), findsNothing);

    await tester.tap(find.byKey(const ValueKey('checkins-destination')));
    await tester.pumpAndSettle();
    expect(find.text('日常打卡'), findsOneWidget);
    expect(find.text('纪念日'), findsOneWidget);
    expect(find.byKey(const Key('checkins-current-period')), findsOneWidget);
    await tester.tap(find.text('纪念日').last);
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('checkins-anniversary-list')), findsOneWidget);
    expect(find.byKey(const Key('task-list-scroll')), findsNothing);
  });
}
