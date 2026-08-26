import '../core/api_client.dart';

class WorkspaceSummary {
  const WorkspaceSummary({
    required this.id,
    required this.name,
    required this.status,
  });

  final String id;
  final String? name;
  final String status;

  factory WorkspaceSummary.fromJson(Map<String, dynamic> json) {
    return WorkspaceSummary(
      id: json['id'] as String,
      name: json['name'] as String?,
      status: json['status'] as String,
    );
  }
}

class WorkspaceBootstrapFailure implements Exception {
  const WorkspaceBootstrapFailure({
    required this.code,
    required this.statusCode,
  });

  final String code;
  final int statusCode;
}

abstract interface class WorkspaceBootstrapRepository {
  Future<WorkspaceSummary?> currentWorkspace();

  Future<WorkspaceSummary> createWorkspace();
}

class HttpWorkspaceBootstrapRepository implements WorkspaceBootstrapRepository {
  HttpWorkspaceBootstrapRepository(this._api);

  final ApiClient _api;

  @override
  Future<WorkspaceSummary?> currentWorkspace() async {
    try {
      final value = await _api.request(
        'GET',
        '/api/v1/workspaces/current',
        authenticated: true,
      );
      return value == null
          ? null
          : WorkspaceSummary.fromJson(value as Map<String, dynamic>);
    } on ApiException catch (error) {
      throw WorkspaceBootstrapFailure(
        code: error.code,
        statusCode: error.statusCode,
      );
    }
  }

  @override
  Future<WorkspaceSummary> createWorkspace() async {
    try {
      final value = await _api.request(
        'POST',
        '/api/v1/workspaces',
        body: const <String, Object?>{},
        authenticated: true,
      );
      return WorkspaceSummary.fromJson(value as Map<String, dynamic>);
    } on ApiException catch (error) {
      throw WorkspaceBootstrapFailure(
        code: error.code,
        statusCode: error.statusCode,
      );
    }
  }
}
