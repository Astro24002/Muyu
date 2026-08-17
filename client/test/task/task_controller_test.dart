import 'package:flutter_test/flutter_test.dart';
import 'package:muyu_client/models/task.dart';
import 'package:muyu_client/task/task_controller.dart';
import 'package:muyu_client/task/task_repository.dart';

TaskItem task(
  String id, {
  String status = 'TODO',
  DateTime? dueAt,
  String? blockedReason,
  String? resumeHandlerId,
  int delayCount = 0,
  int totalDelayMinutes = 0,
}) => TaskItem(
  id: id,
  parentTaskId: null,
  title: '任务 $id',
  description: '',
  status: status,
  currentHandlerId: 'user-a',
  blockedReason: blockedReason,
  resumeHandlerId: resumeHandlerId,
  plannedStartAt: null,
  dueAt: dueAt,
  estimatedMinutes: null,
  completedAt: null,
  createdBy: 'user-a',
  version: 1,
  statusVersion: 1,
  createdAt: DateTime.utc(2026, 8, 17),
  updatedAt: DateTime.utc(2026, 8, 17),
  assigneeIds: const ['user-a'],
  delayCount: delayCount,
  totalDelayMinutes: totalDelayMinutes,
);

class FakeTaskRepository implements TaskRepository {
  List<TaskItem> values = [task('one')];
  bool fail = false;
  bool failActions = false;

  @override
  Future<TaskItem> cancel(String taskId) async =>
      task(taskId, status: 'CANCELLED');

  @override
  Future<TaskItem> complete(String taskId) async =>
      task(taskId, status: 'DONE');

  @override
  Future<TaskItem> delay(
    String taskId, {
    required DateTime newDueAt,
    required String reason,
    String? note,
  }) async {
    if (failActions) throw const TaskFailure('操作失败');
    return task(
      taskId,
      dueAt: newDueAt,
      delayCount: 1,
      totalDelayMinutes: 1440,
    );
  }

  @override
  Future<List<TaskDelayRecord>> delays(String taskId) async => [
    TaskDelayRecord(
      id: 'delay-1',
      taskId: taskId,
      userId: 'user-a',
      originalDueAt: DateTime.utc(2026, 9, 3),
      newDueAt: DateTime.utc(2026, 9, 4),
      delayedAt: DateTime.utc(2026, 9, 1),
      delayDurationMinutes: 1440,
      reason: 'NO_TIME',
      note: null,
      createdAt: DateTime.utc(2026, 9, 1),
    ),
  ];

  @override
  Future<TaskItem> block(
    String taskId, {
    required String blockedReason,
    required String resumeHandlerId,
    String? waitingForUserId,
  }) async {
    if (failActions) throw const TaskFailure('操作失败');
    return task(
      taskId,
      status: 'WAITING',
      blockedReason: blockedReason,
      resumeHandlerId: resumeHandlerId,
    );
  }

  @override
  Future<TaskItem> unblock(String taskId) async {
    if (failActions) throw const TaskFailure('操作失败');
    return task(taskId, status: 'IN_PROGRESS');
  }

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

  test('controller handles delay history block and unblock actions', () async {
    final repository = FakeTaskRepository();
    final controller = TaskController(repository);
    await controller.load();

    expect(
      await controller.delay(
        'one',
        newDueAt: DateTime.utc(2026, 9, 4),
        reason: 'NO_TIME',
      ),
      isTrue,
    );
    await controller.loadDelays('one');
    expect(controller.tasks.single.delayCount, 1);
    expect(controller.delayRecords.single.delayDurationMinutes, 1440);

    expect(
      await controller.block(
        'one',
        blockedReason: '等待确认',
        resumeHandlerId: 'user-a',
      ),
      isTrue,
    );
    expect(controller.tasks.single.status, 'WAITING');
    expect(await controller.unblock('one'), isTrue);
    expect(controller.tasks.single.status, 'IN_PROGRESS');
  });

  test('controller retains task and exposes action failure', () async {
    final repository = FakeTaskRepository();
    final controller = TaskController(repository);
    await controller.load();
    repository.failActions = true;

    final succeeded = await controller.block(
      'one',
      blockedReason: '等待确认',
      resumeHandlerId: 'user-a',
    );

    expect(succeeded, isFalse);
    expect(controller.errorMessage, '操作失败');
    expect(controller.tasks.single.status, 'TODO');
  });
}
