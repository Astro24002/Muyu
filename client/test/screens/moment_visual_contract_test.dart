import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:muyu_client/core/api_client.dart';
import 'package:muyu_client/models/home.dart';
import 'package:muyu_client/models/task.dart';
import 'package:muyu_client/models/workspace_snapshot.dart';
import 'package:muyu_client/screens/cloud_workspace_screen.dart';
import 'package:muyu_client/sync/workspace_sync_controller.dart';
import 'package:muyu_client/theme/muyu_theme.dart';

TaskItem _visualTask(
  String id, {
  required String status,
  required String handler,
  List<String> labels = const ['工作'],
}) => TaskItem(
  id: id,
  workspaceId: 'workspace-1',
  parentTaskId: null,
  title: '短任务$id',
  description: '',
  status: status,
  currentHandlerId: handler,
  quadrant: 'Q1',
  labels: labels,
  progress: status == 'IN_PROGRESS' ? 35 : null,
  blockedReason: status == 'BLOCKED' ? '等待对方' : null,
  blockedSince: status == 'BLOCKED' ? DateTime.utc(2026, 9, 14) : null,
  plannedStartAt: null,
  dueAt: null,
  estimatedMinutes: null,
  completedAt: null,
  createdBy: 'user-1',
  version: 1,
  statusVersion: 1,
  createdAt: DateTime.utc(2026, 9, 3),
  updatedAt: DateTime.utc(2026, 9, 3),
);

ApiClient _visualTestApi() => ApiClient(
  baseUrl: 'https://api.example',
  httpClient: MockClient((_) async => http.Response('{}', 200)),
);

void _expectContained(WidgetTester tester, Finder finder, Size viewport) {
  final rect = tester.getRect(finder);
  expect(rect.left, greaterThanOrEqualTo(0));
  expect(rect.top, greaterThanOrEqualTo(0));
  expect(rect.right, lessThanOrEqualTo(viewport.width));
  expect(rect.bottom, lessThanOrEqualTo(viewport.height));
}

void main() {
  testWidgets('moment home fits the 390x844 visual contract', (tester) async {
    const viewport = Size(390, 844);
    tester.view.physicalSize = viewport;
    tester.view.devicePixelRatio = 1;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });

    final blocked = _visualTask(
      'blocked',
      status: 'BLOCKED',
      handler: 'user-2',
    );
    final mine = _visualTask('mine', status: 'IN_PROGRESS', handler: 'user-1');
    final other = _visualTask('other', status: 'TODO', handler: 'user-2');
    final sync = WorkspaceSyncController.unavailable();
    sync.state = WorkspaceSyncState(
      snapshot: WorkspaceSnapshot(
        workspaceId: 'workspace-1',
        cursor: 1,
        viewerUserId: 'user-1',
        tasks: [blocked, mine, other],
        members: const [
          {'user_id': 'user-1', 'display_name': '我'},
          {'user_id': 'user-2', 'display_name': '对方'},
        ],
      ),
      home: HomeResponse(
        currentTasks: HomeTaskSection(items: [mine]),
        blockedTasks: HomeTaskSection(items: [blocked]),
        reviewTasks: HomeTaskSection(items: const []),
        pendingApprovalCount: 0,
        moment: MomentProjection(
          blockedTasks: HomeTaskSection(items: [blocked]),
          myTasks: HomeTaskSection(items: [mine]),
          otherTasks: HomeTaskSection(items: [other]),
        ),
        needsActionCount: 3,
        waitingOnOtherCount: 1,
        weekDueCount: 2,
      ),
      isStale: false,
    );

    await tester.pumpWidget(
      MaterialApp(
        theme: muyuLightTheme(),
        home: CloudWorkspaceScreen(api: _visualTestApi(), syncController: sync),
      ),
    );
    await tester.pumpAndSettle();

    final appBarTitle = find.byKey(const Key('task-system-title'));
    expect(appBarTitle, findsOneWidget);
    final titleText = find.descendant(
      of: appBarTitle,
      matching: find.byWidgetPredicate((widget) {
        if (widget is! Text) return false;
        final text = widget.data ?? widget.textSpan?.toPlainText() ?? '';
        return text.contains('清单→此刻');
      }),
    );
    expect(titleText, findsOneWidget);
    expect(tester.getSize(appBarTitle).height, greaterThan(0));
    _expectContained(tester, appBarTitle, viewport);

    final summary = find.byKey(const Key('moment-summary'));
    expect(summary, findsOneWidget);
    expect(tester.getSize(summary), isNot(Size.zero));
    _expectContained(tester, summary, viewport);

    const sections = <String, String>{
      'blocked': '卡住的事情',
      'mine': '我在推进',
      'other': '对方在推进',
    };
    for (final entry in sections.entries) {
      final section = find.byKey(Key('moment-section-${entry.key}'));
      expect(section, findsOneWidget);
      final title = find.byKey(Key('moment-section-title-${entry.key}'));
      expect(tester.widget<Text>(title).data, entry.value);
      expect(tester.getSize(section), isNot(Size.zero));
      _expectContained(tester, section, viewport);
    }

    for (final task in [blocked, mine, other]) {
      final card = find.byKey(ValueKey('task-card-${task.id}'));
      final metadata = find.byKey(ValueKey('task-card-metadata-${task.id}'));
      expect(card, findsOneWidget);
      expect(metadata, findsOneWidget);
      expect(tester.getSize(metadata).height, lessThanOrEqualTo(24));
      expect(
        find.descendant(
          of: card,
          matching: find.byKey(ValueKey('task-card-status-${task.id}')),
        ),
        findsOneWidget,
      );
      expect(
        find.descendant(
          of: metadata,
          matching: find.byKey(ValueKey('task-card-due-${task.id}')),
        ),
        findsOneWidget,
      );
      expect(
        find.descendant(
          of: metadata,
          matching: find.byKey(ValueKey('task-card-owner-${task.id}')),
        ),
        findsOneWidget,
      );
      expect(
        find.descendant(
          of: metadata,
          matching: find.byKey(ValueKey('task-card-quadrant-${task.id}')),
        ),
        findsOneWidget,
      );
      expect(
        find.descendant(
          of: metadata,
          matching: find.byKey(ValueKey('task-card-label-${task.id}')),
        ),
        findsOneWidget,
      );
      _expectContained(tester, card, viewport);
    }

    final navigation = find.byKey(const Key('workspace-navigation-bar'));
    expect(navigation, findsOneWidget);
    expect(
      find.descendant(
        of: navigation,
        matching: find.byType(NavigationDestination),
      ),
      findsNWidgets(4),
    );
    for (final key in const [
      'task-list-destination',
      'task-quadrant-destination',
      'task-schedule-destination',
      'task-profile-destination',
    ]) {
      expect(find.byKey(ValueKey(key)), findsOneWidget);
    }
    expect(tester.getSize(navigation).height, greaterThan(0));
    _expectContained(tester, navigation, viewport);

    final fab = find.byKey(const Key('create-task-fab'));
    expect(fab, findsOneWidget);
    expect(tester.getSize(fab), const Size(56, 56));
    _expectContained(tester, fab, viewport);

    expect(tester.takeException(), isNull);
  });
}
