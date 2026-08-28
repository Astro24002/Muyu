import 'dart:async';
import 'dart:math';

import 'package:flutter/foundation.dart';

import 'workspace_bootstrap_repository.dart';

enum WorkspaceBootstrapStatus {
  loading,
  needsPartner,
  waitingForPartner,
  invited,
  ready,
  readOnlyDevice,
  bindingPartner,
  acceptingInvite,
  failure,

  // Compatibility states for callers that still use the old one-person flow.
  needsWorkspace,
  creatingWorkspace,
}

class WorkspaceBootstrapState {
  const WorkspaceBootstrapState({
    required this.status,
    WorkspaceSummary? workspace,
    this.payload,
    this.errorMessage,
  }) : _legacyWorkspace = workspace;

  final WorkspaceBootstrapStatus status;
  final WorkspaceBootstrapPayload? payload;
  final WorkspaceSummary? _legacyWorkspace;
  final String? errorMessage;

  WorkspaceSummary? get workspace => payload?.workspace ?? _legacyWorkspace;

  bool get canWrite => payload?.device.canWrite ?? false;

  bool get isReadOnlyDevice =>
      status == WorkspaceBootstrapStatus.readOnlyDevice;

  WorkspaceDeviceStatus? get deviceStatus => payload?.device.status;
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
      final payload = await _repository.loadBootstrap();
      if (_isObsolete(generation)) return;
      _publishPayload(payload);
    } on UnsupportedError {
      await _loadLegacy(generation);
    } on WorkspaceBootstrapFailure catch (error) {
      if (_isObsolete(generation)) return;
      _publish(
        WorkspaceBootstrapState(
          status: WorkspaceBootstrapStatus.failure,
          errorMessage: _message(error, '无法加载共享空间，请检查网络后重试'),
        ),
      );
    }
  }

  Future<void> bindPartner(String phone) async {
    if (state.status != WorkspaceBootstrapStatus.needsPartner) return;
    final generation = ++_generation;
    _publish(
      const WorkspaceBootstrapState(
        status: WorkspaceBootstrapStatus.bindingPartner,
      ),
    );
    try {
      // Normalizing here gives UI and fake repositories the same contract as
      // the HTTP repository. The repository repeats the check at the boundary.
      final normalized = normalizePhone(phone);
      final payload = await _repository.bindPartner(normalized, _requestId());
      if (_isObsolete(generation)) return;
      _publishPayload(payload);
    } on FormatException {
      if (_isObsolete(generation)) return;
      _publish(
        WorkspaceBootstrapState(
          status: WorkspaceBootstrapStatus.needsPartner,
          errorMessage: '请输入有效的手机号',
        ),
      );
    } on WorkspaceBootstrapFailure catch (error) {
      if (_isObsolete(generation)) return;
      _publish(
        WorkspaceBootstrapState(
          status: WorkspaceBootstrapStatus.needsPartner,
          errorMessage: _message(error, '绑定共同使用人失败，请稍后重试'),
        ),
      );
    }
  }

  Future<void> acceptInvite([String? inviteId]) async {
    if (state.status != WorkspaceBootstrapStatus.invited) return;
    final invite = state.payload?.invite;
    final id = inviteId ?? invite?.id;
    if (id == null || id.isEmpty) return;
    final generation = ++_generation;
    _publish(
      WorkspaceBootstrapState(
        status: WorkspaceBootstrapStatus.acceptingInvite,
        payload: state.payload,
      ),
    );
    try {
      final payload = await _repository.acceptInvite(id, _requestId());
      if (_isObsolete(generation)) return;
      _publishPayload(payload);
    } on WorkspaceBootstrapFailure catch (error) {
      if (_isObsolete(generation)) return;
      _publish(
        WorkspaceBootstrapState(
          status: WorkspaceBootstrapStatus.invited,
          payload: state.payload,
          errorMessage: _message(error, '接受邀请失败，请稍后重试'),
        ),
      );
    }
  }

  /// Compatibility action for old callers. Production Android UI exposes the
  /// partner binding form instead.
  Future<void> createWorkspace() async {
    if (state.status != WorkspaceBootstrapStatus.needsWorkspace) return;
    final legacy = _repository;
    if (legacy is! LegacyWorkspaceBootstrapRepository) return;
    final legacyRepository = legacy as LegacyWorkspaceBootstrapRepository;
    final generation = ++_generation;
    _publish(
      const WorkspaceBootstrapState(
        status: WorkspaceBootstrapStatus.creatingWorkspace,
      ),
    );
    try {
      final workspace = await legacyRepository.createWorkspace();
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
        WorkspaceBootstrapState(
          status: WorkspaceBootstrapStatus.needsWorkspace,
          errorMessage: _message(error, '创建共享空间失败，请稍后重试'),
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

  Future<void> _loadLegacy(int generation) async {
    final legacy = _repository;
    if (legacy is! LegacyWorkspaceBootstrapRepository) {
      if (_isObsolete(generation)) return;
      _publish(
        const WorkspaceBootstrapState(
          status: WorkspaceBootstrapStatus.failure,
          errorMessage: '无法加载共享空间，请检查网络后重试',
        ),
      );
      return;
    }
    final legacyRepository = legacy as LegacyWorkspaceBootstrapRepository;
    try {
      final workspace = await legacyRepository.currentWorkspace();
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
    } on WorkspaceBootstrapFailure catch (error) {
      if (_isObsolete(generation)) return;
      _publish(
        WorkspaceBootstrapState(
          status: WorkspaceBootstrapStatus.failure,
          errorMessage: _message(error, '无法加载共享空间，请检查网络后重试'),
        ),
      );
    }
  }

  void _publishPayload(WorkspaceBootstrapPayload payload) {
    final status = switch (payload.state) {
      WorkspaceBootstrapPhase.needsPartner =>
        WorkspaceBootstrapStatus.needsPartner,
      WorkspaceBootstrapPhase.waitingForPartner =>
        WorkspaceBootstrapStatus.waitingForPartner,
      WorkspaceBootstrapPhase.invited => WorkspaceBootstrapStatus.invited,
      WorkspaceBootstrapPhase.ready when payload.device.canWrite =>
        WorkspaceBootstrapStatus.ready,
      WorkspaceBootstrapPhase.ready => WorkspaceBootstrapStatus.readOnlyDevice,
    };
    _publish(WorkspaceBootstrapState(status: status, payload: payload));
  }

  bool _isObsolete(int generation) => _disposed || generation != _generation;

  void _publish(WorkspaceBootstrapState next) {
    if (_disposed) return;
    state = next;
    notifyListeners();
  }

  static String _message(WorkspaceBootstrapFailure error, String fallback) {
    if (error.message == '请求失败，请稍后重试') return fallback;
    return error.message;
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
}
