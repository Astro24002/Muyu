import 'package:flutter/material.dart';

import '../models/task.dart';
import '../models/task_view.dart';
import '../sync/workspace_sync_controller.dart';
import 'task_list_view.dart';

class TaskQuadrantView extends StatefulWidget {
  const TaskQuadrantView({
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
  State<TaskQuadrantView> createState() => _TaskQuadrantViewState();
}

class _TaskQuadrantViewState extends State<TaskQuadrantView> {
  String? _selectedLabel;

  @override
  Widget build(BuildContext context) {
    final tasks = widget.state.snapshot?.tasks ?? const <TaskItem>[];
    final filtered = TaskView.filterByLabel(tasks, _selectedLabel);
    final grouped = TaskView.byQuadrant(filtered);
    return RefreshIndicator(
      onRefresh: widget.sync.refresh,
      child: ListView(
        key: const Key('task-quadrant-scroll'),
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
        children: [
          TaskLabelFilter(
            key: const Key('task-quadrant-label-filter'),
            fieldKey: const Key('task-quadrant-label-filter-field'),
            labels: collectTaskLabels(tasks),
            selectedLabel: _selectedLabel,
            onChanged: (value) => setState(() => _selectedLabel = value),
          ),
          if (widget.state.errorMessage != null)
            Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: Text(
                widget.state.errorMessage!,
                key: const Key('task-quadrant-error'),
              ),
            ),
          for (final quadrant in TaskView.quadrants)
            _QuadrantGroup(
              key: Key('task-quadrant-group-$quadrant'),
              quadrant: quadrant,
              tasks: grouped[quadrant]!,
              state: widget.state,
              onTaskTap: widget.onTaskTap,
            ),
        ],
      ),
    );
  }
}

class _QuadrantGroup extends StatelessWidget {
  const _QuadrantGroup({
    super.key,
    required this.quadrant,
    required this.tasks,
    required this.state,
    required this.onTaskTap,
  });

  final String quadrant;
  final List<TaskItem> tasks;
  final WorkspaceSyncState state;
  final TaskNavigationCallback onTaskTap;

  static const _labels = <String, String>{
    'Q1': '重要且紧急',
    'Q2': '重要不紧急',
    'Q3': '紧急不重要',
    'Q4': '不重要不紧急',
  };

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 16),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          '$quadrant ${_labels[quadrant]}',
          key: Key('task-quadrant-title-$quadrant'),
          style: Theme.of(context).textTheme.titleMedium,
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
