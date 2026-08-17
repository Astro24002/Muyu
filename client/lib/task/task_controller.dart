import 'package:flutter/foundation.dart';

import '../models/task.dart';
import 'task_repository.dart';

class TaskController extends ChangeNotifier {
  TaskController(this._repository);

  final TaskRepository _repository;
  List<TaskItem> tasks = const [];
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

  Future<void> start(String taskId) =>
      _runAction(() => _repository.start(taskId));

  Future<void> complete(String taskId) =>
      _runAction(() => _repository.complete(taskId));

  Future<void> reopen(String taskId) =>
      _runAction(() => _repository.reopen(taskId));

  Future<void> cancel(String taskId) =>
      _runAction(() => _repository.cancel(taskId));

  Future<void> transfer(String taskId, String userId) =>
      _runAction(() => _repository.transfer(taskId, userId));

  Future<void> _runAction(Future<TaskItem> Function() action) async {
    try {
      _upsert(await action());
      errorMessage = null;
    } on TaskFailure catch (error) {
      errorMessage = error.message;
    }
    notifyListeners();
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
