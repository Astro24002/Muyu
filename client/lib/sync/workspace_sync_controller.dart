// ignore_for_file: prefer_initializing_formals

import 'dart:async';
import 'dart:math';

import 'package:flutter/foundation.dart';

import '../core/api_client.dart';
import '../models/workspace_change.dart';
import '../models/workspace_snapshot.dart';
import '../models/task.dart';
import '../models/task_approval_request.dart';
import 'workspace_cache.dart';
import 'workspace_sync_repository.dart';

class WorkspaceSyncState {
  const WorkspaceSyncState({
    this.snapshot,
    this.isStale = true,
    this.loading = false,
    this.errorMessage,
  });

  final WorkspaceSnapshot? snapshot;
  final bool isStale;
  final bool loading;
  final String? errorMessage;

  int get cursor => snapshot?.cursor ?? 0;

  List<TaskApprovalRequest> get approvalRequests =>
      snapshot?.approvalRequests ?? const <TaskApprovalRequest>[];

  List<TaskComment> get comments => snapshot?.comments ?? const <TaskComment>[];

  WorkspaceSyncState copyWith({
    WorkspaceSnapshot? snapshot,
    bool? isStale,
    bool? loading,
    String? errorMessage,
  }) => WorkspaceSyncState(
    snapshot: snapshot ?? this.snapshot,
    isStale: isStale ?? this.isStale,
    loading: loading ?? this.loading,
    errorMessage: errorMessage,
  );
}

class WorkspaceSyncController extends ChangeNotifier {
  // Keep public constructor aliases while retaining private controller state.
  WorkspaceSyncController(
    this._repository, {
    WorkspaceCache? cache,
    String? workspaceId,
  }) : _cache = cache,
       _workspaceId = workspaceId;

  WorkspaceSyncController.unavailable()
    : _repository = null,
      _cache = null,
      _workspaceId = null;

  final WorkspaceSyncRepository? _repository;
  final WorkspaceCache? _cache;
  final String? _workspaceId;
  WorkspaceSyncState state = const WorkspaceSyncState();
  final List<Object> inFlightMutations = [];
  StreamSubscription? _hintsSubscription;
  Future<void>? _refreshInFlight;
  Future<void>? _pullInFlight;

  Future<bool> get canMutate async => _repository != null && !state.isStale;

  Future<void> start() async {
    if (_repository == null) return;
    await _restoreCachedSnapshot();
    await refresh();
    scheduleMicrotask(() {
      _hintsSubscription = _repository.openWorkspaceHints().listen((hint) {
        if (hint.cursor > state.cursor) pull();
      });
    });
  }

  Future<void> refresh() {
    final existing = _refreshInFlight;
    if (existing != null) return existing;
    final operation = _refreshSnapshot();
    _refreshInFlight = operation;
    operation.whenComplete(() {
      if (identical(_refreshInFlight, operation)) _refreshInFlight = null;
    });
    return operation;
  }

  Future<void> _refreshSnapshot() async {
    if (_repository == null) return;
    _setLoading();
    try {
      final snapshot = await _repository.snapshot();
      if (!snapshot.isValidForWorkspace()) {
        throw const FormatException('workspace snapshot contains foreign data');
      }
      state = WorkspaceSyncState(snapshot: snapshot, isStale: false);
      await _writeCache(snapshot);
    } catch (error) {
      state = state.copyWith(isStale: true, errorMessage: '$error');
    }
    notifyListeners();
  }

  Future<void> pull() {
    final existing = _pullInFlight;
    if (existing != null) return existing;
    final operation = _pullChanges();
    _pullInFlight = operation;
    operation.whenComplete(() {
      if (identical(_pullInFlight, operation)) _pullInFlight = null;
    });
    return operation;
  }

