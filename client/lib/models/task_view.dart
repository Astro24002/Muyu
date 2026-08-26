import 'task.dart';

class TaskView {
  static const statuses = <String>[
    'TODO',
    'IN_PROGRESS',
    'WAITING',
    'DONE',
    'CANCELLED',
  ];

  static List<TaskItem> mine(Iterable<TaskItem> tasks, String userId) =>
      List.unmodifiable(
        tasks.where(
          (task) =>
              task.currentHandlerId == userId ||
              task.assigneeIds.contains(userId),
        ),
      );

  static Map<String, List<TaskItem>> byStatus(Iterable<TaskItem> tasks) => {
    for (final status in statuses)
      status: List.unmodifiable(tasks.where((task) => task.status == status)),
  };

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
}
