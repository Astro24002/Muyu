import 'task.dart';
import 'task_approval_request.dart';

class WorkspaceChange {
  const WorkspaceChange({
    required this.cursor,
    required this.resourceType,
    required this.resourceId,
    required this.action,
    this.task,
    this.conflict,
    this.approvalRequest,
    this.comment,
    this.operationId,
  });

  final int cursor;
  final String resourceType;
  final String resourceId;
  final String action;
  final TaskItem? task;
  final Map<String, dynamic>? conflict;
  final TaskApprovalRequest? approvalRequest;
  final TaskComment? comment;
  final String? operationId;

  factory WorkspaceChange.taskUpdated({
    required int cursor,
    required TaskItem task,
  }) => WorkspaceChange(
    cursor: cursor,
    resourceType: 'task',
    resourceId: task.id,
    action: 'updated',
    task: task,
  );

  factory WorkspaceChange.taskConflict({
    required int cursor,
    required Map<String, dynamic> conflict,
    String action = 'updated',
  }) => WorkspaceChange(
    cursor: cursor,
    resourceType: 'task_conflict',
    resourceId: conflict['id'] as String,
    action: action,
    conflict: conflict,
  );

  factory WorkspaceChange.approvalRequestUpdated({
    required int cursor,
    required TaskApprovalRequest approvalRequest,
    String action = 'updated',
  }) => WorkspaceChange(
    cursor: cursor,
    resourceType: 'approval_request',
    resourceId: approvalRequest.id,
    action: action,
    approvalRequest: approvalRequest,
  );

  factory WorkspaceChange.commentUpdated({
    required int cursor,
    required TaskComment comment,
    String action = 'updated',
  }) => WorkspaceChange(
    cursor: cursor,
    resourceType: 'comment',
    resourceId: comment.id,
    action: action,
    comment: comment,
  );

  factory WorkspaceChange.fromJson(Map<String, dynamic> json) {
    final rawCursor = json['cursor'];
    if (rawCursor is! int || rawCursor < 0) {
      throw const FormatException(
        'change cursor must be a non-negative integer',
      );
    }
    final resourceType = json['resource_type'];
    if (resourceType is! String || resourceType.isEmpty) {
      throw const FormatException('change resource_type is required');
    }
    final resourceId = json['resource_id'];
    if (resourceId is! String || resourceId.isEmpty) {
      throw const FormatException('change resource_id is required');
    }
    final rawAction = json['action'];
    if (rawAction is! String ||
        !WorkspaceChanges._actions.contains(rawAction.toUpperCase())) {
      throw const FormatException('change action is invalid');
    }
    final operationId = json['operation_id'];
    if (operationId != null && operationId is! String) {
      throw const FormatException(
        'change operation_id must be a string or null',
      );
    }
    final resource = json['resource'];
    Map<String, dynamic>? resourceMap;
    if (resource != null) {
      if (resource is! Map) {
        throw const FormatException(
          'change resource must be an object or null',
        );
      }
      try {
        resourceMap = Map<String, dynamic>.from(resource);
      } on TypeError {
        throw const FormatException('change resource keys must be strings');
      }
      if (resourceMap['id'] != null && resourceMap['id'] != resourceId) {
        throw const FormatException(
          'change resource id does not match resource_id',
        );
      }
    }
    try {
      return WorkspaceChange(
        cursor: rawCursor,
        resourceType: resourceType,
        resourceId: resourceId,
        action: rawAction.toLowerCase(),
        task: resourceType == 'task' && resourceMap != null
            ? TaskItem.fromJson(resourceMap)
            : null,
        conflict: resourceType == 'task_conflict' && resourceMap != null
            ? resourceMap
            : null,
        approvalRequest:
            resourceType == 'approval_request' && resourceMap != null
            ? TaskApprovalRequest.fromJson(resourceMap)
            : null,
        comment: resourceType == 'comment' && resourceMap != null
            ? TaskComment.fromJson(resourceMap)
            : null,
        operationId: operationId as String?,
      );
    } on TypeError catch (_) {
      throw const FormatException('change resource is invalid');
    }
  }
}

