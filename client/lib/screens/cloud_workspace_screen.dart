import 'package:flutter/material.dart';

import '../core/api_client.dart';
import '../auth/mobile_session_store.dart';
import '../devices/device_management_repository.dart';
import '../models/task.dart';
import '../models/task_view.dart';
import '../platform/device_signing_key.dart';
import '../sync/workspace_sync_controller.dart';
import '../sync/workspace_sync_repository.dart';
import '../workspace/device_authorization_repository.dart';
import '../workspace/device_repository.dart';
import 'web_qr_scanner_screen.dart';
import 'task_detail_screen.dart';
import 'task_approval_screen.dart';
import 'my_profile_screen.dart';
import 'task_list_view.dart';
import 'task_quadrant_view.dart';
import 'task_schedule_view.dart';

enum _TaskListMenuAction {
  sortDueAt,
  sortQuadrant,
  sortUpdatedAt,
  sortCreatedAt,
  toggleSubtitle,
  toggleCompleted,
  toggleFailed,
  approvals,
}

class CloudWorkspaceScreen extends StatefulWidget {
  const CloudWorkspaceScreen({
    super.key,
    required this.api,
    this.signingKey,
    this.syncController,
    this.session,
    this.canWrite = true,
    this.waitingForPartner = false,
  });

  final ApiClient api;
  final DeviceSigningKey? signingKey;
  final WorkspaceSyncController? syncController;
  final MobileSession? session;
  final bool canWrite;
  final bool waitingForPartner;

  @override
  State<CloudWorkspaceScreen> createState() => _CloudWorkspaceScreenState();
}

class _CloudWorkspaceScreenState extends State<CloudWorkspaceScreen> {
  static const _destinationTitles = <String>['清单', '四象限', '日程', '我的'];

  final _scaffoldKey = GlobalKey<ScaffoldState>();
  late final WorkspaceSyncController _sync;
  int _selectedDestination = 0;
  String? _selectedTaskLabel;
  TaskListSort _taskListSort = TaskListSort.dueAt;
  bool _showTaskSubtitle = true;
  bool _showCompleted = true;
  bool _showFailed = true;

  @override
  void initState() {
    super.initState();
    _sync =
        widget.syncController ??
        WorkspaceSyncController(HttpWorkspaceSyncRepository(widget.api));
    if (widget.syncController == null) _sync.start();
  }