  Future<void> _pullChanges() async {
    final repository = _repository;
    final current = state.snapshot;
    if (repository == null || current == null) return;
    try {
      final result = await repository.changes(afterCursor: current.cursor);
      if (!result.isValidFor(
        workspaceId: current.workspaceId,
        afterCursor: current.cursor,
      )) {
        await refresh();
        return;
      }
      if (result.changes.isEmpty) return;
      final tasks = [...current.tasks];
      final conflicts = current.conflicts
          .map((item) => Map<String, dynamic>.from(item))
          .toList();
      final approvals = [...current.approvalRequests];
      final comments = [...current.comments];
      for (final change in result.changes) {
        _applyTask(tasks, change, current.workspaceId);
        _applyConflict(conflicts, change, current.workspaceId);
        _applyApproval(approvals, change, current.workspaceId);
        _applyComment(comments, change);
      }
      state = WorkspaceSyncState(
        snapshot: WorkspaceSnapshot(
          workspaceId: current.workspaceId,
          cursor: result.cursor,
          tasks: tasks,
          members: current.members,
          conflicts: conflicts,
          viewerUserId: current.viewerUserId,
          comments: comments,
          approvalRequests: approvals,
          fetchedAt: DateTime.now(),
        ),
        isStale: false,
      );
      await _writeCache(state.snapshot!);
      notifyListeners();
    } catch (error) {
      if (error is FormatException || error is TypeError) {
        await refresh();
        return;
      }
      state = state.copyWith(isStale: true, errorMessage: '$error');
      notifyListeners();
    }
  }

  Future<TaskMutationResult?> transition(
    String taskId,
    String targetStatus, {
    String? blockedReason,
    String? resumeHandlerId,
    String? waitingForUserId,
  }) async {
    final repository = _repository;
    final matches =
        state.snapshot?.tasks.where((item) => item.id == taskId).toList() ??
        const [];
    final task = matches.isEmpty ? null : matches.first;
    if (repository == null || task == null) return null;
    try {
      final result = await repository.transition(
        taskId,
        targetStatus: targetStatus,
        baseStatusVersion: task.statusVersion,
        blockedReason: blockedReason,
        resumeHandlerId: resumeHandlerId,
        waitingForUserId: waitingForUserId,
        requestId: _requestId(),
      );
      if (result is TaskItem) {
        _replaceTask(result);
        // The write response carries no cursor; reconcile through the
        // authoritative cursor endpoint before accepting another mutation.
        await pull();
      } else if (result is PendingApproval) {
        _mergeApproval(result.approvalRequest);
      }
      return result;
    } catch (error) {
      final isFieldConflict =
          error is ApiException &&
          error.statusCode == 409 &&
          error.code == 'field_conflict';
      if (await _mergeApiConflict(error)) return null;
      state = state.copyWith(
        isStale: isFieldConflict ? state.isStale : state.snapshot != null,
        errorMessage: '$error',
      );
      notifyListeners();
      return null;
    }
  }

  Future<TaskItem?> create(
    String title, {
    required String quadrant,
    List<String> labels = const [],
    String? description,
    String? dueAt,
    String? parentTaskId,
    String? plannedStartAt,
    int? estimatedMinutes,
  }) async {
    final repository = _repository;
    if (repository == null || state.snapshot == null || state.isStale) {
      return null;
    }
    try {
      final created = await repository.create(
        title: title,
        quadrant: quadrant,
        labels: labels,
        description: description,
        dueAt: dueAt,
        parentTaskId: parentTaskId,
        plannedStartAt: plannedStartAt,
        estimatedMinutes: estimatedMinutes,
        requestId: _requestId(),
      );
      _replaceTask(created);
      await pull();
      return created;
    } catch (error) {
      if (await _mergeApiConflict(error)) return null;
      _setError(error);
      rethrow;
    }
  }

  Future<TaskMutationResult?> update(
    String taskId, {
    required Map<String, Object?> fields,
  }) async {
    final repository = _repository;
    final task = _task(taskId);
    if (repository == null || task == null || state.isStale) return null;
    try {
      final result = await repository.update(
        taskId,
        fields: fields,
        fieldVersions: {
          for (final field in fields.keys)
            field: task.fieldVersions[field] ?? 1,
        },
        requestId: _requestId(),
      );
      if (result is TaskItem) {
        _replaceTask(result);
        await pull();
      } else if (result is PendingApproval) {
        _mergeApproval(result.approvalRequest);
      }
      return result;
    } catch (error) {
      if (await _mergeApiConflict(error)) return null;
      _setError(error);
      rethrow;
    }
  }

