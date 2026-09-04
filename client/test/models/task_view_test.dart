import 'package:flutter_test/flutter_test.dart';
import 'package:muyu_client/models/task.dart';
import 'package:muyu_client/models/task_view.dart';

TaskItem makeTask(
  String id,
  String status,
  DateTime? due, {
  String handler = 'u1',
  String quadrant = 'Q1',
  List<String> labels = const [],
  DateTime? updatedAt,
  String? parentTaskId,
  String? blockedReason,
  DateTime? blockedSince,
}) => TaskItem(
  id: id,
  parentTaskId: parentTaskId,
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
  blockedReason: blockedReason,
  blockedSince: blockedSince,
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

  test(
    'filters mine by current handler and ignores another member history',
    () {
      final tasks = [
        makeTask('owned-by-me', 'TODO', null, handler: 'u1'),
        makeTask('owned-by-other', 'TODO', null, handler: 'u2'),
      ];

      expect(TaskView.mine(tasks, 'u1').map((task) => task.id), [
        'owned-by-me',
      ]);
    },
  );

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

  test('list categories count unfinished top-level tasks only', () {
    final tasks = [
      makeTask('work-active', 'IN_PROGRESS', null, labels: ['工作', '常规事项']),
      makeTask('work-done', 'DONE', null, labels: ['工作']),
      makeTask(
        'child',
        'TODO',
        null,
        labels: ['工作'],
        parentTaskId: 'work-active',
      ),
      makeTask('cancelled', 'CANCELLED', null, labels: ['婚礼']),
      makeTask('wedding-active', 'TODO', null, labels: ['婚礼']),
    ];

    final categories = TaskView.listCategories(tasks);

    expect(categories.first.label, isNull);
    expect(categories.first.unfinishedCount, 2);
    expect(
      categories.skip(1).map((item) => (item.label, item.unfinishedCount)),
      [('婚礼', 1), ('工作', 1), ('常规事项', 1)],
    );
  });

  test('list groups use delayed and upcoming sections and hide terminal work by default', () {
    final now = DateTime(2026, 8, 31, 12);
    final groups = TaskView.listGroups([
      makeTask('past', 'TODO', DateTime(2026, 8, 30, 9)),
      makeTask('today', 'IN_PROGRESS', DateTime(2026, 8, 31, 18)),
      makeTask('future', 'BLOCKED', DateTime(2026, 9, 1, 9)),
      makeTask('none', 'TODO', null),
      makeTask('outside-window', 'TODO', DateTime(2026, 9, 7, 9)),
      makeTask('done', 'DONE', DateTime(2026, 8, 29)),
      makeTask('failed', 'CANCELLED', DateTime(2026, 8, 28)),
    ], now: now);

    expect(groups.map((group) => group.key), ['past', 'upcoming']);
    expect(groups[0].title, '已经延期');
    expect(groups[1].title, '即将到期');
    expect(groups[0].tasks.map((item) => item.id), ['past']);
    expect(groups[1].tasks.map((item) => item.id), ['today', 'none']);
  });

  test('list groups include exactly seven calendar days and move blocked/review out', () {
    final now = DateTime(2026, 8, 31, 12);
    final groups = TaskView.listGroups([
      makeTask('today-later', 'TODO', DateTime(2026, 8, 31, 18)),
      makeTask('last-day', 'IN_PROGRESS', DateTime(2026, 9, 6, 23, 59)),
      makeTask('outside-window', 'TODO', DateTime(2026, 9, 7, 0)),
      makeTask('blocked', 'BLOCKED', DateTime(2026, 9, 1, 9)),
      makeTask('review', 'REVIEW', DateTime(2026, 9, 1, 10)),
    ], now: now);

    expect(groups[0].tasks, isEmpty);
    expect(groups[1].tasks.map((item) => item.id), ['today-later', 'last-day']);
  });

  test('list groups treat earlier today as overdue', () {
    final now = DateTime(2026, 8, 31, 12);
    final groups = TaskView.listGroups([
      makeTask('earlier-today', 'TODO', DateTime(2026, 8, 31, 9)),
    ], now: now);

    expect(groups[0].tasks.map((item) => item.id), ['earlier-today']);
    expect(groups[1].tasks, isEmpty);
  });

  test('list groups show terminal section only when completed or cancelled is enabled', () {
    final tasks = [
      makeTask('done', 'DONE', DateTime(2026, 8, 29)),
      makeTask('failed', 'CANCELLED', DateTime(2026, 8, 28)),
    ];

    final completedOnly = TaskView.listGroups(
      tasks,
      showCompleted: true,
      showFailed: false,
    );
    expect(completedOnly.map((group) => group.key), [
      'past',
      'upcoming',
      'terminal',
    ]);
    expect(completedOnly.last.tasks.map((task) => task.id), ['done']);

    final allTerminal = TaskView.listGroups(
      tasks,
      showCompleted: true,
      showFailed: true,
    );
    expect(allTerminal.last.tasks.map((task) => task.id), ['done', 'failed']);
    expect(allTerminal.last.title, '已完成 / 已取消');
  });

  test('list groups keep legacy COMPLETED tasks out of active sections', () {
    final groups = TaskView.listGroups([
      makeTask('legacy-completed', 'COMPLETED', null),
    ], showCompleted: true);

    expect(groups[0].tasks, isEmpty);
    expect(groups[1].tasks, isEmpty);
    expect(groups[2].tasks.map((item) => item.id), ['legacy-completed']);
  });

  test('list groups filter terminal visibility and apply selected label', () {
    final groups = TaskView.listGroups(
      [
        makeTask('work', 'TODO', null, labels: ['工作']),
        makeTask('work-done', 'DONE', null, labels: ['工作']),
        makeTask('wedding-failed', 'CANCELLED', null, labels: ['婚礼']),
      ],
      label: ' 工作 ',
      showCompleted: false,
      showFailed: false,
    );

    expect(groups.expand((group) => group.tasks).map((item) => item.id), [
      'work',
    ]);
    expect(groups.map((group) => group.key), ['past', 'upcoming']);
  });

  test('list groups sort each group by the selected sort mode', () {
    final now = DateTime(2026, 8, 31, 12);
    final tasks = [
      makeTask(
        'q4',
        'TODO',
        DateTime(2026, 9, 1, 9),
        quadrant: 'Q4',
        updatedAt: DateTime(2026, 8, 31, 2),
      ),
      makeTask(
        'q1',
        'TODO',
        DateTime(2026, 9, 2, 9),
        quadrant: 'Q1',
        updatedAt: DateTime(2026, 8, 31, 1),
      ),
    ];

    expect(
      TaskView.listGroups(
        tasks,
        now: now,
        sort: TaskListSort.quadrant,
      )[1].tasks.map((item) => item.id),
      ['q1', 'q4'],
    );
    expect(
      TaskView.listGroups(
        tasks,
        now: now,
        sort: TaskListSort.updatedAt,
      )[1].tasks.map((item) => item.id),
      ['q4', 'q1'],
    );
  });

  test('elapsed labels use compact minute, hour and day formats', () {
    final now = DateTime(2026, 8, 31, 12);

    expect(
      TaskView.elapsedLabel(
        prefix: '逾期',
        since: now.subtract(const Duration(minutes: 8)),
        now: now,
      ),
      '逾期08m',
    );
    expect(
      TaskView.elapsedLabel(
        prefix: '逾期',
        since: now.subtract(const Duration(hours: 14, minutes: 20)),
        now: now,
      ),
      '逾期14h20m',
    );
    expect(
      TaskView.elapsedLabel(
        prefix: '阻塞',
        since: now.subtract(const Duration(days: 2, hours: 4)),
        now: now,
      ),
      '阻塞  2d04h',
    );
  });
}
