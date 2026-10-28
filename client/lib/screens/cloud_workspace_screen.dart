import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../core/api_client.dart';
import '../auth/mobile_session_store.dart';
import '../devices/device_management_repository.dart';
import '../models/task.dart';
import '../models/home.dart';
import '../task/home_entry_repository.dart';
import '../task/task_query_repository.dart';
import '../tasks/task_status.dart';
import '../models/task_view.dart';
import '../life/life_controller.dart';
import '../life/life_repository.dart';
import '../platform/device_signing_key.dart';
import '../profile/profile_repository.dart';
import '../sync/workspace_sync_controller.dart';
import '../sync/workspace_cache.dart';
import '../sync/workspace_sync_repository.dart';
import '../theme/muyu_theme.dart';
import '../workspace/device_authorization_repository.dart';
import '../workspace/device_repository.dart';
import '../workspace/workspace_bootstrap_repository.dart';
import 'web_qr_scanner_screen.dart';
import 'task_detail_screen.dart';
import 'task_approval_screen.dart';
import 'my_profile_screen.dart';
import 'task_list_view.dart';
import 'all_tasks_screen.dart';
import 'task_quadrant_view.dart';
import 'task_schedule_view.dart';
import 'ledger_screen.dart';
import 'checkins_screen.dart';
import '../widgets/task_system_app_bar.dart';

enum _TaskListMenuAction {
  sortDueAt,
  sortQuadrant,
  sortUpdatedAt,
  sortCreatedAt,
  toggleSubtitle,
  toggleCompleted,
  toggleFailed,
}

enum _MatterView { moment, quadrant, schedule }

class CloudWorkspaceScreen extends StatefulWidget {
  const CloudWorkspaceScreen({
    super.key,
    required this.api,
    this.signingKey,
    this.syncController,
    this.session,
    this.canWrite = true,
    this.waitingForPartner = false,
    this.workspaceBootstrapRepository,
    this.authorizationRepository,
    this.profileRepository,
    this.sessionStore,
    this.workspaceCache,
    this.workspaceId,
    this.lifeController,
    this.homeEntryRepository,
  });

  final ApiClient api;
  final DeviceSigningKey? signingKey;
  final WorkspaceSyncController? syncController;
  final MobileSession? session;
  final bool canWrite;
  final bool waitingForPartner;
  final WorkspaceBootstrapRepository? workspaceBootstrapRepository;
  final DeviceAuthorizationRepository? authorizationRepository;
  final ProfileRepository? profileRepository;
  final MobileSessionStore? sessionStore;
  final WorkspaceCache? workspaceCache;
  final String? workspaceId;
  final LifeController? lifeController;
  final HomeEntryRepository? homeEntryRepository;

  @override
  State<CloudWorkspaceScreen> createState() => _CloudWorkspaceScreenState();
}

class _CloudWorkspaceScreenState extends State<CloudWorkspaceScreen> {
  static const _destinationTitles = <String>['事项', '记账', '打卡', '我的'];

  late final WorkspaceSyncController _sync;
  late final LifeController _life;
  int _selectedDestination = 0;
  _MatterView _selectedMatterView = _MatterView.moment;
  String? _selectedTaskLabel;
  TaskListSort _taskListSort = TaskListSort.dueAt;
  bool _showTaskSubtitle = true;
  bool _showCompleted = true;
  bool _showFailed = false;

  @override
  void initState() {
    super.initState();
    _sync =
        widget.syncController ??
        WorkspaceSyncController(
          HttpWorkspaceSyncRepository(widget.api),
          cache: widget.workspaceCache,
          workspaceId: widget.workspaceId,
        );
    _life =
        widget.lifeController ?? LifeController(HttpLifeRepository(widget.api));
    _sync.addListener(_applySyncedLifeResources);
    if (widget.syncController == null) _sync.start();
  }

  @override
  void dispose() {
    _sync.removeListener(_applySyncedLifeResources);
    if (widget.syncController == null) _sync.dispose();
    if (widget.lifeController == null) _life.dispose();
    super.dispose();
  }

