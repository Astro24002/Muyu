import 'package:flutter_test/flutter_test.dart';
import 'package:muyu_client/models/task.dart';
import 'package:muyu_client/models/task_view.dart';

TaskItem makeTask(
  String id,
  String status,
  DateTime? due, {
  String handler = 'u2',
  List<String> assignees = const ['u1'],
  String quadrant = 'Q1',
  List<String> labels = const [],
  DateTime? updatedAt,
}) => TaskItem(
  id: id,
  parentTaskId: null,
  title: id,
  description: '',
  status: status,
  currentHandlerId: handler,
  quadrant: quadrant,
  labels: labels,
  plannedStartAt: null,
  dueAt: due,
  estimatedMinutes: null,
  completedAt: null,
  createdBy: 'u1',
  version: 1,
  statusVersion: 1,
  createdAt: DateTime.utc(2026),
  updatedAt: updatedAt ?? DateTime.utc(2026),
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

  test('byStatus exposes only the fixed lifecycle groups', () {
    final grouped = TaskView.byStatus([
      makeTask('todo', 'TODO', null),
      makeTask('done', 'DONE', null),
      makeTask('unknown', 'ARCHIVED', null),
    ]);

    expect(grouped.keys, TaskView.statuses);
    expect(grouped['TODO']!.map((task) => task.id), ['todo']);
    expect(grouped['DONE']!.map((task) => task.id), ['done']);
    expect(grouped.containsKey('看板'), isFalse);
    expect(grouped.containsKey('ARCHIVED'), isFalse);
  });

  test('byQuadrant always returns Q1 through Q4 in order', () {
    final grouped = TaskView.byQuadrant([
      makeTask('q3', 'TODO', null, quadrant: 'Q3'),
      makeTask('q1', 'TODO', null, quadrant: 'Q1'),
      makeTask('q3-second', 'DONE', null, quadrant: 'Q3'),
    ]);

    expect(grouped.keys, ['Q1', 'Q2', 'Q3', 'Q4']);
    expect(grouped['Q1']!.map((task) => task.id), ['q1']);
    expect(grouped['Q2'], isEmpty);
    expect(grouped['Q3']!.map((task) => task.id), ['q3', 'q3-second']);
    expect(grouped['Q4'], isEmpty);
    expect(grouped.keys, isNot(contains('UNSET')));
  });

  test('byDueDate sorts local ISO date groups and puts unscheduled last', () {
    final grouped = TaskView.byDueDate([
      makeTask('later', 'TODO', DateTime(2026, 9, 3, 9)),
      makeTask('unscheduled', 'TODO', null),
      makeTask('earlier', 'TODO', DateTime(2026, 9, 1, 9)),
    ], now: DateTime(2026, 9, 1));

    expect(grouped.keys, ['2026-09-01', '2026-09-03', '未安排']);
    expect(grouped['2026-09-01']!.map((task) => task.id), ['earlier']);
    expect(grouped['2026-09-03']!.map((task) => task.id), ['later']);
    expect(grouped['未安排']!.map((task) => task.id), ['unscheduled']);
  });

  test('byDueDate sorts tasks within a date by due time then update time', () {
    final grouped = TaskView.byDueDate([
      makeTask(
        'same-deadline-newer',
        'TODO',
        DateTime(2026, 9, 1, 9),
        updatedAt: DateTime(2026, 8, 31, 3),
      ),
      makeTask(
        'later-deadline',
        'TODO',
        DateTime(2026, 9, 1, 12),
        updatedAt: DateTime(2026, 8, 31, 1),
      ),
      makeTask(
        'same-deadline-older',
        'TODO',
        DateTime(2026, 9, 1, 9),
        updatedAt: DateTime(2026, 8, 31, 2),
      ),
    ]);

    expect(grouped['2026-09-01']!.map((task) => task.id), [
      'same-deadline-older',
      'same-deadline-newer',
      'later-deadline',
    ]);
  });

  test(
    'filterByLabel matches labels case-insensitively and preserves order',
    () {
      final tasks = [
        makeTask('work', 'TODO', null, labels: ['Work', '党员']),
        makeTask('home', 'TODO', null, labels: ['Home']),
        makeTask('work-again', 'TODO', null, labels: ['work']),
      ];

      expect(TaskView.filterByLabel(tasks, ' work ').map((task) => task.id), [
        'work',
        'work-again',
      ]);
      expect(TaskView.filterByLabel(tasks, null), tasks);
      expect(TaskView.filterByLabel(tasks, ''), tasks);
    },
  );
}
