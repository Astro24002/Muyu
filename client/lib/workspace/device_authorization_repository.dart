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
    required this.safetyCode,
    required this.expiresAt,
    required this.status,
    this.origin,
  });

  final String id;
  final String safetyCode;
  final DateTime expiresAt;
  final String status;
  final String? origin;

  factory DeviceAuthorizationRequest.fromJson(Map<String, dynamic> json) =>
      DeviceAuthorizationRequest(
        id: json['id'] as String,
        safetyCode: json['safety_code'] as String,
        expiresAt: DateTime.parse(json['expires_at'] as String),
        status: json['status'] as String,
        origin: json['origin'] as String?,
      );
}

abstract interface class DeviceAuthorizationRepository {
  Future<DeviceAuthorizationRequest> createDeviceRequest(String publicKey);

  Future<DeviceAuthorizationRequest> scanWebQr(String qrPayload);

  Future<void> approve(
    String requestId, {
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
  }) async {
    final payload = utf8.encode('WEB_LOGIN_APPROVE:$requestId');
    final signature = await signingKey.sign(Uint8List.fromList(payload));
    await _api.request(
      'POST',
      '/api/v1/devices/authorization-requests/$requestId/approve',
      body: {'signature': base64Encode(signature)},
      authenticated: true,
    );
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
