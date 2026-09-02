import 'package:flutter_test/flutter_test.dart';
import 'package:muyu_client/models/task.dart';
import 'package:muyu_client/models/task_view.dart';

Map<String, dynamic> taskJson(String status) => {
  'id': 'task-contract',
  'parent_task_id': null,
  'title': 'Contract task',
  'description': '',
  'status': status,
  'current_handler_id': 'user-1',
  'quadrant': 'Q1',
  'labels': <String>[],
  'blocked_reason': null,
  'blocked_since': null,
  'resume_handler_id': null,
  'waiting_for_user_id': null,
  'planned_start_at': null,
  'due_at': null,
  'estimated_minutes': null,
  'completed_at': null,
  'created_by': 'user-1',
  'version': 1,
  'status_version': 1,
  'created_at': '2026-09-02T00:00:00Z',
  'updated_at': '2026-09-02T00:00:00Z',
  'delay_count': 0,
  'total_delay_minutes': 0,
  'field_versions': <String, int>{},
  'lifecycle_version': 1,
  'deleted_at': null,
};

void main() {
  test('exposes exactly the six canonical internal statuses', () {
    expect(TaskView.statuses, [
      'TODO',
      'IN_PROGRESS',
      'BLOCKED',
      'REVIEW',
      'DONE',
      'CANCELLED',
    ]);
  });

  test('normalizes legacy statuses when reading a task snapshot', () {
    expect(TaskItem.fromJson(taskJson('WAITING')).status, 'BLOCKED');
    expect(TaskItem.fromJson(taskJson('COMPLETED')).status, 'DONE');
  });
}
