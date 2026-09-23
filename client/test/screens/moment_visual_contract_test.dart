import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:muyu_client/core/api_client.dart';
import 'package:muyu_client/models/home.dart';
import 'package:muyu_client/models/task.dart';
import 'package:muyu_client/models/task_approval_request.dart';
import 'package:muyu_client/models/workspace_snapshot.dart';
import 'package:muyu_client/screens/cloud_workspace_screen.dart';
import 'package:muyu_client/sync/workspace_sync_controller.dart';
import 'package:muyu_client/task/home_entry_repository.dart';
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

class _VisualHomeEntryRepository extends HomeEntryRepository {
  _VisualHomeEntryRepository() : super(_visualTestApi());

  @override
  Future<HomeEntryPage> load({
    required String entry,
    String? afterCursor,
  }) async {
    return HomeEntryPage(
      count: 2,
      tasks: [_visualTask('more', status: 'TODO', handler: 'user-1')],
      hasMore: false,
      nextCursor: null,
    );
  }
}

TaskApprovalRequest _visualApproval(String id, String type, String taskId) =>
    TaskApprovalRequest(
      id: id,
      workspaceId: 'workspace-1',
      taskId: taskId,
      requesterId: 'user-2',
      approverId: 'user-1',
      requestType: type,
      proposedChanges: type == 'STATUS_UPDATE'
          ? const {'review_submission': true, 'target_status': 'DONE'}
          : const {},
      baseFieldVersions: const {},
      requestId: 'request-$id',
      status: 'PENDING',
      createdAt: DateTime.utc(2026, 9, 20),
    );

class _ApprovalEntryRepository extends HomeEntryRepository {
  _ApprovalEntryRepository(this.request, this.task) : super(_visualTestApi());
  final TaskApprovalRequest request;
  final TaskItem task;

  @override
  Future<HomeEntryPage> load({
    required String entry,
    String? afterCursor,
  }) async => HomeEntryPage(
    count: 2,
    tasks: [task],
    approvals: [HomeApprovalItem(approvalRequest: request, task: task)],
    hasMore: false,
    nextCursor: null,
  );
}

void _expectContained(WidgetTester tester, Finder finder, Size viewport) {
  final rect = tester.getRect(finder);
  expect(rect.left, greaterThanOrEqualTo(0));
  expect(rect.top, greaterThanOrEqualTo(0));
  expect(rect.right, lessThanOrEqualTo(viewport.width));
  expect(rect.bottom, lessThanOrEqualTo(viewport.height));
}

