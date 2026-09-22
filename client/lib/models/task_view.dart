import 'task.dart';
import '../tasks/task_status.dart';

enum TaskListSort { dueAt, quadrant, updatedAt, createdAt }

class TaskListCategory {
  const TaskListCategory({required this.label, required this.unfinishedCount});

  final String? label;
  final int unfinishedCount;

  String get title => label ?? '全部任务';
}

class TaskListGroup {
  const TaskListGroup({
    required this.key,
    required this.title,
    required this.tasks,
  });

  final String key;
  final String title;
  final List<TaskItem> tasks;
}

class TaskView {
  static const statuses = taskStatuses;

  static bool isOpen(TaskItem task) =>
      task.deletedAt == null &&
      const {
        'TODO',
        'IN_PROGRESS',
        'BLOCKED',
        'REVIEW',
      }.contains(normalizeTaskStatus(task.status));

  static const quadrants = <String>['Q1', 'Q2', 'Q3', 'Q4'];

  /// The list is an action window, not an archive of every future task.
  static const listWindowDays = 7;

  static List<TaskItem> mine(Iterable<TaskItem> tasks, String userId) =>
      List.unmodifiable(tasks.where((task) => task.currentHandlerId == userId));

  static Map<String, List<TaskItem>> byStatus(Iterable<TaskItem> tasks) {
    final source = tasks.toList(growable: false);
    return {
      for (final status in statuses)
        status: List.unmodifiable(
          source.where((task) => normalizeTaskStatus(task.status) == status),
        ),
    };
  }

  static Map<String, List<TaskItem>> byQuadrant(Iterable<TaskItem> tasks) {
    final source = tasks.toList(growable: false);
    return {
      for (final quadrant in quadrants)
        quadrant: List.unmodifiable(
          source.where((task) => task.quadrant == quadrant),
        ),
    };
  }

  static Map<String, List<TaskItem>> byDueDate(
    Iterable<TaskItem> tasks, {
    DateTime? now,
  }) {
    final grouped = <String, List<TaskItem>>{};
    for (final task in tasks) {
      final due = task.dueAt;
      final key = due == null ? '未安排' : _localDateKey(due);
      grouped.putIfAbsent(key, () => []).add(task);
    }

    for (final tasksForDate in grouped.values) {
      tasksForDate.sort((left, right) {
        final dueComparison = _compareNullableDates(left.dueAt, right.dueAt);
        if (dueComparison != 0) return dueComparison;
        return left.updatedAt.compareTo(right.updatedAt);
      });
    }

    final datedKeys = grouped.keys.where((key) => key != '未安排').toList()
      ..sort();
    final orderedKeys = [...datedKeys, if (grouped.containsKey('未安排')) '未安排'];
    return {
      for (final key in orderedKeys) key: List.unmodifiable(grouped[key]!),
    };
  }

  static List<TaskItem> filterByLabel(Iterable<TaskItem> tasks, String? label) {
    final normalized = label?.trim().toLowerCase();
    if (normalized == null || normalized.isEmpty) {
      return List.unmodifiable(tasks);
    }
    return List.unmodifiable(
      tasks.where(
        (task) => task.labels.any(
          (candidate) => candidate.trim().toLowerCase() == normalized,
        ),
      ),
    );
  }

  static List<TaskListCategory> listCategories(
    Iterable<TaskItem> tasks, {
    Iterable<String>? approvedClassifications,
  }) {
    final topLevel = _visibleTopLevel(tasks);
    final counts = <String, int>{};
    final names = <String, String>{};
    var unfinished = 0;
    for (final task in topLevel) {
      if (_isUnfinished(task.status)) unfinished++;
      final labelsForTask = <String>{};
      for (final label in task.labels) {
        final trimmed = label.trim();
        if (trimmed.isEmpty) continue;
        final normalized = trimmed.toLowerCase();
        if (!labelsForTask.add(normalized)) continue;
        names.putIfAbsent(normalized, () => trimmed);
        if (_isUnfinished(task.status)) {
          counts[normalized] = (counts[normalized] ?? 0) + 1;
        }
      }
    }
    if (approvedClassifications != null) {
      names.clear();
      counts.clear();
      for (final classification in approvedClassifications) {
        final trimmed = classification.trim();
        if (trimmed.isNotEmpty) names[trimmed.toLowerCase()] = trimmed;
      }
      for (final task in topLevel) {
        if (!_isUnfinished(task.status)) continue;
        for (final label in task.labels) {
          final normalized = label.trim().toLowerCase();
          if (names.containsKey(normalized)) {
            counts[normalized] = (counts[normalized] ?? 0) + 1;
          }
        }
      }
    }
    final labels = names.keys.toList()
      ..sort((left, right) => names[left]!.compareTo(names[right]!));
    return [
      TaskListCategory(label: null, unfinishedCount: unfinished),
      for (final normalized in labels)
        TaskListCategory(
          label: names[normalized],
          unfinishedCount: counts[normalized] ?? 0,
        ),
    ];
  }