  void _applySyncedLifeResources() {
    _life.applyWorkspaceSnapshot(
      _sync.state.snapshot,
      viewerId: widget.session?.user.id ?? _sync.state.snapshot?.viewerUserId,
    );
  }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: _sync,
    builder: (context, _) {
      final state = _sync.state;
      final theme = Theme.of(context);
      return AnnotatedRegion<SystemUiOverlayStyle>(
        key: const Key('workspace-system-ui-overlay'),
        value: SystemUiOverlayStyle(
          statusBarColor: theme.scaffoldBackgroundColor,
          statusBarIconBrightness: Brightness.dark,
          systemNavigationBarColor: theme.scaffoldBackgroundColor,
          systemNavigationBarIconBrightness: Brightness.dark,
        ),
        child: Scaffold(
          appBar: _buildAppBar(state),
          body: Column(
            children: [
              if (!widget.canWrite)
                const MaterialBanner(
                  key: Key('read-only-device-banner'),
                  content: Text('当前设备尚未验证，仅可查看和刷新任务'),
                  actions: [SizedBox.shrink()],
                ),
              if (widget.waitingForPartner)
                const MaterialBanner(
                  key: Key('waiting-for-partner-banner'),
                  content: Text('共享空间已创建，等待对方加入，不影响当前使用'),
                  actions: [SizedBox.shrink()],
                ),
              Expanded(child: _destinationBody(state)),
            ],
          ),
          bottomNavigationBar: _buildBottomNavigationBar(),
          floatingActionButton:
              _selectedDestination == 0 &&
                  _selectedMatterView == _MatterView.moment
              ? FloatingActionButton(
                  key: const Key('create-task-fab'),
                  tooltip: '新增任务',
                  onPressed: widget.canWrite ? _openCreateTask : null,
                  child: const Icon(Icons.add),
                )
              : null,
        ),
      );
    },
  );

  PreferredSizeWidget _buildProfileAppBar() => AppBar(
    key: const Key('profile-account-app-bar'),
    title: Text('我的', style: Theme.of(context).textTheme.titleLarge),
    actions: [
      if (widget.session != null)
        IconButton(
          key: const Key('profile-approval-center'),
          tooltip: '审批中心',
          onPressed: _openApprovals,
          icon: const Icon(Icons.rule_outlined),
        ),
      if (widget.session != null &&
          widget.signingKey != null &&
          widget.canWrite)
        IconButton(
          key: const Key('profile-web-qr-login'),
          tooltip: '扫码登录 Web',
          onPressed: _openWebQrScanner,
          icon: const Icon(Icons.qr_code_scanner),
        ),
    ],
  );

  PreferredSizeWidget _buildAppBar(WorkspaceSyncState state) {
    if (_selectedDestination == 3) return _buildProfileAppBar();
    if (_selectedDestination != 0) {
      return AppBar(
        key: Key(
          'workspace-${_destinationTitles[_selectedDestination]}-app-bar',
        ),
        title: Text(_destinationTitles[_selectedDestination]),
      );
    }
    final categories = TaskView.listCategories(
      state.snapshot?.tasks ?? const <TaskItem>[],
      approvedClassifications: state.classifications.map(
        (classification) => classification.name,
      ),
    );
    return TaskSystemAppBar(
      title: _matterViewTitle,
      titleContent: _MatterViewSelector(
        value: _selectedMatterView,
        onSelected: (view) => setState(() => _selectedMatterView = view),
      ),
      actions: [
        _TaskCategorySelector(
          categories: categories,
          selectedLabel: _selectedTaskLabel,
          onSelected: (label) => setState(() => _selectedTaskLabel = label),
          compact: _selectedMatterView == _MatterView.moment,
        ),
        if (_selectedMatterView == _MatterView.moment)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: MuyuSpacing.xs),
            child: Center(
              child: Text(
                _momentDateLabel(DateTime.now()),
                key: const Key('matter-current-date'),
                style: Theme.of(context).textTheme.bodySmall
                    ?.copyWith(fontSize: 10),
              ),
            ),
          ),
        if (_selectedMatterView == _MatterView.moment) _buildTaskListMoreMenu(),
      ],
    );
  }

  String get _matterViewTitle => switch (_selectedMatterView) {
    _MatterView.moment => '此刻',
    _MatterView.quadrant => '四象限',
    _MatterView.schedule => '日程',
  };

  static String _momentDateLabel(DateTime date) {
    const weekdays = ['一', '二', '三', '四', '五', '六', '日'];
    return '${date.month}月${date.day}日周${weekdays[date.weekday - 1]}';
  }

  Widget _destinationBody(WorkspaceSyncState state) => IndexedStack(
    key: const Key('workspace-destination-stack'),
    index: _selectedDestination,
    children: [
      _mattersBody(state),
      LedgerScreen(
        key: const PageStorageKey('ledger-domain-view'),
        controller: _life,
        members: state.snapshot?.members ?? const [],
        viewerId: widget.session?.user.id ?? state.snapshot?.viewerUserId,
        canWrite: widget.canWrite,
      ),
      CheckinsScreen(
        key: const PageStorageKey('checkins-domain-view'),
        controller: _life,
        viewerId: widget.session?.user.id ?? state.snapshot?.viewerUserId,
        canWrite: widget.canWrite,
        members: state.snapshot?.members ?? const [],
        onOpenTask: (id) async {
          await _sync.refresh();
          if (!mounted) return;
          for (final task
              in _sync.state.snapshot?.tasks ?? const <TaskItem>[]) {
            if (task.id == id) {
              _openTask(task);
              break;
            }
          }
        },
      ),
      if (widget.session != null)
        MyProfileScreen(
          key: const PageStorageKey('task-profile-view'),
          session: widget.session!,
          repository: HttpDeviceRepository(widget.api),
          managementRepository: HttpDeviceManagementRepository(widget.api),
          profileRepository:
              widget.profileRepository ?? HttpProfileRepository(widget.api),
          sessionStore: widget.sessionStore,
          workspaceRepository: widget.workspaceBootstrapRepository,
          sync: _sync,
          canWrite: widget.canWrite,
          showAppBar: false,
          onOpenAllTasks: _openAllTasks,
        )
      else
        const _UnavailableProfileView(key: PageStorageKey('task-profile-view')),
    ],
  );

  Widget _mattersBody(WorkspaceSyncState state) => Column(
    children: [
      if (_selectedMatterView == _MatterView.moment)
        _WorkspaceContextHeader(
          state: state,
          viewerName: _viewerName(state),
          onSummaryTap: _openSummary,
        ),
      Expanded(child: _matterViewStack(state)),
    ],
  );

  Widget _matterViewStack(WorkspaceSyncState state) => IndexedStack(
    key: const Key('matter-view-stack'),
    index: _selectedMatterView.index,
    children: [
      TaskListView(
        key: const PageStorageKey('task-list-view'),
        sync: _sync,
        state: state,
        canWrite: widget.canWrite,
        selectedLabel: _selectedTaskLabel,
        sort: _taskListSort,
        showSubtitle: _showTaskSubtitle,
        showCompleted: _showCompleted,
        showFailed: _showFailed,
        showMomentMetrics: false,
        showMomentTaskSections: false,
        onTaskTap: _openTask,
      ),
      TaskQuadrantView(
        key: const PageStorageKey('task-quadrant-view'),
        sync: _sync,
        state: state,
        canWrite: widget.canWrite,
        selectedLabel: _selectedTaskLabel,
        onTaskTap: _openTask,
      ),
      TaskScheduleView(
        key: const PageStorageKey('task-schedule-view'),
        sync: _sync,
        state: state,
        canWrite: widget.canWrite,
        selectedLabel: _selectedTaskLabel,
        onTaskTap: _openTask,
      ),
    ],
  );

  Widget _buildBottomNavigationBar() {
    final theme = Theme.of(context);
    return DecoratedBox(
      key: const Key('workspace-navigation-shell'),
      decoration: BoxDecoration(color: theme.scaffoldBackgroundColor),
      child: NavigationBar(
        key: const Key('workspace-navigation-bar'),
        height: 68,
        selectedIndex: _selectedDestination,
        onDestinationSelected: (index) =>
            setState(() => _selectedDestination = index),
        labelBehavior: NavigationDestinationLabelBehavior.alwaysShow,
        destinations: const [
          NavigationDestination(
            key: ValueKey('matters-destination'),
            icon: Icon(Icons.checklist_outlined),
            selectedIcon: Icon(Icons.checklist),
            label: '事项',
          ),
          NavigationDestination(
            key: ValueKey('ledger-destination'),
            icon: Icon(Icons.account_balance_wallet_outlined),
            selectedIcon: Icon(Icons.account_balance_wallet),
            label: '记账',
          ),
          NavigationDestination(
            key: ValueKey('checkins-destination'),
            icon: Icon(Icons.check_circle_outline),
            selectedIcon: Icon(Icons.check_circle),
            label: '打卡',
          ),
          NavigationDestination(
            key: ValueKey('task-profile-destination'),
            icon: Icon(Icons.person_outline),
            selectedIcon: Icon(Icons.person),
            label: '我的',
          ),
        ],
      ),
    );
  }

  String _viewerName(WorkspaceSyncState state) {
    final viewerId =
        widget.session?.user.id ??
        state.home?.viewerUserId ??
        state.snapshot?.viewerUserId;
    if (viewerId == null || viewerId.isEmpty) return '当前用户';
    if (widget.session?.user.id == viewerId) {
      final nickname = widget.session?.user.nickname.trim();
      if (nickname != null && nickname.isNotEmpty) return nickname;
    }
    for (final member
        in state.snapshot?.members ?? const <Map<String, dynamic>>[]) {
      if (member['user_id'] != viewerId) continue;
      final displayName = member['display_name'];
      if (displayName is String && displayName.trim().isNotEmpty) {
        return displayName.trim();
      }
    }
    return viewerId;
  }

  Future<void> _openSummary(_WorkspaceSummaryKind kind) async {
    final home = _sync.state.home;
    final details = switch (kind) {
      _WorkspaceSummaryKind.needsAction => (
        '需要我处理',
        '待处理的交接和验收，会随着当前视角变化。',
        home?.needsActionCount ?? 0,
      ),
      _WorkspaceSummaryKind.waitingOnOther => (
        '等对方',
        '仍在等待对方回应的交接或验收请求。',
        home?.waitingOnOtherCount ?? 0,
      ),
      _WorkspaceSummaryKind.dueSoon => (
        '即将到期',
        '未来 14 天内截止的未完成事项。',
        home?.dueSoonCount ?? 0,
      ),
    };
    final entries = home?.entries;
    final approvals = switch (kind) {
      _WorkspaceSummaryKind.needsAction =>
        entries?.needsMe.items ?? <HomeApprovalItem>[],
      _WorkspaceSummaryKind.waitingOnOther =>
        entries?.waitingOnOther.items ?? <HomeApprovalItem>[],
      _WorkspaceSummaryKind.dueSoon => <HomeApprovalItem>[],
    };
    final tasks = switch (kind) {
      _WorkspaceSummaryKind.needsAction =>
        entries?.needsMe.items
                .map((item) => item.task)
                .whereType<TaskItem>()
                .toList() ??
            <TaskItem>[],
      _WorkspaceSummaryKind.waitingOnOther =>
        entries?.waitingOnOther.items
                .map((item) => item.task)
                .whereType<TaskItem>()
                .toList() ??
            <TaskItem>[],
      _WorkspaceSummaryKind.dueSoon => entries?.dueSoon.items ?? <TaskItem>[],
    };
    final hasMore = switch (kind) {
      _WorkspaceSummaryKind.needsAction => entries?.needsMe.hasMore ?? false,
      _WorkspaceSummaryKind.waitingOnOther =>
        entries?.waitingOnOther.hasMore ?? false,
      _WorkspaceSummaryKind.dueSoon => entries?.dueSoon.hasMore ?? false,
    };
    final selected = await showModalBottomSheet<TaskItem>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      showDragHandle: true,
      builder: (sheetContext) => SizedBox(
        height: MediaQuery.sizeOf(sheetContext).height * 0.85,
        child: _WorkspaceSummarySheet(
          title: details.$1,
          description: details.$2,
          count: details.$3,
          tasks: tasks,
          approvals: approvals,
          members: _sync.state.snapshot?.members ?? const [],
          onOpenApprovals: _openApprovals,
          hasMore: hasMore,
          entry: switch (kind) {
            _WorkspaceSummaryKind.needsAction => 'needs_me',
            _WorkspaceSummaryKind.waitingOnOther => 'waiting_on_other',
            _WorkspaceSummaryKind.dueSoon => 'due_soon',
          },
          repository:
              widget.homeEntryRepository ?? HomeEntryRepository(widget.api),
        ),
      ),
    );
    if (mounted && selected != null) _openTask(selected);
  }

  Widget _buildTaskListMoreMenu() => PopupMenuButton<_TaskListMenuAction>(
    key: const Key('task-list-more-button'),
    tooltip: '更多',
    icon: const Icon(Icons.more_vert),
    onSelected: _handleTaskListMenuAction,
    itemBuilder: (context) => [
      const PopupMenuItem<_TaskListMenuAction>(
        enabled: false,
        child: Text('排序'),
      ),
      _sortMenuItem(
        _TaskListMenuAction.sortDueAt,
        '截止时间',
        _taskListSort == TaskListSort.dueAt,
      ),
      _sortMenuItem(
        _TaskListMenuAction.sortQuadrant,
        '四象限优先级',
        _taskListSort == TaskListSort.quadrant,
      ),
      _sortMenuItem(
        _TaskListMenuAction.sortUpdatedAt,
        '最近更新',
        _taskListSort == TaskListSort.updatedAt,
      ),
      _sortMenuItem(
        _TaskListMenuAction.sortCreatedAt,
        '创建时间',
        _taskListSort == TaskListSort.createdAt,
      ),
      const PopupMenuDivider(),
      const PopupMenuItem<_TaskListMenuAction>(
        enabled: false,
        child: Text('显示'),
      ),
      CheckedPopupMenuItem<_TaskListMenuAction>(
        value: _TaskListMenuAction.toggleSubtitle,
        checked: _showTaskSubtitle,
        child: const Text('显示副标题'),
      ),
      CheckedPopupMenuItem<_TaskListMenuAction>(
        key: const Key('task-list-toggle-completed'),
        value: _TaskListMenuAction.toggleCompleted,
        checked: _showCompleted,
        child: const Text('显示已完成任务'),
      ),
      CheckedPopupMenuItem<_TaskListMenuAction>(
        key: const Key('task-list-toggle-failed'),
        value: _TaskListMenuAction.toggleFailed,
        checked: _showFailed,
        child: const Text('显示已取消任务'),
      ),
    ],
  );

  PopupMenuItem<_TaskListMenuAction> _sortMenuItem(
    _TaskListMenuAction value,
    String title,
    bool selected,
  ) => PopupMenuItem(
    value: value,
    child: Row(
      children: [
        SizedBox(
          width: MuyuSpacing.xl,
          child: selected ? const Icon(Icons.check, size: 18) : null,
        ),
        Text(title),
      ],
    ),
  );

  void _handleTaskListMenuAction(_TaskListMenuAction action) {
    switch (action) {
      case _TaskListMenuAction.sortDueAt:
        setState(() => _taskListSort = TaskListSort.dueAt);
      case _TaskListMenuAction.sortQuadrant:
        setState(() => _taskListSort = TaskListSort.quadrant);
      case _TaskListMenuAction.sortUpdatedAt:
        setState(() => _taskListSort = TaskListSort.updatedAt);
      case _TaskListMenuAction.sortCreatedAt:
        setState(() => _taskListSort = TaskListSort.createdAt);
      case _TaskListMenuAction.toggleSubtitle:
        setState(() => _showTaskSubtitle = !_showTaskSubtitle);
      case _TaskListMenuAction.toggleCompleted:
        setState(() => _showCompleted = !_showCompleted);
      case _TaskListMenuAction.toggleFailed:
        setState(() => _showFailed = !_showFailed);
    }
  }

  void _openApprovals() {
    final snapshot = _sync.state.snapshot;
    if (snapshot == null) return;
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => TaskApprovalScreen(
          sync: _sync,
          currentUserId: widget.session?.user.id ?? snapshot.viewerUserId ?? '',
          canWrite: widget.canWrite,
        ),
      ),
    );
  }

  void _openWebQrScanner() {
    final signingKey = widget.signingKey;
    if (signingKey == null) return;
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => WebQrScannerScreen(
          repository: HttpDeviceAuthorizationRepository(widget.api),
          signingKey: signingKey,
        ),
      ),
    );
  }

  Future<void> _openCreateTask() async {
    if (!widget.canWrite) return;
    if (_sync.state.isStale) {
      await _sync.refresh();
      if (!mounted) return;
      if (_sync.state.isStale) {
        ScaffoldMessenger.of(context)
            .showSnackBar(const SnackBar(content: Text('任务数据暂时不可用，请下拉刷新后重试')));
        return;
      }
    }
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (_) => _CreateTaskBar(sync: _sync, enabled: true),
    );
  }

  void _openTask(TaskItem task) {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      showDragHandle: true,
      backgroundColor: Theme.of(context).colorScheme.surface,
      builder: (sheetContext) => SizedBox(
        key: const Key('task-detail-bottom-sheet'),
        height: MediaQuery.sizeOf(sheetContext).height * 0.86,
        child: TaskDetailScreen(
          task: task,
          sync: _sync,
          canWrite: widget.canWrite,
          inSheet: true,
        ),
      ),
    );
  }

  void _openAllTasks() {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => AllTasksScreen(
          repository: TaskQueryRepository(widget.api),
          members: _sync.state.snapshot?.members ?? const [],
          onTaskTap: _openTask,
        ),
      ),
    );
  }
}

