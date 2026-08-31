import 'package:flutter/material.dart';

import '../models/task.dart';
import '../models/task_view.dart';
import '../sync/workspace_sync_controller.dart';

typedef TaskNavigationCallback = void Function(TaskItem task);

List<String> collectTaskLabels(Iterable<TaskItem> tasks) {
  final seen = <String>{};
  final labels = <String>[];
  for (final task in tasks) {
    for (final label in task.labels) {
      final trimmed = label.trim();
      if (trimmed.isNotEmpty && seen.add(trimmed.toLowerCase())) {
        labels.add(trimmed);
      }
    }
  }
  labels.sort(
    (left, right) => left.toLowerCase().compareTo(right.toLowerCase()),
  );
  return labels;
}

class TaskListView extends StatefulWidget {
  const TaskListView({
    super.key,
    required this.sync,
    required this.state,
    required this.canWrite,
    required this.onTaskTap,
  });

  final WorkspaceSyncController sync;
  final WorkspaceSyncState state;
  final bool canWrite;
  final TaskNavigationCallback onTaskTap;

  @override
  State<TaskListView> createState() => _TaskListViewState();
}

class _TaskListViewState extends State<TaskListView> {
  String? _selectedLabel;

  @override
  Widget build(BuildContext context) {
    final tasks = widget.state.snapshot?.tasks ?? const <TaskItem>[];
    final filtered = TaskView.filterByLabel(tasks, _selectedLabel);
    final grouped = TaskView.byStatus(filtered);
    final labels = collectTaskLabels(tasks);
    return RefreshIndicator(
      onRefresh: widget.sync.refresh,
      child: ListView(
        key: const Key('task-list-scroll'),
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
        children: [
          TaskLabelFilter(
            key: const Key('task-list-label-filter'),
            labels: labels,
            selectedLabel: _selectedLabel,
            onChanged: (value) => setState(() => _selectedLabel = value),
          ),
          if (widget.state.errorMessage != null)
            Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: Text(
                widget.state.errorMessage!,
                key: const Key('task-list-error'),
              ),
            ),
          _TaskGroup(
            key: const Key('task-group-todo'),
            title: '未开始',
            tasks: grouped['TODO']!,
            state: widget.state,
            onTaskTap: widget.onTaskTap,
          ),
          _TaskGroup(
            key: const Key('task-group-active'),
            title: '进行中',
            tasks: [...grouped['IN_PROGRESS']!, ...grouped['WAITING']!],
            state: widget.state,
            onTaskTap: widget.onTaskTap,
          ),
          _TaskGroup(
            key: const Key('task-group-terminal'),
            title: '已完成/已失败',
            tasks: [...grouped['DONE']!, ...grouped['CANCELLED']!],
            state: widget.state,
            onTaskTap: widget.onTaskTap,
          ),
        ],
      ),
    );
  }
}

class TaskLabelFilter extends StatelessWidget {
  const TaskLabelFilter({
    super.key,
    required this.labels,
    required this.selectedLabel,
    required this.onChanged,
    this.fieldKey,
  });

  final List<String> labels;
  final String? selectedLabel;
  final ValueChanged<String?> onChanged;
  final Key? fieldKey;

  @override
  Widget build(BuildContext context) => DropdownButtonFormField<String>(
    key: fieldKey,
    initialValue: labels.contains(selectedLabel) ? selectedLabel : '',
    decoration: const InputDecoration(labelText: '标签筛选'),
    items: [
      const DropdownMenuItem(value: '', child: Text('全部标签')),
      for (final label in labels)
        DropdownMenuItem(value: label, child: Text(label)),
    ],
    onChanged: (value) =>
        onChanged(value == null || value.isEmpty ? null : value),
  );
}

class _TaskGroup extends StatelessWidget {
  const _TaskGroup({
    super.key,
    required this.title,
    required this.tasks,
    required this.state,
    required this.onTaskTap,
  });

  final String title;
  final List<TaskItem> tasks;
  final WorkspaceSyncState state;
  final TaskNavigationCallback onTaskTap;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 16),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Text(title, style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(width: 8),
            Text(
              '${tasks.length}',
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ],
        ),
        const SizedBox(height: 8),
        if (tasks.isEmpty)
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 8),
            child: Text('无任务'),
          )
        else
          for (final task in tasks)
            TaskSummaryCard(
              task: task,
              state: state,
              onTap: () => onTaskTap(task),
            ),
      ],
    ),
  );
}

class TaskSummaryCard extends StatelessWidget {
  const TaskSummaryCard({
    super.key,
    required this.task,
    required this.state,
    this.onTap,
  });

  final TaskItem task;
  final WorkspaceSyncState state;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) => Card(
    key: ValueKey('task-card-${task.id}'),
    child: ListTile(
      title: Text(
        task.taskNumber.isEmpty
            ? task.title
            : '${task.taskNumber} ${task.title}',
      ),
      subtitle: Text(_subtitle(task, state)),
      trailing: Text('v${task.version}'),
      onTap: onTap,
    ),
  );

  static String _subtitle(TaskItem task, WorkspaceSyncState state) {
    final pending = state.approvalRequests.any(
      (request) =>
          request.taskId == task.id &&
          request.status == 'PENDING' &&
          request.isOutgoing(state.snapshot?.viewerUserId ?? ''),
    );
    final parts = <String>[];
    if (pending) {
      parts.add('等待负责人审批');
    } else {
      parts.add(task.status);
    }
    parts.add(task.quadrant);
    if (task.labels.isNotEmpty) {
      parts.add(task.labels.map((label) => '#$label').join(' '));
    }
    if (task.dueAt != null) {
      parts.add('截止 ${_dateText(task.dueAt!)}');
    }
    if (task.status == 'WAITING') {
      parts.add(task.blockedReason ?? '等待中');
    }
    return parts.join(' · ');
  }

  static String _dateText(DateTime value) {
    final local = value.toLocal();
    final year = local.year.toString().padLeft(4, '0');
    final month = local.month.toString().padLeft(2, '0');
    final day = local.day.toString().padLeft(2, '0');
    return '$year-$month-$day';
  }
}
