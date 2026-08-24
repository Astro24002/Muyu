import '../core/api_client.dart';
import '../models/workspace_change.dart';
import '../models/workspace_snapshot.dart';

abstract interface class WorkspaceSyncRepository {
  Future<WorkspaceSnapshot> snapshot();

  Future<WorkspaceChanges> changes({required int afterCursor});

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
}
