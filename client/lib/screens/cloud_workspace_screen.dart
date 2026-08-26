import 'package:flutter/material.dart';

import '../core/api_client.dart';
import '../models/task.dart';
import '../models/task_view.dart';
import '../platform/device_signing_key.dart';
import '../sync/workspace_sync_controller.dart';
import '../sync/workspace_sync_repository.dart';
import '../workspace/device_authorization_repository.dart';
import 'web_qr_scanner_screen.dart';
import 'task_detail_screen.dart';

class CloudWorkspaceScreen extends StatefulWidget {
  const CloudWorkspaceScreen({super.key, required this.api, this.signingKey});

  final ApiClient api;
  final DeviceSigningKey? signingKey;

  @override
  State<CloudWorkspaceScreen> createState() => _CloudWorkspaceScreenState();
}

class _CloudWorkspaceScreenState extends State<CloudWorkspaceScreen> {
  late final WorkspaceSyncController _sync;

  @override
  void initState() {
    super.initState();
    _sync = WorkspaceSyncController(HttpWorkspaceSyncRepository(widget.api));
    _sync.start();
  }

  @override
  void dispose() {
    _sync.dispose();
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
            if (widget.signingKey != null)
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
        /* body: RefreshIndicator(
          onRefresh: _sync.refresh,
          child: ListView(
            padding: const EdgeInsets.all(16),
            children: [
              if (state.errorMessage != null)
                ListTile(
                  leading: const Icon(Icons.cloud_off),
                  title: Text(state.errorMessage!),
                  trailing: TextButton(
                    onPressed: _sync.refresh,
                    child: const Text('重试'),
                  ),
                ),
              TextField(
                controller: _title,
                textInputAction: TextInputAction.done,
                onSubmitted: (_) => _createTask(),
                decoration: InputDecoration(
                  labelText: '新任务',
                  suffixIcon: IconButton(
                    tooltip: '创建任务',
                    onPressed: _creating ? null : _createTask,
                    icon: _creating
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.add),
                  ),
                ),
              ),
              const SizedBox(height: 12),
              if (state.loading && tasks.isEmpty)
                const Padding(
                  padding: EdgeInsets.all(24),
                  child: Center(child: CircularProgressIndicator()),
                )
              else if (tasks.isEmpty)
                const Padding(
                  padding: EdgeInsets.all(32),
                  child: Center(child: Text('还没有任务')),
                )
              else
                ...tasks.map(
                  (task) => Card(
                    child: ListTile(
                      title: Text(task.title),
                      subtitle: Text(
                        task.description.isEmpty
                            ? task.status
                            : task.description,
                      ),
                      trailing: Text('v${task.version}'),
                    ),
                  ),
                ),
              if (state.snapshot != null)
                Padding(
                  padding: const EdgeInsets.only(top: 12),
                  child: Text(
                    '同步游标 ${state.cursor}',
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                ),
            ],
          ),
        ), */
      );
    },
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
                        builder: (_) =>
                            TaskDetailScreen(task: task, sync: screen._sync),
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
) => ListView(
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
            ),
        ],
      ),
  ],
);
