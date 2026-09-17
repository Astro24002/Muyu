import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../core/api_client.dart';
import '../auth/mobile_session_store.dart';
import '../devices/device_management_repository.dart';
import '../models/task.dart';
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
  bool _showCompleted = false;
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
    if (widget.syncController == null) _sync.start();
  }

  @override
  void dispose() {
    if (widget.syncController == null) _sync.dispose();
    if (widget.lifeController == null) _life.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: _sync,
    builder: (context, _) {
      final state = _sync.state;
      final theme = Theme.of(context);
      return AnnotatedRegion<SystemUiOverlayStyle>(
        value: SystemUiOverlayStyle(
          statusBarColor: theme.colorScheme.surface,
          statusBarIconBrightness: Brightness.dark,
          systemNavigationBarColor: theme.colorScheme.surface,
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
        )
      else
        const _UnavailableProfileView(key: PageStorageKey('task-profile-view')),
    ],
  );

  Widget _mattersBody(WorkspaceSyncState state) => Column(
    children: [
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
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        border: Border(top: BorderSide(color: theme.colorScheme.outline)),
      ),
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

  void _openSummary(_WorkspaceSummaryKind kind) {
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
      _WorkspaceSummaryKind.weekDue => (
        '本周到期',
        '当前视角下未来七天需要留意的任务。',
        home?.weekDueCount ?? 0,
      ),
    };
    showModalBottomSheet<void>(
      context: context,
      useSafeArea: true,
      builder: (_) => _WorkspaceSummarySheet(
        title: details.$1,
        description: details.$2,
        count: details.$3,
      ),
    );
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
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => TaskDetailScreen(
          task: task,
          sync: _sync,
          canWrite: widget.canWrite,
        ),
      ),
    );
  }
}

enum _WorkspaceSummaryKind { needsAction, waitingOnOther, weekDue }

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
        '待处理请求',
      ),
      (
        _WorkspaceSummaryKind.waitingOnOther,
        'waiting-on-other',
        home?.waitingOnOtherCount ?? 0,
        '等对方',
        '交接中',
      ),
      (
        _WorkspaceSummaryKind.weekDue,
        'week-due',
        home?.weekDueCount ?? 0,
        '本周到期',
        '未完成任务',
      ),
    ];
    return DecoratedBox(
      key: const Key('workspace-context-header'),
      decoration: BoxDecoration(color: theme.scaffoldBackgroundColor),
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(
              MuyuSpacing.lg,
              MuyuSpacing.sm,
              MuyuSpacing.lg,
              MuyuSpacing.md,
            ),
            child: DecoratedBox(
              key: const Key('workspace-actor-strip'),
              decoration: BoxDecoration(
                color: theme.colorScheme.surfaceContainerHighest.withValues(
                  alpha: 0.55,
                ),
                border: Border.all(color: theme.colorScheme.outline),
                borderRadius: const BorderRadius.all(Radius.circular(6)),
              ),
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: MuyuSpacing.md,
                  vertical: MuyuSpacing.sm,
                ),
                child: Row(
                  children: [
                    Expanded(
                      child: Text.rich(
                        TextSpan(
                          text: '正在以 ',
                          children: [
                            TextSpan(
                              text: viewerName,
                              style: TextStyle(
                                color: theme.colorScheme.primary,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                            const TextSpan(text: ' 查看'),
                          ],
                        ),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant,
                          height: 16 / 12,
                        ),
                      ),
                    ),
                    const SizedBox(width: MuyuSpacing.sm),
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        DecoratedBox(
                          decoration: BoxDecoration(
                            color: statusColor,
                            shape: BoxShape.circle,
                          ),
                          child: const SizedBox(width: 6, height: 6),
                        ),
                        const SizedBox(width: MuyuSpacing.xs),
                        Text(
                          status,
                          style: theme.textTheme.labelMedium?.copyWith(
                            color: statusColor,
                            fontSize: 10,
                            height: 14 / 10,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.only(
              left: MuyuSpacing.lg,
              right: MuyuSpacing.lg,
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
    required this.onTap,
  });

  final int count;
  final String label;
  final String caption;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Semantics(
      button: true,
      label: '$label，$count项',
      child: Material(
        color: theme.colorScheme.surface,
        shape: RoundedRectangleBorder(
          borderRadius: const BorderRadius.all(Radius.circular(8)),
          side: BorderSide(color: theme.colorScheme.outline),
        ),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          child: ConstrainedBox(
            constraints: const BoxConstraints(minHeight: 68),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(10, 10, 10, 8),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '$count',
                    style: theme.textTheme.titleMedium?.copyWith(
                      color: theme.colorScheme.primary,
                      fontSize: 20,
                      height: 20 / 20,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  const SizedBox(height: MuyuSpacing.xs),
                  Text(
                    label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.labelMedium?.copyWith(
                      color: theme.colorScheme.onSurface,
                      fontSize: 11,
                      height: 14 / 11,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  Text(
                    caption,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.bodySmall?.copyWith(
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

class _WorkspaceSummarySheet extends StatelessWidget {
  const _WorkspaceSummarySheet({
    required this.title,
    required this.description,
    required this.count,
  });

  final String title;
  final String description;
  final int count;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
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
                Expanded(child: Text(title, style: theme.textTheme.titleLarge)),
                IconButton(
                  key: const Key('workspace-summary-close'),
                  tooltip: '关闭',
                  onPressed: () => Navigator.of(context).pop(),
                  icon: const Icon(Icons.close),
                ),
              ],
            ),
            Text(description, style: theme.textTheme.bodySmall),
            const SizedBox(height: MuyuSpacing.md),
            Text(
              '$count 项',
              style: theme.textTheme.titleMedium?.copyWith(
                color: theme.colorScheme.primary,
              ),
            ),
            const SizedBox(height: MuyuSpacing.sm),
          ],
        ),
      ),
    );
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
  });

  final List<TaskListCategory> categories;
  final String? selectedLabel;
  final ValueChanged<String?> onSelected;

  @override
  Widget build(BuildContext context) {
    final selectedTitle = _selectedTitle();
    return PopupMenuButton<String>(
      key: const Key('task-category-selector'),
      tooltip: '选择任务分类',
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
      child: Row(
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
  final _labels = <String>[];
  DateTime? _dueAt;
  String? _selectedQuadrant;
  String? _createError;
  bool _creating = false;

  @override
  void dispose() {
    _title.dispose();
    _nextStep.dispose();
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
        dueAt: _dueAt?.toUtc().toIso8601String(),
      );
      if (mounted) {
        _title.clear();
        _nextStep.clear();
        _labels.clear();
        _dueAt = null;
        _selectedQuadrant = null;
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
