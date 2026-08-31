import '../core/api_client.dart';

/// The server-derived state of the two-person workspace onboarding flow.
enum WorkspaceBootstrapPhase { needsPartner, waitingForPartner, invited, ready }

enum WorkspaceDeviceStatus { unverified, verified, revoked }

enum WorkspaceMatchStatus { waitingPartner, matched, error }

WorkspaceBootstrapPhase _phaseFromJson(Object? value) => switch (value) {
  'NEEDS_PARTNER' => WorkspaceBootstrapPhase.needsPartner,
  'WAITING_FOR_PARTNER' => WorkspaceBootstrapPhase.waitingForPartner,
  'INVITED' => WorkspaceBootstrapPhase.invited,
  'READY' => WorkspaceBootstrapPhase.ready,
  _ => throw const FormatException('unknown workspace bootstrap state'),
};

WorkspaceDeviceStatus _deviceStatusFromJson(Object? value) => switch (value) {
  'UNVERIFIED' => WorkspaceDeviceStatus.unverified,
  'VERIFIED' => WorkspaceDeviceStatus.verified,
  'REVOKED' => WorkspaceDeviceStatus.revoked,
  _ => throw const FormatException('unknown device status'),
};

/// Normalize the phone number at the client/API boundary.
///
/// Domestic 11-digit input is interpreted as a mainland China number. Other
/// E.164 input is kept intact so a future international account can use the
/// same endpoint.
String normalizePhone(String value) {
  final compact = value.trim().replaceAll(RegExp(r'[\s-]'), '');
  if (RegExp(r'^\d{11}$').hasMatch(compact)) return '+86$compact';
  if (compact.startsWith('0086') && RegExp(r'^0086\d{11}$').hasMatch(compact)) {
    return '+${compact.substring(2)}';
  }
  if (RegExp(r'^\+[1-9]\d{7,14}$').hasMatch(compact)) return compact;
  throw const FormatException('invalid phone number');
}

class WorkspaceSummary {
  const WorkspaceSummary({
    required this.id,
    required this.name,
    required this.status,
    this.memberCount = 0,
    this.matchStatus = WorkspaceMatchStatus.waitingPartner,
    this.members = const [],
  });

  final String id;
  final String? name;
  final String status;
  final int memberCount;
  final WorkspaceMatchStatus matchStatus;
  final List<WorkspaceMemberSummary> members;

  factory WorkspaceSummary.fromJson(Map<String, dynamic> json) {
    final members = json['members'];
    final memberCount =
        json['member_count'] as int? ??
        (members is List<dynamic> ? members.length : 0);
    final parsedMembers = members is List<dynamic>
        ? members
              .whereType<Map<String, dynamic>>()
              .map(WorkspaceMemberSummary.fromJson)
              .toList(growable: false)
        : const <WorkspaceMemberSummary>[];
    return WorkspaceSummary(
      id: json['id'] as String,
      name: json['name'] as String?,
      status: json['status'] as String? ?? 'ACTIVE',
      memberCount: memberCount,
      matchStatus: _matchStatusFromJson(json['match_status'], memberCount),
      members: parsedMembers,
    );
  }
}

class WorkspaceMemberSummary {
  const WorkspaceMemberSummary({
    required this.userId,
    required this.displayName,
    required this.phoneMasked,
    required this.memberSlot,
    required this.membershipStatus,
    required this.isCurrent,
  });

  final String userId;
  final String? displayName;
  final String phoneMasked;
  final int memberSlot;
  final String membershipStatus;
  final bool isCurrent;

  factory WorkspaceMemberSummary.fromJson(Map<String, dynamic> json) =>
      WorkspaceMemberSummary(
        userId: json['user_id'] as String,
        displayName: json['display_name'] as String?,
        phoneMasked: json['phone_masked'] as String? ?? '',
        memberSlot: json['member_slot'] as int? ?? 0,
        membershipStatus: json['membership_status'] as String? ?? 'ACTIVE',
        isCurrent: json['is_current'] as bool? ?? false,
      );
}

WorkspaceMatchStatus _matchStatusFromJson(Object? value, int memberCount) =>
    switch (value) {
      'matched' => WorkspaceMatchStatus.matched,
      'error' => WorkspaceMatchStatus.error,
      'waiting_partner' => WorkspaceMatchStatus.waitingPartner,
      _ =>
        memberCount == 2
            ? WorkspaceMatchStatus.matched
            : WorkspaceMatchStatus.waitingPartner,
    };

class WorkspaceInviteSummary {
  const WorkspaceInviteSummary({
    required this.id,
    required this.phoneMasked,
    required this.status,
    required this.expiresAt,
  });

  final String id;
  final String phoneMasked;
  final String status;
  final DateTime expiresAt;

  factory WorkspaceInviteSummary.fromJson(Map<String, dynamic> json) =>
      WorkspaceInviteSummary(
        id: json['id'] as String,
        phoneMasked: json['phone_masked'] as String,
        status: json['status'] as String,
        expiresAt: DateTime.parse(json['expires_at'] as String),
      );
}

class WorkspaceDeviceCapability {
  const WorkspaceDeviceCapability({
    required this.status,
    required this.canWrite,
  });

  final WorkspaceDeviceStatus status;
  final bool canWrite;

  bool get isReadOnly => !canWrite;

