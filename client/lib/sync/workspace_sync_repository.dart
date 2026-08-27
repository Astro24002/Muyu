import '../core/api_client.dart';
import '../models/workspace_change.dart';
import '../models/workspace_snapshot.dart';
import '../models/task.dart';

abstract class WorkspaceSyncRepository {
  Future<WorkspaceSnapshot> snapshot();

  Future<WorkspaceChanges> changes({required int afterCursor});

  Future<TaskItem> create({
    required String title,
    String? description,
    String? dueAt,
    String? parentTaskId,
    List<String>? assigneeIds,
    String? plannedStartAt,
    int? estimatedMinutes,
    required String requestId,
  }) {
    throw UnimplementedError();
  }

  Future<TaskItem?> update(
    String taskId, {
    required Map<String, Object?> fields,
    required Map<String, int> fieldVersions,
    required String requestId,
  }) {
    throw UnimplementedError();
  }

  Future<TaskItem> transition(
    String taskId, {
    required String targetStatus,
    required int baseStatusVersion,
    String? blockedReason,
    String? resumeHandlerId,
    String? waitingForUserId,
    required String requestId,
  }) {
    throw UnimplementedError();
  }

  Future<Object?> addComment(
    String taskId, {
    required String body,
    required String requestId,
  }) {
    throw UnimplementedError();
  }

  Future<Object?> addDelay(
    String taskId, {
    required String newDueAt,
    required String reason,
    String? note,
    required String requestId,
  }) {
    throw UnimplementedError();
  }

  Future<TaskItem> resolveConflict(
    String taskId,
    String conflictId, {
    required String resolution,
    required String requestId,
  }) {
    throw UnimplementedError();
  }

  Stream<WorkspaceChanged> openWorkspaceHints();
}

class HttpWorkspaceSyncRepository implements WorkspaceSyncRepository {
  HttpWorkspaceSyncRepository(this._api, {this.hints = const Stream.empty()});

  final ApiClient _api;
  final Stream<WorkspaceChanged> hints;

  @override
  Stream<WorkspaceChanged> openWorkspaceHints() => hints;

  @override
  Future<TaskItem> create({
    required String title,
    String? description,
    String? dueAt,
    String? parentTaskId,
    List<String>? assigneeIds,
    String? plannedStartAt,
    int? estimatedMinutes,
    required String requestId,
  }) async {
    final body = <String, Object?>{'request_id': requestId, 'title': title};
    if (description != null) {
      body['description'] = description;
    }
    if (dueAt != null) {
      body['due_at'] = dueAt;
    }
    if (parentTaskId != null) {
      body['parent_task_id'] = parentTaskId;
    }
    if (assigneeIds != null) {
      body['assignee_ids'] = assigneeIds;
    }
    if (plannedStartAt != null) {
      body['planned_start_at'] = plannedStartAt;
    }
    if (estimatedMinutes != null) {
      body['estimated_minutes'] = estimatedMinutes;
    }
    final value = await _api.request(
      'POST',
      '/api/v1/tasks',
      body: body,
      authenticated: true,
      headers: {'x-request-id': requestId},
    );
    return TaskItem.fromJson(value as Map<String, dynamic>);
  }

  @override
  Future<TaskItem?> update(
    String taskId, {
    required Map<String, Object?> fields,
    required Map<String, int> fieldVersions,
    required String requestId,
  }) async {
    final value = await _api.request(
      'PATCH',
      '/api/v1/tasks/$taskId',
      body: {
        'request_id': requestId,
        'changes': fields,
        'base_field_versions': fieldVersions,
      },
      authenticated: true,
      headers: {'x-request-id': requestId},
    );
    return value is Map<String, dynamic> && value['id'] != null
        ? TaskItem.fromJson(value)
        : null;
  }

  @override
  Future<WorkspaceSnapshot> snapshot() async => WorkspaceSnapshot.fromJson(
    await _api.request(
      'GET',
      '/api/v1/workspaces/current/snapshot',
      authenticated: true,
    ) as Map<String, dynamic>,
  );

  @override
  Future<WorkspaceChanges> changes({required int afterCursor}) async =>
      WorkspaceChanges.fromJson(
        await _api.request(
          'GET',
          '/api/v1/workspaces/current/changes?after_cursor=$afterCursor',
          authenticated: true,
        ) as Map<String, dynamic>,
      );

  @override
  Future<TaskItem> transition(
    String taskId, {
    required String targetStatus,
    required int baseStatusVersion,
    String? blockedReason,
    String? resumeHandlerId,
    String? waitingForUserId,
    required String requestId,
  }) async => TaskItem.fromJson(
    await _api.request(
      'POST',
      '/api/v1/tasks/$taskId/transition',
      body: {
        'request_id': requestId,
        'target_status': targetStatus,
        'base_status_version': baseStatusVersion,
        'blocked_reason': blockedReason,
        'resume_handler_id': resumeHandlerId,
        'waiting_for_user_id': waitingForUserId,
      },
      authenticated: true,
      headers: {'x-request-id': requestId},
    ) as Map<String, dynamic>,
  );

  @override
  Future<Object?> addComment(
    String taskId, {
    required String body,
    required String requestId,
  }) => _api.request(
    'POST',
    '/api/v1/tasks/$taskId/comments',
    body: {'request_id': requestId, 'body': body},
    authenticated: true,
    headers: {'x-request-id': requestId},
  );

  @override
  Future<Object?> addDelay(
    String taskId, {
    required String newDueAt,
    required String reason,
    String? note,
    required String requestId,
  }) => _api.request(
    'POST',
    '/api/v1/tasks/$taskId/delays',
    body: {
      'request_id': requestId,
      'new_due_at': newDueAt,
      'reason': reason,
      'note': note,
    },
    authenticated: true,
    headers: {'x-request-id': requestId},
  );

  @override
  Future<TaskItem> resolveConflict(
    String taskId,
    String conflictId, {
    required String resolution,
    required String requestId,
  }) async => TaskItem.fromJson(
    await _api.request(
      'POST',
      '/api/v1/tasks/$taskId/conflicts/$conflictId/resolve',
      body: {'request_id': requestId, 'resolution': resolution},
      authenticated: true,
      headers: {'x-request-id': requestId},
    ) as Map<String, dynamic>,
  );
}
