import 'package:flutter_test/flutter_test.dart';
import 'package:muyu_client/models/task.dart';

void main() {
  test('TaskItem parses API timestamps and nullable task fields', () {
    final task = TaskItem.fromJson({
      'id': 'task-1',
      'parent_task_id': null,
      'title': '整理旅行计划',
      'description': '确定交通',
      'status': 'TODO',
      'current_handler_id': 'user-a',
      'planned_start_at': '2026-09-01T01:00:00Z',
      'due_at': null,
      'estimated_minutes': 90,
      'completed_at': null,
      'created_by': 'user-a',
      'version': 1,
      'status_version': 1,
      'created_at': '2026-08-17T00:00:00Z',
      'updated_at': '2026-08-17T00:00:00Z',
      'assignee_ids': ['user-a', 'user-b'],
    });

    expect(task.title, '整理旅行计划');
    expect(task.plannedStartAt, DateTime.utc(2026, 9, 1, 1));
    expect(task.dueAt, isNull);
    expect(task.assigneeIds, ['user-a', 'user-b']);
  });
}
