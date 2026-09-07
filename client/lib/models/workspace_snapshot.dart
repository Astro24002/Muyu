import 'classification.dart';
import 'task.dart';
import 'task_approval_request.dart';

class WorkspaceSnapshot {
  const WorkspaceSnapshot({
    required this.workspaceId,
    required this.cursor,
    required this.tasks,
    this.viewerUserId,
    this.members = const [],
    this.conflicts = const [],
    this.comments = const [],
    this.approvalRequests = const [],
    this.classifications = const [],
    this.hasClassificationContract = false,
    this.fetchedAt,
  });

  final String workspaceId;
  final int cursor;
  final List<TaskItem> tasks;
  final String? viewerUserId;
  final List<Map<String, dynamic>> members;
  final List<Map<String, dynamic>> conflicts;
  final List<TaskComment> comments;
  final List<TaskApprovalRequest> approvalRequests;
  final List<WorkspaceClassification> classifications;

  /// Whether the source explicitly provided the classifications resource.
  ///
  /// Older cached snapshots predate classifications altogether. They remain
  /// readable until the next authoritative refresh, while every current API
  /// snapshot must prove non-empty task classifications are approved.
  final bool hasClassificationContract;
  final DateTime? fetchedAt;

  factory WorkspaceSnapshot.fromJson(Map<String, dynamic> json) {
    final snapshot = WorkspaceSnapshot(
      workspaceId: json['workspace_id'] as String,
      cursor: json['cursor'] as int,
      viewerUserId: json['viewer_user_id'] as String?,
      tasks: (json['tasks'] as List<dynamic>? ?? const [])
          .map((item) => TaskItem.fromJson(item as Map<String, dynamic>))
          .toList(),
      members: (json['members'] as List<dynamic>? ?? const [])
          .cast<Map<String, dynamic>>(),
      conflicts: (json['conflicts'] as List<dynamic>? ?? const [])
          .cast<Map<String, dynamic>>(),
      comments: (json['comments'] as List<dynamic>? ?? const [])
          .map((item) => TaskComment.fromJson(item as Map<String, dynamic>))
          .toList(),
      approvalRequests:
          (json['approval_requests'] as List<dynamic>? ?? const [])
              .map(
                (item) =>
                    TaskApprovalRequest.fromJson(item as Map<String, dynamic>),
              )
              .toList(),
      classifications: (json['classifications'] as List<dynamic>? ?? const [])
          .map(
            (item) =>
                WorkspaceClassification.fromJson(item as Map<String, dynamic>),
          )
          .toList(),
      hasClassificationContract: json.containsKey('classifications'),
      fetchedAt: json['fetched_at'] == null
          ? null
          : DateTime.parse(json['fetched_at'] as String),
    );
    if (!snapshot.isValidForWorkspace()) {
      throw const FormatException('workspace snapshot contains foreign data');
    }
    return snapshot;
  }

  bool isValidForWorkspace() {
    if (workspaceId.isEmpty || cursor < 0) return false;
    if (tasks.any(
      (task) => task.workspaceId != null && task.workspaceId != workspaceId,
    )) {
      return false;
    }
    if (comments.any((comment) => comment.workspaceId != workspaceId)) {
      return false;
    }
    if (conflicts.any((conflict) {
      final conflictWorkspaceId = conflict['workspace_id'];
      if (conflict.containsKey('workspace_id') &&
          conflictWorkspaceId != workspaceId) {
        return true;
      }
      final currentSnapshot = conflict['current_snapshot'];
      if (currentSnapshot == null) return false;
      if (currentSnapshot is! Map) return true;
      if (currentSnapshot.containsKey('workspace_id') &&
          currentSnapshot['workspace_id'] != workspaceId) {
        return true;
      }
      final taskId = conflict['task_id'];
      return currentSnapshot.containsKey('id') &&
          currentSnapshot['id'] != taskId;
    })) {
      return false;
    }
    if (!approvalRequests.every(
          (request) => request.workspaceId == workspaceId,
        ) ||
        !classifications.every(
          (classification) => classification.workspaceId == workspaceId,
        )) {
      return false;
    }
    if (!hasClassificationContract) return true;

    final approvedNames = <String>{};
    for (final classification in classifications) {
      final normalized = classification.name.trim().toLowerCase();
      if (!approvedNames.add(normalized)) return false;
    }
    return tasks.every((task) {
      if (task.labels.isEmpty) return true;
      return task.labels.length == 1 &&
          approvedNames.contains(task.labels.single.trim().toLowerCase());
    });
  }

  Map<String, Object?> toJson() => {
    'workspace_id': workspaceId,
    'cursor': cursor,
    'viewer_user_id': viewerUserId,
    'tasks': tasks.map(_taskJson).toList(),
    'members': members,
    'conflicts': conflicts,
    'comments': comments.map((comment) => comment.toJson()).toList(),
    'approval_requests': approvalRequests
        .map((request) => request.toJson())
        .toList(),
    if (hasClassificationContract)
      'classifications': classifications
          .map((classification) => classification.toJson())
          .toList(),
    'fetched_at': fetchedAt?.toUtc().toIso8601String(),
  };

  static Map<String, Object?> _taskJson(TaskItem task) => task.toJson();
}
