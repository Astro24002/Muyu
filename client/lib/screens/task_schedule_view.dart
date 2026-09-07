import 'package:flutter/material.dart';

import '../models/task.dart';
import '../models/task_view.dart';
import '../sync/workspace_sync_controller.dart';
import '../theme/muyu_theme.dart';
import 'task_list_view.dart';

class TaskScheduleView extends StatefulWidget {
  const TaskScheduleView({
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
  State<TaskScheduleView> createState() => _TaskScheduleViewState();
}

class _TaskScheduleViewState extends State<TaskScheduleView> {
  String? _selectedLabel;

  @override
  Widget build(BuildContext context) {
    final tasks = widget.state.snapshot?.tasks ?? const <TaskItem>[];
    final filtered = TaskView.filterByLabel(tasks, _selectedLabel);
    final grouped = TaskView.byDueDate(filtered);
    return RefreshIndicator(
      onRefresh: widget.sync.refresh,
      child: ListView(
        key: const Key('task-schedule-scroll'),
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(
          MuyuSpacing.lg,
          MuyuSpacing.md,
          MuyuSpacing.lg,
          MuyuSpacing.xl,
        ),
        children: [
          TaskLabelFilter(
            key: const Key('task-schedule-label-filter'),
            fieldKey: const Key('task-schedule-label-filter-field'),
            labels: widget.state.classifications.isEmpty
                ? collectTaskLabels(tasks)
                : widget.state.classifications
                      .map((classification) => classification.name)
                      .toList(),
            selectedLabel: _selectedLabel,
            onChanged: (value) => setState(() => _selectedLabel = value),
          ),
          if (widget.state.errorMessage != null)
            Padding(
              padding: const EdgeInsets.only(bottom: MuyuSpacing.md),
              child: Text(
                widget.state.errorMessage!,
                key: const Key('task-schedule-error'),
              ),
            ),
          if (grouped.isEmpty)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: MuyuSpacing.xxl),
              child: Center(child: Text('还没有任务')),
            )
          else
            for (final entry in grouped.entries)
              _ScheduleGroup(
                key: Key('task-schedule-group-${entry.key}'),
                dateKey: entry.key,
                tasks: entry.value,
                state: widget.state,
                onTaskTap: widget.onTaskTap,
              ),
        ],
      ),
    );
  }
}

class _ScheduleGroup extends StatelessWidget {
  const _ScheduleGroup({
    super.key,
    required this.dateKey,
    required this.tasks,
    required this.state,
    required this.onTaskTap,
  });

  final String dateKey;
  final List<TaskItem> tasks;
  final WorkspaceSyncState state;
  final TaskNavigationCallback onTaskTap;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: MuyuSpacing.lg),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          dateKey,
          key: Key('task-schedule-title-$dateKey'),
          style: Theme.of(context).textTheme.titleMedium,
        ),
        const SizedBox(height: MuyuSpacing.sm),
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
