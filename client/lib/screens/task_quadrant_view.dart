import 'package:flutter/material.dart';

import '../models/task.dart';
import '../models/task_view.dart';
import '../sync/workspace_sync_controller.dart';
import '../theme/muyu_theme.dart';
import 'task_list_view.dart';

class TaskQuadrantView extends StatefulWidget {
  const TaskQuadrantView({
    super.key,
    required this.sync,
    required this.state,
    required this.canWrite,
    required this.onTaskTap,
    this.selectedLabel,
  });

  final WorkspaceSyncController sync;
  final WorkspaceSyncState state;
  final bool canWrite;
  final TaskNavigationCallback onTaskTap;
  final String? selectedLabel;

  @override
  State<TaskQuadrantView> createState() => _TaskQuadrantViewState();
}

class _TaskQuadrantViewState extends State<TaskQuadrantView> {
  String? _expandedQuadrant;
  String _ownerFilter = 'all';

  @override
  Widget build(BuildContext context) {
    final tasks = widget.state.snapshot?.tasks ?? const <TaskItem>[];
    final viewerId =
        widget.state.snapshot?.viewerUserId ?? widget.state.home?.viewerUserId;
    final filtered = TaskView.filterByLabel(tasks, widget.selectedLabel)
        .where(TaskView.isOpen)
        .where(
          (task) =>
              _ownerFilter == 'all' ||
              (viewerId != null &&
                  (task.currentHandlerId == viewerId) ==
                      (_ownerFilter == 'mine')),
        )
        .toList();
    final grouped = TaskView.byQuadrant(filtered);
    final expandedQuadrant = _expandedQuadrant;

    // The quadrant tab is display-only. Task creation remains available from
    // the list tab, while task rows continue to open their detail screen.
    return RefreshIndicator(
      onRefresh: widget.sync.refresh,
      child: ListView(
        key: const Key('task-quadrant-scroll'),
        physics: const AlwaysScrollableScrollPhysics(),
        padding: EdgeInsets.fromLTRB(
          MediaQuery.sizeOf(context).width >= 360
              ? MuyuSpacing.xl
              : MuyuSpacing.lg,
          MuyuSpacing.sm,
          MediaQuery.sizeOf(context).width >= 360
              ? MuyuSpacing.xl
              : MuyuSpacing.lg,
          MuyuSpacing.xl,
        ),
        children: [
          if (widget.state.errorMessage != null)
            Padding(
              padding: const EdgeInsets.only(bottom: MuyuSpacing.md),
              child: Text(
                widget.state.errorMessage!,
                key: const Key('task-quadrant-error'),
              ),
            ),
          Text('让重要的事，有它的位置。', style: Theme.of(context).textTheme.bodySmall),
          const SizedBox(height: MuyuSpacing.md),
          Wrap(
            key: const Key('quadrant-owner-filter'),
            spacing: MuyuSpacing.sm,
            children: [
              for (final (value, label) in [
                ('all', '我们'),
                ('mine', '我负责'),
                ('other', 'TA 负责'),
              ])
                ChoiceChip(
                  key: Key('quadrant-owner-$value'),
                  label: Text(label),
                  selected: _ownerFilter == value,
                  onSelected: viewerId == null && value != 'all'
                      ? null
                      : (_) => setState(() {
                          _ownerFilter = value;
                          _expandedQuadrant = null;
                        }),
                ),
            ],
          ),
          const SizedBox(height: MuyuSpacing.md),
          AnimatedSize(
            key: const Key('task-quadrant-content'),
            duration: const Duration(milliseconds: 260),
            curve: Curves.easeInOutCubic,
            alignment: Alignment.topCenter,
            child: expandedQuadrant == null
                ? _QuadrantGrid(
                    key: const ValueKey('task-quadrant-grid'),
                    grouped: grouped,
                    state: widget.state,
                    onTaskTap: widget.onTaskTap,
                    onMore: (quadrant) =>
                        setState(() => _expandedQuadrant = quadrant),
                  )
                : _ExpandedQuadrant(
                    key: ValueKey('task-quadrant-expanded-$expandedQuadrant'),
                    quadrant: expandedQuadrant,
                    tasks: grouped[expandedQuadrant] ?? const <TaskItem>[],
                    state: widget.state,
                    onTaskTap: widget.onTaskTap,
                    onCollapse: () => setState(() => _expandedQuadrant = null),
                  ),
          ),
        ],
      ),
    );
  }
}

class _QuadrantGrid extends StatelessWidget {
  const _QuadrantGrid({
    super.key,
    required this.grouped,
    required this.state,
    required this.onTaskTap,
    required this.onMore,
  });

  final Map<String, List<TaskItem>> grouped;
  final WorkspaceSyncState state;
  final TaskNavigationCallback onTaskTap;
  final ValueChanged<String> onMore;

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      const gap = MuyuSpacing.sm;
      final panelWidth = (constraints.maxWidth - gap) / 2;
      return Wrap(
        spacing: gap,
        runSpacing: MuyuSpacing.md,
        children: [
          for (final quadrant in TaskView.quadrants)
            SizedBox(
              width: panelWidth,
              child: _QuadrantPanel(
                key: Key('task-quadrant-group-$quadrant'),
                quadrant: quadrant,
                tasks: grouped[quadrant] ?? const <TaskItem>[],
                state: state,
                onTaskTap: onTaskTap,
                onMore: (grouped[quadrant]?.length ?? 0) > 4
                    ? () => onMore(quadrant)
                    : null,
              ),
            ),
        ],
      );
    },
  );
}

