import 'dart:async';
import 'dart:math';

import 'package:flutter/foundation.dart';

import '../models/workspace_change.dart';
import '../models/workspace_snapshot.dart';
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
  WorkspaceSyncController(this._repository, {this._cache});

  WorkspaceSyncController.unavailable() : _repository = null, _cache = null;

  final WorkspaceSyncRepository? _repository;
  final WorkspaceCache? _cache;
  WorkspaceSyncState state = const WorkspaceSyncState();
  final List<Object> inFlightMutations = [];
  StreamSubscription? _hintsSubscription;

  Future<bool> get canMutate async => _repository != null && !state.isStale;

  Future<void> start() async {
    if (_repository == null) return;
    await refresh();
    scheduleMicrotask(() {
      _hintsSubscription = _repository.openWorkspaceHints().listen((hint) {
        if (hint.cursor > state.cursor) pull();
      });
    });
  }

  Future<void> refresh() async {
    if (_repository == null) return;
    _setLoading();
    try {
      final snapshot = await _repository.snapshot();
      await _cache?.write(snapshot);
      state = WorkspaceSyncState(snapshot: snapshot, isStale: false);
    } catch (error) {
      state = state.copyWith(isStale: true, errorMessage: '$error');
    }
    notifyListeners();
  }

  Future<void> pull() async {
    final repository = _repository;
    final current = state.snapshot;
    if (repository == null || current == null) return;
    try {
      final result = await repository.changes(afterCursor: current.cursor);
      if (result.cursor <= current.cursor) return;
      if (result.changes.any((change) => change.cursor <= current.cursor) ||
          (result.changes.isNotEmpty &&
              result.changes.first.cursor != current.cursor + 1)) {
        await refresh();
        return;
      }
      final tasks = [...current.tasks];
      for (final change in result.changes) {
        _apply(tasks, change);
      }
      state = WorkspaceSyncState(
        snapshot: WorkspaceSnapshot(
          workspaceId: current.workspaceId,
          cursor: result.cursor,
          tasks: tasks,
          members: current.members,
          conflicts: current.conflicts,
          fetchedAt: DateTime.now(),
        ),
        isStale: false,
      );
      await _cache?.write(state.snapshot!);
      notifyListeners();
    } catch (error) {
      state = state.copyWith(isStale: true, errorMessage: '$error');
      notifyListeners();
    }
  }

  Future<void> transition(
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
    if (repository == null || task == null) return;
    try {
      final updated = await repository.transition(
        taskId,
        targetStatus: targetStatus,
        baseStatusVersion: task.statusVersion,
        blockedReason: blockedReason,
        resumeHandlerId: resumeHandlerId,
        waitingForUserId: waitingForUserId,
        requestId: _requestId(),
      );
      final current = state.snapshot;
      if (current != null) {
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
            fetchedAt: DateTime.now(),
          ),
          isStale: false,
        );
        notifyListeners();
      }
    } catch (error) {
      state = state.copyWith(
        isStale: error is! Exception || state.snapshot != null,
        errorMessage: '$error',
      );
      notifyListeners();
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

  static void _apply(List tasks, WorkspaceChange change) {
    if (change.resourceType != 'task' || change.task == null) return;
    final index = tasks.indexWhere((task) => task.id == change.resourceId);
    if (change.action == 'deleted') {
      if (index != -1) tasks[index] = change.task;
    } else if (index == -1) {
      tasks.add(change.task);
    } else {
      tasks[index] = change.task;
    }
  }
}
