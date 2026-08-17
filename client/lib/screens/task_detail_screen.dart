import 'package:flutter/material.dart';

import '../auth/session_controller.dart';
import '../models/task.dart';
import '../task/task_controller.dart';
import '../task/task_repository.dart';
import 'task_form_screen.dart';
import 'task_list_screen.dart';

class TaskDetailScreen extends StatefulWidget {
  const TaskDetailScreen({
    super.key,
    required this.initialTask,
    required this.controller,
    required this.repository,
    required this.sessionController,
  });

  final TaskItem initialTask;
  final TaskController controller;
  final TaskRepository repository;
  final SessionController sessionController;

  @override
  State<TaskDetailScreen> createState() => _TaskDetailScreenState();
}

class _TaskDetailScreenState extends State<TaskDetailScreen> {
  late final TaskController _subtasks;

  @override
  void initState() {
    super.initState();
    _subtasks = TaskController(widget.repository)
      ..load(parentTaskId: widget.initialTask.id);
  }

  @override
  void dispose() {
    _subtasks.dispose();
    super.dispose();
  }

  TaskItem get _task => widget.controller.tasks.firstWhere(
    (task) => task.id == widget.initialTask.id,
    orElse: () => widget.initialTask,
  );

  String _userName(String id) =>
      widget.sessionController.users
          .where((user) => user.id == id)
          .map((user) => user.nickname)
          .firstOrNull ??
      '未知成员';

  Future<void> _addSubtask() async {
    final created = await Navigator.of(context).push<bool>(
      MaterialPageRoute(
        builder: (_) => TaskFormScreen(
          controller: _subtasks,
          sessionController: widget.sessionController,
          parentTaskId: _task.id,
        ),
      ),
    );
    if (created == true) await _subtasks.load(parentTaskId: _task.id);
  }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: Listenable.merge([widget.controller, _subtasks]),
    builder: (context, _) {
      final task = _task;
      return Scaffold(
        appBar: AppBar(title: const Text('任务详情')),
        body: SafeArea(
          child: ListView(
            padding: const EdgeInsets.fromLTRB(20, 16, 20, 40),
            children: [
              Text(
                task.title,
                style: Theme.of(context).textTheme.headlineSmall,
              ),
              const SizedBox(height: 6),
              Text(taskStatusLabel(task.status)),
              if (task.description.isNotEmpty) ...[
                const SizedBox(height: 20),
                Text(task.description),
              ],
              const SizedBox(height: 24),
              _DetailRow(
                icon: Icons.person_outline,
                label: '当前负责人',
                value: _userName(task.currentHandlerId),
              ),
              _DetailRow(
                icon: Icons.group_outlined,
                label: '参与人',
                value: task.assigneeIds.map(_userName).join('、'),
              ),
              if (task.estimatedMinutes != null)
                _DetailRow(
                  icon: Icons.schedule_outlined,
                  label: '预计耗时',
                  value: '${task.estimatedMinutes} 分钟',
                ),
              const SizedBox(height: 20),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  if (task.status == 'TODO')
                    FilledButton.icon(
                      onPressed: () => widget.controller.start(task.id),
                      icon: const Icon(Icons.play_arrow),
                      label: const Text('开始'),
                    ),
                  if (task.status == 'TODO' || task.status == 'IN_PROGRESS')
                    FilledButton.tonalIcon(
                      onPressed: () => widget.controller.complete(task.id),
                      icon: const Icon(Icons.check),
                      label: const Text('完成'),
                    ),
                  if (task.status == 'TODO' || task.status == 'IN_PROGRESS')
                    OutlinedButton.icon(
                      onPressed: () => widget.controller.cancel(task.id),
                      icon: const Icon(Icons.close),
                      label: const Text('取消'),
                    ),
                  if (task.status == 'DONE' || task.status == 'CANCELLED')
                    FilledButton.icon(
                      onPressed: () => widget.controller.reopen(task.id),
                      icon: const Icon(Icons.replay),
                      label: const Text('重开'),
                    ),
                  if (task.assigneeIds.length > 1)
                    PopupMenuButton<String>(
                      tooltip: '转交负责人',
                      icon: const Icon(Icons.swap_horiz),
                      onSelected: (userId) =>
                          widget.controller.transfer(task.id, userId),
                      itemBuilder: (_) => task.assigneeIds
                          .where((id) => id != task.currentHandlerId)
                          .map(
                            (id) => PopupMenuItem(
                              value: id,
                              child: Text(_userName(id)),
                            ),
                          )
                          .toList(),
                    ),
                ],
              ),
              if (widget.controller.errorMessage != null) ...[
                const SizedBox(height: 12),
                Text(
                  widget.controller.errorMessage!,
                  style: TextStyle(color: Theme.of(context).colorScheme.error),
                ),
              ],
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 24),
                child: Divider(),
              ),
              Row(
                children: [
                  Expanded(
                    child: Text(
                      '子任务',
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                  ),
                  IconButton(
                    tooltip: '新建子任务',
                    onPressed: _addSubtask,
                    icon: const Icon(Icons.add),
                  ),
                ],
              ),
              if (_subtasks.loading && _subtasks.tasks.isEmpty)
                const Padding(
                  padding: EdgeInsets.all(24),
                  child: Center(child: CircularProgressIndicator()),
                )
              else if (_subtasks.tasks.isEmpty)
                const Padding(
                  padding: EdgeInsets.symmetric(vertical: 16),
                  child: Text('暂无子任务'),
                )
              else
                ..._subtasks.tasks.map(
                  (subtask) => ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: const Icon(Icons.subdirectory_arrow_right),
                    title: Text(subtask.title),
                    subtitle: Text(taskStatusLabel(subtask.status)),
                  ),
                ),
            ],
          ),
        ),
      );
    },
  );
}

class _DetailRow extends StatelessWidget {
  const _DetailRow({
    required this.icon,
    required this.label,
    required this.value,
  });

  final IconData icon;
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 10),
    child: Row(
      children: [
        Icon(icon, size: 20),
        const SizedBox(width: 10),
        SizedBox(width: 88, child: Text(label)),
        Expanded(child: Text(value)),
      ],
    ),
  );
}
