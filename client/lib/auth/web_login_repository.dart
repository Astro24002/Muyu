import 'dart:convert';

import 'package:crypto/crypto.dart';

import '../core/api_client.dart';
import '../core/config.dart';

class WebQrPayloadFailure implements Exception {
  const WebQrPayloadFailure(this.message);

  final String message;

  @override
  String toString() => message;
}

class WebQrPayload {
  const WebQrPayload({
    required this.version,
    required this.challengeId,
    required this.scanNonce,
    required this.origin,
    required this.expiresAt,
  });

  final int version;
  final String challengeId;
  final String scanNonce;
  final String origin;
  final DateTime expiresAt;

  factory WebQrPayload.parse(String value, {DateTime? now}) {
    try {
      final json = jsonDecode(value) as Map<String, dynamic>;
      final version = json['version'] as int;
      final challengeId = json['challenge_id'] as String;
      final scanNonce = json['scan_nonce'] as String;
      final origin = json['origin'] as String;
      final expiresAt = DateTime.parse(json['expires_at'] as String);
      final uri = Uri.parse(origin);
      if (version != 1 || challengeId.isEmpty || scanNonce.isEmpty) {
        throw const WebQrPayloadFailure('二维码版本或字段无效');
      }
      if (uri.scheme != 'https' || uri.host.isEmpty) {
        throw const WebQrPayloadFailure('二维码来源必须使用 HTTPS');
      }
      if (!expiresAt.isAfter(now ?? DateTime.now())) {
        throw const WebQrPayloadFailure('二维码已过期');
      }
      return WebQrPayload(
        version: version,
        challengeId: challengeId,
        scanNonce: scanNonce,
        origin: origin,
        expiresAt: expiresAt,
      );
    } on WebQrPayloadFailure {
      rethrow;
    } catch (_) {
      throw const WebQrPayloadFailure('二维码格式无效');
    }
  }
}

class WebLoginChallenge {
  const WebLoginChallenge({
    required this.challengeId,
    required this.qrPayload,
    required this.origin,
    required this.safetyCode,
    required this.expiresAt,
  });

  final String challengeId;
  final String qrPayload;
  final String origin;
  final String safetyCode;
  final DateTime expiresAt;
}

abstract interface class WebLoginApi {
  Future<WebLoginChallenge> createChallenge(String browserProof);

  Future<String> status(String challengeId);

  Future<void> exchange(String challengeId, String browserProof);
}

class WebLoginRepository implements WebLoginApi {
  WebLoginRepository(this._api, {this.origin = AppConfig.webOrigin});

  final ApiClient _api;
  final String origin;

  @override
  Future<WebLoginChallenge> createChallenge(String browserProof) async {
    final proofHash = sha256.convert(utf8.encode(browserProof)).toString();
    final value = await _api.request(
      'POST',
      '/api/v1/web-login/challenges',
      body: {'browser_proof_hash': proofHash, 'origin': origin},
    ) as Map<String, dynamic>;
    return WebLoginChallenge(
      challengeId: value['challenge_id'] as String,
      qrPayload: value['qr_payload'] as String,
      origin: value['origin'] as String,
      safetyCode: value['safety_code'] as String,
      expiresAt: DateTime.parse(value['expires_at'] as String),
    );
  }

  @override
  Future<String> status(String challengeId) async {
    final value = await _api.request(
      'GET',
      '/api/v1/web-login/challenges/$challengeId',
    ) as Map<String, dynamic>;
    return value['status'] as String;
  }

  @override
  Future<void> exchange(String challengeId, String browserProof) async {
    await _api.request(
      'POST',
      '/api/v1/web-login/challenges/$challengeId/exchange',
      body: {
        'browser_proof': sha256.convert(utf8.encode(browserProof)).toString(),
      },
    );
  }
}