  Future<TaskApprovalRequest?> createApprovalRequest(
    String taskId, {
    String? commentId,
    required String requestType,
    required Map<String, Object?> proposedChanges,
    required Map<String, int> baseFieldVersions,
  }) async {
    final repository = _repository;
    final snapshot = state.snapshot;
    if (repository == null || snapshot == null || state.isStale) return null;
    try {
      final approval = await repository.createApprovalRequest(
        workspaceId: snapshot.workspaceId,
        taskId: taskId,
        commentId: commentId,
        requestType: requestType,
        proposedChanges: proposedChanges,
        baseFieldVersions: baseFieldVersions,
        requestId: _requestId(),
      );
      _mergeApproval(approval);
      return approval;
    } catch (error) {
      if (await _mergeApiConflict(error)) return null;
      _setError(error);
      rethrow;
    }
  }

  Future<List<TaskApprovalRequest>> listApprovalRequests({String? box}) async {
    final repository = _repository;
    final snapshot = state.snapshot;
    if (repository == null || snapshot == null) return const [];
    try {
      final approvals = await repository.listApprovalRequests(
        workspaceId: snapshot.workspaceId,
        box: box,
      );
      _mergeApprovals(approvals);
      return approvals;
    } catch (error) {
      _setError(error);
      rethrow;
    }
  }

  Future<ApprovalActionResult> approveApproval(String approvalId) async {
    final repository = _repository;
    final snapshot = state.snapshot;
    if (repository == null || snapshot == null || state.isStale) {
      throw StateError('workspace sync is unavailable');
    }
    try {
      final result = await repository.approveApproval(
        approvalId,
        workspaceId: snapshot.workspaceId,
        requestId: _requestId(),
      );
      await _refreshAfterAction(result.cursor);
      _mergeApprovalResult(result);
      return result;
    } catch (error) {
      _setError(error);
      rethrow;
    }
  }

  Future<ApprovalActionResult> rejectApproval(
    String approvalId, {
    String? reason,
  }) async {
    final repository = _repository;
    final snapshot = state.snapshot;
    if (repository == null || snapshot == null || state.isStale) {
      throw StateError('workspace sync is unavailable');
    }
    try {
      final result = await repository.rejectApproval(
        approvalId,
        workspaceId: snapshot.workspaceId,
        requestId: _requestId(),
        reason: reason,
      );
      await _refreshAfterAction(result.cursor);
      _mergeApprovalResult(result);
      return result;
    } catch (error) {
      _setError(error);
      rethrow;
    }
  }

  Future<ApprovalActionResult> cancelApproval(String approvalId) async {
    final repository = _repository;
    final snapshot = state.snapshot;
    if (repository == null || snapshot == null || state.isStale) {
      throw StateError('workspace sync is unavailable');
    }
    try {
      final result = await repository.cancelApproval(
        approvalId,
        workspaceId: snapshot.workspaceId,
        requestId: _requestId(),
      );
      await _refreshAfterAction(result.cursor);
      _mergeApprovalResult(result);
      return result;
    } catch (error) {
      _setError(error);
      rethrow;
    }
  }

  Future<TaskMutationResult?> deleteComment(
    String taskId,
    String commentId, {
    required int baseVersion,
  }) async {
    final repository = _repository;
    if (repository == null || state.snapshot == null || state.isStale) {
      return null;
    }
    try {
      final result = await repository.deleteComment(
        taskId,
        commentId,
        baseVersion: baseVersion,
        requestId: _requestId(),
      );
      if (result is PendingApproval) {
        _mergeApproval(result.approvalRequest);
      } else if (result is TaskComment) {
        _mergeComment(result);
      }
      return result;
    } catch (error) {
      _setError(error);
      rethrow;
    }
  }

  Future<void> addComment(String taskId, String body) async {
    final repository = _repository;
    if (repository == null || _task(taskId) == null || state.isStale) return;
    try {
      await repository.addComment(taskId, body: body, requestId: _requestId());
      await pull();
    } catch (error) {
      _setError(error);
      rethrow;
    }
  }

  Future<void> addDelay(
    String taskId, {
    required String newDueAt,
    required String reason,
    String? note,
  }) async {
    final repository = _repository;
    if (repository == null || _task(taskId) == null || state.isStale) return;
    try {
      await repository.addDelay(
        taskId,
        newDueAt: newDueAt,
        reason: reason,
        note: note,
        requestId: _requestId(),
      );
      await pull();
    } catch (error) {
      _setError(error);
      rethrow;
    }
  }