void main() {
  testWidgets(
    'request without task opens the approval center without a fake task',
    (tester) async {
      final request = TaskApprovalRequest(
        id: 'classification',
        workspaceId: 'workspace-1',
        taskId: null,
        requesterId: 'user-2',
        approverId: 'user-1',
        requestType: 'CLASSIFICATION_CREATE',
        proposedChanges: const {'name': '婚礼'},
        baseFieldVersions: const {},
        requestId: 'request-classification',
        status: 'PENDING',
        createdAt: DateTime.utc(2026, 9, 20),
      );
      final sync = WorkspaceSyncController.unavailable();
      sync.state = WorkspaceSyncState(
        snapshot: WorkspaceSnapshot(
          workspaceId: 'workspace-1',
          cursor: 1,
          viewerUserId: 'user-1',
          tasks: const [],
        ),
        home: HomeResponse(
          currentTasks: HomeTaskSection(items: const []),
          blockedTasks: HomeTaskSection(items: const []),
          reviewTasks: HomeTaskSection(items: const []),
          pendingApprovalCount: 1,
          needsActionCount: 1,
          entries: HomeEntries(
            needsMe: HomeApprovalSection(
              items: [HomeApprovalItem(approvalRequest: request)],
            ),
          ),
        ),
      );
      await tester.pumpWidget(
        MaterialApp(
          theme: muyuLightTheme(),
          home: CloudWorkspaceScreen(
            api: _visualTestApi(),
            syncController: sync,
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('workspace-summary-needs-action')));
      await tester.pumpAndSettle();
      expect(find.text('婚礼'), findsOneWidget);
      await tester.tap(
        find.byKey(const Key('workspace-summary-request-classification')),
      );
      await tester.pumpAndSettle();
      expect(find.text('任务审批'), findsOneWidget);
      expect(find.byKey(const Key('task-detail-bottom-sheet')), findsNothing);
    },
  );

  testWidgets(
    'needs-me shows canonical requests separately and deduplicates pages by request',
    (tester) async {
      final task = _visualTask(
        'shared',
        status: 'IN_PROGRESS',
        handler: 'user-2',
      );
      final transfer = _visualApproval('handoff', 'HANDLER_TRANSFER', task.id);
      final review = _visualApproval('review', 'STATUS_UPDATE', task.id);
      final sync = WorkspaceSyncController.unavailable();
      sync.state = WorkspaceSyncState(
        snapshot: WorkspaceSnapshot(
          workspaceId: 'workspace-1',
          cursor: 1,
          viewerUserId: 'user-1',
          tasks: [task],
          members: const [
            {'user_id': 'user-1', 'display_name': '我'},
            {'user_id': 'user-2', 'display_name': '对方'},
          ],
        ),
        home: HomeResponse(
          currentTasks: HomeTaskSection(items: [task]),
          blockedTasks: HomeTaskSection(items: const []),
          reviewTasks: HomeTaskSection(items: const []),
          pendingApprovalCount: 2,
          needsActionCount: 2,
          entries: HomeEntries(
            needsMe: HomeApprovalSection(
              items: [HomeApprovalItem(approvalRequest: transfer, task: task)],
              hasMore: true,
            ),
          ),
        ),
      );
      await tester.pumpWidget(
        MaterialApp(
          theme: muyuLightTheme(),
          home: CloudWorkspaceScreen(
            api: _visualTestApi(),
            syncController: sync,
            homeEntryRepository: _ApprovalEntryRepository(review, task),
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('workspace-summary-needs-action')));
      await tester.pumpAndSettle();
      expect(
        find.byKey(const Key('workspace-summary-request-handoff')),
        findsOneWidget,
      );
      expect(find.text('责任交接'), findsOneWidget);
      await tester.tap(find.byKey(const Key('workspace-summary-load-more')));
      await tester.pumpAndSettle();
      expect(
        find.byKey(const Key('workspace-summary-request-handoff')),
        findsOneWidget,
      );
      expect(
        find.byKey(const Key('workspace-summary-request-review')),
        findsOneWidget,
      );
      expect(find.text('成果验收'), findsOneWidget);
    },
  );

  for (final width in [320.0, 360.0, 393.0, 412.0]) {
    testWidgets('moment home fits ${width.toInt()}x844 visual contract', (
      tester,
    ) async {
      final viewport = Size(width, 844);
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
      final mine = _visualTask(
        'mine',
        status: 'IN_PROGRESS',
        handler: 'user-1',
      );
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
          entries: HomeEntries(
            dueThisWeek: HomeTaskSection(items: [mine], hasMore: true),
          ),
        ),
        isStale: false,
      );

      await tester.pumpWidget(
        MaterialApp(
          theme: muyuLightTheme(),
          home: CloudWorkspaceScreen(
            api: _visualTestApi(),
            syncController: sync,
            homeEntryRepository: _VisualHomeEntryRepository(),
          ),
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
          return text.contains('此刻');
        }),
      );
      expect(titleText, findsOneWidget);
      expect(tester.getSize(appBarTitle).height, greaterThan(0));
      _expectContained(tester, appBarTitle, viewport);

      final summary = find.byKey(const Key('moment-summary'));
      final header = find.byKey(const Key('workspace-context-header'));
      expect(header, findsOneWidget);
      expect(find.byKey(const Key('workspace-actor-strip')), findsNothing);
      final greeting = tester.widget<Text>(
        find.byKey(const Key('workspace-moment-greeting')),
      );
      expect(greeting.data, contains('一起向前一点点'));
      final actionMetric = find.byKey(
        const Key('workspace-summary-needs-action'),
      );
      expect(
        find.descendant(of: actionMetric, matching: find.text('3件')),
        findsOneWidget,
      );
      expect(
        find.descendant(
          of: actionMetric,
          matching: find.byIcon(Icons.arrow_forward),
        ),
        findsOneWidget,
      );
      expect(tester.getSize(actionMetric).height, greaterThanOrEqualTo(104));
      expect(tester.getRect(actionMetric).left, width >= 360 ? 24 : 16);
      expect(summary, findsOneWidget);
      expect(tester.getSize(summary), isNot(Size.zero));
      _expectContained(tester, summary, viewport);

      const sections = <String, String>{
        'blocked': '卡住的事情',
        'mine': '我在推进',
        'other': 'TA 在推进',
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
        expect(
          tester.widget<Material>(card).color,
          muyuLightTheme().colorScheme.surface,
        );
        expect(tester.getRect(card).left, width >= 360 ? 24 : 16);
        expect(metadata, findsOneWidget);
        expect(tester.getSize(metadata).height, lessThanOrEqualTo(32));
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
          find.byKey(ValueKey('task-card-quadrant-${task.id}')),
          findsNothing,
        );
        expect(
          find.descendant(
            of: card,
            matching: find.byKey(ValueKey('task-card-action-${task.id}')),
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
        expect(
          tester
              .getRect(find.byKey(ValueKey('task-card-status-${task.id}')))
              .top,
          lessThan(tester.getRect(metadata).top),
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
        'matters-destination',
        'ledger-destination',
        'checkins-destination',
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
      if (width == 393) {
        await tester.tap(find.byKey(const Key('workspace-summary-week-due')));
        await tester.pumpAndSettle();
        expect(
          find.byKey(const Key('workspace-summary-task-mine')),
          findsOneWidget,
        );
        await tester.tap(find.byKey(const Key('workspace-summary-load-more')));
        await tester.pumpAndSettle();
        expect(
          find.byKey(const Key('workspace-summary-task-more')),
          findsOneWidget,
        );
        await tester.tap(find.byKey(const Key('workspace-summary-task-mine')));
        await tester.pumpAndSettle();
        expect(
          find.byKey(const Key('task-detail-bottom-sheet')),
          findsOneWidget,
        );
        await tester.tap(find.byKey(const Key('task-detail-sheet-close')));
        await tester.pumpAndSettle();
        expect(
          find.byKey(const Key('workspace-context-header')),
          findsOneWidget,
        );
      }
    });
  }
}