  @override
  void dispose() {
    if (widget.syncController == null) _sync.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: _sync,
    builder: (context, _) {
      final state = _sync.state;
      return Scaffold(
        key: _scaffoldKey,
        drawer: Drawer(
          key: const Key('task-list-drawer'),
          child: SafeArea(
            child: ListView(
              padding: EdgeInsets.zero,
              children: const [
                DrawerHeader(
                  child: Align(
                    alignment: Alignment.bottomLeft,
                    child: Text('菜单'),
                  ),
                ),
              ],
            ),
          ),
        ),
        appBar: _selectedDestination == 0
            ? _buildTaskListAppBar(state)
            : _buildDestinationAppBar(state),
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
            Expanded(child: _destinationStack(state)),
          ],
        ),
        bottomNavigationBar: NavigationBar(
          key: const Key('workspace-navigation-bar'),
          selectedIndex: _selectedDestination,
          onDestinationSelected: (index) =>
              setState(() => _selectedDestination = index),
          destinations: const [
            NavigationDestination(
              key: ValueKey('task-list-destination'),
              icon: Icon(Icons.list_alt_outlined),
              selectedIcon: Icon(Icons.list_alt),
              label: '清单',
            ),
            NavigationDestination(
              key: ValueKey('task-quadrant-destination'),
              icon: Icon(Icons.grid_view_outlined),
              selectedIcon: Icon(Icons.grid_view),
              label: '四象限',
            ),
            NavigationDestination(
              key: ValueKey('task-schedule-destination'),
              icon: Icon(Icons.event_outlined),
              selectedIcon: Icon(Icons.event),
              label: '日程',
            ),
            NavigationDestination(
              key: ValueKey('task-profile-destination'),
              icon: Icon(Icons.person_outline),
              selectedIcon: Icon(Icons.person),
              label: '我的',
            ),
          ],
        ),
        floatingActionButton: _selectedDestination == 0
            ? FloatingActionButton(
                key: const Key('create-task-fab'),
                tooltip: '新增任务',
                backgroundColor: const Color(0xff2f80ed),
                foregroundColor: Colors.white,
                onPressed: widget.canWrite ? _openCreateTask : null,
                child: const Icon(Icons.add),
              )
            : null,
      );
    },
  );

  PreferredSizeWidget _buildDestinationAppBar(WorkspaceSyncState state) =>
      AppBar(
        title: Text(_destinationTitles[_selectedDestination]),
        actions: [
          if (state.snapshot != null)
            IconButton(
              key: const Key('task-approval-button'),
              tooltip: '任务审批',
              onPressed: _openApprovals,
              icon: const Icon(Icons.rule),
            ),
        ],
      );

  PreferredSizeWidget _buildTaskListAppBar(WorkspaceSyncState state) => AppBar(
    centerTitle: true,
    leading: IconButton(
      key: const Key('task-list-menu-button'),
      tooltip: '菜单',
      onPressed: _openTaskListDrawer,
      icon: const Icon(Icons.menu),
    ),
    title: _TaskCategorySelector(
      categories: TaskView.listCategories(
        state.snapshot?.tasks ?? const <TaskItem>[],
      ),
      selectedLabel: _selectedTaskLabel,
      onSelected: (label) => setState(() => _selectedTaskLabel = label),
    ),
    actions: [
      PopupMenuButton<_TaskListMenuAction>(
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
            value: _TaskListMenuAction.toggleCompleted,
            checked: _showCompleted,
            child: const Text('显示已完成任务'),
          ),
          CheckedPopupMenuItem<_TaskListMenuAction>(
            value: _TaskListMenuAction.toggleFailed,
            checked: _showFailed,
            child: const Text('显示已失败任务'),
          ),
          if (state.snapshot != null)
            const PopupMenuItem<_TaskListMenuAction>(
              value: _TaskListMenuAction.approvals,
              child: Text('任务审批'),
            ),
        ],
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
          width: 24,
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
      case _TaskListMenuAction.approvals:
        _openApprovals();
    }
  }

  void _openTaskListDrawer() {
    _scaffoldKey.currentState?.openDrawer();
  }

  void _openApprovals() {
    final snapshot = _sync.state.snapshot;
    if (snapshot == null) return;
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => TaskApprovalScreen(
          sync: _sync,
          currentUserId: snapshot.viewerUserId ?? widget.session?.user.id ?? '',
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

  Widget _destinationStack(WorkspaceSyncState state) {
    return IndexedStack(
      key: const Key('workspace-destination-stack'),
      index: _selectedDestination,
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
          onTaskTap: _openTask,
        ),
        TaskQuadrantView(
          key: const PageStorageKey('task-quadrant-view'),
          sync: _sync,
          state: state,
          canWrite: widget.canWrite,
          onTaskTap: _openTask,
        ),
        TaskScheduleView(
          key: const PageStorageKey('task-schedule-view'),
          sync: _sync,
          state: state,
          canWrite: widget.canWrite,
          onTaskTap: _openTask,
        ),
        if (widget.session != null)
          MyProfileScreen(
            key: const PageStorageKey('task-profile-view'),
            session: widget.session!,
            repository: HttpDeviceRepository(widget.api),
            managementRepository: HttpDeviceManagementRepository(widget.api),
            canWrite: widget.canWrite,
            showAppBar: false,
            onWebQrLogin: widget.signingKey != null && widget.canWrite
                ? _openWebQrScanner
                : null,
          )
        else
          const _UnavailableProfileView(
            key: PageStorageKey('task-profile-view'),
          ),
      ],
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
                    style: TextStyle(
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
              style: const TextStyle(fontWeight: FontWeight.w700),
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
  final _label = TextEditingController();
  final _labels = <String>[];
  String? _selectedQuadrant;
  String? _labelError;
  String? _createError;
  bool _creating = false;

  static const _quadrantLabels = <String, String>{
    'Q1': 'Q1 重要且紧急',
    'Q2': 'Q2 重要不紧急',
    'Q3': 'Q3 紧急不重要',
    'Q4': 'Q4 不重要不紧急',
  };
  static const _maxLabelTotalLength = 320;

  @override
  void dispose() {
    _title.dispose();
    _label.dispose();
    super.dispose();
  }

  void _addLabel() {
    final label = _label.text.trim();
    if (label.isEmpty) return;
    final normalized = label.toLowerCase();
    setState(() => _labelError = null);
    if (label.runes.length > 32) {
      setState(() => _labelError = '标签不能超过 32 个字符');
      return;
    }
    if (_labels.length >= 10) {
      setState(() => _labelError = '最多添加 10 个标签');
      return;
    }
    final totalLength = _labels.fold<int>(
      0,
      (total, item) => total + item.runes.length,
    );
    if (totalLength + label.runes.length > _maxLabelTotalLength) {
      setState(() => _labelError = '标签总长度不能超过 320 个字符');
      return;
    }
    if (_labels.any((item) => item.toLowerCase() == normalized)) {
      _label.clear();
      return;
    }
    setState(() {
      _labels.add(label);
      _label.clear();
    });
  }

  void _removeLabel(String label) {
    setState(() => _labels.remove(label));
  }

  Future<void> _createTask() async {
    final title = _title.text.trim();
    final quadrant = _selectedQuadrant;
    if (title.isEmpty || quadrant == null || _creating || !widget.enabled) {
      return;
    }
    setState(() => _creating = true);
    try {
      await widget.sync.create(
        title,
        quadrant: quadrant,
        labels: List.unmodifiable(_labels),
      );
      if (mounted) {
        _title.clear();
        _label.clear();
        _labels.clear();
        _selectedQuadrant = null;
        _labelError = null;
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
      16,
      12,
      16,
      16 + MediaQuery.viewInsetsOf(context).bottom,
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
                        _selectedQuadrant != null
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
          const SizedBox(height: 8),
          DropdownButtonFormField<String>(
            key: const Key('task-create-quadrant-select'),
            initialValue: _selectedQuadrant,
            decoration: const InputDecoration(labelText: '四象限（必选）'),
            hint: const Text('请选择象限'),
            items: _quadrantLabels.entries
                .map(
                  (entry) => DropdownMenuItem(
                    value: entry.key,
                    child: Text(entry.value),
                  ),
                )
                .toList(),
            onChanged: !widget.enabled || _creating
                ? null
                : (value) => setState(() => _selectedQuadrant = value),
          ),
          const SizedBox(height: 8),
          TextField(
            key: const Key('task-create-label-input'),
            controller: _label,
            enabled: widget.enabled && !_creating && _labels.length < 10,
            textInputAction: TextInputAction.done,
            onSubmitted: (_) => _addLabel(),
            decoration: InputDecoration(
              labelText: '标签（可选）',
              errorText: _labelError,
              suffixIcon: IconButton(
                key: const Key('task-create-label-add'),
                tooltip: '添加标签',
                onPressed: widget.enabled && !_creating && _labels.length < 10
                    ? _addLabel
                    : null,
                icon: const Icon(Icons.add),
              ),
            ),
          ),
          if (_labels.isNotEmpty)
            Align(
              alignment: Alignment.centerLeft,
              child: Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Wrap(
                  spacing: 4,
                  runSpacing: 4,
                  children: [
                    for (final label in _labels)
                      InputChip(
                        key: Key('task-create-label-chip-$label'),
                        label: Text(label),
                        onDeleted: widget.enabled && !_creating
                            ? () => _removeLabel(label)
                            : null,
                      ),
                  ],
                ),
              ),
            ),
        ],
      ),
    ),
  );
}
