import 'dart:math';

import 'package:flutter/material.dart';

import '../core/api_client.dart';
import '../models/task.dart';
import '../sync/workspace_sync_controller.dart';
import '../sync/workspace_sync_repository.dart';

class CloudWorkspaceScreen extends StatefulWidget {
  const CloudWorkspaceScreen({super.key, required this.api});

  final ApiClient api;

  @override
  State<CloudWorkspaceScreen> createState() => _CloudWorkspaceScreenState();
}

class _CloudWorkspaceScreenState extends State<CloudWorkspaceScreen> {
  late final WorkspaceSyncController _sync;
  final _title = TextEditingController();
  bool _creating = false;

  @override
  void initState() {
    super.initState();
    _sync = WorkspaceSyncController(HttpWorkspaceSyncRepository(widget.api));
    _sync.start();
  }

  @override
  void dispose() {
    _title.dispose();
    _sync.dispose();
    super.dispose();
  }

  Future<void> _createTask() async {
    final title = _title.text.trim();
    if (title.isEmpty || _creating) return;
    setState(() => _creating = true);
    try {
      await widget.api.request(
        'POST',
        '/api/v1/tasks',
        authenticated: true,
        body: {
          'request_id': _newRequestId(),
          'title': title,
          'description': '',
        },
      );
      _title.clear();
      await _sync.refresh();
    } on ApiException catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(error.message)));
      }
    } finally {
      if (mounted) setState(() => _creating = false);
    }
  }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: _sync,
    builder: (context, _) {
      final state = _sync.state;
      final tasks = state.snapshot?.tasks ?? const <TaskItem>[];
      return Scaffold(
        appBar: AppBar(
          title: const Text('共享任务'),
          actions: [
            IconButton(
              tooltip: '刷新',
              onPressed: _sync.refresh,
              icon: const Icon(Icons.refresh),
            ),
          ],
        ),
        body: RefreshIndicator(
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
        ),
      );
    },
  );
}

String _newRequestId() {
  final random = Random.secure();
  final bytes = List<int>.generate(16, (_) => random.nextInt(256));
  final hex = bytes
      .map((value) => value.toRadixString(16).padLeft(2, '0'))
      .join();
  return '${hex.substring(0, 8)}-${hex.substring(8, 12)}-${hex.substring(12, 16)}-${hex.substring(16, 20)}-${hex.substring(20)}';
}
