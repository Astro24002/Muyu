import 'package:flutter_test/flutter_test.dart';
import 'package:muyu_client/models/task.dart';
import 'package:muyu_client/task/task_controller.dart';
import 'package:muyu_client/task/task_repository.dart';

TaskItem task(String id, {String status = 'TODO'}) => TaskItem(
  id: id,
  parentTaskId: null,
  title: '任务 $id',
  description: '',
  status: status,
  currentHandlerId: 'user-a',
  plannedStartAt: null,
  dueAt: null,
  estimatedMinutes: null,
  completedAt: null,
  createdBy: 'user-a',
  version: 1,
  statusVersion: 1,
  createdAt: DateTime.utc(2026, 8, 17),
  updatedAt: DateTime.utc(2026, 8, 17),
  assigneeIds: const ['user-a'],
);

class FakeTaskRepository implements TaskRepository {
  List<TaskItem> values = [task('one')];
  bool fail = false;

  @override
  Future<TaskItem> cancel(String taskId) async =>
      task(taskId, status: 'CANCELLED');

  @override
  Future<TaskItem> complete(String taskId) async =>
      task(taskId, status: 'DONE');

  @override
  Future<TaskItem> create({
    required String title,
    required String description,
    required List<String> assigneeIds,
    String? currentHandlerId,
    String? parentTaskId,
    DateTime? plannedStartAt,
    DateTime? dueAt,
    int? estimatedMinutes,
  }) async => task('created');

  @override
  Future<void> delete(String taskId) async {}

  @override
  Future<TaskItem> get(String taskId) async => task(taskId);

  @override
  Future<List<TaskItem>> list({String? parentTaskId}) async {
    if (fail) throw const TaskFailure('加载失败');
    return values;
  }

  @override
  Future<List<TaskActivity>> events(String taskId) async => const [];

  @override
  Future<TaskItem> reopen(String taskId) async => task(taskId);

  @override
  Future<TaskItem> start(String taskId) async =>
      task(taskId, status: 'IN_PROGRESS');

  @override
  Future<TaskItem> transfer(String taskId, String newHandlerId) async =>
      task(taskId);

  @override
  Future<TaskItem> update(
    String taskId, {
    String? title,
    String? description,
    List<String>? assigneeIds,
    DateTime? plannedStartAt,
    DateTime? dueAt,
    int? estimatedMinutes,
  }) async => task(taskId);

  @override
  Future<List<String>> getOrder() async =>
      values.map((value) => value.id).toList();

  @override
  Future<List<String>> replaceOrder(List<String> taskIds) async => taskIds;
}

void main() {
  test('controller loads tasks and retains API errors', () async {
    final repository = FakeTaskRepository();
    final controller = TaskController(repository);

    await controller.load();
    expect(controller.tasks.single.id, 'one');

    repository.fail = true;
    await controller.load();
    expect(controller.errorMessage, '加载失败');
    expect(controller.tasks.single.id, 'one');
  });

  test('controller action replaces the matching task', () async {
    final controller = TaskController(FakeTaskRepository());
    await controller.load();

    await controller.start('one');

    expect(controller.tasks.single.status, 'IN_PROGRESS');
  });
}