enum _WorkspaceSummaryKind { needsAction, waitingOnOther, dueSoon }

class _WorkspaceContextHeader extends StatelessWidget {
  const _WorkspaceContextHeader({
    required this.state,
    required this.viewerName,
    required this.onSummaryTap,
  });

  final WorkspaceSyncState state;
  final String viewerName;
  final ValueChanged<_WorkspaceSummaryKind> onSummaryTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final horizontalPadding = MediaQuery.sizeOf(context).width >= 360
        ? MuyuSpacing.xl
        : MuyuSpacing.lg;
    final home = state.home;
    final extension = theme.extension<MuyuThemeExtension>();
    final status = state.loading
        ? '同步中'
        : state.isStale || state.errorMessage != null
        ? '可能不是最新'
        : '已同步';
    final statusColor =
        state.loading || state.isStale || state.errorMessage != null
        ? theme.colorScheme.onSurfaceVariant
        : extension?.sync ?? theme.colorScheme.secondary;
    final metrics = [
      (
        _WorkspaceSummaryKind.needsAction,
        'needs-action',
        home?.needsActionCount ?? 0,
        '需要我处理',
        '轮到我回应',
      ),
      (
        _WorkspaceSummaryKind.waitingOnOther,
        'waiting-on-other',
        home?.waitingOnOtherCount ?? 0,
        '等对方',
        '交给 TA 的下一棒',
      ),
      (
        _WorkspaceSummaryKind.dueSoon,
        'due-soon',
        home?.dueSoonCount ?? 0,
        '即将到期',
        '未来 14 天内截止',
      ),
    ];
    return DecoratedBox(
      key: const Key('workspace-context-header'),
      decoration: BoxDecoration(color: theme.scaffoldBackgroundColor),
      child: Column(
        children: [
          Padding(
            padding: EdgeInsets.fromLTRB(
              horizontalPadding,
              MuyuSpacing.md,
              horizontalPadding,
              MuyuSpacing.lg,
            ),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    '$viewerName，${home?.needsActionCount == 0 ? '此刻没有待处理的请求' : '有 ${home?.needsActionCount ?? 0} 件事等你回应'}。',
                    key: const Key('workspace-moment-greeting'),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.bodySmall,
                  ),
                ),
                if (status != '已同步')
                  Text(
                    status,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: statusColor,
                    ),
                  ),
              ],
            ),
          ),
          Padding(
            padding: EdgeInsets.only(
              left: horizontalPadding,
              right: horizontalPadding,
              bottom: MuyuSpacing.md,
            ),
            child: Row(
              key: const Key('workspace-summary-grid'),
              children: [
                for (var index = 0; index < metrics.length; index++) ...[
                  if (index > 0) const SizedBox(width: MuyuSpacing.sm),
                  Expanded(
                    child: _WorkspaceSummaryCard(
                      key: Key('workspace-summary-${metrics[index].$2}'),
                      count: metrics[index].$3,
                      label: metrics[index].$4,
                      caption: metrics[index].$5,
                      highlighted: index == 0,
                      onTap: () => onSummaryTap(metrics[index].$1),
                    ),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _WorkspaceSummaryCard extends StatelessWidget {
  const _WorkspaceSummaryCard({
    super.key,
    required this.count,
    required this.label,
    required this.caption,
    required this.highlighted,
    required this.onTap,
  });

  final int count;
  final String label;
  final String caption;
  final bool highlighted;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Semantics(
      button: true,
      label: '$label，$count项',
      child: Material(
        color: highlighted
            ? theme.colorScheme.primary
            : label == '等对方'
            ? theme.extension<MuyuThemeExtension>()?.sageSurface ??
                  theme.colorScheme.secondaryContainer
            : theme.extension<MuyuThemeExtension>()?.warmSurface ??
                  theme.colorScheme.surfaceContainerHighest,
        shape: RoundedRectangleBorder(
          borderRadius: const BorderRadius.all(Radius.circular(14)),
          side: BorderSide(
            color: highlighted
                ? theme.colorScheme.primary
                : theme.colorScheme.outline,
          ),
        ),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          child: SizedBox(
            height: 108,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(10, 10, 10, 8),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          label,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: theme.textTheme.labelMedium?.copyWith(
                            color: highlighted
                                ? theme.colorScheme.onPrimary
                                : theme.colorScheme.onSurface,
                            fontSize: 11,
                            height: 14 / 11,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                      Icon(
                        Icons.arrow_forward,
                        size: 12,
                        color: highlighted
                            ? theme.colorScheme.onPrimary
                            : theme.colorScheme.onSurfaceVariant,
                      ),
                    ],
                  ),
                  const SizedBox(height: MuyuSpacing.sm),
                  Text.rich(
                    TextSpan(
                      children: [
                        TextSpan(text: '$count'),
                        const TextSpan(
                          text: '件',
                          style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w400,
                          ),
                        ),
                      ],
                    ),
                    style: theme.textTheme.titleMedium?.copyWith(
                      color: highlighted
                          ? theme.colorScheme.onPrimary
                          : theme.colorScheme.onSurface,
                      fontSize: 28,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const Spacer(),
                  Text(
                    caption,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: highlighted
                          ? theme.colorScheme.onPrimary.withValues(alpha: 0.7)
                          : theme.colorScheme.onSurfaceVariant,
                      fontSize: 9,
                      height: 12 / 9,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _WorkspaceSummarySheet extends StatefulWidget {
  const _WorkspaceSummarySheet({
    required this.title,
    required this.description,
    required this.count,
    required this.tasks,
    required this.approvals,
    required this.members,
    required this.onOpenApprovals,
    required this.hasMore,
    required this.entry,
    required this.repository,
  });

  final String title;
  final String description;
  final int count;
  final List<TaskItem> tasks;
  final List<HomeApprovalItem> approvals;
  final List<Map<String, dynamic>> members;
  final VoidCallback onOpenApprovals;
  final bool hasMore;
  final String entry;
  final HomeEntryRepository repository;

  @override
  State<_WorkspaceSummarySheet> createState() => _WorkspaceSummarySheetState();
}

class _WorkspaceSummarySheetState extends State<_WorkspaceSummarySheet> {
  late List<TaskItem> _tasks;
  late List<HomeApprovalItem> _approvals;
  late bool _hasMore;
  String? _cursor;
  String? _error;
  bool _loading = false;

  @override
  void initState() {
    super.initState();
    _tasks = List.of(widget.tasks);
    _approvals = List.of(widget.approvals);
    _hasMore = widget.hasMore;
  }

  Future<void> _loadMore() async {
    if (_loading || !_hasMore) return;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final page = await widget.repository.load(
        entry: widget.entry,
        afterCursor: _cursor,
      );
      if (!mounted) return;
      final seenTasks = _tasks.map((task) => task.id).toSet();
      final seenApprovals = _approvals
          .map((item) => item.approvalRequest.id)
          .toSet();
      setState(() {
        _tasks = [
          ..._tasks,
          for (final task in page.tasks)
            if (seenTasks.add(task.id)) task,
        ];
        _approvals = [
          ..._approvals,
          for (final item in page.approvals)
            if (seenApprovals.add(item.approvalRequest.id)) item,
        ];
        _hasMore = page.hasMore;
        _cursor = page.nextCursor;
      });
    } catch (error) {
      if (!mounted) return;
      setState(
        () => _error = error is ApiException ? error.message : '加载失败，请重试',
      );
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isApprovalEntry = widget.entry != 'due_soon';
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(
          MuyuSpacing.lg,
          MuyuSpacing.md,
          MuyuSpacing.lg,
          MuyuSpacing.lg,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(widget.title, style: theme.textTheme.titleLarge),
                ),
                IconButton(
                  key: const Key('workspace-summary-close'),
                  tooltip: '关闭',
                  onPressed: () => Navigator.of(context).pop(),
                  icon: const Icon(Icons.close),
                ),
              ],
            ),
            Text(
              isApprovalEntry
                  ? widget.entry == 'needs_me'
                        ? '接棒与验收，等你确认。'
                        : '下一棒已交给对方，回应后会自动更新。'
                  : widget.description,
              style: theme.textTheme.bodySmall,
            ),
            const SizedBox(height: MuyuSpacing.md),
            Text(
              isApprovalEntry
                  ? '${widget.count} 件待处理请求'
                  : '${widget.count} 件即将到期的任务',
              style: theme.textTheme.titleMedium?.copyWith(
                color: theme.colorScheme.primary,
              ),
            ),
            Expanded(
              child: ListView(
                children: [
                  if (isApprovalEntry)
                    for (final item in _approvals) _approvalCard(context, item)
                  else
                    for (final task in _tasks)
                      ListTile(
                        key: Key('workspace-summary-task-${task.id}'),
                        title: Text(
                          task.title,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        subtitle: Text(taskStatusLabel(task.status)),
                        trailing: const Icon(Icons.chevron_right),
                        onTap: () => Navigator.of(context).pop(task),
                      ),
                  if (isApprovalEntry && _approvals.isEmpty && !_hasMore)
                    const Padding(
                      padding: EdgeInsets.all(MuyuSpacing.lg),
                      child: Text('暂无待处理请求'),
                    ),
                ],
              ),
            ),
            if (_error != null)
              Text(
                _error!,
                key: const Key('workspace-summary-error'),
                style: TextStyle(color: theme.colorScheme.error),
              ),
            if (_hasMore)
              TextButton(
                key: const Key('workspace-summary-load-more'),
                onPressed: _loading ? null : _loadMore,
                child: Text(_loading ? '加载中' : '加载更多'),
              ),
            const SizedBox(height: MuyuSpacing.sm),
          ],
        ),
      ),
    );
  }

  Widget _approvalCard(BuildContext context, HomeApprovalItem item) {
    final request = item.approvalRequest;
    final task = item.task;
    final theme = Theme.of(context);
    final type = switch (request.requestType) {
      'TASK_INVITATION' => '任务邀请',
      'HANDLER_TRANSFER' => '责任交接',
      'STATUS_UPDATE'
          when request.proposedChanges['review_submission'] == true =>
        '成果验收',
      _ => '审批请求',
    };
    final proposedHandler = request.proposedChanges['current_handler_id'];
    final summary = request.requestType == 'TASK_INVITATION'
        ? '同意后才建立任务'
        : request.requestType == 'HANDLER_TRANSFER' && proposedHandler is String
        ? '负责人：${_memberName(proposedHandler)}'
        : request.requestType == 'STATUS_UPDATE'
        ? '提交验收 · 等待确认'
        : '请查看申请内容';
    final proposedTitle =
        request.proposedChanges['title'] ?? request.proposedChanges['name'];
    return Padding(
      padding: const EdgeInsets.only(bottom: MuyuSpacing.sm),
      child: Material(
        key: Key('workspace-summary-request-${request.id}'),
        color: theme.colorScheme.surface,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(8),
          side: BorderSide(color: theme.colorScheme.outline),
        ),
        child: InkWell(
          onTap: () {
            Navigator.of(context).pop(task);
            if (task == null) widget.onOpenApprovals();
          },
          child: Padding(
            padding: const EdgeInsets.all(MuyuSpacing.md),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        type,
                        style: theme.textTheme.labelMedium?.copyWith(
                          color: theme.colorScheme.primary,
                        ),
                      ),
                    ),
                    Text(
                      widget.entry == 'needs_me' ? '等我回应' : '等 TA 回应',
                      style: theme.textTheme.bodySmall,
                    ),
                  ],
                ),
                const SizedBox(height: MuyuSpacing.sm),
                Text(
                  task?.title ??
                      (proposedTitle is String ? proposedTitle : '申请详情'),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.titleMedium,
                ),
                const SizedBox(height: MuyuSpacing.xs),
                Text(
                  summary,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.bodySmall,
                ),
                const Divider(height: MuyuSpacing.lg),
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        '${_memberName(request.requesterId)} → ${_memberName(request.approverId)}',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.bodySmall,
                      ),
                    ),
                    Text('查看申请', style: theme.textTheme.bodySmall),
                    const Icon(Icons.chevron_right, size: 16),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  String _memberName(String id) {
    for (final member in widget.members) {
      if (member['user_id'] == id) {
        final name = member['display_name'];
        if (name is String && name.trim().isNotEmpty) return name.trim();
      }
    }
    return '协作成员';
  }
}

class _MatterViewSelector extends StatelessWidget {
  const _MatterViewSelector({required this.value, required this.onSelected});

  final _MatterView value;
  final ValueChanged<_MatterView> onSelected;

  @override
  Widget build(BuildContext context) => PopupMenuButton<_MatterView>(
    key: const Key('matter-view-menu'),
    tooltip: '切换事项视图',
    initialValue: value,
    onSelected: onSelected,
    itemBuilder: (context) => [
      for (final option in _MatterView.values)
        CheckedPopupMenuItem<_MatterView>(
          key: Key('matter-view-item-${option.name}'),
          value: option,
          checked: option == value,
          child: Text(_menuTitle(option)),
        ),
    ],
    child: Semantics(
      button: true,
      label: '事项视图：${_title(value)}，打开菜单',
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            _title(value),
            overflow: TextOverflow.ellipsis,
            style: Theme.of(context).textTheme.titleLarge,
          ),
          const Icon(Icons.keyboard_arrow_down, size: 20),
        ],
      ),
    ),
  );

  static String _title(_MatterView view) => switch (view) {
    _MatterView.moment => '此刻',
    _MatterView.quadrant => '四象限',
    _MatterView.schedule => '日程',
  };

  static String _menuTitle(_MatterView view) => switch (view) {
    _MatterView.moment => '清单',
    _MatterView.quadrant => '四象限',
    _MatterView.schedule => '日程',
  };
}