  Future<TaskItem?> resolveConflict(
    String taskId,
    String conflictId, {
    required String resolution,
  }) async {
    final repository = _repository;
    if (repository == null || _task(taskId) == null || state.isStale) {
      return null;
    }
    try {
      final updated = await repository.resolveConflict(
        taskId,
        conflictId,
        resolution: resolution,
        requestId: _requestId(),
      );
      _replaceTask(updated);
      await pull();
      return updated;
    } catch (error) {
      if (await _mergeApiConflict(error)) return null;
      _setError(error);
      rethrow;
    }
  }

  @override
  void dispose() {
    _hintsSubscription?.cancel();
    super.dispose();
  }

  void _setLoading() {
    state = state.copyWith(loading: true, errorMessage: null);
    notifyListeners();
  }

  TaskItem? _task(String taskId) {
    for (final item in state.snapshot?.tasks ?? const <TaskItem>[]) {
      if (item.id == taskId) return item;
    }
    return null;
  }

  void _replaceTask(TaskItem updated) {
    final current = state.snapshot;
    if (current == null) return;
    if (updated.workspaceId != null &&
        updated.workspaceId != current.workspaceId) {
      return;
    }
    final tasks = [...current.tasks]
      ..removeWhere((item) => item.id == updated.id)
      ..add(updated);
    state = WorkspaceSyncState(
      snapshot: WorkspaceSnapshot(
        workspaceId: current.workspaceId,
        cursor: current.cursor,
        tasks: tasks,
        members: current.members,
        conflicts: current.conflicts,
        viewerUserId: current.viewerUserId,
        comments: current.comments,
        approvalRequests: current.approvalRequests,
        fetchedAt: DateTime.now(),
      ),
      isStale: false,
    );
    notifyListeners();
  }

  void _mergeApproval(TaskApprovalRequest approval) {
    final current = state.snapshot;
    if (current == null) return;
    final approvals = [...current.approvalRequests]
      ..removeWhere((item) => item.id == approval.id)
      ..add(approval);
    _setResources(current, approvalRequests: approvals, notify: true);
  }

  void _mergeApprovals(List<TaskApprovalRequest> approvals) {
    final current = state.snapshot;
    if (current == null) return;
    final merged = [...current.approvalRequests];
    for (final approval in approvals) {
      merged
        ..removeWhere((item) => item.id == approval.id)
        ..add(approval);
    }
    _setResources(current, approvalRequests: merged, notify: true);
  }

  void _mergeComment(TaskComment comment) {
    final current = state.snapshot;
    if (current == null) return;
    final comments = [...current.comments]
      ..removeWhere((item) => item.id == comment.id)
      ..add(comment);
    _setResources(current, comments: comments, notify: true);
  }

  void _mergeApprovalResult(ApprovalActionResult result) {
    final current = state.snapshot;
    if (current == null) return;
    final approvals = [...current.approvalRequests]
      ..removeWhere((item) => item.id == result.approvalRequest.id)
      ..add(result.approvalRequest);
    final tasks = [...current.tasks];
    if (result.task != null) {
      tasks
        ..removeWhere((item) => item.id == result.task!.id)
        ..add(result.task!);
    }
    final comments = [...current.comments];
    if (result.comment != null) {
      comments
        ..removeWhere((item) => item.id == result.comment!.id)
        ..add(result.comment!);
    }
    _setResources(
      current,
      tasks: tasks,
      comments: comments,
      approvalRequests: approvals,
      cursor: result.cursor == null
          ? null
          : result.cursor! > current.cursor
          ? result.cursor
          : current.cursor,
      notify: true,
    );
  }

  Future<void> _refreshAfterAction(int? cursor) async {
    if (cursor == null || cursor <= state.cursor) return;
    // Pull the authoritative resources before applying the response fallback.
    // This also keeps the local cache aligned with the server cursor.
    await pull();
  }