class _ExpandedQuadrant extends StatelessWidget {
  const _ExpandedQuadrant({
    super.key,
    required this.quadrant,
    required this.tasks,
    required this.state,
    required this.onTaskTap,
    required this.onCollapse,
  });

  final String quadrant;
  final List<TaskItem> tasks;
  final WorkspaceSyncState state;
  final TaskNavigationCallback onTaskTap;
  final VoidCallback onCollapse;

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      TextButton.icon(
        key: const Key('task-quadrant-collapse'),
        onPressed: onCollapse,
        icon: const Icon(Icons.arrow_back, size: 18),
        label: const Text('返回四象限'),
        style: TextButton.styleFrom(
          padding: const EdgeInsets.symmetric(horizontal: MuyuSpacing.xs),
          minimumSize: const Size(0, 40),
        ),
      ),
      const SizedBox(height: MuyuSpacing.xs),
      _QuadrantPanel(
        key: Key('task-quadrant-expanded-panel-$quadrant'),
        quadrant: quadrant,
        tasks: tasks,
        state: state,
        onTaskTap: onTaskTap,
      ),
    ],
  );
}

class _QuadrantPanel extends StatelessWidget {
  const _QuadrantPanel({
    super.key,
    required this.quadrant,
    required this.tasks,
    required this.state,
    required this.onTaskTap,
    this.onMore,
  });

  final String quadrant;
  final List<TaskItem> tasks;
  final WorkspaceSyncState state;
  final TaskNavigationCallback onTaskTap;
  final VoidCallback? onMore;

  static const _labels = <String, String>{
    'Q1': '重要且紧急',
    'Q2': '重要不紧急',
    'Q3': '紧急不重要',
    'Q4': '不重要不紧急',
  };

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final surface = theme.colorScheme.surface;
    final accent = _quadrantColor(context, quadrant);
    final headerSurface = Color.alphaBlend(
      accent.withValues(alpha: 0.14),
      surface,
    );

    return DecoratedBox(
      decoration: BoxDecoration(
        color: surface,
        border: Border.all(color: theme.colorScheme.outline),
        borderRadius: const BorderRadius.all(Radius.circular(8)),
      ),
      child: ClipRRect(
        borderRadius: const BorderRadius.all(Radius.circular(7)),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Container(
              key: Key('task-quadrant-title-$quadrant'),
              color: headerSurface,
              padding: const EdgeInsets.symmetric(
                horizontal: MuyuSpacing.sm,
                vertical: MuyuSpacing.sm,
              ),
              child: Row(
                children: [
                  Container(
                    width: 4,
                    height: 24,
                    decoration: BoxDecoration(
                      color: accent,
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                  const SizedBox(width: MuyuSpacing.sm),
                  Expanded(
                    child: Text(
                      '$quadrant ${_labels[quadrant]}',
                      style: theme.textTheme.titleMedium?.copyWith(
                        color: accent,
                      ),
                    ),
                  ),
                  Text(
                    '${tasks.length}',
                    key: Key('task-quadrant-count-$quadrant'),
                    style: theme.textTheme.labelLarge?.copyWith(color: accent),
                  ),
                ],
              ),
            ),
            if (tasks.isEmpty)
              Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: MuyuSpacing.sm,
                  vertical: MuyuSpacing.lg,
                ),
                child: Text(
                  '暂无任务',
                  style: theme.textTheme.bodySmall,
                  textAlign: TextAlign.center,
                ),
              )
            else ...[
              for (final task in tasks.take(onMore == null ? tasks.length : 4))
                TaskSummaryCard(
                  task: task,
                  state: state,
                  compact: true,
                  onTap: () => onTaskTap(task),
                ),
              if (onMore != null)
                InkWell(
                  key: Key('task-quadrant-more-$quadrant'),
                  onTap: onMore,
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: MuyuSpacing.sm,
                      vertical: MuyuSpacing.sm,
                    ),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Text(
                          '更多任务',
                          style: theme.textTheme.labelLarge?.copyWith(
                            color: accent,
                          ),
                        ),
                        const SizedBox(width: MuyuSpacing.xs),
                        Icon(Icons.arrow_forward, size: 16, color: accent),
                      ],
                    ),
                  ),
                ),
            ],
          ],
        ),
      ),
    );
  }

  static Color _quadrantColor(BuildContext context, String quadrant) {
    final theme = Theme.of(context);
    final extension = theme.extension<MuyuThemeExtension>();
    return switch (quadrant) {
      'Q1' => extension?.quadrantQ1 ?? theme.colorScheme.error,
      'Q2' => extension?.quadrantQ2 ?? theme.colorScheme.primary,
      'Q3' => extension?.quadrantQ3 ?? theme.colorScheme.primary,
      'Q4' => extension?.quadrantQ4 ?? theme.colorScheme.primary,
      _ => theme.colorScheme.primary,
    };
  }
}
