import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:muyu_client/core/api_client.dart';
import 'package:muyu_client/screens/all_tasks_screen.dart';
import 'package:muyu_client/task/task_query_repository.dart';

void main() {
  testWidgets('initial query failure is not shown as an empty result', (
    tester,
  ) async {
    final api = ApiClient(
      baseUrl: 'https://api.example',
      httpClient: MockClient(
        (_) async => http.Response(
          '{"code":"TEMPORARY","message":"暂时无法加载"}',
          503,
          headers: {'content-type': 'application/json; charset=utf-8'},
        ),
      ),
    );
    await tester.pumpWidget(
      MaterialApp(
        home: AllTasksScreen(
          repository: TaskQueryRepository(api),
          onTaskTap: (_) {},
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('all-tasks-error')), findsOneWidget);
    expect(find.text('没有符合当前筛选条件的事情'), findsNothing);
    expect(find.byKey(const Key('all-tasks-refresh')), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('searches, filters, pages and retains results after a failure', (
    tester,
  ) async {
    final requests = <Uri>[];
    var failNext = false;
    final api = ApiClient(
      baseUrl: 'https://api.example',
      httpClient: MockClient((request) async {
        requests.add(request.url);
        if (failNext) {
          failNext = false;
          return http.Response(
            '{"code":"ERROR","message":"暂时无法加载"}',
            503,
            headers: {'content-type': 'application/json; charset=utf-8'},
          );
        }
        final after = request.url.queryParameters['after'];
        final q = request.url.queryParameters['q'];
        final status = request.url.queryParameters['status'];
        return http.Response(
          jsonEncode({
            'items': [
              {
                'id': after == null ? 'first' : 'second',
                'parent_task_id': null,
                'title': after == null ? (q ?? '第一件') : '第二件',
                'description': '',
                'status': status == 'done' ? 'DONE' : 'TODO',
                'current_handler_id': 'user-1',
                'quadrant': 'Q2',
                'labels': ['婚礼'],
                'planned_start_at': null,
                'due_at': null,
                'estimated_minutes': null,
                'completed_at': null,
                'created_by': 'user-1',
                'version': 1,
                'status_version': 1,
                'created_at': '2026-09-01T00:00:00Z',
                'updated_at': '2026-09-01T00:00:00Z',
              },
            ],
            'has_more': after == null,
            'next_cursor': after == null ? 'next.page' : null,
            'query': {'status': status},
          }),
          200,
          headers: {'content-type': 'application/json; charset=utf-8'},
        );
      }),
    );
    final opened = <String>[];
    await tester.pumpWidget(
      MaterialApp(
        home: AllTasksScreen(
          repository: TaskQueryRepository(api),
          onTaskTap: (task) => opened.add(task.id),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('第一件'), findsOneWidget);
    await tester.tap(find.byKey(const Key('all-tasks-load-more')));
    await tester.pumpAndSettle();
    expect(find.text('第二件'), findsOneWidget);
    await tester.tap(find.text('第二件'));
    expect(opened, ['second']);

    await tester.enterText(find.byKey(const Key('all-tasks-search')), '婚礼 歌单');
    await tester.pump(const Duration(milliseconds: 400));
    await tester.pumpAndSettle();
    expect(requests.last.queryParameters['q'], '婚礼 歌单');
    expect(find.text('第二件'), findsNothing);

    await tester.tap(find.byKey(const Key('all-tasks-status')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('完成').last);
    await tester.pumpAndSettle();
    expect(requests.last.queryParameters['status'], 'done');

    await tester.tap(find.byKey(const Key('all-tasks-status')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('已取消').last);
    await tester.pumpAndSettle();
    expect(requests.last.queryParameters['status'], 'cancelled');

    failNext = true;
    await tester.tap(find.byKey(const Key('all-tasks-refresh')));
    await tester.pumpAndSettle();
    expect(find.text('婚礼 歌单'), findsWidgets);
    expect(find.textContaining('暂时无法加载'), findsOneWidget);
  });

  testWidgets('keeps source search and filter state after opening a task', (
    tester,
  ) async {
    final api = ApiClient(
      baseUrl: 'https://api.example',
      httpClient: MockClient(
        (request) async => http.Response(
          jsonEncode({
            'items': [
              {
                'id': 'task-1',
                'parent_task_id': null,
                'title': '保留来源',
                'description': '',
                'status': 'BLOCKED',
                'current_handler_id': 'user-1',
                'quadrant': 'Q1',
                'labels': [],
                'planned_start_at': null,
                'due_at': null,
                'estimated_minutes': null,
                'completed_at': null,
                'created_by': 'user-1',
                'version': 1,
                'status_version': 1,
                'created_at': '2026-09-01T00:00:00Z',
                'updated_at': '2026-09-01T00:00:00Z',
              },
            ],
            'has_more': false,
            'next_cursor': null,
            'query': {},
          }),
          200,
          headers: {'content-type': 'application/json; charset=utf-8'},
        ),
      ),
    );
    await tester.pumpWidget(
      MaterialApp(
        home: AllTasksScreen(
          repository: TaskQueryRepository(api),
          onTaskTap: (task) => showDialog<void>(
            context: tester.element(find.byType(AllTasksScreen)),
            builder: (context) => AlertDialog(
              title: Text(task.title),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: const Text('关闭'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const Key('all-tasks-search')), '来源');
    await tester.pump(const Duration(milliseconds: 400));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('all-tasks-status')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('阻塞').last);
    await tester.pumpAndSettle();
    await tester.tap(find.text('保留来源'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('关闭'));
    await tester.pumpAndSettle();

    expect(find.text('来源'), findsOneWidget);
    expect(find.text('阻塞'), findsOneWidget);
    expect(find.text('保留来源'), findsOneWidget);
  });
}
