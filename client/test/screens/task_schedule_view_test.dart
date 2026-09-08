import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:muyu_client/models/task.dart';
import 'package:muyu_client/models/workspace_snapshot.dart';
import 'package:muyu_client/screens/task_schedule_view.dart';
import 'package:muyu_client/sync/workspace_sync_controller.dart';
import 'package:muyu_client/theme/muyu_theme.dart';

TaskItem scheduleTask(
  String id,
  String title, {
  DateTime? dueAt,
  List<String> labels = const [],
}) => TaskItem(
  id: id,
  parentTaskId: null,
  title: title,
  description: '',
  status: 'TODO',
  currentHandlerId: 'user-1',
  quadrant: 'Q1',
  labels: labels,
  plannedStartAt: null,
  dueAt: dueAt,
  estimatedMinutes: null,
  completedAt: null,
  createdBy: 'user-1',
  version: 1,
  statusVersion: 1,
  createdAt: DateTime.utc(2026, 1, 1),
  updatedAt: DateTime.utc(2026, 1, 1),
);

WorkspaceSyncState scheduleState(List<TaskItem> tasks) => WorkspaceSyncState(
  snapshot: WorkspaceSnapshot(
    workspaceId: 'workspace-1',
    cursor: 1,
    tasks: tasks,
    viewerUserId: 'user-1',
  ),
  isStale: false,
);

Widget scheduleApp(TaskScheduleView view) => MaterialApp(
  theme: muyuLightTheme(),
  home: Scaffold(body: view),
);

DateTime dateOnly(DateTime value) =>
    DateTime(value.year, value.month, value.day);

DateTime weekStart(DateTime value) =>
    dateOnly(value).subtract(Duration(days: value.weekday - DateTime.monday));

int weekNumber(DateTime value) {
  final start = weekStart(value);
  final yearStart = DateTime(start.year, 1, 1);
  return (start.difference(yearStart).inDays ~/ 7) + 1;
}

void main() {
  testWidgets('defaults to today, dims adjacent dates, and marks task dates', (
    tester,
  ) async {
    final today = dateOnly(DateTime.now().toLocal());
    await tester.pumpWidget(
      scheduleApp(
        TaskScheduleView(
          sync: WorkspaceSyncController.unavailable(),
          state: scheduleState([
            scheduleTask('today-task', 'Today task', dueAt: today),
            scheduleTask(
              'unplanned-task',
              'Unplanned task',
              labels: const ['工作'],
            ),
          ]),
          canWrite: true,
          onTaskTap: (_) {},
        ),
      ),
    );

    expect(find.byKey(const Key('task-schedule-month-title')), findsOneWidget);
    expect(
      find.byKey(Key('task-schedule-day-${_dateKey(today)}')),
      findsOneWidget,
    );
    final previousMonthDate = DateTime(
      today.year,
      today.month,
      1,
    ).subtract(const Duration(days: 1));
    final adjacentDateText = tester.widget<Text>(
      find.descendant(
        of: find.byKey(Key('task-schedule-day-${_dateKey(previousMonthDate)}')),
        matching: find.byType(Text),
      ),
    );
    final todayText = tester.widget<Text>(
      find.descendant(
        of: find.byKey(Key('task-schedule-day-${_dateKey(today)}')),
        matching: find.byType(Text),
      ),
    );
    expect(
      adjacentDateText.style?.color?.a,
      lessThan(todayText.style?.color?.a ?? 1),
    );
    expect(
      find.descendant(
        of: find.byKey(const Key('task-schedule-agenda-header')),
        matching: find.textContaining('今天'),
      ),
      findsOneWidget,
    );
    expect(find.text('Today task'), findsOneWidget);
    expect(find.text('Unplanned task'), findsOneWidget);
    expect(
      find.byKey(const Key('task-schedule-month-previous')),
      findsOneWidget,
    );
    expect(find.byKey(const Key('task-schedule-month-next')), findsOneWidget);
  });

  testWidgets('month arrows and week-number selection update the agenda', (
    tester,
  ) async {
    final today = dateOnly(DateTime.now().toLocal());
    final nextWeek = today.add(const Duration(days: 7));
    await tester.pumpWidget(
      scheduleApp(
        TaskScheduleView(
          sync: WorkspaceSyncController.unavailable(),
          state: scheduleState([
            scheduleTask('today-task', 'Today task', dueAt: today),
            scheduleTask('next-week-task', 'Next week task', dueAt: nextWeek),
          ]),
          canWrite: true,
          onTaskTap: (_) {},
        ),
      ),
    );

    final initialMonth = tester
        .widget<Text>(find.byKey(const Key('task-schedule-month-title')))
        .data;
    await tester.tap(find.byKey(const Key('task-schedule-month-next')));
    await tester.pump();
    expect(
      tester
          .widget<Text>(find.byKey(const Key('task-schedule-month-title')))
          .data,
      isNot(initialMonth),
    );
    await tester.tap(find.byKey(const Key('task-schedule-month-previous')));
    await tester.pump();

    await tester.tap(
      find.byKey(Key('task-schedule-week-${weekNumber(nextWeek)}')),
    );
    await tester.pump();
    expect(find.text('整周'), findsOneWidget);
    expect(find.text('Next week task'), findsOneWidget);
    expect(find.text('Today task'), findsNothing);
  });

  testWidgets('agenda cards preserve task navigation and category filtering', (
    tester,
  ) async {
    final today = dateOnly(DateTime.now().toLocal());
    TaskItem? tapped;
    await tester.pumpWidget(
      scheduleApp(
        TaskScheduleView(
          sync: WorkspaceSyncController.unavailable(),
          state: scheduleState([
            scheduleTask(
              'work-task',
              'Work task',
              dueAt: today,
              labels: const ['工作'],
            ),
            scheduleTask(
              'home-task',
              'Home task',
              dueAt: today,
              labels: const ['生活'],
            ),
          ]),
          canWrite: true,
          selectedLabel: '工作',
          onTaskTap: (task) => tapped = task,
        ),
      ),
    );

    expect(find.text('Work task'), findsOneWidget);
    expect(find.text('Home task'), findsNothing);
    await tester.tap(find.byKey(const ValueKey('task-card-work-task')));
    expect(tapped?.id, 'work-task');
  });
}

String _dateKey(DateTime value) {
  final month = value.month.toString().padLeft(2, '0');
  final day = value.day.toString().padLeft(2, '0');
  return '${value.year.toString().padLeft(4, '0')}-$month-$day';
}