class WorkspaceChanged {
  const WorkspaceChanged({required this.workspaceId, required this.cursor});

  final String workspaceId;
  final int cursor;
}

class WorkspaceChanges {
  const WorkspaceChanges({
    required this.workspaceId,
    required this.cursor,
    required this.changes,
  });

  final String workspaceId;
  final int cursor;
  final List<WorkspaceChange> changes;

  factory WorkspaceChanges.fromJson(Map<String, dynamic> json) =>
      _fromJson(json);

  static WorkspaceChanges _fromJson(Map<String, dynamic> json) {
    final workspaceId = json['workspace_id'];
    final cursor = json['cursor'];
    final changes = json['changes'];
    if (workspaceId is! String || workspaceId.isEmpty) {
      throw const FormatException('changes workspace_id is required');
    }
    if (cursor is! int || cursor < 0) {
      throw const FormatException(
        'changes cursor must be a non-negative integer',
      );
    }
    if (changes is! List) {
      throw const FormatException('changes must be an array');
    }
    try {
      return WorkspaceChanges(
        workspaceId: workspaceId,
        cursor: cursor,
        changes: changes
            .map(
              (item) => WorkspaceChange.fromJson(
                Map<String, dynamic>.from(item as Map),
              ),
            )
            .toList(),
      );
    } on TypeError {
      throw const FormatException('change entries must be objects');
    }
  }

  bool isValidFor({required String workspaceId, required int afterCursor}) {
    if (this.workspaceId != workspaceId || afterCursor < 0 || cursor < 0) {
      return false;
    }
    if (changes.isEmpty) return cursor == afterCursor;
    for (var index = 0; index < changes.length; index++) {
      final change = changes[index];
      if (change.cursor != afterCursor + index + 1 ||
          !_belongsToWorkspace(change, workspaceId)) {
        return false;
      }
    }
    return cursor == changes.last.cursor;
  }

  static bool _belongsToWorkspace(WorkspaceChange change, String workspaceId) {
    if (!_actions.contains(change.action.toUpperCase())) return false;
    if (change.resourceType == 'task' && change.task != null) {
      final resourceWorkspaceId = change.task!.workspaceId;
      if (resourceWorkspaceId != null && resourceWorkspaceId != workspaceId) {
        return false;
      }
    }
    if (change.resourceType == 'task_conflict' && change.conflict != null) {
      final resourceWorkspaceId = change.conflict!['workspace_id'];
      if (change.conflict!.containsKey('workspace_id') &&
          resourceWorkspaceId != workspaceId) {
        return false;
      }
      final conflictId = change.conflict!['id'];
      final taskId = change.conflict!['task_id'];
      final field = change.conflict!['field'];
      final status = change.conflict!['status'] ?? change.conflict!['state'];
      if (conflictId is! String || conflictId.isEmpty ||
          conflictId != change.resourceId ||
          taskId is! String || taskId.isEmpty ||
          field is! String || field.isEmpty ||
          status is! String) {
        return false;
      }
      final currentSnapshot = change.conflict!['current_snapshot'];
      if (currentSnapshot != null) {
        if (currentSnapshot is! Map ||
            (currentSnapshot.containsKey('workspace_id') &&
                currentSnapshot['workspace_id'] != workspaceId) ||
            (currentSnapshot['id'] != null &&
                currentSnapshot['id'] != taskId)) {
          return false;
        }
      }
    }
    if (change.resourceType == 'approval_request' &&
        change.approvalRequest != null &&
        change.approvalRequest!.workspaceId != workspaceId) {
      return false;
    }
    return true;
  }

  static const _actions = {'CREATED', 'UPDATED', 'DELETED', 'RESTORED'};
}
