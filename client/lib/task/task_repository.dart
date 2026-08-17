import '../core/api_client.dart';
import '../models/task.dart';

class TaskFailure implements Exception {
  const TaskFailure(this.message);

  final String message;

  @override
  String toString() => message;
}

abstract interface class TaskRepository {
  Future<List<TaskItem>> list({String? parentTaskId});

  Future<TaskItem> get(String taskId);

  Future<TaskItem> create({
    required String title,
    required String description,
    required List<String> assigneeIds,
    String? currentHandlerId,
    String? parentTaskId,
    DateTime? plannedStartAt,
    DateTime? dueAt,
    int? estimatedMinutes,
  });

  Future<TaskItem> update(
    String taskId, {
    String? title,
    String? description,
    List<String>? assigneeIds,
    DateTime? plannedStartAt,
    DateTime? dueAt,
    int? estimatedMinutes,
  });

  Future<void> delete(String taskId);

  Future<TaskItem> start(String taskId);

  Future<TaskItem> complete(String taskId);

  Future<TaskItem> reopen(String taskId);

  Future<TaskItem> cancel(String taskId);

  Future<TaskItem> transfer(String taskId, String newHandlerId);

  Future<List<TaskActivity>> events(String taskId);

  Future<List<String>> getOrder();

  Future<List<String>> replaceOrder(List<String> taskIds);
}

class HttpTaskRepository implements TaskRepository {
  HttpTaskRepository(this._apiClient, {this.refreshTokens});

  final ApiClient _apiClient;
  final Future<void> Function()? refreshTokens;

  @override
  Future<List<TaskItem>> list({String? parentTaskId}) async {
    final query = parentTaskId == null ? '' : '?parent_task_id=$parentTaskId';
    final json =
        await _authenticated('GET', '/api/tasks$query') as List<dynamic>;
    return json
        .map((item) => TaskItem.fromJson(item as Map<String, dynamic>))
        .toList();
  }

  @override
  Future<TaskItem> get(String taskId) async => TaskItem.fromJson(
    await _authenticated('GET', '/api/tasks/$taskId') as Map<String, dynamic>,
  );

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
    final body = <String, Object?>{
      'title': title,
      'description': description,
      'assignee_ids': assigneeIds,
      'current_handler_id': ?currentHandlerId,
      'parent_task_id': ?parentTaskId,
      'planned_start_at': ?plannedStartAt?.toUtc().toIso8601String(),
      'due_at': ?dueAt?.toUtc().toIso8601String(),
      'estimated_minutes': ?estimatedMinutes,
    };
    return TaskItem.fromJson(
      await _authenticated('POST', '/api/tasks', body: body)
          as Map<String, dynamic>,
    );
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
  }) async {
    final body = <String, Object?>{
      'title': ?title,
      'description': ?description,
      'assignee_ids': ?assigneeIds,
      'planned_start_at': ?plannedStartAt?.toUtc().toIso8601String(),
      'due_at': ?dueAt?.toUtc().toIso8601String(),
      'estimated_minutes': ?estimatedMinutes,
    };
    return TaskItem.fromJson(
      await _authenticated('PATCH', '/api/tasks/$taskId', body: body)
          as Map<String, dynamic>,
    );
  }

  @override
  Future<void> delete(String taskId) async {
    await _authenticated('DELETE', '/api/tasks/$taskId');
  }

  @override
  Future<TaskItem> start(String taskId) => _action(taskId, 'start');

  @override
  Future<TaskItem> complete(String taskId) => _action(taskId, 'complete');

  @override
  Future<TaskItem> reopen(String taskId) => _action(taskId, 'reopen');

  @override
  Future<TaskItem> cancel(String taskId) => _action(taskId, 'cancel');

  @override
  Future<TaskItem> transfer(String taskId, String newHandlerId) async =>
      TaskItem.fromJson(
        await _authenticated(
          'POST',
          '/api/tasks/$taskId/transfer',
          body: {'new_handler_id': newHandlerId},
        ) as Map<String, dynamic>,
      );

  @override
  Future<List<TaskActivity>> events(String taskId) async {
    final json = await _authenticated(
      'GET',
      '/api/tasks/$taskId/events',
    ) as List<dynamic>;
    return json
        .map((item) => TaskActivity.fromJson(item as Map<String, dynamic>))
        .toList();
  }

  @override
  Future<List<String>> getOrder() async {
    final json = await _authenticated(
      'GET',
      '/api/me/tasks/order',
    ) as Map<String, dynamic>;
    return (json['task_ids'] as List<dynamic>).cast<String>();
  }

  @override
  Future<List<String>> replaceOrder(List<String> taskIds) async {
    final json = await _authenticated(
      'PUT',
      '/api/me/tasks/order',
      body: {'task_ids': taskIds},
    ) as Map<String, dynamic>;
    return (json['task_ids'] as List<dynamic>).cast<String>();
  }

  Future<TaskItem> _action(String taskId, String action) async =>
      TaskItem.fromJson(
        await _authenticated('POST', '/api/tasks/$taskId/$action')
            as Map<String, dynamic>,
      );

  Future<Object?> _authenticated(
    String method,
    String path, {
    Map<String, Object?>? body,
  }) async {
    try {
      return await _apiClient.request(
        method,
        path,
        body: body,
        authenticated: true,
        refreshTokens: refreshTokens,
      );
    } on TaskFailure {
      rethrow;
    } on ApiException catch (error) {
      throw TaskFailure(error.message);
    }
  }
}