  factory WorkspaceDeviceCapability.fromJson(Map<String, dynamic> json) =>
      WorkspaceDeviceCapability(
        status: _deviceStatusFromJson(json['status']),
        canWrite: json['can_write'] as bool? ?? false,
      );
}

class WorkspaceBootstrapPayload {
  const WorkspaceBootstrapPayload({
    required this.state,
    required this.workspace,
    required this.invite,
    required this.device,
  });

  final WorkspaceBootstrapPhase state;
  final WorkspaceSummary? workspace;
  final WorkspaceInviteSummary? invite;
  final WorkspaceDeviceCapability device;

  factory WorkspaceBootstrapPayload.fromJson(Map<String, dynamic> json) {
    final workspaceJson = json['workspace'];
    final inviteJson = json['invite'];
    final deviceJson = json['device'];
    if (deviceJson is! Map<String, dynamic>) {
      throw const FormatException('bootstrap device is missing');
    }
    return WorkspaceBootstrapPayload(
      state: _phaseFromJson(json['state']),
      workspace: workspaceJson is Map<String, dynamic>
          ? WorkspaceSummary.fromJson(workspaceJson)
          : null,
      invite: inviteJson is Map<String, dynamic>
          ? WorkspaceInviteSummary.fromJson(inviteJson)
          : null,
      device: WorkspaceDeviceCapability.fromJson(deviceJson),
    );
  }
}

class WorkspaceBootstrapFailure implements Exception {
  const WorkspaceBootstrapFailure({
    required this.code,
    required this.statusCode,
    this.message = '请求失败，请稍后重试',
    this.details,
  });

  final String code;
  final int statusCode;
  final String message;
  final Object? details;

  @override
  String toString() => message;
}

abstract interface class WorkspaceBootstrapRepository {
  Future<WorkspaceBootstrapPayload> loadBootstrap();

  Future<WorkspaceBootstrapPayload> bindPartner(String phone, String requestId);

  Future<WorkspaceBootstrapPayload> acceptInvite(
    String inviteId,
    String requestId,
  );
}

/// Legacy one-person workspace contract retained for old host integrations.
/// New Android code must implement [WorkspaceBootstrapRepository] instead.
abstract interface class LegacyWorkspaceBootstrapRepository {
  @Deprecated('Use WorkspaceBootstrapRepository.loadBootstrap')
  Future<WorkspaceSummary?> currentWorkspace();

  @Deprecated('Use WorkspaceBootstrapRepository.bindPartner')
  Future<WorkspaceSummary> createWorkspace();
}

class HttpWorkspaceBootstrapRepository
    implements
        WorkspaceBootstrapRepository,
        LegacyWorkspaceBootstrapRepository {
  HttpWorkspaceBootstrapRepository(this._api);

  final ApiClient _api;

  @override
  Future<WorkspaceBootstrapPayload> loadBootstrap() async {
    try {
      final value = await _api.request(
        'GET',
        '/api/v1/workspaces/bootstrap',
        authenticated: true,
      );
      return _payload(value);
    } on ApiException catch (error) {
      throw _failure(error);
    } on FormatException catch (error) {
      throw WorkspaceBootstrapFailure(
        code: 'invalid_response',
        statusCode: 500,
        message: error.message,
      );
    }
  }

  @override
  Future<WorkspaceBootstrapPayload> bindPartner(
    String phone,
    String requestId,
  ) async {
    final normalized = _normalizeOrThrow(phone);
    try {
      final value = await _api.request(
        'POST',
        '/api/v1/workspaces/bind-partner',
        body: {'phone': normalized, 'request_id': requestId},
        authenticated: true,
      );
      return _payload(value);
    } on ApiException catch (error) {
      throw _failure(error);
    } on FormatException catch (error) {
      throw WorkspaceBootstrapFailure(
        code: 'invalid_response',
        statusCode: 500,
        message: error.message,
      );
    }
  }

  @override
  Future<WorkspaceBootstrapPayload> acceptInvite(
    String inviteId,
    String requestId,
  ) async {
    try {
      final value = await _api.request(
        'POST',
        '/api/v1/workspace-invites/$inviteId/accept',
        body: {'request_id': requestId},
        authenticated: true,
      );
      return _payload(value);
    } on ApiException catch (error) {
      throw _failure(error);
    } on FormatException catch (error) {
      throw WorkspaceBootstrapFailure(
        code: 'invalid_response',
        statusCode: 500,
        message: error.message,
      );
    }
  }

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
      throw _failure(error);
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
      throw _failure(error);
    }
  }

  WorkspaceBootstrapPayload _payload(Object? value) {
    if (value is! Map<String, dynamic>) {
      throw const FormatException('bootstrap response is not an object');
    }
    return WorkspaceBootstrapPayload.fromJson(value);
  }

  static String _normalizeOrThrow(String phone) {
    try {
      return normalizePhone(phone);
    } on FormatException {
      throw const WorkspaceBootstrapFailure(
        code: 'invalid_phone',
        statusCode: 422,
        message: '请输入有效的手机号',
      );
    }
  }

  static WorkspaceBootstrapFailure _failure(ApiException error) =>
      WorkspaceBootstrapFailure(
        code: error.code,
        statusCode: error.statusCode,
        message: error.message,
        details: error.details,
      );
}