  static List<TaskListGroup> listGroups(
    Iterable<TaskItem> tasks, {
    String? label,
    DateTime? now,
    TaskListSort sort = TaskListSort.dueAt,
    bool showCompleted = false,
    bool showFailed = false,
  }) {
    final current = (now ?? DateTime.now()).toLocal();
    final today = DateTime(current.year, current.month, current.day);
    final windowEnd = today.add(const Duration(days: listWindowDays));
    final filtered = filterByLabel(
      tasks,
      label,
    ).where((task) => task.deletedAt == null && task.parentTaskId == null);
    final actionable = filtered.where((task) {
      final status = normalizeTaskStatus(task.status);
      return status == 'TODO' || status == 'IN_PROGRESS';
    });
    final terminal = filtered.where((task) {
      final status = normalizeTaskStatus(task.status);
      if (status == 'DONE') return showCompleted;
      if (status == 'CANCELLED') return showFailed;
      return false;
    });
    final past = actionable.where((task) {
      final due = task.dueAt?.toLocal();
      return due != null && due.isBefore(current);
    });
    final upcoming = actionable.where((task) {
      final due = task.dueAt?.toLocal();
      // Older cached snapshots may not have the now-required deadline. Keep
      // them visible in the action list until the next server refresh.
      if (due == null) return true;
      final date = _dateOnly(due);
      return !due.isBefore(current) && date.isBefore(windowEnd);
    });
    final terminalTasks = _sortForList(terminal, sort, terminal: true);
    return [
      TaskListGroup(
        key: 'past',
        title: '已经延期',
        tasks: _sortForList(past, sort),
      ),
      TaskListGroup(
        key: 'upcoming',
        title: '即将到期',
        tasks: _sortForList(upcoming, sort),
      ),
      if (showCompleted || showFailed)
        TaskListGroup(
          key: 'terminal',
          title: '已完成 / 已取消',
          tasks: terminalTasks,
        ),
    ];
  }

  static List<TaskItem> visibleTopLevel(Iterable<TaskItem> tasks) =>
      _visibleTopLevel(tasks);

  static List<TaskItem> _visibleTopLevel(Iterable<TaskItem> tasks) =>
      List.unmodifiable(
        tasks.where(
          (task) => task.deletedAt == null && task.parentTaskId == null,
        ),
      );

  static List<TaskItem> _sortForList(
    Iterable<TaskItem> tasks,
    TaskListSort sort, {
    bool terminal = false,
  }) {
    final sorted = tasks.toList();
    sorted.sort((left, right) {
      final comparison = switch (sort) {
        TaskListSort.dueAt =>
          terminal
              ? right.updatedAt.compareTo(left.updatedAt)
              : _compareNullableDates(left.dueAt, right.dueAt),
        TaskListSort.quadrant => _quadrantIndex(
          left.quadrant,
        ).compareTo(_quadrantIndex(right.quadrant)),
        TaskListSort.updatedAt => right.updatedAt.compareTo(left.updatedAt),
        TaskListSort.createdAt => right.createdAt.compareTo(left.createdAt),
      };
      if (comparison != 0) return comparison;
      if (!(terminal && sort == TaskListSort.dueAt)) {
        final dueComparison = _compareNullableDates(left.dueAt, right.dueAt);
        if (dueComparison != 0) return dueComparison;
      }
      final updatedComparison = right.updatedAt.compareTo(left.updatedAt);
      if (updatedComparison != 0) return updatedComparison;
      return left.id.compareTo(right.id);
    });
    return List.unmodifiable(sorted);
  }

  static bool _isUnfinished(String status) {
    final normalized = normalizeTaskStatus(status);
    return normalized != 'DONE' && normalized != 'CANCELLED';
  }

  static String elapsedLabel({
    required String prefix,
    required DateTime? since,
    DateTime? now,
  }) {
    final end = (now ?? DateTime.now()).toLocal();
    final start = (since ?? end).toLocal();
    final elapsed = end.difference(start);
    final minutes = elapsed.isNegative ? 0 : elapsed.inMinutes;
    if (minutes < 60) {
      return '$prefix${minutes.toString().padLeft(2, '0')}m';
    }
    if (minutes < 48 * 60) {
      final hours = minutes ~/ 60;
      final remainder = minutes % 60;
      return '$prefix${hours.toString().padLeft(2, '0')}h'
          '${remainder.toString().padLeft(2, '0')}m';
    }
    final totalHours = minutes ~/ 60;
    final days = totalHours ~/ 24;
    final hours = totalHours % 24;
    return '$prefix${days.toString().padLeft(3, ' ')}d'
        '${hours.toString().padLeft(2, '0')}h';
  }

  static DateTime _dateOnly(DateTime value) =>
      DateTime(value.year, value.month, value.day);

  static int _quadrantIndex(String value) => quadrants.indexOf(value);

  static Map<String, int> summary(Iterable<TaskItem> tasks, DateTime now) {
    final active = tasks.where((task) => _isUnfinished(task.status));
    final dueSoon = active.where((task) {
      final due = task.dueAt;
      return due != null &&
          !due.isBefore(now) &&
          !due.isAfter(now.add(const Duration(hours: 24)));
    }).length;
    final overdue = active
        .where((task) => task.dueAt != null && task.dueAt!.isBefore(now))
        .length;
    return {
      'mine': tasks.length,
      'blocked': tasks
          .where((task) => normalizeTaskStatus(task.status) == 'BLOCKED')
          .length,
      'dueSoon': dueSoon,
      'overdue': overdue,
    };
  }

  static String _localDateKey(DateTime dateTime) {
    final local = dateTime.toLocal();
    final year = local.year.toString().padLeft(4, '0');
    final month = local.month.toString().padLeft(2, '0');
    final day = local.day.toString().padLeft(2, '0');
    return '$year-$month-$day';
  }

  static int _compareNullableDates(DateTime? left, DateTime? right) {
    if (left == null && right == null) return 0;
    if (left == null) return 1;
    if (right == null) return -1;
    return left.compareTo(right);
  }
}
