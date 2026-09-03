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
  });

  final int cursor;
  final String resourceType;
  final String resourceId;
  final String action;
  final TaskItem? task;
  final Map<String, dynamic>? conflict;
  final TaskApprovalRequest? approvalRequest;
  final TaskComment? comment;

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
    final resourceType = json['resource_type'] as String;
    final resource = json['resource'];
    final resourceMap = resource is Map
        ? resource.cast<String, dynamic>()
        : null;
    return WorkspaceChange(
      cursor: json['cursor'] as int,
      resourceType: resourceType,
      resourceId: json['resource_id'] as String,
      action: (json['action'] as String).toLowerCase(),
      task: resourceType == 'task' && resourceMap != null
          ? TaskItem.fromJson(resourceMap)
          : null,
      conflict: resourceType == 'task_conflict' && resourceMap != null
          ? resourceMap
          : null,
      approvalRequest: resourceType == 'approval_request' && resourceMap != null
          ? TaskApprovalRequest.fromJson(resourceMap)
          : null,
      comment: resourceType == 'comment' && resourceMap != null
          ? TaskComment.fromJson(resourceMap)
          : null,
    );
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
      WorkspaceChanges(
        workspaceId: json['workspace_id'] as String,
        cursor: json['cursor'] as int,
        changes: (json['changes'] as List<dynamic>? ?? const [])
            .map(
              (item) => WorkspaceChange.fromJson(item as Map<String, dynamic>),
            )
            .toList(),
      );
}
