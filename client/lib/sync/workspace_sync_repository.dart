import '../core/api_client.dart';
import '../models/workspace_change.dart';
import '../models/workspace_snapshot.dart';
import '../models/task.dart';

abstract class WorkspaceSyncRepository {
  Future<WorkspaceSnapshot> snapshot();

  Future<WorkspaceChanges> changes({required int afterCursor});

  Future<TaskItem> transition(String taskId, {required String targetStatus, required int baseStatusVersion, String? blockedReason, String? resumeHandlerId, String? waitingForUserId, required String requestId}) => throw UnimplementedError();
  Future<Object?> addComment(String taskId, {required String body, required String requestId}) => throw UnimplementedError();
  Future<Object?> addDelay(String taskId, {required String newDueAt, required String reason, String? note, required String requestId}) => throw UnimplementedError();

  Stream<WorkspaceChanged> openWorkspaceHints();
}

class HttpWorkspaceSyncRepository implements WorkspaceSyncRepository {
  HttpWorkspaceSyncRepository(this._api, {this.hints = const Stream.empty()});

  final ApiClient _api;
  final Stream<WorkspaceChanged> hints;

  @override
  Stream<WorkspaceChanged> openWorkspaceHints() => hints;

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
  Future<TaskItem> transition(String taskId, {required String targetStatus, required int baseStatusVersion, String? blockedReason, String? resumeHandlerId, String? waitingForUserId, required String requestId}) async => TaskItem.fromJson(await _api.request('POST', '/api/v1/tasks/$taskId/transition', body: {'request_id': requestId, 'target_status': targetStatus, 'base_status_version': baseStatusVersion, 'blocked_reason': blockedReason, 'resume_handler_id': resumeHandlerId, 'waiting_for_user_id': waitingForUserId}, authenticated: true, headers: {'x-request-id': requestId}) as Map<String, dynamic>);

  @override
  Future<Object?> addComment(String taskId, {required String body, required String requestId}) => _api.request('POST', '/api/v1/tasks/$taskId/comments', body: {'request_id': requestId, 'body': body}, authenticated: true, headers: {'x-request-id': requestId});

  @override
  Future<Object?> addDelay(String taskId, {required String newDueAt, required String reason, String? note, required String requestId}) => _api.request('POST', '/api/v1/tasks/$taskId/delays', body: {'request_id': requestId, 'new_due_at': newDueAt, 'reason': reason, 'note': note}, authenticated: true, headers: {'x-request-id': requestId});
}
