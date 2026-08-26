import 'package:flutter_test/flutter_test.dart';
import 'package:muyu_client/models/task.dart';
import 'package:muyu_client/models/task_view.dart';

TaskItem makeTask(
  String id,
  String status,
  DateTime? due, {
  String handler = 'u2',
  List<String> assignees = const ['u1'],
}) => TaskItem(
  id: id,
  parentTaskId: null,
  title: id,
  description: '',
  status: status,
  currentHandlerId: handler,
  plannedStartAt: null,
  dueAt: due,
  estimatedMinutes: null,
  completedAt: null,
  createdBy: 'u1',
  version: 1,
  statusVersion: 1,
  createdAt: DateTime.utc(2026),
  updatedAt: DateTime.utc(2026),
  assigneeIds: assignees,
);

void main() {
  test('filters mine, preserves DONE, and derives due summary', () {
    final now = DateTime.utc(2026, 8, 26);
    final tasks = [
      makeTask('done', 'DONE', now.subtract(const Duration(days: 1))),
      makeTask('soon', 'TODO', now.add(const Duration(hours: 2))),
    ];
    expect(TaskView.mine(tasks, 'u1').map((task) => task.id), ['done', 'soon']);
    expect(TaskView.byStatus(tasks)['DONE']!.single.status, 'DONE');
    expect(TaskView.summary(tasks, now), {
      'mine': 2,
      'blocked': 0,
      'dueSoon': 1,
      'overdue': 0,
    });
  });
}
