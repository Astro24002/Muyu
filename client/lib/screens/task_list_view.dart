import 'package:flutter/material.dart';

import '../models/task.dart';
import '../models/task_view.dart';
import '../models/home.dart';
import '../tasks/task_status.dart';
import '../sync/workspace_sync_controller.dart';
import '../theme/muyu_theme.dart';

typedef TaskNavigationCallback = void Function(TaskItem task);

String _memberDisplayName(WorkspaceSyncState state, String userId) {
  for (final member
      in state.snapshot?.members ?? const <Map<String, dynamic>>[]) {
    if (member['user_id'] != userId) continue;
    final displayName = member['display_name'];
    if (displayName is String && displayName.trim().isNotEmpty) {
      return displayName.trim();
    }
    break;
  }
  return userId;
}

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
    this.onViewAll,
    this.selectedLabel,
    this.sort = TaskListSort.dueAt,
    this.showSubtitle = true,
    this.showCompleted = false,
    this.showFailed = false,
    this.showMomentMetrics = true,
  });

  final WorkspaceSyncController sync;
  final WorkspaceSyncState state;
  final bool canWrite;
  final TaskNavigationCallback onTaskTap;
  final VoidCallback? onViewAll;
  final String? selectedLabel;
  final TaskListSort sort;
  final bool showSubtitle;
  final bool showCompleted;
  final bool showFailed;
  final bool showMomentMetrics;

  @override
  State<TaskListView> createState() => _TaskListViewState();
}

class _TaskListViewState extends State<TaskListView> {
  final _collapsedGroups = <String>{'past'};
  bool _showAllTasks = false;

  @override
  Widget build(BuildContext context) {
    final tasks = widget.state.snapshot?.tasks ?? const <TaskItem>[];
    final home = widget.state.home;
    final hasMomentProjection = home?.hasMomentProjection ?? false;
    final showAllTasks = !hasMomentProjection || _showAllTasks;
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
        padding: EdgeInsets.fromLTRB(
          MediaQuery.sizeOf(context).width >= 360
              ? MuyuSpacing.xl
              : MuyuSpacing.lg,
          MuyuSpacing.sm,
          MediaQuery.sizeOf(context).width >= 360
              ? MuyuSpacing.xl
              : MuyuSpacing.lg,
          96,
        ),
        children: [
          if (widget.state.errorMessage != null)
            Padding(
              padding: const EdgeInsets.fromLTRB(
                MuyuSpacing.xs,
                0,
                MuyuSpacing.xs,
                MuyuSpacing.sm,
              ),
              child: Text(
                widget.state.errorMessage!,
                key: const Key('task-list-error'),
              ),
            ),
          if (hasMomentProjection && !_showAllTasks)
            Padding(
              padding: const EdgeInsets.only(bottom: MuyuSpacing.lg),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      '每件事，都有下一步',
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                  ),
                  TextButton.icon(
                    key: const Key('moment-view-all'),
                    onPressed:
                        widget.onViewAll ??
                        () => setState(() => _showAllTasks = true),
                    iconAlignment: IconAlignment.end,
                    icon: const Icon(Icons.chevron_right, size: 18),
                    label: const Text('全部事情'),
                  ),
                ],
              ),
            ),
          if (hasMomentProjection)
            _MomentSummary(
              home: home!,
              state: widget.state,
              onTaskTap: widget.onTaskTap,
              showMetrics: widget.showMomentMetrics,
            ),
          if (!hasMomentProjection && widget.state.home != null)
            _HomeActionSummary(
              home: widget.state.home!,
              state: widget.state,
              onTaskTap: widget.onTaskTap,
            ),
          if (showAllTasks && visibleTaskCount == 0)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: MuyuSpacing.xxl),
              child: Center(child: Text('还没有任务')),
            ),
          if (showAllTasks)
            for (final group in groups)
              TaskListSection(
                key: Key('task-section-${group.key}'),
                headerKey: Key('task-section-header-${group.key}'),
                group: group,
                expanded: !_collapsedGroups.contains(group.key),
                showSubtitle: widget.showSubtitle,
                childrenByParent: childrenByParent,
                state: widget.state,
                onToggle: () => setState(() {
                  if (!_collapsedGroups.add(group.key)) {
                    _collapsedGroups.remove(group.key);
                  }
                }),
                onTaskTap: widget.onTaskTap,
              ),
        ],
      ),
    );
  }
}

class _MomentSummary extends StatelessWidget {
  const _MomentSummary({
    required this.home,
    required this.state,
    required this.onTaskTap,
    this.showMetrics = true,
  });

  final HomeResponse home;
  final WorkspaceSyncState state;
  final TaskNavigationCallback onTaskTap;
  final bool showMetrics;

