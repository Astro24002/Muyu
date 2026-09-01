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
      'quadrant': 'Q2',
      'labels': ['工作', '婚礼'],
      'blocked_reason': '等待确认',
      'blocked_since': '2026-09-01T02:00:00Z',
      'resume_handler_id': 'user-b',
      'waiting_for_user_id': 'user-b',
      'planned_start_at': '2026-09-01T01:00:00Z',
      'due_at': null,
      'estimated_minutes': 90,
      'completed_at': null,
      'created_by': 'user-a',
      'version': 1,
      'status_version': 1,
      'created_at': '2026-08-17T00:00:00Z',
      'updated_at': '2026-08-17T00:00:00Z',
      'delay_count': 3,
      'total_delay_minutes': 8640,
    });

    expect(task.title, '整理旅行计划');
    expect(task.quadrant, 'Q2');
    expect(task.labels, ['工作', '婚礼']);
    expect(task.plannedStartAt, DateTime.utc(2026, 9, 1, 1));
    expect(task.dueAt, isNull);
    expect(task.toJson(), isNot(contains('assignee_ids')));
    expect(task.blockedReason, '等待确认');
    expect(task.blockedSince, DateTime.utc(2026, 9, 1, 2));
    expect(task.resumeHandlerId, 'user-b');
    expect(task.waitingForUserId, 'user-b');
    expect(task.delayCount, 3);
    expect(task.totalDelayMinutes, 8640);
  });

  test('TaskItem normalizes the legacy COMPLETED status to DONE', () {
    final task = TaskItem.fromJson({
      'id': 'task-legacy-completed',
      'parent_task_id': null,
      'title': 'Legacy completed task',
      'description': '',
      'status': 'COMPLETED',
      'current_handler_id': 'user-a',
      'quadrant': 'Q1',
      'labels': const <String>[],
      'blocked_reason': null,
      'blocked_since': null,
      'resume_handler_id': null,
      'waiting_for_user_id': null,
      'planned_start_at': null,
      'due_at': null,
      'estimated_minutes': null,
      'completed_at': '2026-08-28T01:00:00Z',
      'created_by': 'user-a',
      'version': 1,
      'status_version': 1,
      'created_at': '2026-08-28T00:00:00Z',
      'updated_at': '2026-08-28T01:00:00Z',
      'delay_count': 0,
      'total_delay_minutes': 0,
      'field_versions': const <String, int>{},
      'lifecycle_version': 1,
      'deleted_at': null,
    });

    expect(task.status, 'DONE');
    expect(task.progress, 100);
  });

  test('TaskItem rejects a missing quadrant as a protocol error', () {
    final json = <String, dynamic>{
      'id': 'task-1',
      'parent_task_id': null,
      'title': '整理旅行计划',
      'description': '确定交通',
      'status': 'TODO',
      'current_handler_id': 'user-a',
      'labels': const <String>[],
      'planned_start_at': null,
      'due_at': null,
      'estimated_minutes': null,
      'completed_at': null,
      'created_by': 'user-a',
      'version': 1,
      'status_version': 1,
      'created_at': '2026-08-17T00:00:00Z',
      'updated_at': '2026-08-17T00:00:00Z',
    };

    expect(() => TaskItem.fromJson(json), throwsA(isA<FormatException>()));
  });

  test('TaskItem defensively copies and freezes labels', () {
    final labels = <String>['工作'];
    final task = TaskItem(
      id: 'task-1',
      parentTaskId: null,
      title: '整理旅行计划',
      description: '确定交通',
      status: 'TODO',
      currentHandlerId: 'user-a',
      quadrant: 'Q1',
      labels: labels,
      plannedStartAt: null,
      dueAt: null,
      estimatedMinutes: null,
      completedAt: null,
      createdBy: 'user-a',
      version: 1,
      statusVersion: 1,
      createdAt: DateTime.utc(2026, 8, 17),
      updatedAt: DateTime.utc(2026, 8, 17),
    );

    labels.add('婚礼');

    expect(task.labels, ['工作']);
    expect(() => task.labels.add('党员'), throwsUnsupportedError);
  });

  test('TaskItem defensively keeps only string labels from the wire', () {
    final json = <String, dynamic>{
      'id': 'task-1',
      'parent_task_id': null,
      'title': '整理旅行计划',
      'description': '确定交通',
      'status': 'TODO',
      'current_handler_id': 'user-a',
      'quadrant': 'Q1',
      'labels': [' 工作 ', 1, '婚礼'],
      'planned_start_at': null,
      'due_at': null,
      'estimated_minutes': null,
      'completed_at': null,
      'created_by': 'user-a',
      'version': 1,
      'status_version': 1,
      'created_at': '2026-08-17T00:00:00Z',
      'updated_at': '2026-08-17T00:00:00Z',
    };

    final task = TaskItem.fromJson(json);

    expect(task.labels, [' 工作 ', '婚礼']);
  });

  test('TaskItem rejects a non-array labels payload', () {
    final json = <String, dynamic>{
      'id': 'task-1',
      'parent_task_id': null,
      'title': '整理旅行计划',
      'description': '确定交通',
      'status': 'TODO',
      'current_handler_id': 'user-a',
      'quadrant': 'Q1',
      'labels': null,
      'planned_start_at': null,
      'due_at': null,
      'estimated_minutes': null,
      'completed_at': null,
      'created_by': 'user-a',
      'version': 1,
      'status_version': 1,
      'created_at': '2026-08-17T00:00:00Z',
      'updated_at': '2026-08-17T00:00:00Z',
    };

    expect(() => TaskItem.fromJson(json), throwsA(isA<FormatException>()));
  });

  test('TaskDelayRecord parses immutable delay facts', () {
    final record = TaskDelayRecord.fromJson({
      'id': 'delay-1',
      'task_id': 'task-1',
      'user_id': 'user-a',
      'original_due_at': '2026-09-03T01:00:00Z',
      'new_due_at': '2026-09-04T01:00:00Z',
      'delayed_at': '2026-09-01T02:00:00Z',
      'delay_duration_minutes': 1440,
      'reason': 'NO_TIME',
      'note': '当天没有时间',
      'created_at': '2026-09-01T02:00:00Z',
    });

    expect(record.taskId, 'task-1');
    expect(record.originalDueAt, DateTime.utc(2026, 9, 3, 1));
    expect(record.newDueAt, DateTime.utc(2026, 9, 4, 1));
    expect(record.delayDurationMinutes, 1440);
    expect(taskDelayReasonLabels[record.reason], '没有时间');
  });
}