  void _setResources(
    WorkspaceSnapshot current, {
    List<TaskItem>? tasks,
    List<TaskComment>? comments,
    List<TaskApprovalRequest>? approvalRequests,
    int? cursor,
    required bool notify,
  }) {
    state = WorkspaceSyncState(
      snapshot: WorkspaceSnapshot(
        workspaceId: current.workspaceId,
        cursor: cursor ?? current.cursor,
        tasks: tasks ?? current.tasks,
        members: current.members,
        conflicts: current.conflicts,
        viewerUserId: current.viewerUserId,
        comments: comments ?? current.comments,
        approvalRequests: approvalRequests ?? current.approvalRequests,
        fetchedAt: DateTime.now(),
      ),
      isStale: false,
    );
    if (notify) notifyListeners();
  }

  void _setError(Object error) {
    state = state.copyWith(errorMessage: '$error');
    notifyListeners();
  }

  Future<bool> _mergeApiConflict(Object error) async {
    if (error is! ApiException ||
        error.statusCode != 409 ||
        error.code != 'field_conflict') {
      return false;
    }
    final current = state.snapshot;
    final details = error.details;
    if (current == null || details is! Map) {
      await refresh();
      return false;
    }
    final targetCursor = details['cursor'];
    if (targetCursor is! int || targetCursor < 0) {
      await refresh();
      return false;
    }
    final rawConflicts = details['conflicts'];
    if (rawConflicts is! List || rawConflicts.isEmpty) {
      await refresh();
      return false;
    }

    final conflicts = current.conflicts
        .map((item) => Map<String, dynamic>.from(item))
        .toList();
    final tasks = [...current.tasks];
    final parsed = <Map<String, dynamic>>[];
    try {
      for (final raw in rawConflicts) {
        if (raw is! Map) {
          await refresh();
          return false;
        }
        final conflict = Map<String, dynamic>.from(raw);
        final workspaceId = conflict['workspace_id'];
        if (conflict.containsKey('workspace_id') &&
            workspaceId != current.workspaceId) {
          await refresh();
          return false;
        }
        final conflictId = conflict['id'];
        final taskId = conflict['task_id'];
        final field = conflict['field'];
        final status = conflict['status'];
        if (conflictId is! String ||
            conflictId.isEmpty ||
            taskId is! String ||
            taskId.isEmpty ||
            field is! String ||
            field.isEmpty ||
            conflict['workspace_id'] != current.workspaceId ||
            status != 'OPEN') {
          await refresh();
          return false;
        }
        final currentSnapshot = conflict['current_snapshot'];
        if (currentSnapshot is! Map ||
            currentSnapshot['workspace_id'] != current.workspaceId ||
            !_isCanonicalTaskStatus(currentSnapshot['status'])) {
          await refresh();
          return false;
        }
        try {
          final task = TaskItem.fromJson(
            Map<String, dynamic>.from(currentSnapshot),
          );
          if (task.workspaceId != current.workspaceId || task.id != taskId) {
            await refresh();
            return false;
          }
          final index = tasks.indexWhere((item) => item.id == task.id);
          if (index == -1) {
            tasks.add(task);
          } else {
            tasks[index] = task;
          }
        } catch (_) {
          await refresh();
          return false;
        }
        parsed.add(conflict);
      }
    } catch (_) {
      await refresh();
      return false;
    }

    for (final conflict in parsed) {
      final id = conflict['id'];
      conflicts.removeWhere((item) => item['id'] == id);
      if (conflict['status'] == 'OPEN') conflicts.add(conflict);
    }
    final next = WorkspaceSnapshot(
      workspaceId: current.workspaceId,
      cursor: current.cursor,
      tasks: tasks,
      members: current.members,
      conflicts: conflicts,
      viewerUserId: current.viewerUserId,
      comments: current.comments,
      approvalRequests: current.approvalRequests,
      fetchedAt: DateTime.now(),
    );
    state = WorkspaceSyncState(snapshot: next, isStale: false);
    await _writeCache(next);
    notifyListeners();

    if (targetCursor > current.cursor) {
      await _reconcileConflictCursor(targetCursor);
    }
    return true;
  }

  Future<void> _reconcileConflictCursor(int targetCursor) async {
    while (state.snapshot != null && state.cursor < targetCursor) {
      final before = state.cursor;
      await pull();
      if (state.snapshot == null || state.cursor <= before) {
        await refresh();
        return;
      }
    }
  }