class _TaskCategorySelector extends StatelessWidget {
  const _TaskCategorySelector({
    required this.categories,
    required this.selectedLabel,
    required this.onSelected,
    this.compact = false,
  });

  final List<TaskListCategory> categories;
  final String? selectedLabel;
  final ValueChanged<String?> onSelected;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final selectedTitle = _selectedTitle();
    return PopupMenuButton<String>(
      key: const Key('task-category-selector'),
      tooltip: compact ? '筛选任务分类：$selectedTitle' : '选择任务分类',
      onSelected: (value) => onSelected(value.isEmpty ? null : value),
      itemBuilder: (context) => [
        for (final category in categories)
          PopupMenuItem<String>(
            key: Key('task-category-item-${category.label ?? 'all'}'),
            value: category.label ?? '',
            child: Row(
              children: [
                Text(category.title),
                if (category.unfinishedCount > 0) ...[
                  const Spacer(),
                  Text(
                    '${category.unfinishedCount}',
                    key: Key('task-category-count-${category.label ?? 'all'}'),
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: Theme.of(context).colorScheme.error,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ],
              ],
            ),
          ),
      ],
      child: compact
          ? Padding(
              padding: const EdgeInsets.all(MuyuSpacing.md),
              child: Icon(
                selectedLabel == null
                    ? Icons.filter_list_outlined
                    : Icons.filter_list,
                size: 20,
                semanticLabel: '任务分类：$selectedTitle',
              ),
            )
          : Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Flexible(
                  child: Text(
                    selectedTitle,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.titleMedium
                        ?.copyWith(fontWeight: FontWeight.w700),
                  ),
                ),
                const Icon(Icons.keyboard_arrow_down, size: 20),
              ],
            ),
    );
  }

  String _selectedTitle() {
    if (selectedLabel == null) return '全部任务';
    for (final category in categories) {
      if (category.label == selectedLabel) return category.title;
    }
    return selectedLabel!;
  }
}

