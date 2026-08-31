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
    this.selectedLabel,
    this.sort = TaskListSort.dueAt,
    this.showSubtitle = true,
    this.showCompleted = true,
    this.showFailed = true,
  });

  final WorkspaceSyncController sync;
  final WorkspaceSyncState state;
  final bool canWrite;
  final TaskNavigationCallback onTaskTap;
  final String? selectedLabel;
  final TaskListSort sort;
  final bool showSubtitle;
  final bool showCompleted;
  final bool showFailed;

  @override
  State<TaskListView> createState() => _TaskListViewState();
}

class _TaskListViewState extends State<TaskListView> {
  final _collapsedGroups = <String>{};
  final _expandedTasks = <String>{};

  @override
  Widget build(BuildContext context) {
    final tasks = widget.state.snapshot?.tasks ?? const <TaskItem>[];
    final groups = TaskView.listGroups(
      tasks,
      label: widget.selectedLabel,
      sort: widget.sort,
      showCompleted: widget.showCompleted,
      showFailed: widget.showFailed,
    );
    final childrenByParent = <String, List<TaskItem>>{};
    for (final task in tasks) {
      if (task.deletedAt == null && task.parentTaskId != null) {
        childrenByParent.putIfAbsent(task.parentTaskId!, () => []).add(task);
      }
    }
    final visibleTaskCount = groups.fold<int>(
      0,
      (total, group) => total + group.tasks.length,
    );
    return RefreshIndicator(
      onRefresh: widget.sync.refresh,
      child: ListView(
        key: const Key('task-list-scroll'),
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(12, 8, 12, 96),
        children: [
          if (widget.state.errorMessage != null)
            Padding(
              padding: const EdgeInsets.fromLTRB(4, 0, 4, 8),
              child: Text(
                widget.state.errorMessage!,
                key: const Key('task-list-error'),
              ),
            ),
          if (visibleTaskCount == 0)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 40),
              child: Center(child: Text('还没有任务')),
            ),
          for (final group in groups)
            TaskListSection(
              key: Key('task-section-${group.key}'),
              headerKey: Key('task-section-header-${group.key}'),
              group: group,
              expanded: !_collapsedGroups.contains(group.key),
              showSubtitle: widget.showSubtitle,
              childrenByParent: childrenByParent,
              expandedTaskIds: _expandedTasks,
              state: widget.state,
              onToggle: () => setState(() {
                if (!_collapsedGroups.add(group.key)) {
                  _collapsedGroups.remove(group.key);
                }
              }),
              onToggleTask: (taskId) => setState(() {
                if (!_expandedTasks.add(taskId)) _expandedTasks.remove(taskId);
              }),
              onTaskTap: widget.onTaskTap,
            ),
        ],
      ),
    );
  }
}

class TaskListSection extends StatelessWidget {
  const TaskListSection({
    super.key,
    required this.headerKey,
    required this.group,
    required this.expanded,
    required this.showSubtitle,
    required this.childrenByParent,
    required this.expandedTaskIds,
    required this.state,
    required this.onToggle,
    required this.onToggleTask,
    required this.onTaskTap,
  });

  final Key headerKey;
  final TaskListGroup group;
  final bool expanded;
  final bool showSubtitle;
  final Map<String, List<TaskItem>> childrenByParent;
  final Set<String> expandedTaskIds;
  final WorkspaceSyncState state;
  final VoidCallback onToggle;
  final ValueChanged<String> onToggleTask;
  final TaskNavigationCallback onTaskTap;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 12),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Material(
          color: Colors.transparent,
          child: InkWell(
            key: headerKey,
            onTap: onToggle,
            borderRadius: const BorderRadius.all(Radius.circular(8)),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 8),
              child: Row(
                children: [
                  Text(
                    group.title,
                    style: Theme.of(context).textTheme.titleMedium
                        ?.copyWith(fontWeight: FontWeight.w700),
                  ),
                  if (group.actionLabel != null) ...[
                    const SizedBox(width: 10),
                    Text(
                      group.actionLabel!,
                      style: TextStyle(
                        color: Theme.of(context).colorScheme.primary,
                        fontSize: 13,
                      ),
                    ),
                  ],
                  const Spacer(),
                  Text(
                    '${group.tasks.length}',
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                  const SizedBox(width: 4),
                  Icon(
                    expanded
                        ? Icons.keyboard_arrow_up
                        : Icons.keyboard_arrow_down,
                    size: 22,
                  ),
                ],
              ),
            ),
          ),
        ),
        if (expanded)
          if (group.tasks.isEmpty)
            const Padding(
              padding: EdgeInsets.fromLTRB(4, 4, 4, 12),
              child: Text('无任务'),
            )
          else
            for (final task in group.tasks) ...[
              TaskListRow(
                task: task,
                state: state,
                showSubtitle: showSubtitle,
                subtasks: childrenByParent[task.id] ?? const [],
                expanded: expandedTaskIds.contains(task.id),
                onToggleSubtasks: childrenByParent.containsKey(task.id)
                    ? () => onToggleTask(task.id)
                    : null,
                onTap: () => onTaskTap(task),
              ),
              if (expandedTaskIds.contains(task.id))
                for (final subtask in childrenByParent[task.id] ?? const [])
                  Padding(
                    padding: const EdgeInsets.only(left: 28),
                    child: TaskListRow(
                      task: subtask,
                      state: state,
                      showSubtitle: showSubtitle,
                      subtasks: const [],
                      onTap: () => onTaskTap(subtask),
                    ),
                  ),
            ],
      ],
    ),
  );
}

