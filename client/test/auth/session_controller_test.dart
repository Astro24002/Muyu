import 'package:flutter_test/flutter_test.dart';
import 'package:muyu_client/auth/auth_repository.dart';
import 'package:muyu_client/auth/session_controller.dart';
import 'package:muyu_client/auth/token_store.dart';
import 'package:muyu_client/models/user.dart';

class MemoryTokenStore implements TokenStore {
  String? access;
  String? refresh;

  @override
  Future<String?> readAccessToken() async => access;

  @override
  Future<String?> readRefreshToken() async => refresh;

  @override
  Future<void> write({
    required String accessToken,
    required String refreshToken,
  }) async {
    access = accessToken;
    refresh = refreshToken;
  }

  @override
  Future<void> clear() async {
    access = null;
    refresh = null;
  }
}

class FakeAuthRepository implements AuthRepository {
  AuthSession? loginResult;
  AuthSession? refreshResult;
  User? meResult;
  List<User> usersResult = const [];
  Object? loginError;
  Object? refreshError;
  int refreshCalls = 0;
  int logoutCalls = 0;

  @override
  Future<AuthSession> login(String phone, String password) async {
    if (loginError != null) throw loginError!;
    return loginResult!;
  }

  @override
  Future<AuthSession> refresh() async {
    refreshCalls++;
    if (refreshError != null) throw refreshError!;
    return refreshResult!;
  }

  @override
  Future<void> logout() async => logoutCalls++;

  @override
  Future<User> me() async => meResult!;

  @override
  Future<List<User>> users() async => usersResult;

  @override
  Future<User> updateProfile({String? nickname, String? role}) async =>
      meResult!;
}

User user() => const User(
  id: '1',
  phone: '15028180169',
  nickname: '用户一',
  avatarKey: 'avatar-1',
  role: '成员',
);

AuthSession session() => AuthSession(
  user: user(),
  accessToken: 'access-1',
  refreshToken: 'refresh-1',
);

void main() {
  test('successful login stores tokens and enters signed-in state', () async {
    final repository = FakeAuthRepository()..loginResult = session();
    final store = MemoryTokenStore();
    final controller = SessionController(repository, store);

    await controller.login('15028180169', 'password');

    expect(controller.status, SessionStatus.signedIn);
    expect(controller.currentUser, user());
    expect(store.access, 'access-1');
    expect(store.refresh, 'refresh-1');
  });

  test('invalid login exposes a failure without storing tokens', () async {
    final repository = FakeAuthRepository()
      ..loginError = const AuthFailure('invalid credentials');
    final store = MemoryTokenStore();
    final controller = SessionController(repository, store);

    await controller.login('15028180169', 'wrong');

    expect(controller.status, SessionStatus.failure);
    expect(controller.errorMessage, 'invalid credentials');
    expect(store.access, isNull);
  });

  test(
    'restore refreshes an expired access token and recovers the session',
    () async {
      final repository = FakeAuthRepository()
        ..refreshResult = session()
        ..meResult = user();
      final store = MemoryTokenStore()
        ..access = 'expired'
        ..refresh = 'refresh-1';
      final controller = SessionController(repository, store);

      await controller.restore();

      expect(repository.refreshCalls, 1);
      expect(controller.status, SessionStatus.signedIn);
      expect(controller.currentUser, user());
    },
  );

  test('restore clears credentials when refresh fails', () async {
    final repository = FakeAuthRepository()
      ..refreshError = const AuthFailure('session expired');
    final store = MemoryTokenStore()
      ..access = 'expired'
      ..refresh = 'refresh-1';
    final controller = SessionController(repository, store);

    await controller.restore();

    expect(controller.status, SessionStatus.signedOut);
    expect(store.access, isNull);
    expect(store.refresh, isNull);
  });

  test('logout calls repository, clears credentials, and signs out', () async {
    final repository = FakeAuthRepository()..loginResult = session();
    final store = MemoryTokenStore();
    final controller = SessionController(repository, store);
    await controller.login('15028180169', 'password');

    await controller.logout();

    expect(repository.logoutCalls, 1);
    expect(controller.status, SessionStatus.signedOut);
    expect(store.refresh, isNull);
  });
}