class _UnavailableProfileView extends StatelessWidget {
  const _UnavailableProfileView({super.key});

  @override
  Widget build(BuildContext context) => const Center(child: Text('当前会话不可用'));
}

class _CreateTaskBar extends StatefulWidget {
  const _CreateTaskBar({required this.sync, required this.enabled});
  final WorkspaceSyncController sync;
  final bool enabled;

  @override
  State<_CreateTaskBar> createState() => _CreateTaskBarState();
}

class _CreateTaskBarState extends State<_CreateTaskBar> {
  final _title = TextEditingController();
  final _nextStep = TextEditingController();
  final _acceptance = TextEditingController();
  final _labels = <String>[];
  DateTime? _dueAt;
  String? _selectedQuadrant;
  String? _targetHandlerId;
  String? _createError;
  bool _creating = false;

  @override
  void dispose() {
    _title.dispose();
    _nextStep.dispose();
    _acceptance.dispose();
    super.dispose();
  }

  Future<void> _pickDueAt() async {
    final initial = _dueAt ?? DateTime.now().add(const Duration(hours: 1));
    final date = await showDatePicker(
      context: context,
      initialDate: DateTime(initial.year, initial.month, initial.day),
      firstDate: DateTime(2000),
      lastDate: DateTime(2100),
    );
    if (!mounted || date == null) return;
    final time = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.fromDateTime(initial),
    );
    if (!mounted || time == null) return;
    setState(
      () => _dueAt = DateTime(
        date.year,
        date.month,
        date.day,
        time.hour,
        time.minute,
      ),
    );
  }

  Future<void> _pickLabels() async {
    final picked = await showModalBottomSheet<List<String>>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (_) => _TaskLabelPicker(
        initialLabels: _labels,
        availableLabels: _availableLabels(),
      ),
    );
    if (!mounted || picked == null) return;
    setState(() {
      _labels
        ..clear()
        ..addAll(picked);
    });
  }

  Future<void> _pickQuadrant() async {
    final picked = await showModalBottomSheet<String>(
      context: context,
      useSafeArea: true,
      builder: (_) => _TaskQuadrantPicker(selectedQuadrant: _selectedQuadrant),
    );
    if (!mounted || picked == null) return;
    setState(() => _selectedQuadrant = picked);
  }

  List<String> _availableLabels() {
    final labels = <String>{
      for (final classification in widget.sync.state.classifications)
        classification.name,
    };
    final values = labels.toList()
      ..sort((left, right) => left.compareTo(right));
    return values;
  }

  List<Map<String, dynamic>> _targetChoices() {
    final snapshot = widget.sync.state.snapshot;
    final viewerId = snapshot?.viewerUserId;
    if (snapshot == null || viewerId == null) return const [];
    return snapshot.members
        .where((member) {
          final id = member['user_id'] as String?;
          final status =
              (member['membership_status'] ?? member['status'] ?? 'ACTIVE')
                  .toString()
                  .toUpperCase();
          return id != null && id != viewerId && status == 'ACTIVE';
        })
        .toList(growable: false);
  }

  String _memberLabel(Map<String, dynamic> member) {
    final displayName = member['display_name'] as String?;
    if (displayName != null && displayName.trim().isNotEmpty) {
      return displayName.trim();
    }
    return 'TA';
  }

  Future<void> _pickTargetHandler() async {
    final choices = _targetChoices();
    if (choices.isEmpty) return;
    final picked = await showModalBottomSheet<String>(
      context: context,
      useSafeArea: true,
      builder: (_) => SafeArea(
        child: ListView(
          shrinkWrap: true,
          children: [
            const ListTile(title: Text('创建后由谁接棒？')),
            ListTile(
              leading: const Icon(Icons.person_outline),
              title: const Text('我负责'),
              trailing: _targetHandlerId == null
                  ? const Icon(Icons.check)
                  : null,
              onTap: () => Navigator.of(context).pop(''),
            ),
            for (final member in choices)
              ListTile(
                leading: const Icon(Icons.swap_horiz),
                title: Text(_memberLabel(member)),
                trailing: _targetHandlerId == member['user_id']
                    ? const Icon(Icons.check)
                    : null,
                onTap: () =>
                    Navigator.of(context).pop(member['user_id'] as String),
              ),
          ],
        ),
      ),
    );
    if (!mounted || picked == null) return;
    setState(() => _targetHandlerId = picked.isEmpty ? null : picked);
  }

  String _dueText(DateTime value) {
    final local = value.toLocal();
    const weekdays = <String>['一', '二', '三', '四', '五', '六', '日'];
    final weekday = weekdays[local.weekday - 1];
    final month = local.month.toString().padLeft(2, '0');
    final day = local.day.toString().padLeft(2, '0');
    final hour = local.hour.toString().padLeft(2, '0');
    final minute = local.minute.toString().padLeft(2, '0');
    return '$month月$day日 周$weekday $hour:$minute';
  }

  Color _quadrantColor(BuildContext context, String? quadrant) {
    final extension = Theme.of(context).extension<MuyuThemeExtension>();
    return switch (quadrant) {
      'Q1' => extension?.quadrantQ1 ?? Theme.of(context).colorScheme.error,
      'Q2' => extension?.quadrantQ2 ?? Theme.of(context).colorScheme.primary,
      'Q3' => extension?.quadrantQ3 ?? Theme.of(context).colorScheme.primary,
      'Q4' => extension?.quadrantQ4 ?? Theme.of(context).colorScheme.primary,
      _ => Theme.of(context).colorScheme.onSurfaceVariant,
    };
  }

  Future<void> _createTask() async {
    final title = _title.text.trim();
    final nextStep = _nextStep.text.trim();
    final quadrant = _selectedQuadrant;
    if (title.isEmpty || quadrant == null || _creating || !widget.enabled) {
      return;
    }
    if (nextStep.isEmpty) {
      setState(() => _createError = '请填写明确下一步');
      return;
    }
    if (nextStep.runes.length > 90) {
      setState(() => _createError = '明确下一步不能超过 90 个字符');
      return;
    }
    final acceptance = _acceptance.text.trim();
    if (acceptance.runes.length > 500) {
      setState(() => _createError = '完成标准不能超过 500 字');
      return;
    }
    if (_targetHandlerId != null && acceptance.isEmpty) {
      setState(() => _createError = '邀请 TA 时请填写完成标准');
      return;
    }
    if (_labels.length != 1) {
      setState(() => _createError = '请选择一个已批准分类');
      return;
    }
    setState(() => _creating = true);
    try {
      await widget.sync.create(
        title,
        quadrant: quadrant,
        labels: List.unmodifiable(_labels),
        nextStepText: nextStep,
        acceptanceCriteria: acceptance.isEmpty ? null : acceptance,
        dueAt: _dueAt?.toUtc().toIso8601String(),
        targetHandlerId: _targetHandlerId,
      );
      if (mounted) {
        _title.clear();
        _nextStep.clear();
        _acceptance.clear();
        _labels.clear();
        _dueAt = null;
        _selectedQuadrant = null;
        _targetHandlerId = null;
        _createError = null;
        setState(() => _creating = false);
        Navigator.of(context).pop();
      }
    } catch (error) {
      if (mounted) {
        setState(() {
          _creating = false;
          _createError = '$error';
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) => Padding(
    padding: EdgeInsets.fromLTRB(
      MuyuSpacing.lg,
      MuyuSpacing.md,
      MuyuSpacing.lg,
      MuyuSpacing.lg + MediaQuery.viewInsetsOf(context).bottom,
    ),
    child: SingleChildScrollView(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text(
                '新建任务',
                style: Theme.of(context).textTheme.titleLarge
                    ?.copyWith(fontWeight: FontWeight.w700),
              ),
              const Spacer(),
              IconButton(
                tooltip: '关闭',
                onPressed: _creating ? null : () => Navigator.of(context).pop(),
                icon: const Icon(Icons.close),
              ),
            ],
          ),
          TextField(
            key: const Key('task-title-input'),
            controller: _title,
            enabled: widget.enabled && !_creating,
            autofocus: true,
            textInputAction: TextInputAction.done,
            onSubmitted: (_) => _createTask(),
            decoration: InputDecoration(
              labelText: '新任务标题',
              errorText: _createError,
              suffixIcon: IconButton(
                key: const Key('create-task-button'),
                tooltip: '创建任务',
                onPressed:
                    widget.enabled &&
                        !_creating &&
                        _title.text.trim().isNotEmpty &&
                        _nextStep.text.trim().isNotEmpty &&
                        _acceptance.text.trim().isNotEmpty &&
                        _selectedQuadrant != null &&
                        _labels.length == 1
                    ? _createTask
                    : null,
                icon: _creating
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.add),
              ),
            ),
            onChanged: (_) => setState(() {}),
          ),
          const SizedBox(height: MuyuSpacing.sm),
          TextField(
            key: const Key('task-next-step-input'),
            controller: _nextStep,
            enabled: widget.enabled && !_creating,
            maxLines: 2,
            maxLength: 90,
            textInputAction: TextInputAction.next,
            decoration: const InputDecoration(labelText: '明确下一步'),
            onChanged: (_) => setState(() {}),
          ),
          TextField(
            key: const Key('task-acceptance-input'),
            controller: _acceptance,
            enabled: widget.enabled && !_creating,
            minLines: 2,
            maxLines: 4,
            maxLength: 500,
            decoration: const InputDecoration(labelText: '完成标准'),
            onChanged: (_) => setState(() {}),
          ),
          const SizedBox(height: MuyuSpacing.sm),
          Row(
            children: [
              Flexible(
                fit: FlexFit.loose,
                child: AnimatedSize(
                  duration: const Duration(milliseconds: 180),
                  curve: Curves.easeOut,
                  child: _dueAt == null
                      ? IconButton(
                          key: const Key('task-create-due-button'),
                          tooltip: '选择截止时间',
                          onPressed: widget.enabled && !_creating
                              ? _pickDueAt
                              : null,
                          style: IconButton.styleFrom(
                            backgroundColor: Theme.of(context)
                                .colorScheme
                                .surfaceContainerHighest,
                            foregroundColor: Theme.of(context)
                                .colorScheme
                                .onSurfaceVariant,
                            shape: const CircleBorder(),
                          ),
                          icon: const Icon(Icons.schedule_outlined),
                        )
                      : FilledButton.icon(
                          key: const Key('task-create-due-button'),
                          onPressed: widget.enabled && !_creating
                              ? _pickDueAt
                              : null,
                          icon: const Icon(Icons.schedule, size: 18),
                          label: FittedBox(
                            fit: BoxFit.scaleDown,
                            alignment: Alignment.centerLeft,
                            child: Text(
                              _dueText(_dueAt!),
                              maxLines: 1,
                              style: Theme.of(context).textTheme.bodySmall,
                            ),
                          ),
                          style: FilledButton.styleFrom(
                            backgroundColor: Theme.of(context)
                                .colorScheme
                                .surfaceContainerHighest,
                            foregroundColor: Theme.of(context)
                                .colorScheme
                                .onSurface,
                            padding: const EdgeInsets.symmetric(horizontal: 10),
                            minimumSize: const Size(0, 40),
                            shape: const StadiumBorder(),
                          ),
                        ),
                ),
              ),
              Flexible(
                fit: FlexFit.loose,
                child: AnimatedSize(
                  duration: const Duration(milliseconds: 180),
                  curve: Curves.easeOut,
                  child: _labels.isEmpty
                      ? IconButton(
                          key: const Key('task-create-label-button'),
                          onPressed: widget.enabled && !_creating
                              ? _pickLabels
                              : null,
                          style: IconButton.styleFrom(
                            backgroundColor: Theme.of(context)
                                .colorScheme
                                .surfaceContainerHighest,
                            foregroundColor: Theme.of(context)
                                .colorScheme
                                .onSurfaceVariant,
                            shape: const CircleBorder(),
                          ),
                          icon: const Icon(Icons.star_border),
                        )
                      : FilledButton.icon(
                          key: const Key('task-create-label-button'),
                          onPressed: widget.enabled && !_creating
                              ? _pickLabels
                              : null,
                          icon: const Icon(Icons.star, size: 18),
                          label: FittedBox(
                            fit: BoxFit.scaleDown,
                            alignment: Alignment.centerLeft,
                            child: Text(
                              _categoryButtonText(),
                              maxLines: 1,
                              style: Theme.of(context).textTheme.bodySmall,
                            ),
                          ),
                          style: FilledButton.styleFrom(
                            backgroundColor: Theme.of(context)
                                .colorScheme
                                .surfaceContainerHighest,
                            foregroundColor: Theme.of(context)
                                .colorScheme
                                .primary,
                            padding: const EdgeInsets.symmetric(horizontal: 10),
                            minimumSize: const Size(0, 40),
                            shape: const StadiumBorder(),
                          ),
                        ),
                ),
              ),
              if (_targetChoices().isNotEmpty)
                Flexible(
                  fit: FlexFit.loose,
                  child: FilledButton.icon(
                    key: const Key('task-create-handler-button'),
                    onPressed: widget.enabled && !_creating
                        ? _pickTargetHandler
                        : null,
                    icon: const Icon(Icons.swap_horiz, size: 18),
                    label: FittedBox(
                      fit: BoxFit.scaleDown,
                      alignment: Alignment.centerLeft,
                      child: Text(
                        _targetHandlerId == null ? '我负责' : '交给 TA',
                        maxLines: 1,
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                    ),
                    style: FilledButton.styleFrom(
                      backgroundColor: _targetHandlerId == null
                          ? Theme.of(context)
                                .colorScheme
                                .surfaceContainerHighest
                          : Theme.of(context).colorScheme.secondaryContainer,
                      foregroundColor: Theme.of(context).colorScheme.onSurface,
                      padding: const EdgeInsets.symmetric(horizontal: 10),
                      minimumSize: const Size(0, 40),
                      shape: const StadiumBorder(),
                    ),
                  ),
                ),
              IconButton(
                key: const Key('task-create-quadrant-button'),
                tooltip: '选择四象限（必选）',
                onPressed: widget.enabled && !_creating ? _pickQuadrant : null,
                style: IconButton.styleFrom(
                  backgroundColor: _selectedQuadrant == null
                      ? Theme.of(context).colorScheme.surfaceContainerHighest
                      : _quadrantColor(context, _selectedQuadrant),
                  foregroundColor: _selectedQuadrant == null
                      ? Theme.of(context).colorScheme.onSurfaceVariant
                      : Theme.of(context).colorScheme.onPrimary,
                  shape: const CircleBorder(),
                ),
                icon: Icon(
                  _selectedQuadrant == null
                      ? Icons.priority_high_outlined
                      : Icons.priority_high,
                  color: _selectedQuadrant == null
                      ? Theme.of(context).colorScheme.onSurfaceVariant
                      : Theme.of(context).colorScheme.onPrimary,
                ),
              ),
            ],
          ),
        ],
      ),
    ),
  );

  String _categoryButtonText() {
    return _labels.single;
  }
}

