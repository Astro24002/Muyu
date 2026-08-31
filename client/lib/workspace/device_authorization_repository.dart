import 'dart:convert';
import 'dart:typed_data';

import '../core/api_client.dart';
import '../platform/device_signing_key.dart';

class DeviceAuthorizationFailure implements Exception {
  const DeviceAuthorizationFailure(this.message, {this.code});

  final String message;
  final String? code;
}

class DeviceAuthorizationRequest {
  const DeviceAuthorizationRequest({
    required this.id,
    this.safetyCode,
    required this.expiresAt,
    required this.status,
    this.origin,
    this.signaturePayload,
    this.candidateDeviceId,
    this.candidateDeviceLabel,
    this.candidatePlatform,
    this.candidateUserId,
    this.candidatePhoneMasked,
    this.requesterUserId,
    this.requesterPhoneMasked,
    this.isIncoming = false,
    this.createdAt,
  });

  final String id;
  final String? safetyCode;
  final DateTime expiresAt;
  final String status;
  final String? origin;
  final String? signaturePayload;
  final String? candidateDeviceId;
  final String? candidateDeviceLabel;
  final String? candidatePlatform;
  final String? candidateUserId;
  final String? candidatePhoneMasked;
  final String? requesterUserId;
  final String? requesterPhoneMasked;
  final bool isIncoming;
  final DateTime? createdAt;

  factory DeviceAuthorizationRequest.fromJson(Map<String, dynamic> json) =>
      DeviceAuthorizationRequest(
        id: json['id'] as String,
        safetyCode: json['safety_code'] as String?,
        expiresAt: DateTime.parse(json['expires_at'] as String),
        status: json['status'] as String,
        origin: json['origin'] as String?,
        signaturePayload: json['signature_payload'] as String?,
        candidateDeviceId: json['candidate_device_id'] as String?,
        candidateDeviceLabel: json['candidate_device_label'] as String?,
        candidatePlatform: json['candidate_platform'] as String?,
        candidateUserId: json['candidate_user_id'] as String?,
        candidatePhoneMasked: json['candidate_phone_masked'] as String?,
        requesterUserId: json['requester_user_id'] as String?,
        requesterPhoneMasked: json['requester_phone_masked'] as String?,
        isIncoming: json['is_incoming'] as bool? ?? false,
        createdAt: json['created_at'] == null
            ? null
            : DateTime.parse(json['created_at'] as String),
      );
}

abstract interface class DeviceAuthorizationRepository {
  Future<DeviceAuthorizationRequest> createDeviceRequest(String publicKey);

  Future<List<DeviceAuthorizationRequest>> listRequests();

  Future<void> reject(String requestId);

  Future<DeviceAuthorizationRequest> beginApproval(String requestId);

  Future<DeviceAuthorizationRequest> scanWebQr(String qrPayload);

  Future<void> approve(
    String requestId, {
    required DeviceSigningKey signingKey,
    required String signaturePayload,
  });

  Future<void> approveWebLogin(
    DeviceAuthorizationRequest request, {
    required DeviceSigningKey signingKey,
  });
}

class HttpDeviceAuthorizationRepository
    implements DeviceAuthorizationRepository {
  HttpDeviceAuthorizationRepository(this._api);

  final ApiClient _api;

  @override
  Future<DeviceAuthorizationRequest> createDeviceRequest(String publicKey) =>
      _post('/api/v1/devices/authorization-requests', {
        'public_key': publicKey,
      });

  @override
  Future<List<DeviceAuthorizationRequest>> listRequests() async {
    try {
      final value = await _api.request(
        'GET',
        '/api/v1/devices/authorization-requests',
        authenticated: true,
      );
      if (value is! List<dynamic>) {
        throw const FormatException(
          'authorization request list is not an array',
        );
      }
      return value
          .whereType<Map<String, dynamic>>()
          .map(DeviceAuthorizationRequest.fromJson)
          .toList(growable: false);
    } on ApiException catch (error) {
      throw DeviceAuthorizationFailure(error.message, code: error.code);
    } on FormatException {
      throw const DeviceAuthorizationFailure('设备验证请求格式无效');
    }
  }

  @override
  Future<void> reject(String requestId) async {
    try {
      await _api.request(
        'POST',
        '/api/v1/devices/authorization-requests/$requestId/reject',
        authenticated: true,
      );
    } on ApiException catch (error) {
      throw DeviceAuthorizationFailure(error.message, code: error.code);
    }
  }

  @override
  Future<DeviceAuthorizationRequest> beginApproval(String requestId) => _post(
    '/api/v1/devices/authorization-requests/$requestId/begin-approval',
    {},
  );

  @override
  Future<DeviceAuthorizationRequest> scanWebQr(String qrPayload) async {
    final parsed = _parseQr(qrPayload);
    return _post(
      '/api/v1/web-login/challenges/${parsed['challenge_id']}/scan',
      {'scan_nonce': parsed['scan_nonce']},
    );
  }

  @override
  Future<void> approve(
    String requestId, {
    required DeviceSigningKey signingKey,
    required String signaturePayload,
  }) async {
    try {
      final payload = base64Url.decode(base64Url.normalize(signaturePayload));
      final signature = await signingKey.sign(Uint8List.fromList(payload));
      await _api.request(
        'POST',
        '/api/v1/devices/authorization-requests/$requestId/approve',
        body: {'signature': base64Encode(signature)},
        authenticated: true,
      );
    } on ApiException catch (error) {
      throw DeviceAuthorizationFailure(error.message, code: error.code);
    } on FormatException {
      throw const DeviceAuthorizationFailure('设备审批签名载荷格式无效');
    }
  }

  @override
  Future<void> approveWebLogin(
    DeviceAuthorizationRequest request, {
    required DeviceSigningKey signingKey,
  }) async {
    final payload = request.signaturePayload;
    if (payload == null || payload.isEmpty) {
      throw const DeviceAuthorizationFailure('二维码签名载荷不可用');
    }
    try {
      final bytes = base64Url.decode(base64Url.normalize(payload));
      final signature = await signingKey.sign(Uint8List.fromList(bytes));
      await _api.request(
        'POST',
        '/api/v1/web-login/challenges/${request.id}/approve',
        body: {'signature': base64Encode(signature)},
        authenticated: true,
      );
    } on ApiException catch (error) {
      throw DeviceAuthorizationFailure(error.message, code: error.code);
    } on FormatException {
      throw const DeviceAuthorizationFailure('二维码签名载荷格式无效');
    }
  }

  Future<DeviceAuthorizationRequest> _post(
    String path,
    Map<String, Object?> body,
  ) async {
    try {
      return DeviceAuthorizationRequest.fromJson(
        await _api.request('POST', path, body: body, authenticated: true)
            as Map<String, dynamic>,
      );
    } on ApiException catch (error) {
      throw DeviceAuthorizationFailure(error.message, code: error.code);
    }
  }

  static Map<String, dynamic> _parseQr(String value) {
    try {
      final json = jsonDecode(value) as Map<String, dynamic>;
      final origin = Uri.parse(json['origin'] as String);
      final expiry = DateTime.parse(json['expires_at'] as String);
      if (json['version'] != 1 ||
          origin.scheme != 'https' ||
          !expiry.isAfter(DateTime.now())) {
        throw const FormatException();
      }
      return json;
    } catch (_) {
      throw const DeviceAuthorizationFailure('二维码无效、已过期或来源不安全');
    }
  }
}
