import 'task.dart';

class TaskOverview {
  const TaskOverview({
    required this.taskCount,
    required this.unfinishedCount,
    required this.completedCount,
    required this.delayCount,
    required this.totalDelayMinutes,
  });

  factory TaskOverview.fromTasks(Iterable<TaskItem> tasks, String userId) {
    var taskCount = 0;
    var unfinishedCount = 0;
    var completedCount = 0;
    var delayCount = 0;
    var totalDelayMinutes = 0;

    for (final task in tasks) {
      if (task.deletedAt != null || task.currentHandlerId != userId) {
        continue;
      }
      taskCount++;
      if (task.status == 'DONE') {
        completedCount++;
      } else {
        unfinishedCount++;
      }
      delayCount += task.delayCount;
      totalDelayMinutes += task.totalDelayMinutes;
    }

    return TaskOverview(
      taskCount: taskCount,
      unfinishedCount: unfinishedCount,
      completedCount: completedCount,
      delayCount: delayCount,
      totalDelayMinutes: totalDelayMinutes,
    );
  }

  final int taskCount;
  final int unfinishedCount;
  final int completedCount;
  final int delayCount;
  final int totalDelayMinutes;

  int get totalDelayDays => totalDelayMinutes ~/ _minutesPerDay;

  int get totalDelayHours =>
      (totalDelayMinutes % _minutesPerDay) ~/ _minutesPerHour;

  int get remainingDelayMinutes => totalDelayMinutes % _minutesPerHour;

  String get formattedTotalDelay => formatDelayMinutes(totalDelayMinutes);

  static String formatDelayMinutes(int minutes) {
    if (minutes <= 0) return '0';
    final days = minutes ~/ _minutesPerDay;
    final hours = (minutes % _minutesPerDay) ~/ _minutesPerHour;
    final remainingMinutes = minutes % _minutesPerHour;
    final parts = <String>[];
    if (days > 0) parts.add('$days天');
    if (hours > 0) parts.add('$hours小时');
    if (remainingMinutes > 0) parts.add('$remainingMinutes分钟');
    return parts.isEmpty ? '0' : parts.join();
  }

  static const _minutesPerHour = 60;
  static const _minutesPerDay = 24 * _minutesPerHour;
}
