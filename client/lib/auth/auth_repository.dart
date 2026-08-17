import '../models/user.dart';
import '../core/api_client.dart';
import 'token_store.dart';

class AuthSession {
  const AuthSession({
    required this.user,
    required this.accessToken,
    required this.refreshToken,
  });

  final User user;
  final String accessToken;
  final String refreshToken;
}

class AuthFailure implements Exception {
  const AuthFailure(this.message);

  final String message;

  @override
  String toString() => message;
}

abstract interface class AuthRepository {
  Future<AuthSession> login(String phone, String password);

  Future<AuthSession> refresh();

  Future<void> logout();

  Future<User> me();

  Future<List<User>> users();

  Future<User> updateProfile({String? nickname, String? role});
}

class HttpAuthRepository implements AuthRepository {
  HttpAuthRepository(this._apiClient, this._tokenStore);

  final ApiClient _apiClient;
  final TokenStore _tokenStore;

  @override
  Future<AuthSession> login(String phone, String password) async {
    try {
      final json = await _apiClient.request(
        'POST',
        '/api/auth/login',
        body: {'phone': phone, 'password': password},
      );
      return await _saveAuthResponse(json);
    } on ApiException catch (error) {
      throw AuthFailure(error.message);
    }
  }

  @override
  Future<AuthSession> refresh() async {
    final refreshToken = await _tokenStore.readRefreshToken();
    if (refreshToken == null) throw const AuthFailure('登录已过期，请重新登录');
    try {
      final json = await _apiClient.request(
        'POST',
        '/api/auth/refresh',
        body: {'refresh_token': refreshToken},
      );
      return await _saveAuthResponse(json);
    } on ApiException catch (error) {
      await _tokenStore.clear();
      throw AuthFailure(error.message);
    }
  }

  @override
  Future<void> logout() async {
    final refreshToken = await _tokenStore.readRefreshToken();
    try {
      if (refreshToken != null) {
        await _apiClient.request(
          'POST',
          '/api/auth/logout',
          body: {'refresh_token': refreshToken},
        );
      }
    } on ApiException {
      // Local logout must complete even if the server session is already gone.
    } finally {
      await _tokenStore.clear();
    }
  }

  @override
  Future<User> me() async {
    final json = await _authenticated('GET', '/api/me');
    return User.fromJson(json as Map<String, dynamic>);
  }

  @override
  Future<List<User>> users() async {
    final json = await _authenticated('GET', '/api/users') as List<dynamic>;
    return json
        .map((value) => User.fromJson(value as Map<String, dynamic>))
        .toList();
  }

  @override
  Future<User> updateProfile({String? nickname, String? role}) async {
    final body = <String, Object?>{};
    if (nickname != null) body['nickname'] = nickname;
    if (role != null) body['role'] = role;
    final json = await _authenticated('PATCH', '/api/me', body: body);
    return User.fromJson(json as Map<String, dynamic>);
  }

  Future<Object?> _authenticated(
    String method,
    String path, {
    Map<String, Object?>? body,
  }) async {
    try {
      return await _apiClient.request(
        method,
        path,
        body: body,
        authenticated: true,
        refreshTokens: () async {
          await refresh();
        },
      );
    } on ApiException catch (error) {
      throw AuthFailure(error.message);
    }
  }

  Future<AuthSession> _saveAuthResponse(Object? value) async {
    final json = value as Map<String, dynamic>;
    final session = AuthSession(
      user: User.fromJson(json['user'] as Map<String, dynamic>),
      accessToken: json['access_token'] as String,
      refreshToken: json['refresh_token'] as String,
    );
    await _tokenStore.write(
      accessToken: session.accessToken,
      refreshToken: session.refreshToken,
    );
    return session;
  }
}