class _TaskLabelPicker extends StatefulWidget {
  const _TaskLabelPicker({
    required this.initialLabels,
    required this.availableLabels,
  });

  final List<String> initialLabels;
  final List<String> availableLabels;

  @override
  State<_TaskLabelPicker> createState() => _TaskLabelPickerState();
}

class _TaskLabelPickerState extends State<_TaskLabelPicker> {
  late final List<String> _availableLabels;
  final _selectedLabels = <String>[];

  @override
  void initState() {
    super.initState();
    _availableLabels = [...widget.availableLabels];
    if (widget.initialLabels.isNotEmpty) {
      _selectedLabels.add(widget.initialLabels.first);
    }
  }

  @override
  void dispose() {
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Padding(
    padding: EdgeInsets.fromLTRB(
      MuyuSpacing.lg,
      MuyuSpacing.md,
      MuyuSpacing.lg,
      MuyuSpacing.lg + MediaQuery.viewInsetsOf(context).bottom,
    ),
    child: SingleChildScrollView(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '选择分类（必选一个）',
            style: Theme.of(context).textTheme.titleLarge
                ?.copyWith(fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: MuyuSpacing.sm),
          if (_availableLabels.isNotEmpty) ...[
            const SizedBox(height: MuyuSpacing.sm),
            Wrap(
              spacing: MuyuSpacing.xs,
              runSpacing: MuyuSpacing.xs,
              children: [
                for (final label in _availableLabels)
                  ChoiceChip(
                    key: Key('task-create-label-option-$label'),
                    label: Text(label),
                    selected: _selectedLabels.contains(label),
                    onSelected: (selected) {
                      setState(() {
                        if (selected) {
                          _selectedLabels
                            ..clear()
                            ..add(label);
                        } else {
                          _selectedLabels.remove(label);
                        }
                      });
                    },
                  ),
              ],
            ),
          ] else
            const Padding(
              padding: EdgeInsets.symmetric(vertical: MuyuSpacing.sm),
              child: Text('暂无已批准分类，请前往“我的”→“分类管理”创建'),
            ),
          const SizedBox(height: MuyuSpacing.md),
          Align(
            alignment: Alignment.centerRight,
            child: FilledButton.icon(
              key: const Key('task-create-label-done'),
              onPressed: () =>
                  Navigator.of(context)
                      .pop(List<String>.unmodifiable(_selectedLabels)),
              icon: const Icon(Icons.check),
              label: const Text('完成'),
            ),
          ),
        ],
      ),
    ),
  );
}

class _TaskQuadrantPicker extends StatelessWidget {
  const _TaskQuadrantPicker({required this.selectedQuadrant});

  final String? selectedQuadrant;

  static const _quadrants = <String, String>{
    'Q1': 'Q1 重要且紧急',
    'Q2': 'Q2 重要不紧急',
    'Q3': 'Q3 紧急不重要',
    'Q4': 'Q4 不重要不紧急',
  };

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.fromLTRB(
      MuyuSpacing.lg,
      MuyuSpacing.md,
      MuyuSpacing.lg,
      MuyuSpacing.lg,
    ),
    child: Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          '选择四象限（必选）',
          style: Theme.of(context).textTheme.titleLarge
              ?.copyWith(fontWeight: FontWeight.w700),
        ),
        const SizedBox(height: MuyuSpacing.sm),
        RadioGroup<String>(
          groupValue: selectedQuadrant,
          onChanged: (value) {
            if (value != null) Navigator.of(context).pop(value);
          },
          child: Column(
            children: [
              for (final entry in _quadrants.entries)
                RadioListTile<String>(
                  key: Key('task-create-quadrant-option-${entry.key}'),
                  value: entry.key,
                  title: Text(entry.value),
                ),
            ],
          ),
        ),
      ],
    ),
  );
}
