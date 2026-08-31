import 'package:flutter/material.dart';

import '../core/api_client.dart';
import '../auth/mobile_session_store.dart';
import '../devices/device_management_repository.dart';
import '../models/task.dart';
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

  late final WorkspaceSyncController _sync;
  int _selectedDestination = 0;

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
        appBar: AppBar(
          title: Text(_destinationTitles[_selectedDestination]),
          actions: [
            if (widget.signingKey != null && widget.canWrite)
              IconButton(
                tooltip: '扫码登录 Web',
                onPressed: () => Navigator.of(context).push(
                  MaterialPageRoute(
                    builder: (_) => WebQrScannerScreen(
                      repository: HttpDeviceAuthorizationRepository(widget.api),
                      signingKey: widget.signingKey!,
                    ),
                  ),
                ),
                icon: const Icon(Icons.qr_code_scanner),
              ),
            if (state.snapshot != null)
              IconButton(
                key: const Key('task-approval-button'),
                tooltip: '任务审批',
                onPressed: () => Navigator.of(context).push(
                  MaterialPageRoute(
                    builder: (_) => TaskApprovalScreen(
                      sync: _sync,
                      currentUserId:
                          state.snapshot!.viewerUserId ??
                          widget.session?.user.id ??
                          '',
                      canWrite: widget.canWrite,
                    ),
                  ),
                ),
                icon: const Icon(Icons.rule),
              ),
            IconButton(
              tooltip: '刷新',
              onPressed: _sync.refresh,
              icon: const Icon(Icons.refresh),
            ),
          ],
        ),
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
      );
    },
  );

  Widget _destinationStack(WorkspaceSyncState state) {
    return IndexedStack(
      key: const Key('workspace-destination-stack'),
      index: _selectedDestination,
      children: [
        Column(
          children: [
            _CreateTaskBar(
              sync: _sync,
              enabled: widget.canWrite && !state.isStale,
            ),
            Expanded(
              child: TaskListView(
                key: const PageStorageKey('task-list-view'),
                sync: _sync,
                state: state,
                canWrite: widget.canWrite,
                onTaskTap: _openTask,
              ),
            ),
          ],
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
        setState(() => _creating = false);
      }
    } catch (_) {
      if (mounted) setState(() => _creating = false);
    }
  }

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
    child: Column(
      children: [
        TextField(
          key: const Key('task-title-input'),
          controller: _title,
          enabled: widget.enabled && !_creating,
          textInputAction: TextInputAction.done,
          onSubmitted: (_) => _createTask(),
          decoration: InputDecoration(
            labelText: '新任务标题',
            errorText: widget.sync.state.errorMessage,
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
  );
}
