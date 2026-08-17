import 'package:muyu_client/models/task.dart';
import 'package:muyu_client/task/task_repository.dart';

TaskItem fakeTask(
  String id, {
  String title = '准备旅行',
  String status = 'TODO',
  List<String> assigneeIds = const ['1'],
  String currentHandlerId = '1',
  String? parentTaskId,
  String? blockedReason,
  String? resumeHandlerId,
  String? waitingForUserId,
  DateTime? dueAt,
  int delayCount = 0,
  int totalDelayMinutes = 0,
}) => TaskItem(
  id: id,
  parentTaskId: parentTaskId,
  title: title,
  description: '确定交通和住宿',
  status: status,
  currentHandlerId: currentHandlerId,
  blockedReason: blockedReason,
  resumeHandlerId: resumeHandlerId,
  waitingForUserId: waitingForUserId,
  plannedStartAt: null,
  dueAt: dueAt,
  estimatedMinutes: 60,
  completedAt: status == 'DONE' ? DateTime.utc(2026, 8, 17) : null,
  createdBy: '1',
  version: 1,
  statusVersion: 1,
  createdAt: DateTime.utc(2026, 8, 17),
  updatedAt: DateTime.utc(2026, 8, 17),
  assigneeIds: assigneeIds,
  delayCount: delayCount,
  totalDelayMinutes: totalDelayMinutes,
);

class FakeTaskRepository implements TaskRepository {
  List<TaskItem> values;

  FakeTaskRepository({List<TaskItem>? values}) : values = values ?? [];

  @override
  Future<List<TaskItem>> list({String? parentTaskId}) async =>
      values.where((task) => task.parentTaskId == parentTaskId).toList();

  @override
  Future<TaskItem> get(String taskId) async =>
      values.firstWhere((task) => task.id == taskId);

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
  }) async {
    final value = fakeTask(
      'task-${values.length + 1}',
      title: title,
      assigneeIds: assigneeIds,
      currentHandlerId: currentHandlerId ?? assigneeIds.first,
      parentTaskId: parentTaskId,
    );
    values = [...values, value];
    return value;
  }

  @override
  Future<TaskItem> update(
    String taskId, {
    String? title,
    String? description,
    List<String>? assigneeIds,
    DateTime? plannedStartAt,
    DateTime? dueAt,
    int? estimatedMinutes,
  }) async => get(taskId);

  @override
  Future<void> delete(String taskId) async {
    values = values.where((task) => task.id != taskId).toList();
  }

  @override
  Future<TaskItem> start(String taskId) => _status(taskId, 'IN_PROGRESS');

  @override
  Future<TaskItem> complete(String taskId) => _status(taskId, 'DONE');

  @override
  Future<TaskItem> delay(
    String taskId, {
    required DateTime newDueAt,
    required String reason,
    String? note,
  }) async {
    final current = await get(taskId);
    final updated = fakeTask(
      current.id,
      title: current.title,
      status: current.status,
      assigneeIds: current.assigneeIds,
      currentHandlerId: current.currentHandlerId,
      parentTaskId: current.parentTaskId,
      dueAt: newDueAt,
      delayCount: current.delayCount + 1,
      totalDelayMinutes: current.totalDelayMinutes + 1440,
    );
    _replace(updated);
    return updated;
  }

  @override
  Future<List<TaskDelayRecord>> delays(String taskId) async => const [];

  @override
  Future<TaskItem> block(
    String taskId, {
    required String blockedReason,
    required String resumeHandlerId,
    String? waitingForUserId,
  }) async {
    final current = await get(taskId);
    final updated = fakeTask(
      current.id,
      title: current.title,
      status: 'WAITING',
      assigneeIds: current.assigneeIds,
      currentHandlerId: current.currentHandlerId,
      parentTaskId: current.parentTaskId,
      blockedReason: blockedReason,
      resumeHandlerId: resumeHandlerId,
      waitingForUserId: waitingForUserId,
      dueAt: current.dueAt,
      delayCount: current.delayCount,
      totalDelayMinutes: current.totalDelayMinutes,
    );
    _replace(updated);
    return updated;
  }

  @override
  Future<TaskItem> unblock(String taskId) => _status(taskId, 'IN_PROGRESS');

  @override
  Future<TaskItem> reopen(String taskId) => _status(taskId, 'TODO');

  @override
  Future<TaskItem> cancel(String taskId) => _status(taskId, 'CANCELLED');

  @override
  Future<TaskItem> transfer(String taskId, String newHandlerId) async {
    final current = await get(taskId);
    final updated = current.copyWith(currentHandlerId: newHandlerId);
    _replace(updated);
    return updated;
  }

  @override
  Future<List<TaskActivity>> events(String taskId) async => const [];

  @override
  Future<List<String>> getOrder() async => values
      .where((task) => task.parentTaskId == null)
      .map((task) => task.id)
      .toList();

  @override
  Future<List<String>> replaceOrder(List<String> taskIds) async => taskIds;

  Future<TaskItem> _status(String taskId, String status) async {
    final updated = (await get(taskId)).copyWith(status: status);
    _replace(updated);
    return updated;
  }

  void _replace(TaskItem value) {
    values = values.map((task) => task.id == value.id ? value : task).toList();
  }
}
