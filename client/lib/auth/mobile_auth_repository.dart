import '../core/api_client.dart';
import '../models/user.dart';
import 'mobile_session_store.dart';

class MobileAuthFailure implements Exception {
  const MobileAuthFailure(this.message, {this.statusCode});

  final String message;
  final int? statusCode;

  @override
  String toString() => message;
}

abstract interface class MobileAuthRepository {
  Future<void> sendSms(String phone);

  Future<MobileSession> verifySms({
    required String phone,
    required String code,
    required String publicKey,
  });

  Future<MobileSession> refresh();

  Future<void> logout();

  Future<User> me();
}

class HttpMobileAuthRepository implements MobileAuthRepository {
  HttpMobileAuthRepository(this._api, this._store);

  final ApiClient _api;
  final MobileSessionStore _store;

  @override
  Future<void> sendSms(String phone) async {
    try {
      await _api.request(
        'POST',
        '/api/v1/auth/sms/send',
        body: {'phone': phone},
      );
    } on ApiException catch (error) {
      throw MobileAuthFailure(error.message, statusCode: error.statusCode);
    }
  }

  @override
  Future<MobileSession> verifySms({
    required String phone,
    required String code,
    required String publicKey,
  }) async {
    try {
      final value = await _api.request(
        'POST',
        '/api/v1/auth/sms/verify',
        body: {'phone': phone, 'code': code, 'public_key': publicKey},
      );
      return await _save(value);
    } on ApiException catch (error) {
      throw MobileAuthFailure(error.message, statusCode: error.statusCode);
    }
  }

  @override
  Future<MobileSession> refresh() async {
    final current = await _store.read();
    if (current == null) throw const MobileAuthFailure('移动端会话已过期');
    try {
      final value = await _api.request(
        'POST',
        '/api/v1/auth/mobile/refresh',
        body: {'refresh_token': current.refreshToken},
      );
      return await _save(value);
    } on ApiException catch (error) {
      await _store.clear();
      throw MobileAuthFailure(error.message, statusCode: error.statusCode);
    }
  }

  @override
  Future<void> logout() async {
    final current = await _store.read();
    try {
      if (current != null) {
        await _api.request(
          'POST',
          '/api/v1/auth/mobile/logout',
          body: {'refresh_token': current.refreshToken},
        );
      }
    } on ApiException {
      // Local credentials are cleared even when the remote session is gone.
    } finally {
      await _store.clear();
    }
  }

  @override
  Future<User> me() async {
    try {
      final value = await _api.request(
        'GET',
        '/api/v1/me',
        authenticated: true,
        refreshTokens: refresh,
      );
      return User.fromJson(value as Map<String, dynamic>);
    } on ApiException catch (error) {
      throw MobileAuthFailure(error.message, statusCode: error.statusCode);
    }
  }

  Future<MobileSession> _save(Object? value) async {
    final json = value as Map<String, dynamic>;
    final session = MobileSession(
      accessToken: json['access_token'] as String,
      refreshToken: json['refresh_token'] as String,
      deviceId: json['device_id'] as String,
      user: User.fromJson(json['user'] as Map<String, dynamic>),
      expiresAt: json['expires_at'] == null
          ? null
          : DateTime.parse(json['expires_at'] as String),
    );
    await _store.write(session);
    return session;
  }
}
