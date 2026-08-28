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
import 'my_profile_screen.dart';

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
  late final WorkspaceSyncController _sync;

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
      final tasks = state.snapshot?.tasks ?? const <TaskItem>[];
      final grouped = TaskView.byStatus(tasks);
      return Scaffold(
        appBar: AppBar(
          title: const Text('共享任务'),
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
            if (widget.session != null)
              IconButton(
                tooltip: '我的',
                onPressed: () => Navigator.of(context).push(
                  MaterialPageRoute(
                    builder: (_) => MyProfileScreen(
                      session: widget.session!,
                      repository: HttpDeviceRepository(widget.api),
                      managementRepository: HttpDeviceManagementRepository(
                        widget.api,
                      ),
                      canWrite: widget.canWrite,
                    ),
                  ),
                ),
                icon: const Icon(Icons.person_outline),
              ),
            IconButton(
              tooltip: '刷新',
              onPressed: _sync.refresh,
              icon: const Icon(Icons.refresh),
            ),
          ],
        ),
        body: DefaultTabController(
          length: 3,
          child: Column(
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
              _CreateTaskBar(
                sync: _sync,
                enabled: widget.canWrite && !state.isStale,
              ),
              const TabBar(
                tabs: [
                  Tab(text: '我的任务'),
                  Tab(text: '全部任务'),
                  Tab(text: '看板'),
                ],
              ),
              Expanded(
                child: TabBarView(
                  children: [
                    _taskList(
                      context,
                      TaskView.mine(
                        tasks,
                        state.snapshot == null ||
                                state.snapshot!.members.isEmpty
                            ? ''
                            : state.snapshot!.members.first['user_id']
                                  as String,
                      ),
                      state,
                    ),
                    _taskList(context, tasks, state),
                    _board(context, grouped, state),
                  ],
                ),
              ),
            ],
          ),
        ),
      );
    },
  );
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
  bool _creating = false;

  @override
  void dispose() {
    _title.dispose();
    super.dispose();
  }

  Future<void> _createTask() async {
    final title = _title.text.trim();
    if (title.isEmpty || _creating || !widget.enabled) return;
    setState(() => _creating = true);
    try {
      await widget.sync.create(title);
      if (mounted) {
        _title.clear();
        setState(() => _creating = false);
      }
    } catch (_) {
      if (mounted) setState(() => _creating = false);
    }
  }

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
    child: TextField(
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
              widget.enabled && !_creating && _title.text.trim().isNotEmpty
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
  );
}

Widget _taskList(
  BuildContext context,
  List<TaskItem> tasks,
  WorkspaceSyncState state,
) {
  final screen = context.findAncestorStateOfType<_CloudWorkspaceScreenState>();
  return RefreshIndicator(
    onRefresh: screen?._sync.refresh ?? () async {},
    child: ListView(
      padding: const EdgeInsets.all(16),
      children: [
        if (state.errorMessage != null) Text(state.errorMessage!),
        if (tasks.isEmpty)
          const Padding(
            padding: EdgeInsets.all(32),
            child: Center(child: Text('还没有任务')),
          ),
        for (final task in tasks)
          Card(
            child: ListTile(
              title: Text(task.title),
              subtitle: Text(
                task.status == 'WAITING'
                    ? (task.blockedReason ?? '等待中')
                    : task.description.isEmpty
                    ? task.status
                    : task.description,
              ),
              trailing: Text('v${task.version}'),
              onTap: screen == null
                  ? null
                  : () => Navigator.of(context).push(
                      MaterialPageRoute(
                        builder: (_) => TaskDetailScreen(
                          task: task,
                          sync: screen._sync,
                          canWrite: screen.widget.canWrite,
                        ),
                      ),
                    ),
            ),
          ),
      ],
    ),
  );
}

Widget _board(
  BuildContext context,
  Map<String, List<TaskItem>> grouped,
  WorkspaceSyncState state,
) {
  final screen = context.findAncestorStateOfType<_CloudWorkspaceScreenState>();
  return ListView(
    padding: const EdgeInsets.all(12),
    children: [
      for (final status in TaskView.statuses)
        ExpansionTile(
          title: Text(status),
          children: [
            for (final task in grouped[status]!)
              ListTile(
                title: Text(task.title),
                subtitle: task.status == 'WAITING'
                    ? Text(task.blockedReason ?? '')
                    : null,
                onTap: screen == null
                    ? null
                    : () => Navigator.of(context).push(
                        MaterialPageRoute(
                          builder: (_) => TaskDetailScreen(
                            task: task,
                            sync: screen._sync,
                            canWrite: screen.widget.canWrite,
                          ),
                        ),
                      ),
              ),
          ],
        ),
    ],
  );
}
