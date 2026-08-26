import 'package:flutter/foundation.dart';

import 'workspace_bootstrap_repository.dart';

enum WorkspaceBootstrapStatus {
  loading,
  needsWorkspace,
  creatingWorkspace,
  ready,
  failure,
}

class WorkspaceBootstrapState {
  const WorkspaceBootstrapState({
    required this.status,
    this.workspace,
    this.errorMessage,
  });

  final WorkspaceBootstrapStatus status;
  final WorkspaceSummary? workspace;
  final String? errorMessage;
}

class WorkspaceBootstrapController extends ChangeNotifier {
  WorkspaceBootstrapController(this._repository);

  final WorkspaceBootstrapRepository _repository;
  WorkspaceBootstrapState state = const WorkspaceBootstrapState(
    status: WorkspaceBootstrapStatus.loading,
  );
  int _generation = 0;
  bool _disposed = false;

  Future<void> load() async {
    final generation = ++_generation;
    _publish(
      const WorkspaceBootstrapState(status: WorkspaceBootstrapStatus.loading),
    );
    try {
      final workspace = await _repository.currentWorkspace();
      if (_isObsolete(generation)) return;
      if (workspace == null) {
        _publish(
          const WorkspaceBootstrapState(
            status: WorkspaceBootstrapStatus.needsWorkspace,
          ),
        );
      } else {
        _publish(
          WorkspaceBootstrapState(
            status: WorkspaceBootstrapStatus.ready,
            workspace: workspace,
          ),
        );
      }
    } on WorkspaceBootstrapFailure {
      if (_isObsolete(generation)) return;
      _publish(
        const WorkspaceBootstrapState(
          status: WorkspaceBootstrapStatus.failure,
          errorMessage: '无法加载共享空间，请检查网络后重试',
        ),
      );
    }
  }

  Future<void> createWorkspace() async {
    if (state.status != WorkspaceBootstrapStatus.needsWorkspace) return;
    final generation = ++_generation;
    _publish(
      const WorkspaceBootstrapState(
        status: WorkspaceBootstrapStatus.creatingWorkspace,
      ),
    );
    try {
      final workspace = await _repository.createWorkspace();
      if (_isObsolete(generation)) return;
      _publish(
        WorkspaceBootstrapState(
          status: WorkspaceBootstrapStatus.ready,
          workspace: workspace,
        ),
      );
    } on WorkspaceBootstrapFailure catch (error) {
      if (_isObsolete(generation)) return;
      if (error.code == 'workspace_limit_reached') {
        await load();
        return;
      }
      _publish(
        const WorkspaceBootstrapState(
          status: WorkspaceBootstrapStatus.needsWorkspace,
          errorMessage: '创建共享空间失败，请稍后重试',
        ),
      );
    }
  }

  @override
  void dispose() {
    _generation++;
    _disposed = true;
    super.dispose();
  }

  bool _isObsolete(int generation) => _disposed || generation != _generation;

  void _publish(WorkspaceBootstrapState next) {
    if (_disposed) return;
    state = next;
    notifyListeners();
  }
}