  @override
  Widget build(BuildContext context) {
    final moment = home.moment;
    final seen = <String>{};
    HomeTaskSection uniqueSection(HomeTaskSection section) => HomeTaskSection(
      items: section.items.where((task) => seen.add(task.id)),
      hasMore: section.hasMore,
    );
    final blocked = uniqueSection(moment.blocked);
    final mine = uniqueSection(moment.mine);
    final other = uniqueSection(moment.other);
    return Padding(
      key: const Key('moment-summary'),
      padding: const EdgeInsets.only(bottom: MuyuSpacing.sm),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (showMetrics)
            Padding(
              padding: const EdgeInsets.fromLTRB(
                0,
                MuyuSpacing.sm,
                0,
                MuyuSpacing.lg,
              ),
              child: Text(
                '${_memberDisplayName(state, state.snapshot?.viewerUserId ?? '')}，${home.needsActionCount == 0 ? '此刻没有待处理的请求' : '有 ${home.needsActionCount} 件事等你回应'}。一起向前一点点。',
                key: const Key('moment-greeting'),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ),
          if (showMetrics) _MomentMetrics(home: home),
          const SizedBox(height: MuyuSpacing.sm),
          _MomentTaskSection(
            key: const Key('moment-section-blocked'),
            sectionKey: 'blocked',
            title: '卡住的事情',
            description: '先把这一步走通',
            section: blocked,
            state: state,
            onTaskTap: onTaskTap,
          ),
          _MomentTaskSection(
            key: const Key('moment-section-mine'),
            sectionKey: 'mine',
            title: '我在推进',
            description: '稳稳地，向前走',
            section: mine,
            state: state,
            onTaskTap: onTaskTap,
          ),
          _MomentTaskSection(
            key: const Key('moment-section-other'),
            sectionKey: 'other',
            title: 'TA 在推进',
            description: '彼此看见，各自负责',
            section: other,
            state: state,
            onTaskTap: onTaskTap,
          ),
        ],
      ),
    );
  }
}

class _MomentMetrics extends StatelessWidget {
  const _MomentMetrics({required this.home});

  final HomeResponse home;

  @override
  Widget build(BuildContext context) {
    final metrics = [
      ('needs-action', '需要我处理', home.needsActionCount, '轮到我回应'),
      ('waiting-on-other', '等对方', home.waitingOnOtherCount, '交给 TA 的下一棒'),
      ('week-due', '本周到期', home.weekDueCount, '一起留意截止时间'),
    ];
    return Row(
      key: const Key('moment-metrics'),
      children: [
        for (var index = 0; index < metrics.length; index++) ...[
          if (index > 0) const SizedBox(width: MuyuSpacing.sm),
          Expanded(
            child: _MomentMetric(
              key: Key('moment-metric-${metrics[index].$1}'),
              metricKey: metrics[index].$1,
              label: metrics[index].$2,
              count: metrics[index].$3,
              subtitle: metrics[index].$4,
              highlighted: index == 0,
            ),
          ),
        ],
      ],
    );
  }
}

class _MomentMetric extends StatelessWidget {
  const _MomentMetric({
    super.key,
    required this.metricKey,
    required this.label,
    required this.count,
    required this.subtitle,
    required this.highlighted,
  });

