import 'package:flutter_test/flutter_test.dart';
import 'package:muyu_client/models/task.dart';
import 'package:muyu_client/models/task_overview.dart';

TaskItem task(
  String id, {
  String status = 'TODO',
  String currentHandlerId = 'user-1',
  String? parentTaskId,
  int delayCount = 0,
  int totalDelayMinutes = 0,
  DateTime? deletedAt,
}) => TaskItem(
  id: id,
  parentTaskId: parentTaskId,
  title: id,
  description: '',
  status: status,
  currentHandlerId: currentHandlerId,
  quadrant: 'Q1',
  plannedStartAt: null,
  dueAt: null,
  estimatedMinutes: null,
  completedAt: status == 'DONE' ? DateTime.utc(2026, 9, 1) : null,
  createdBy: 'user-1',
  version: 1,
  statusVersion: 1,
  createdAt: DateTime.utc(2026, 9, 1),
  updatedAt: DateTime.utc(2026, 9, 1),
  delayCount: delayCount,
  totalDelayMinutes: totalDelayMinutes,
  deletedAt: deletedAt,
);

void main() {
  test('counts owned parents and children while excluding deleted tasks', () {
    final overview = TaskOverview.fromTasks([
      task('parent', delayCount: 2, totalDelayMinutes: 1440),
      task(
        'child',
        status: 'DONE',
        parentTaskId: 'parent',
        delayCount: 1,
        totalDelayMinutes: 61,
      ),
      task(
        'other-owner',
        currentHandlerId: 'user-2',
        delayCount: 8,
        totalDelayMinutes: 480,
      ),
      task(
        'deleted',
        delayCount: 5,
        totalDelayMinutes: 300,
        deletedAt: DateTime.utc(2026, 9, 1),
      ),
    ], 'user-1');

    expect(overview.taskCount, 2);
    expect(overview.unfinishedCount, 1);
    expect(overview.completedCount, 1);
    expect(overview.delayCount, 3);
    expect(overview.totalDelayMinutes, 1501);
  });

  test('counts cancelled tasks as terminal in status counts', () {
    final overview = TaskOverview.fromTasks([
      task('todo', delayCount: 2, totalDelayMinutes: 30),
      task(
        'cancelled',
        status: 'CANCELLED',
        delayCount: 3,
        totalDelayMinutes: 45,
      ),
      task('done', status: 'DONE', delayCount: 4, totalDelayMinutes: 60),
    ], 'user-1');

    expect(overview.taskCount, 3);
    expect(overview.unfinishedCount, 1);
    expect(overview.completedCount, 1);
    expect(overview.delayCount, 9);
    expect(overview.totalDelayMinutes, 135);
  });

  test(
    'formats total delay into days, hours, and minutes without losing minutes',
    () {
      final overview = TaskOverview.fromTasks([
        task('delayed', totalDelayMinutes: 1501),
      ], 'user-1');

      expect(overview.totalDelayMinutes, 1501);
      expect(overview.totalDelayDays, 1);
      expect(overview.totalDelayHours, 1);
      expect(overview.remainingDelayMinutes, 1);
      expect(overview.formattedTotalDelay, '1天1小时1分钟');
    },
  );

  test('formats zero delay as zero', () {
    final overview = TaskOverview.fromTasks([task('on-time')], 'user-1');

    expect(overview.totalDelayMinutes, 0);
    expect(overview.formattedTotalDelay, '0');
  });
}
