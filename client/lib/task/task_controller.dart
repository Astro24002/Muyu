import 'package:flutter/foundation.dart';

import '../models/task.dart';
import 'task_repository.dart';

class TaskController extends ChangeNotifier {
  TaskController(this._repository);

  final TaskRepository _repository;
  List<TaskItem> tasks = const [];
  List<TaskDelayRecord> delayRecords = const [];
  String? errorMessage;
  bool loading = false;

  Future<void> load({String? parentTaskId}) async {
    loading = true;
    notifyListeners();
    try {
      tasks = await _repository.list(parentTaskId: parentTaskId);
      errorMessage = null;
    } on TaskFailure catch (error) {
      errorMessage = error.message;
    } finally {
      loading = false;
      notifyListeners();
    }
  }

  Future<void> loadDelays(String taskId) async {
    loading = true;
    notifyListeners();
    try {
      delayRecords = await _repository.delays(taskId);
      errorMessage = null;
    } on TaskFailure catch (error) {
      errorMessage = error.message;
    } finally {
      loading = false;
      notifyListeners();
    }
  }

  Future<TaskItem?> create({
    required String title,
    required String description,
    required List<String> assigneeIds,
    String? currentHandlerId,
    String? parentTaskId,
    DateTime? plannedStartAt,
    DateTime? dueAt,
    int? estimatedMinutes,
  }) async {
    try {
      final task = await _repository.create(
        title: title,
        description: description,
        assigneeIds: assigneeIds,
        currentHandlerId: currentHandlerId,
        parentTaskId: parentTaskId,
        plannedStartAt: plannedStartAt,
        dueAt: dueAt,
        estimatedMinutes: estimatedMinutes,
      );
      _upsert(task);
      errorMessage = null;
      notifyListeners();
      return task;
    } on TaskFailure catch (error) {
      errorMessage = error.message;
      notifyListeners();
      return null;
    }
  }

  Future<bool> start(String taskId) =>
      _runAction(() => _repository.start(taskId));

  Future<bool> complete(String taskId) =>
      _runAction(() => _repository.complete(taskId));

  Future<bool> reopen(String taskId) =>
      _runAction(() => _repository.reopen(taskId));

  Future<bool> cancel(String taskId) =>
      _runAction(() => _repository.cancel(taskId));

  Future<bool> transfer(String taskId, String userId) =>
      _runAction(() => _repository.transfer(taskId, userId));

  Future<bool> delay(
    String taskId, {
    required DateTime newDueAt,
    required String reason,
    String? note,
  }) => _runAction(
    () => _repository.delay(
      taskId,
      newDueAt: newDueAt,
      reason: reason,
      note: note,
    ),
  );

  Future<bool> block(
    String taskId, {
    required String blockedReason,
    required String resumeHandlerId,
    String? waitingForUserId,
  }) => _runAction(
    () => _repository.block(
      taskId,
      blockedReason: blockedReason,
      resumeHandlerId: resumeHandlerId,
      waitingForUserId: waitingForUserId,
    ),
  );

  Future<bool> unblock(String taskId) =>
      _runAction(() => _repository.unblock(taskId));

  Future<bool> _runAction(Future<TaskItem> Function() action) async {
    try {
      _upsert(await action());
      errorMessage = null;
      notifyListeners();
      return true;
    } on TaskFailure catch (error) {
      errorMessage = error.message;
      notifyListeners();
      return false;
    }
  }

  void _upsert(TaskItem value) {
    final index = tasks.indexWhere((task) => task.id == value.id);
    if (index == -1) {
      tasks = [...tasks, value];
    } else {
      final next = [...tasks]..[index] = value;
      tasks = next;
    }
  }
}