  Future<void> _restoreCachedSnapshot() async {
    final cache = _cache;
    final workspaceId = _workspaceId;
    if (cache == null || workspaceId == null || workspaceId.isEmpty) return;
    try {
      final snapshot = await cache.read(workspaceId);
      if (snapshot == null || snapshot.workspaceId != workspaceId) return;
      state = WorkspaceSyncState(snapshot: snapshot, isStale: true);
      notifyListeners();
    } catch (_) {
      // A cache is an optimization; network sync remains authoritative.
    }
  }

  Future<void> _writeCache(WorkspaceSnapshot snapshot) async {
    try {
      await _cache?.write(snapshot);
    } catch (_) {
      // A persistence failure must not discard a fresh network snapshot.
    }
  }

  static String _requestId() {
    final random = Random.secure();
    final bytes = List<int>.generate(16, (_) => random.nextInt(256));
    bytes[6] = (bytes[6] & 0x0f) | 0x40;
    bytes[8] = (bytes[8] & 0x3f) | 0x80;
    final hex = bytes
        .map((value) => value.toRadixString(16).padLeft(2, '0'))
        .join();
    return '${hex.substring(0, 8)}-${hex.substring(8, 12)}-${hex.substring(12, 16)}-${hex.substring(16, 20)}-${hex.substring(20)}';
  }

  static void _applyTask(
    List<TaskItem> tasks,
    WorkspaceChange change,
    String workspaceId,
  ) {
    final task = change.task;
    if (change.resourceType != 'task' || task == null) return;
    if (task.workspaceId != workspaceId) return;
    final index = tasks.indexWhere((item) => item.id == change.resourceId);
    if (change.action == 'deleted') {
      if (index != -1) tasks[index] = task;
    } else if (index == -1) {
      tasks.add(task);
    } else {
      tasks[index] = task;
    }
  }

  static bool _isCanonicalTaskStatus(Object? value) =>
      value == 'TODO' ||
      value == 'IN_PROGRESS' ||
      value == 'BLOCKED' ||
      value == 'REVIEW' ||
      value == 'DONE' ||
      value == 'CANCELLED';

  static void _applyConflict(
    List<Map<String, dynamic>> conflicts,
    WorkspaceChange change,
    String workspaceId,
  ) {
    if (change.resourceType != 'task_conflict') return;
    final conflict = change.conflict;
    if (conflict != null) {
      final conflictWorkspaceId = conflict['workspace_id'];
      if (conflict.containsKey('workspace_id') &&
          conflictWorkspaceId != workspaceId) {
        return;
      }
      final currentSnapshot = conflict['current_snapshot'];
      if (currentSnapshot is Map &&
          currentSnapshot.containsKey('workspace_id') &&
          currentSnapshot['workspace_id'] != workspaceId) {
        return;
      }
      if (conflict['id'] != null && conflict['id'] != change.resourceId) {
        return;
      }
    }
    conflicts.removeWhere((item) => item['id'] == change.resourceId);
    final action = change.action.toUpperCase();
    if (action == 'DELETED') return;
    if (conflict == null) return;
    final status = conflict['status'] ?? conflict['state'];
    if (status == null || status == 'OPEN') {
      conflicts.add(Map<String, dynamic>.from(conflict));
    }
  }

  static void _applyApproval(
    List<TaskApprovalRequest> approvals,
    WorkspaceChange change,
    String workspaceId,
  ) {
    if (change.resourceType != 'approval_request' ||
        change.approvalRequest == null) {
      return;
    }
    if (change.approvalRequest!.workspaceId != workspaceId) return;
    final index = approvals.indexWhere((item) => item.id == change.resourceId);
    if (change.action == 'deleted') {
      if (index != -1) approvals.removeAt(index);
    } else if (index == -1) {
      approvals.add(change.approvalRequest!);
    } else {
      approvals[index] = change.approvalRequest!;
    }
  }

  static void _applyComment(
    List<TaskComment> comments,
    WorkspaceChange change,
  ) {
    if (change.resourceType != 'comment' || change.comment == null) return;
    final index = comments.indexWhere((item) => item.id == change.resourceId);
    if (change.action == 'deleted') {
      if (index != -1) comments[index] = change.comment!;
    } else if (index == -1) {
      comments.add(change.comment!);
    } else {
      comments[index] = change.comment!;
    }
  }
}