class TaskListRow extends StatelessWidget {
  const TaskListRow({
    super.key,
    required this.task,
    required this.state,
    required this.showSubtitle,
    required this.subtasks,
    required this.onTap,
    this.expanded = false,
    this.onToggleSubtasks,
  });

  final TaskItem task;
  final WorkspaceSyncState state;
  final bool showSubtitle;
  final List<TaskItem> subtasks;
  final bool expanded;
  final VoidCallback? onToggleSubtasks;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final subtitle = _subtitle(task, state, subtasks);
    return Material(
      color: Theme.of(context).colorScheme.surface,
      child: Container(
        key: ValueKey('task-list-row-${task.id}'),
        margin: const EdgeInsets.only(bottom: 2),
        decoration: BoxDecoration(
          border: Border(
            bottom: BorderSide(
              color: Theme.of(context).dividerColor.withValues(alpha: 0.35),
            ),
          ),
        ),
        child: ListTile(
          contentPadding: const EdgeInsets.symmetric(
            horizontal: 4,
            vertical: 2,
          ),
          leading: _TaskStatusIcon(status: task.status),
          title: Text(
            task.title,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              color: _isTerminal(task.status)
                  ? Theme.of(context).textTheme.bodyLarge?.color
                        ?.withValues(alpha: 0.5)
                  : null,
              decoration: task.status == 'DONE'
                  ? TextDecoration.lineThrough
                  : TextDecoration.none,
            ),
          ),
          subtitle: showSubtitle && subtitle.isNotEmpty
              ? Text(
                  subtitle,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
                )
              : null,
          trailing: onToggleSubtasks == null
              ? null
              : IconButton(
                  key: Key('task-subtasks-toggle-${task.id}'),
                  tooltip: expanded ? '收起子任务' : '展开子任务',
                  onPressed: onToggleSubtasks,
                  icon: Icon(
                    expanded
                        ? Icons.keyboard_arrow_up
                        : Icons.keyboard_arrow_down,
                  ),
                ),
          onTap: onTap,
        ),
      ),
    );
  }

  static String _subtitle(
    TaskItem task,
    WorkspaceSyncState state,
    List<TaskItem> subtasks,
  ) {
    final pending = state.approvalRequests.any(
      (request) =>
          request.taskId == task.id &&
          request.status == 'PENDING' &&
          request.isOutgoing(state.snapshot?.viewerUserId ?? ''),
    );
    final parts = <String>[];
    if (pending) parts.add('等待负责人审批');
    final due = task.dueAt;
    if (due != null) {
      final local = due.toLocal();
      parts.add(_dateText(local));
      final now = DateTime.now().toLocal();
      final today = DateTime(now.year, now.month, now.day);
      final dueDate = DateTime(local.year, local.month, local.day);
      if (dueDate.isBefore(today)) {
        parts.add('延期${today.difference(dueDate).inDays}天');
      }
    }
    if (task.status == 'IN_PROGRESS' && task.progress != null) {
      parts.add('进度 ${task.progress}%');
    }
    if (subtasks.isNotEmpty) {
      final completed = subtasks.where((item) => item.status == 'DONE').length;
      parts.add('子任务 $completed/${subtasks.length}');
    }
    if (task.status == 'WAITING') parts.add(task.blockedReason ?? '等待中');
    return parts.join(' · ');
  }

  static String _dateText(DateTime value) {
    const weekdays = <String>['一', '二', '三', '四', '五', '六', '日'];
    final month = value.month.toString().padLeft(2, '0');
    final day = value.day.toString().padLeft(2, '0');
    final hour = value.hour.toString().padLeft(2, '0');
    final minute = value.minute.toString().padLeft(2, '0');
    return '$month/$day 周${weekdays[value.weekday - 1]} $hour:$minute';
  }

  static bool _isTerminal(String status) =>
      status == 'DONE' || status == 'CANCELLED';
}

class _TaskStatusIcon extends StatelessWidget {
  const _TaskStatusIcon({required this.status});

  final String status;

  @override
  Widget build(BuildContext context) {
    if (status == 'DONE') {
      return const Icon(Icons.check_circle, color: Color(0xff2e9d62), size: 24);
    }
    if (status == 'CANCELLED') {
      return const Icon(Icons.check_circle, color: Color(0xff7a59b8), size: 24);
    }
    final color = status == 'WAITING'
        ? const Color(0xffe28b3d)
        : Theme.of(context).colorScheme.primary;
    return Icon(Icons.radio_button_unchecked, color: color, size: 24);
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
