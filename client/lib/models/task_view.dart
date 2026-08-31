import 'task.dart';

class TaskView {
  static const statuses = <String>[
    'TODO',
    'IN_PROGRESS',
    'WAITING',
    'DONE',
    'CANCELLED',
  ];

  static const quadrants = <String>['Q1', 'Q2', 'Q3', 'Q4'];

  static List<TaskItem> mine(Iterable<TaskItem> tasks, String userId) =>
      List.unmodifiable(
        tasks.where(
          (task) =>
              task.currentHandlerId == userId ||
              task.assigneeIds.contains(userId),
        ),
      );

  static Map<String, List<TaskItem>> byStatus(Iterable<TaskItem> tasks) {
    final source = tasks.toList(growable: false);
    return {
      for (final status in statuses)
        status: List.unmodifiable(
          source.where((task) => task.status == status),
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

  static Map<String, int> summary(Iterable<TaskItem> tasks, DateTime now) {
    final active = tasks.where(
      (task) => task.status != 'DONE' && task.status != 'CANCELLED',
    );
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
      'blocked': tasks.where((task) => task.status == 'WAITING').length,
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