  final String metricKey;
  final String label;
  final int count;
  final String subtitle;
  final bool highlighted;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final foreground = highlighted
        ? theme.colorScheme.onPrimary
        : theme.colorScheme.onSurface;
    return Container(
      height: 108,
      decoration: BoxDecoration(
        color: highlighted ? theme.colorScheme.primary : indexColor(metricKey),
        border: highlighted
            ? null
            : Border.all(color: theme.colorScheme.outline),
        borderRadius: BorderRadius.circular(15),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(
          horizontal: MuyuSpacing.sm,
          vertical: MuyuSpacing.md,
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.labelMedium?.copyWith(color: foreground),
            ),
            Text(
              _taskCountLabel(count),
              key: Key('moment-count-$metricKey'),
              style: theme.textTheme.titleMedium?.copyWith(
                color: foreground,
                fontSize: 28,
                fontWeight: FontWeight.w700,
              ),
            ),
            Text(
              subtitle,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.bodySmall?.copyWith(
                color: highlighted
                    ? theme.colorScheme.onPrimary.withValues(alpha: 0.7)
                    : theme.colorScheme.onSurfaceVariant,
                fontSize: 10,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Color indexColor(String key) => key == 'waiting-on-other'
      ? const Color(0xfff5f8ed)
      : const Color(0xfffaf6ef);
}

class _MomentTaskSection extends StatelessWidget {
  const _MomentTaskSection({
    super.key,
    required this.sectionKey,
    required this.title,
    required this.description,
    required this.section,
    required this.state,
    required this.onTaskTap,
  });

  final String sectionKey;
  final String title;
  final String description;
  final HomeTaskSection section;
  final WorkspaceSyncState state;
  final TaskNavigationCallback onTaskTap;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: MuyuSpacing.sm),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(
            horizontal: MuyuSpacing.xs,
            vertical: MuyuSpacing.xs,
          ),
          child: Row(
            children: [
              Container(
                width: 7,
                height: 7,
                margin: const EdgeInsets.only(right: MuyuSpacing.sm),
                decoration: BoxDecoration(
                  color: sectionKey == 'blocked'
                      ? Theme.of(context).extension<MuyuThemeExtension>()?.coral
                      : Theme.of(context).colorScheme.primary,
                  shape: BoxShape.circle,
                ),
              ),
              Expanded(
                child: Text(
                  title,
                  key: Key('moment-section-title-$sectionKey'),
                  style: Theme.of(context).textTheme.titleMedium
                      ?.copyWith(fontWeight: FontWeight.w700),
                ),
              ),
              _TaskCountBadge(
                key: Key('moment-section-count-$sectionKey'),
                count: _taskCountLabel(
                  section.items.length,
                  hasMore: section.hasMore,
                ),
                semanticLabel: '$title，${section.items.length}项',
              ),
              const SizedBox(width: MuyuSpacing.sm),
              Flexible(
                child: Text(
                  description,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ),
            ],
          ),
        ),
        if (section.items.isEmpty)
          const Padding(
            padding: EdgeInsets.fromLTRB(
              MuyuSpacing.xs,
              MuyuSpacing.xs,
              MuyuSpacing.xs,
              MuyuSpacing.sm,
            ),
            child: Text('暂无'),
          )
        else
          for (final task in section.items)
            TaskSummaryCard(
              key: ValueKey('moment-task-${task.id}'),
              task: task,
              state: state,
              onTap: () => onTaskTap(task),
              compact: true,
              momentLayout: true,
            ),
      ],
    ),
  );
}

class _HomeActionSummary extends StatelessWidget {
  const _HomeActionSummary({
    required this.home,
    required this.state,
    required this.onTaskTap,
  });

  final HomeResponse home;
  final WorkspaceSyncState state;
  final TaskNavigationCallback onTaskTap;

  @override
  Widget build(BuildContext context) {
    final section = home.blockedTasks;
    if (section.items.isEmpty && !section.hasMore) {
      return const SizedBox.shrink();
    }
    return Padding(
      padding: const EdgeInsets.only(bottom: MuyuSpacing.md),
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: Theme.of(context).colorScheme.surface,
          border: Border.all(color: Theme.of(context).colorScheme.outline),
          borderRadius: const BorderRadius.all(Radius.circular(6)),
        ),
        child: _HomeActionSection(
          key: const Key('home-action-section-blocked'),
          title: '当前阻塞',
          icon: Icons.pause_circle_outline,
          section: section,
          state: state,
          onTaskTap: onTaskTap,
        ),
      ),
    );
  }
}

class _HomeActionSection extends StatelessWidget {
  const _HomeActionSection({
    super.key,
    required this.title,
    required this.icon,
    required this.section,
    required this.state,
    required this.onTaskTap,
  });

  final String title;
  final IconData icon;
  final HomeTaskSection section;
  final WorkspaceSyncState state;
  final TaskNavigationCallback onTaskTap;

  @override
  Widget build(BuildContext context) {
    final count = _taskCountLabel(
      section.items.length,
      hasMore: section.hasMore,
    );
    final extension = Theme.of(context).extension<MuyuThemeExtension>();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(
            MuyuSpacing.md,
            MuyuSpacing.sm,
            MuyuSpacing.md,
            MuyuSpacing.xs,
          ),
          child: Row(
            children: [
              Icon(
                icon,
                size: 18,
                color: extension?.coral ?? Theme.of(context).colorScheme.error,
              ),
              const SizedBox(width: MuyuSpacing.xs),
              Text(title, style: Theme.of(context).textTheme.titleMedium),
              const SizedBox(width: MuyuSpacing.sm),
              _TaskCountBadge(
                key: const Key('home-action-count-blocked'),
                count: count,
                semanticLabel: '$title，$count项',
              ),
            ],
          ),
        ),
        for (final task in section.items)
          _BlockedTaskSummaryRow(
            key: Key('home-action-task-${task.id}'),
            task: task,
            state: state,
            onTap: () => onTaskTap(task),
          ),
      ],
    );
  }
}

class _BlockedTaskSummaryRow extends StatelessWidget {
  const _BlockedTaskSummaryRow({
    super.key,
    required this.task,
    required this.state,
    required this.onTap,
  });

