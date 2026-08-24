import 'dart:convert';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import '../models/user.dart';
import 'token_store.dart';

class MobileSession {
  const MobileSession({
    required this.accessToken,
    required this.refreshToken,
    required this.deviceId,
    required this.user,
    required this.expiresAt,
  });

  final String accessToken;
  final String refreshToken;
  final String deviceId;
  final User user;
  final DateTime? expiresAt;

  Map<String, Object?> toJson() => {
    'access_token': accessToken,
    'refresh_token': refreshToken,
    'device_id': deviceId,
    'user': {
      'id': user.id,
      'phone': user.phone,
      'nickname': user.nickname,
      'avatar_key': user.avatarKey,
      'role': user.role,
    },
    'expires_at': expiresAt?.toUtc().toIso8601String(),
  };

  factory MobileSession.fromJson(Map<String, dynamic> json) => MobileSession(
    accessToken: json['access_token'] as String,
    refreshToken: json['refresh_token'] as String,
    deviceId: json['device_id'] as String,
    user: User.fromJson(json['user'] as Map<String, dynamic>),
    expiresAt: json['expires_at'] == null
        ? null
        : DateTime.parse(json['expires_at'] as String),
  );

  @override
  bool operator ==(Object other) =>
      other is MobileSession &&
      other.accessToken == accessToken &&
      other.refreshToken == refreshToken &&
      other.deviceId == deviceId &&
      other.user == user &&
      other.expiresAt == expiresAt;

  @override
  int get hashCode =>
      Object.hash(accessToken, refreshToken, deviceId, user, expiresAt);
}

abstract interface class MobileSessionStore {
  Future<MobileSession?> read();

  Future<void> write(MobileSession session);

  Future<void> clear();
}

class MobileTokenStoreAdapter implements TokenStore {
  MobileTokenStoreAdapter(this._store);

  final MobileSessionStore _store;

  @override
  Future<String?> readAccessToken() async => (await _store.read())?.accessToken;

  @override
  Future<String?> readRefreshToken() async =>
      (await _store.read())?.refreshToken;

  @override
  Future<void> write({
    required String accessToken,
    required String refreshToken,
  }) async {
    final current = await _store.read();
    if (current != null) {
      await _store.write(
        MobileSession(
          accessToken: accessToken,
          refreshToken: refreshToken,
          deviceId: current.deviceId,
          user: current.user,
          expiresAt: current.expiresAt,
        ),
      );
    }
  }

  @override
  Future<void> clear() => _store.clear();
}

class SecureMobileSessionStore implements MobileSessionStore {
  SecureMobileSessionStore([FlutterSecureStorage? storage])
    : _storage = storage ?? const FlutterSecureStorage();

  static const _key = 'muyu_mobile_session';
  final FlutterSecureStorage _storage;

  @override
  Future<MobileSession?> read() async {
    final value = await _storage.read(key: _key);
    if (value == null) return null;
    try {
      return MobileSession.fromJson(jsonDecode(value) as Map<String, dynamic>);
    } on FormatException {
      await clear();
      return null;
    }
  }

  @override
  Future<void> write(MobileSession session) =>
      _storage.write(key: _key, value: jsonEncode(session.toJson()));

  @override
  Future<void> clear() => _storage.delete(key: _key);
}
