import 'package:flutter/material.dart';

import '../models/task.dart';
import '../models/task_view.dart';
import '../sync/workspace_sync_controller.dart';
import '../theme/muyu_theme.dart';
import 'task_list_view.dart';

enum _ScheduleSelectionMode { day, week }

class TaskScheduleView extends StatefulWidget {
  const TaskScheduleView({
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
  State<TaskScheduleView> createState() => _TaskScheduleViewState();
}

class _TaskScheduleViewState extends State<TaskScheduleView> {
  late DateTime _today;
  late DateTime _selectedDate;
  late DateTime _selectedWeekStart;
  late DateTime _visibleMonth;
  _ScheduleSelectionMode _selectionMode = _ScheduleSelectionMode.day;

  @override
  void initState() {
    super.initState();
    _today = _dateOnly(DateTime.now().toLocal());
    _selectedDate = _today;
    _selectedWeekStart = _weekStart(_today);
    _visibleMonth = DateTime(_today.year, _today.month);
  }

  @override
  Widget build(BuildContext context) {
    final tasks = widget.state.snapshot?.tasks ?? const <TaskItem>[];
    final filtered = TaskView.filterByLabel(tasks, widget.selectedLabel);
    final rows = _calendarRows();
    final grouped = _agendaGroups(filtered);
    return RefreshIndicator(
      onRefresh: widget.sync.refresh,
      child: ListView(
        key: const Key('task-schedule-scroll'),
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(
          MuyuSpacing.md,
          MuyuSpacing.sm,
          MuyuSpacing.md,
          MuyuSpacing.xl,
        ),
        children: [
          if (widget.state.errorMessage != null)
            Padding(
              padding: const EdgeInsets.only(bottom: MuyuSpacing.sm),
              child: Text(
                widget.state.errorMessage!,
                key: const Key('task-schedule-error'),
              ),
            ),
          _MonthCalendar(
            month: _visibleMonth,
            today: _today,
            selectedDate: _selectedDate,
            selectedWeekStart: _selectedWeekStart,
            selectionMode: _selectionMode,
            rows: rows,
            taskDateKeys: {
              for (final task in filtered)
                if (task.dueAt != null) _dateKey(task.dueAt!.toLocal()),
            },
            onPreviousMonth: () => setState(() {
              _visibleMonth = DateTime(
                _visibleMonth.year,
                _visibleMonth.month - 1,
              );
            }),
            onNextMonth: () => setState(() {
              _visibleMonth = DateTime(
                _visibleMonth.year,
                _visibleMonth.month + 1,
              );
            }),
            onDateSelected: _selectDate,
            onWeekSelected: _selectWeek,
          ),
          const SizedBox(height: MuyuSpacing.md),
          _AgendaHeader(
            mode: _selectionMode,
            selectedDate: _selectedDate,
            weekStart: _selectedWeekStart,
          ),
          const SizedBox(height: MuyuSpacing.xs),
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

  void _selectDate(DateTime date) {
    final selected = _dateOnly(date);
    setState(() {
      _selectedDate = selected;
      _selectedWeekStart = _weekStart(selected);
      _selectionMode = _ScheduleSelectionMode.day;
      if (selected.year != _visibleMonth.year ||
          selected.month != _visibleMonth.month) {
        _visibleMonth = DateTime(selected.year, selected.month);
      }
    });
  }

  void _selectWeek(DateTime weekStart) {
    setState(() {
      _selectedWeekStart = _dateOnly(weekStart);
      _selectedDate = _selectedWeekStart;
      _selectionMode = _ScheduleSelectionMode.week;
    });
  }

  List<_CalendarRow> _calendarRows() {
    final firstOfMonth = DateTime(_visibleMonth.year, _visibleMonth.month);
    final gridStart = firstOfMonth.subtract(
      Duration(days: firstOfMonth.weekday - DateTime.monday),
    );
    final lastOfMonth = DateTime(
      _visibleMonth.year,
      _visibleMonth.month + 1,
      0,
    );
    final gridEnd = lastOfMonth.add(
      Duration(days: DateTime.sunday - lastOfMonth.weekday),
    );
    final rows = <_CalendarRow>[];
    for (
      var date = gridStart;
      !date.isAfter(gridEnd);
      date = date.add(const Duration(days: 7))
    ) {
      rows.add(_CalendarRow(start: date));
    }
    return rows;
  }

  Map<String, List<TaskItem>> _agendaGroups(Iterable<TaskItem> tasks) {
    final source = tasks.toList(growable: false);
    final selectedTasks = source.where((task) {
      final due = task.dueAt?.toLocal();
      if (due == null) return false;
      final date = _dateOnly(due);
      if (_selectionMode == _ScheduleSelectionMode.day) {
        return date == _selectedDate;
      }
      final weekEnd = _selectedWeekStart.add(const Duration(days: 7));
      return !date.isBefore(_selectedWeekStart) && date.isBefore(weekEnd);
    });
    final grouped = TaskView.byDueDate(selectedTasks);

    // Keep unscheduled work visible, as the former schedule list did. It is
    // intentionally kept after dated agenda sections.
    final unscheduled = source.where((task) => task.dueAt == null).toList();
    if (unscheduled.isNotEmpty) {
      unscheduled.sort(
        (left, right) => right.updatedAt.compareTo(left.updatedAt),
      );
      grouped['未安排'] = List.unmodifiable(unscheduled);
    }
    return grouped;
  }
}

class _CalendarRow {
  const _CalendarRow({required this.start});

  final DateTime start;

  List<DateTime> get dates => [
    for (var offset = 0; offset < 7; offset++)
      start.add(Duration(days: offset)),
  ];
}

class _MonthCalendar extends StatelessWidget {
  const _MonthCalendar({
    required this.month,
    required this.today,
    required this.selectedDate,
    required this.selectedWeekStart,
    required this.selectionMode,
    required this.rows,
    required this.taskDateKeys,
    required this.onPreviousMonth,
    required this.onNextMonth,
    required this.onDateSelected,
    required this.onWeekSelected,
  });

  final DateTime month;
  final DateTime today;
  final DateTime selectedDate;
  final DateTime selectedWeekStart;
  final _ScheduleSelectionMode selectionMode;
  final List<_CalendarRow> rows;
  final Set<String> taskDateKeys;
  final VoidCallback onPreviousMonth;
  final VoidCallback onNextMonth;
  final ValueChanged<DateTime> onDateSelected;
  final ValueChanged<DateTime> onWeekSelected;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final monthText =
        '${month.year}年${month.month.toString().padLeft(2, '0')}月';
    return DecoratedBox(
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        border: Border.all(color: theme.colorScheme.outline),
        borderRadius: const BorderRadius.all(Radius.circular(6)),
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(
          MuyuSpacing.xs,
          MuyuSpacing.xs,
          MuyuSpacing.xs,
          MuyuSpacing.sm,
        ),
        child: Column(
          children: [
            Row(
              children: [
                IconButton(
                  key: const Key('task-schedule-month-previous'),
                  tooltip: '上个月',
                  onPressed: onPreviousMonth,
                  visualDensity: VisualDensity.compact,
                  icon: const Icon(Icons.chevron_left),
                ),
                Expanded(
                  child: Text(
                    monthText,
                    key: const Key('task-schedule-month-title'),
                    textAlign: TextAlign.center,
                    style: theme.textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
                IconButton(
                  key: const Key('task-schedule-month-next'),
                  tooltip: '下个月',
                  onPressed: onNextMonth,
                  visualDensity: VisualDensity.compact,
                  icon: const Icon(Icons.chevron_right),
                ),
              ],
            ),
            _WeekdayHeader(),
            const SizedBox(height: MuyuSpacing.xs / 2),
            for (final row in rows)
              _CalendarWeekRow(
                row: row,
                month: month,
                today: today,
                selectedDate: selectedDate,
                selectedWeekStart: selectedWeekStart,
                selectionMode: selectionMode,
                taskDateKeys: taskDateKeys,
                onDateSelected: onDateSelected,
                onWeekSelected: onWeekSelected,
              ),
          ],
        ),
      ),
    );
  }
}

class _WeekdayHeader extends StatelessWidget {
  @override
  Widget build(BuildContext context) => Row(
    children: [
      for (final label in const ['一', '二', '三', '四', '五', '六', '日'])
        Expanded(
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: MuyuSpacing.xs),
            child: Text(
              label,
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.labelMedium?.copyWith(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        ),
      const SizedBox(width: 32, child: Text('周', textAlign: TextAlign.center)),
    ],
  );
}

class _CalendarWeekRow extends StatelessWidget {
  const _CalendarWeekRow({
    required this.row,
    required this.month,
    required this.today,
    required this.selectedDate,
    required this.selectedWeekStart,
    required this.selectionMode,
    required this.taskDateKeys,
    required this.onDateSelected,
    required this.onWeekSelected,
  });

  final _CalendarRow row;
  final DateTime month;
  final DateTime today;
  final DateTime selectedDate;
  final DateTime selectedWeekStart;
  final _ScheduleSelectionMode selectionMode;
  final Set<String> taskDateKeys;
  final ValueChanged<DateTime> onDateSelected;
  final ValueChanged<DateTime> onWeekSelected;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final rowSelected = row.start == selectedWeekStart;
    final weekNumber = _weekNumber(row.start);
    return SizedBox(
      height: 38,
      child: Row(
        children: [
          for (final date in row.dates)
            Expanded(
              child: _CalendarDayCell(
                date: date,
                month: month,
                today: today,
                selected:
                    selectionMode == _ScheduleSelectionMode.day &&
                    date == selectedDate,
                hasTasks: taskDateKeys.contains(_dateKey(date)),
                onTap: () => onDateSelected(date),
              ),
            ),
          SizedBox(
            width: 32,
            child: Semantics(
              button: true,
              label: '第$weekNumber周',
              selected: rowSelected,
              child: TextButton(
                key: Key('task-schedule-week-$weekNumber'),
                onPressed: () => onWeekSelected(row.start),
                style: TextButton.styleFrom(
                  padding: EdgeInsets.zero,
                  minimumSize: Size.zero,
                  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  foregroundColor: rowSelected
                      ? theme.colorScheme.primary
                      : theme.colorScheme.onSurfaceVariant,
                  backgroundColor: rowSelected
                      ? theme.colorScheme.secondaryContainer
                      : Colors.transparent,
                  shape: const RoundedRectangleBorder(
                    borderRadius: BorderRadius.all(Radius.circular(4)),
                  ),
                ),
                child: Text(
                  '$weekNumber',
                  style: theme.textTheme.labelMedium?.copyWith(
                    fontWeight: rowSelected ? FontWeight.w700 : null,
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _CalendarDayCell extends StatelessWidget {
  const _CalendarDayCell({
    required this.date,
    required this.month,
    required this.today,
    required this.selected,
    required this.hasTasks,
    required this.onTap,
  });

  final DateTime date;
  final DateTime month;
  final DateTime today;
  final bool selected;
  final bool hasTasks;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final inMonth = date.year == month.year && date.month == month.month;
    final isToday = date == today;
    final textColor = inMonth
        ? theme.colorScheme.onSurface
        : theme.colorScheme.onSurfaceVariant.withValues(alpha: 0.45);
    return Padding(
      padding: const EdgeInsets.all(1),
      child: Material(
        color: selected
            ? theme.colorScheme.secondaryContainer.withValues(alpha: 0.65)
            : theme.colorScheme.surface,
        shape: RoundedRectangleBorder(
          side: BorderSide(
            color: isToday
                ? theme.colorScheme.primary
                : theme.colorScheme.outline.withValues(alpha: 0.42),
            width: isToday ? 2 : 1,
          ),
          borderRadius: const BorderRadius.all(Radius.circular(4)),
        ),
        child: InkWell(
          key: Key('task-schedule-day-${_dateKey(date)}'),
          onTap: onTap,
          borderRadius: const BorderRadius.all(Radius.circular(4)),
          child: Padding(
            padding: EdgeInsets.fromLTRB(4, isToday ? 2 : 3, 4, 2),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '${date.day}',
                  style: theme.textTheme.labelMedium?.copyWith(
                    color: textColor,
                    fontWeight: isToday || selected ? FontWeight.w700 : null,
                  ),
                ),
                if (hasTasks)
                  Padding(
                    padding: const EdgeInsets.only(top: 2),
                    child: SizedBox(
                      width: 5,
                      height: 5,
                      child: DecoratedBox(
                        decoration: BoxDecoration(
                          color: theme.colorScheme.error,
                          shape: BoxShape.circle,
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _AgendaHeader extends StatelessWidget {
  const _AgendaHeader({
    required this.mode,
    required this.selectedDate,
    required this.weekStart,
  });

  final _ScheduleSelectionMode mode;
  final DateTime selectedDate;
  final DateTime weekStart;

  @override
  Widget build(BuildContext context) {
    final title = mode == _ScheduleSelectionMode.day
        ? _dayTitle(selectedDate)
        : _weekTitle(weekStart);
    return Row(
      key: const Key('task-schedule-agenda-header'),
      children: [
        Expanded(
          child: Text(
            title,
            style: Theme.of(context).textTheme.titleMedium
                ?.copyWith(fontWeight: FontWeight.w700),
          ),
        ),
        Text(
          mode == _ScheduleSelectionMode.day ? '当天' : '整周',
          style: Theme.of(context).textTheme.bodySmall
              ?.copyWith(color: Theme.of(context).colorScheme.onSurfaceVariant),
        ),
      ],
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
          _groupTitle(dateKey),
          key: Key('task-schedule-title-$dateKey'),
          style: Theme.of(context).textTheme.titleSmall?.copyWith(
            color: Theme.of(context).colorScheme.onSurfaceVariant,
            fontWeight: FontWeight.w700,
          ),
        ),
        const SizedBox(height: MuyuSpacing.xs),
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

String _groupTitle(String dateKey) {
  if (dateKey == '未安排') return dateKey;
  final parsed = DateTime.tryParse(dateKey);
  if (parsed == null) return dateKey;
  return _dayTitle(parsed);
}

String _dayTitle(DateTime date) {
  final current = _dateOnly(DateTime.now().toLocal());
  final normalized = _dateOnly(date);
  final month = normalized.month.toString().padLeft(2, '0');
  final day = normalized.day.toString().padLeft(2, '0');
  final prefix = normalized == current
      ? '今天'
      : normalized == current.add(const Duration(days: 1))
      ? '明天'
      : normalized == current.subtract(const Duration(days: 1))
      ? '昨天'
      : '${normalized.year}年';
  return '$prefix · $month月$day日';
}

String _weekTitle(DateTime start) {
  final end = start.add(const Duration(days: 6));
  final startMonth = start.month.toString().padLeft(2, '0');
  final startDay = start.day.toString().padLeft(2, '0');
  final endMonth = end.month.toString().padLeft(2, '0');
  final endDay = end.day.toString().padLeft(2, '0');
  return '第${_weekNumber(start)}周 · $startMonth/$startDay—$endMonth/$endDay';
}

DateTime _dateOnly(DateTime value) =>
    DateTime(value.year, value.month, value.day);

DateTime _weekStart(DateTime value) =>
    _dateOnly(value).subtract(Duration(days: value.weekday - DateTime.monday));

String _dateKey(DateTime value) {
  final date = value.toLocal();
  final month = date.month.toString().padLeft(2, '0');
  final day = date.day.toString().padLeft(2, '0');
  return '${date.year.toString().padLeft(4, '0')}-$month-$day';
}

int _weekNumber(DateTime value) {
  final weekStart = _weekStart(value);
  final yearStart = DateTime(weekStart.year, 1, 1);
  final days = weekStart.difference(yearStart).inDays;
  return (days ~/ 7) + 1;
}