  final TaskItem task;
  final WorkspaceSyncState state;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final extension = theme.extension<MuyuThemeExtension>();
    final owner = _memberDisplayName(state, task.currentHandlerId);
    final reason = task.blockedReason?.trim();
    final reasonText = reason == null || reason.isEmpty ? '等待继续处理' : reason;
    final duration = TaskView.elapsedLabel(
      prefix: '阻塞',
      since: task.blockedSince,
    );
    return Semantics(
      button: true,
      label: '${task.title}，负责人$owner，$reasonText，$duration',
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          child: ConstrainedBox(
            constraints: const BoxConstraints(minHeight: 48),
            child: Padding(
              padding: const EdgeInsets.symmetric(
                horizontal: MuyuSpacing.md,
                vertical: MuyuSpacing.sm,
              ),
              child: Row(
                children: [
                  Expanded(
                    flex: 2,
                    child: Text(
                      task.title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  const SizedBox(width: MuyuSpacing.xs),
                  Flexible(
                    flex: 1,
                    child: _MetadataPill(
                      key: Key('home-action-owner-${task.id}'),
                      label: owner,
                      semanticLabel: '负责人$owner',
                      background:
                          extension?.focusSurface ??
                          theme.colorScheme.secondaryContainer,
                      foreground: theme.colorScheme.primary,
                    ),
                  ),
                  const SizedBox(width: MuyuSpacing.xs),
                  Flexible(
                    flex: 1,
                    child: _MetadataPill(
                      key: Key('home-action-duration-${task.id}'),
                      label: duration,
                      semanticLabel: duration,
                      background:
                          extension?.coralSurface ??
                          theme.colorScheme.errorContainer,
                      foreground:
                          extension?.coral ??
                          theme.colorScheme.onErrorContainer,
                    ),
                  ),
                  const SizedBox(width: MuyuSpacing.xs),
                  const Icon(Icons.chevron_right, size: 20),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _MetadataPill extends StatelessWidget {
  const _MetadataPill({
    super.key,
    required this.label,
    required this.semanticLabel,
    required this.background,
    required this.foreground,
    this.compact = false,
  });

  final String label;
  final String semanticLabel;
  final Color background;
  final Color foreground;
  final bool compact;

  @override
  Widget build(BuildContext context) => Semantics(
    label: semanticLabel,
    child: ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 132),
      child: IntrinsicWidth(
        child: Container(
          height: compact ? 20 : 24,
          alignment: Alignment.center,
          padding: EdgeInsets.symmetric(
            horizontal: compact ? MuyuSpacing.xs : MuyuSpacing.sm,
          ),
          decoration: BoxDecoration(
            color: background,
            borderRadius: const BorderRadius.all(Radius.circular(999)),
          ),
          child: Text(
            label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.labelMedium?.copyWith(
              color: foreground,
              fontSize: compact ? 9 : null,
              height: compact ? 12 / 9 : null,
            ),
          ),
        ),
      ),
    ),
  );
}

class _TaskCountBadge extends StatelessWidget {
  const _TaskCountBadge({
    super.key,
    required this.count,
    required this.semanticLabel,
  });

  final String count;
  final String semanticLabel;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final extension = theme.extension<MuyuThemeExtension>();
    return Semantics(
      label: semanticLabel,
      child: Container(
        constraints: const BoxConstraints(minWidth: 24, minHeight: 22),
        padding: const EdgeInsets.symmetric(horizontal: MuyuSpacing.xs),
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color:
              extension?.focusSurface ?? theme.colorScheme.secondaryContainer,
          borderRadius: const BorderRadius.all(Radius.circular(6)),
        ),
        child: Text(
          count,
          style: theme.textTheme.labelMedium?.copyWith(
            color: theme.colorScheme.primary,
          ),
        ),
      ),
    );
  }
}

String _taskCountLabel(int count, {bool hasMore = false}) {
  if (count >= 100) return '99+';
  if (hasMore) return '$count+';
  return '$count';
}

class TaskListSection extends StatelessWidget {
  const TaskListSection({
    super.key,
    required this.headerKey,
    required this.group,
    required this.expanded,
    required this.showSubtitle,
    required this.childrenByParent,
    required this.state,
    required this.onToggle,
    required this.onTaskTap,
  });

  final Key headerKey;
  final TaskListGroup group;
  final bool expanded;
  final bool showSubtitle;
  final Map<String, List<TaskItem>> childrenByParent;
  final WorkspaceSyncState state;
  final VoidCallback onToggle;
  final TaskNavigationCallback onTaskTap;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: MuyuSpacing.md),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Material(
          color: Theme.of(context).colorScheme.surface.withValues(alpha: 0),
          child: InkWell(
            key: headerKey,
            onTap: onToggle,
            borderRadius: const BorderRadius.all(Radius.circular(6)),
            child: Padding(
              padding: const EdgeInsets.symmetric(
                horizontal: MuyuSpacing.xs,
                vertical: MuyuSpacing.sm,
              ),
              child: Row(
                children: [
                  Text(
                    group.title,
                    key: Key('task-section-title-${group.key}'),
                    style: Theme.of(context).textTheme.titleMedium
                        ?.copyWith(fontWeight: FontWeight.w700),
                  ),
                  const SizedBox(width: MuyuSpacing.sm),
                  _TaskCountBadge(
                    key: Key('task-section-count-${group.key}'),
                    count: _taskCountLabel(group.tasks.length),
                    semanticLabel: '${group.title}，${group.tasks.length}项',
                  ),
                  const Spacer(),
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
              padding: EdgeInsets.fromLTRB(
                MuyuSpacing.xs,
                MuyuSpacing.xs,
                MuyuSpacing.xs,
                MuyuSpacing.md,
              ),
              child: Text('无任务'),
            )
          else
            for (final task in group.tasks) ...[
              TaskListRow(
                task: task,
                state: state,
                showSubtitle: showSubtitle,
                subtasks: childrenByParent[task.id] ?? const [],
                onTap: () => onTaskTap(task),
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
  });

  final TaskItem task;
  final WorkspaceSyncState state;
  final bool showSubtitle;
  final List<TaskItem> subtasks;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final subtitle = _subtitle(task, state, subtasks);
    return Material(
      color: Theme.of(context).colorScheme.surface,
      child: Container(
        key: ValueKey('task-list-row-${task.id}'),
        margin: const EdgeInsets.only(bottom: MuyuSpacing.xs / 2),
        decoration: BoxDecoration(
          border: Border(
            bottom: BorderSide(
              color: Theme.of(context).dividerColor.withValues(alpha: 0.35),
            ),
          ),
        ),
        child: ListTile(
          contentPadding: const EdgeInsets.symmetric(
            horizontal: MuyuSpacing.xs,
            vertical: MuyuSpacing.xs,
          ),
          leading: _TaskStatusIcon(status: task.status),
          title: Text(
            task.title,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: Theme.of(context).textTheme.bodyLarge?.copyWith(
              color: _isTerminal(task.status)
                  ? Theme.of(context).textTheme.bodyLarge?.color
                        ?.withValues(alpha: 0.5)
                  : null,
              decoration: normalizeTaskStatus(task.status) == 'DONE'
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
    parts.add('负责人 ${_memberDisplayName(state, task.currentHandlerId)}');
    if (pending) parts.add('等待负责人审批');
    final due = task.dueAt;
    if (due != null) {
      final local = due.toLocal();
      parts.add(_dateText(local));
      final now = DateTime.now().toLocal();
      if (due.isBefore(now)) {
        parts.add(TaskView.elapsedLabel(prefix: '逾期', since: due, now: now));
      }
    }
    if (normalizeTaskStatus(task.status) == 'IN_PROGRESS' &&
        task.progress != null) {
      parts.add('进度 ${task.progress}%');
    }
    if (subtasks.isNotEmpty) {
      final completed = subtasks.where((item) => item.status == 'DONE').length;
      parts.add('子任务 $completed/${subtasks.length}');
    }
    if (normalizeTaskStatus(task.status) == 'BLOCKED') {
      parts.add(task.blockedReason ?? taskStatusLabel('BLOCKED'));
    }
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
      normalizeTaskStatus(status) == 'DONE' ||
      normalizeTaskStatus(status) == 'CANCELLED';
}

class _TaskStatusIcon extends StatelessWidget {
  const _TaskStatusIcon({required this.status, this.compact = false});

  final String status;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final extension = theme.extension<MuyuThemeExtension>();
    final normalized = normalizeTaskStatus(status);
    final tone = taskStatusTone(normalized);
    final (icon, color) = switch (tone) {
      TaskStatusTone.done => (
        Icons.check_circle,
        extension?.sync ?? theme.colorScheme.secondary,
      ),
      TaskStatusTone.cancelled => (Icons.cancel, theme.colorScheme.error),
      TaskStatusTone.blocked => (
        Icons.pause_circle_outline,
        extension?.coral ?? theme.colorScheme.secondary,
      ),
      TaskStatusTone.review => (
        Icons.fact_check_outlined,
        theme.colorScheme.primary,
      ),
      TaskStatusTone.inProgress => (
        Icons.play_circle_outline,
        theme.colorScheme.primary,
      ),
      TaskStatusTone.todo => (
        Icons.radio_button_unchecked,
        theme.colorScheme.primary,
      ),
      TaskStatusTone.unknown => (Icons.help_outline, theme.colorScheme.error),
    };
    return Icon(
      icon,
      color: color,
      size: compact ? 18 : 24,
      semanticLabel: taskStatusLabel(normalized),
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
    decoration: const InputDecoration(labelText: '分类筛选'),
    items: [
      const DropdownMenuItem(value: '', child: Text('全部分类')),
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
    this.compact = false,
    this.momentLayout = false,
  });

  final TaskItem task;
  final WorkspaceSyncState state;
  final VoidCallback? onTap;
  final bool compact;
  final bool momentLayout;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final subtitle = _subtitle(task, state);
    if (compact) {
      return momentLayout ? _buildMomentCompact(theme) : _buildCompact(theme);
    }
    return Material(
      key: ValueKey('task-card-${task.id}'),
      color: theme.colorScheme.surface,
      elevation: 0,
      child: InkWell(
        onTap: onTap,
        child: Container(
          constraints: BoxConstraints(minHeight: compact ? 44 : 56),
          padding: EdgeInsets.symmetric(
            horizontal: MuyuSpacing.xs,
            vertical: compact ? MuyuSpacing.xs : MuyuSpacing.sm,
          ),
          decoration: BoxDecoration(
            border: Border(
              bottom: BorderSide(color: theme.colorScheme.outline),
            ),
          ),
          child: Row(
            children: [
              _TaskStatusIcon(status: task.status, compact: compact),
              SizedBox(width: compact ? MuyuSpacing.xs : MuyuSpacing.sm),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      key: ValueKey('task-card-title-${task.id}'),
                      compact || task.taskNumber.isEmpty
                          ? task.title
                          : '${task.taskNumber} ${task.title}',
                      maxLines: compact ? 1 : 2,
                      overflow: TextOverflow.ellipsis,
                      style:
                          (compact
                                  ? theme.textTheme.bodySmall?.copyWith(
                                      fontSize: 13,
                                      height: 18 / 13,
                                    )
                                  : theme.textTheme.bodyLarge)
                              ?.copyWith(
                                fontWeight: FontWeight.w600,
                                decoration:
                                    normalizeTaskStatus(task.status) == 'DONE'
                                    ? TextDecoration.lineThrough
                                    : TextDecoration.none,
                                color: _isTerminal(task.status)
                                    ? theme.colorScheme.onSurface.withValues(
                                        alpha: 0.55,
                                      )
                                    : theme.colorScheme.onSurface,
                              ),
                    ),
                    SizedBox(height: compact ? 1 : MuyuSpacing.xs),
                    Text(
                      key: ValueKey('task-card-subtitle-${task.id}'),
                      subtitle,
                      maxLines: compact ? 1 : 2,
                      overflow: TextOverflow.ellipsis,
                      style: compact
                          ? theme.textTheme.labelMedium?.copyWith(
                              fontSize: 10,
                              height: 14 / 10,
                            )
                          : theme.textTheme.bodySmall,
                    ),
                  ],
                ),
              ),
              if (!compact && task.dueAt != null) ...[
                const SizedBox(width: MuyuSpacing.sm),
                Text(
                  _dateText(task.dueAt!),
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.primary,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildCompact(ThemeData theme) {
    final extension = theme.extension<MuyuThemeExtension>();
    final owner = _memberDisplayName(state, task.currentHandlerId);
    final status = taskStatusLabel(task.status);
    final classification = task.labels.isEmpty ? null : task.labels.first;
    final focusSurface =
        extension?.focusSurface ?? theme.colorScheme.secondaryContainer;
    final ownerPill = _MetadataPill(
      key: ValueKey('task-card-owner-${task.id}'),
      label: owner,
      semanticLabel: '负责人$owner',
      background: focusSurface,
      foreground: theme.colorScheme.primary,
      compact: true,
    );
    final statusPill = _MetadataPill(
      key: ValueKey('task-card-status-${task.id}'),
      label: status,
      semanticLabel: '状态$status',
      background: _compactStatusBackground(theme, extension),
      foreground: _compactStatusForeground(theme, extension),
      compact: true,
    );

    return Material(
      key: ValueKey('task-card-${task.id}'),
      color: theme.colorScheme.surface,
      elevation: 0,
      child: InkWell(
        onTap: onTap,
        child: Container(
          constraints: const BoxConstraints(minHeight: 44),
          padding: const EdgeInsets.symmetric(
            horizontal: MuyuSpacing.xs,
            vertical: MuyuSpacing.xs,
          ),
          decoration: BoxDecoration(
            border: Border(
              bottom: BorderSide(color: theme.colorScheme.outline),
            ),
          ),
          child: Row(
            children: [
              _TaskStatusIcon(status: task.status, compact: true),
              const SizedBox(width: MuyuSpacing.xs),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      key: ValueKey('task-card-title-${task.id}'),
                      task.title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.bodySmall?.copyWith(
                        fontSize: 12,
                        height: 16 / 12,
                        fontWeight: FontWeight.w600,
                        decoration: normalizeTaskStatus(task.status) == 'DONE'
                            ? TextDecoration.lineThrough
                            : TextDecoration.none,
                        color: _isTerminal(task.status)
                            ? theme.colorScheme.onSurface.withValues(
                                alpha: 0.55,
                              )
                            : theme.colorScheme.onSurface,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Wrap(
                      key: ValueKey('task-card-metadata-${task.id}'),
                      spacing: MuyuSpacing.xs,
                      runSpacing: 2,
                      children: [
                        ownerPill,
                        statusPill,
                        if (classification != null)
                          _MetadataPill(
                            key: ValueKey('task-card-label-${task.id}'),
                            label: classification,
                            semanticLabel: '分类$classification',
                            background:
                                theme.colorScheme.surfaceContainerHighest,
                            foreground: theme.colorScheme.onSurfaceVariant,
                            compact: true,
                          ),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildMomentCompact(ThemeData theme) {
    final extension = theme.extension<MuyuThemeExtension>();
    final owner = _memberDisplayName(state, task.currentHandlerId);
    final status = taskStatusLabel(task.status);
    final classification = task.labels.isEmpty ? null : task.labels.first;
    final due = _momentDueLabel(task);
    final dueIsOverdue = _momentDueIsOverdue(task);
    final metadataStyle = theme.textTheme.bodySmall;
    final blockedReason = _nonEmpty(task.blockedReason);
    final nextStep =
        _nonEmpty(task.nextStepText) ?? _nonEmpty(task.nextStep?.label);
    final contextLabel = <String>[
      if (blockedReason != null) '阻塞原因$blockedReason',
      if (nextStep != null) '下一步$nextStep',
    ].join('，');
    final cardLabel = [
      task.title,
      '状态$status',
      '截止$due',
      if (classification != null) '分类$classification',
      '象限${task.quadrant}',
      '负责人$owner',
      if (contextLabel.isNotEmpty) contextLabel,
    ].join('，');
    final normalizedStatus = normalizeTaskStatus(task.status);
    final coral = extension?.coral ?? theme.colorScheme.error;
    final border = Border.all(
      color: normalizedStatus == 'BLOCKED'
          ? coral.withValues(alpha: 0.45)
          : theme.colorScheme.outline,
    );

    return Semantics(
      button: onTap != null,
      label: cardLabel,
      child: Material(
        key: ValueKey('task-card-${task.id}'),
        color: theme.colorScheme.surface,
        elevation: 0,
        child: InkWell(
          onTap: onTap,
          child: Container(
            constraints: const BoxConstraints(minHeight: 48),
            padding: const EdgeInsets.symmetric(
              horizontal: MuyuSpacing.sm,
              vertical: MuyuSpacing.sm,
            ),
            decoration: BoxDecoration(
              border: border,
              borderRadius: const BorderRadius.all(Radius.circular(12)),
              color: normalizedStatus == 'BLOCKED'
                  ? Color.alphaBlend(
                      coral.withValues(alpha: 0.025),
                      theme.colorScheme.surface,
                    )
                  : theme.colorScheme.surface,
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: Text(
                        key: ValueKey('task-card-title-${task.id}'),
                        task.title,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: _isTerminal(task.status)
                              ? theme.colorScheme.onSurface.withValues(
                                  alpha: 0.55,
                                )
                              : theme.colorScheme.onSurface,
                          fontSize: 13,
                          height: 18 / 13,
                          fontWeight: FontWeight.w700,
                          decoration: normalizedStatus == 'DONE'
                              ? TextDecoration.lineThrough
                              : TextDecoration.none,
                        ),
                      ),
                    ),
                    const SizedBox(width: MuyuSpacing.sm),
                    _MetadataPill(
                      key: ValueKey('task-card-status-${task.id}'),
                      label: status,
                      semanticLabel: '状态$status',
                      background: _compactStatusBackground(theme, extension),
                      foreground: _compactStatusForeground(theme, extension),
                      compact: true,
                    ),
                  ],
                ),
                const SizedBox(height: MuyuSpacing.xs),
                DefaultTextStyle(
                  style: metadataStyle ?? const TextStyle(),
                  child: Row(
                    key: ValueKey('task-card-metadata-${task.id}'),
                    children: [
                      Flexible(
                        child: Text(
                          owner,
                          key: ValueKey('task-card-owner-${task.id}'),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      if (classification != null) ...[
                        const Text('  ·  '),
                        Text(
                          classification,
                          key: ValueKey('task-card-label-${task.id}'),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ],
                      const Text('  ·  '),
                      Flexible(
                        child: Text(
                          due,
                          key: ValueKey('task-card-due-${task.id}'),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: dueIsOverdue ? TextStyle(color: coral) : null,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: MuyuSpacing.sm),
                Divider(height: 1, color: theme.colorScheme.outline),
                const SizedBox(height: MuyuSpacing.sm),
                Row(
                  children: [
                    if (blockedReason != null || nextStep != null)
                      Expanded(
                        child: _MomentContextLine(
                          taskId: task.id,
                          blockedReason: blockedReason,
                          nextStep: nextStep,
                        ),
                      )
                    else
                      const Spacer(),
                    const SizedBox(width: MuyuSpacing.xs),
                    Text(
                      normalizedStatus == 'BLOCKED' ? '查看阻塞' : '查看',
                      key: ValueKey('task-card-action-${task.id}'),
                      style: theme.textTheme.labelMedium?.copyWith(
                        color: theme.colorScheme.primary,
                        fontSize: 10,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    Icon(
                      Icons.chevron_right,
                      size: 14,
                      color: theme.colorScheme.primary,
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  static String _momentDueLabel(TaskItem task) {
    final due = task.dueAt;
    if (due == null) return '未设截止';
    if (_momentDueIsOverdue(task)) return '已逾期';
    return '截止 ${_dateText(due)}';
  }

  static bool _momentDueIsOverdue(TaskItem task) {
    final due = task.dueAt;
    if (due == null || _isTerminal(task.status)) return false;
    return due.isBefore(DateTime.now());
  }

  static String? _nonEmpty(String? value) {
    final trimmed = value?.trim();
    return trimmed == null || trimmed.isEmpty ? null : trimmed;
  }

  Color _compactStatusBackground(
    ThemeData theme,
    MuyuThemeExtension? extension,
  ) {
    return switch (taskStatusTone(task.status)) {
      TaskStatusTone.blocked || TaskStatusTone.cancelled =>
        extension?.coralSurface ?? theme.colorScheme.errorContainer,
      _ => extension?.focusSurface ?? theme.colorScheme.secondaryContainer,
    };
  }

  Color _compactStatusForeground(
    ThemeData theme,
    MuyuThemeExtension? extension,
  ) {
    return switch (taskStatusTone(task.status)) {
      TaskStatusTone.blocked || TaskStatusTone.cancelled =>
        extension?.coral ?? theme.colorScheme.onErrorContainer,
      _ => theme.colorScheme.primary,
    };
  }

  static String _subtitle(TaskItem task, WorkspaceSyncState state) {
    final pending = state.approvalRequests.any(
      (request) =>
          request.taskId == task.id &&
          request.status == 'PENDING' &&
          request.isOutgoing(state.snapshot?.viewerUserId ?? ''),
    );
    final parts = <String>[];
    parts.add('负责人 ${_memberDisplayName(state, task.currentHandlerId)}');
    if (pending) {
      parts.add('等待负责人审批');
    } else {
      parts.add(taskStatusLabel(task.status));
    }
    parts.add(task.quadrant);
    if (task.labels.isNotEmpty) {
      parts.add(task.labels.map((label) => '#$label').join(' '));
    }
    if (task.dueAt != null) {
      parts.add('截止 ${_dateText(task.dueAt!)}');
    }
    if (normalizeTaskStatus(task.status) == 'BLOCKED') {
      parts.add(task.blockedReason ?? taskStatusLabel('BLOCKED'));
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

  static bool _isTerminal(String status) =>
      normalizeTaskStatus(status) == 'DONE' ||
      normalizeTaskStatus(status) == 'CANCELLED';
}

class _MomentContextLine extends StatelessWidget {
  const _MomentContextLine({
    required this.taskId,
    required this.blockedReason,
    required this.nextStep,
  });

  final String taskId;
  final String? blockedReason;
  final String? nextStep;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final textStyle = theme.textTheme.labelMedium?.copyWith(
      fontSize: 10,
      height: 14 / 10,
      color: theme.colorScheme.onSurfaceVariant,
    );
    return SizedBox(
      key: ValueKey('task-card-context-$taskId'),
      height: 14,
      child: Row(
        children: [
          if (blockedReason != null)
            _buildItem(
              label: '阻塞原因',
              value: blockedReason!,
              valueKey: ValueKey('task-card-blocked-reason-$taskId'),
              style: textStyle,
              labelColor: theme.colorScheme.error,
            ),
          if (blockedReason != null && nextStep != null)
            const SizedBox(width: MuyuSpacing.sm),
          if (nextStep != null)
            _buildItem(
              label: '下一步',
              value: nextStep!,
              valueKey: ValueKey('task-card-next-step-$taskId'),
              style: textStyle,
              labelColor: theme.colorScheme.primary,
            ),
        ],
      ),
    );
  }

  Widget _buildItem({
    required String label,
    required String value,
    required Key valueKey,
    required TextStyle? style,
    required Color labelColor,
  }) => Flexible(
    child: Row(
      children: [
        Text(
          '$label：',
          maxLines: 1,
          overflow: TextOverflow.clip,
          style: style?.copyWith(
            color: labelColor,
            fontWeight: FontWeight.w700,
          ),
        ),
        const SizedBox(width: MuyuSpacing.xs / 2),
        Expanded(
          child: Text(
            value,
            key: valueKey,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: style,
          ),
        ),
      ],
    ),
  );
}
