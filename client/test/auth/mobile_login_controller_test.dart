import 'package:flutter_test/flutter_test.dart';
import 'package:muyu_client/auth/mobile_auth_repository.dart';
import 'package:muyu_client/auth/mobile_login_controller.dart';
import 'package:muyu_client/auth/mobile_session_store.dart';
import 'package:muyu_client/models/user.dart';

class FakeMobileRepository implements MobileAuthRepository {
  MobileSession? verifyResult;
  MobileAuthFailure? verifyFailure;
  MobileSession? refreshResult;
  MobileAuthFailure? refreshFailure;
  int sendCalls = 0;
  int refreshCalls = 0;

  @override
  Future<void> sendSms(String phone) async => sendCalls++;

  @override
  Future<MobileSession> verifySms({
    required String phone,
    required String code,
    required String publicKey,
  }) async {
    if (verifyFailure != null) throw verifyFailure!;
    return verifyResult!;
  }

  @override
  Future<MobileSession> refresh() async {
    refreshCalls++;
    if (refreshFailure != null) throw refreshFailure!;
    return refreshResult ?? verifyResult!;
  }

  @override
  Future<void> logout() async {}

  @override
  Future<User> me() async => verifyResult!.user;
}

class MemoryMobileSessionStore implements MobileSessionStore {
  MobileSession? value;

  @override
  Future<MobileSession?> read() async => value;

  @override
  Future<void> write(MobileSession session) async => value = session;

  @override
  Future<void> replaceUser(User user) async {
    if (value == null) return;
    value = MobileSession(
      accessToken: value!.accessToken,
      refreshToken: value!.refreshToken,
      deviceId: value!.deviceId,
      user: user,
      expiresAt: value!.expiresAt,
    );
  }

  @override
  Future<void> clear() async => value = null;
}

const session = MobileSession(
  accessToken: 'mobile-access',
  refreshToken: 'mobile-refresh',
  deviceId: 'device-1',
  user: User(
    id: 'user-1',
    phone: '+8613800138000',
    nickname: 'A',
    avatarKey: 'avatar',
    role: 'member',
  ),
  expiresAt: null,
);

void main() {
  test('requests an OTP and exposes the retry state', () async {
    final repository = FakeMobileRepository();
    final controller = MobileLoginController(
      repository,
      MemoryMobileSessionStore(),
      publicKey: () async => 'public-key',
    );

    await controller.requestCode('+8613800138000');

    expect(repository.sendCalls, 1);
    expect(controller.status, MobileLoginStatus.codeSent);
    expect(controller.phone, '+8613800138000');
  });

  test('successful OTP verification stores an opaque mobile session', () async {
    final repository = FakeMobileRepository()..verifyResult = session;
    final store = MemoryMobileSessionStore();
    final controller = MobileLoginController(
      repository,
      store,
      publicKey: () async => 'public-key',
    );

    await controller.requestCode(session.user.phone);
    await controller.verifyCode('123456');

    expect(controller.status, MobileLoginStatus.signedIn);
    expect(store.value, session);
    expect(controller.currentSession, session);
  });

  test('wrong or expired OTP is shown without storing credentials', () async {
    final repository = FakeMobileRepository()
      ..verifyFailure = const MobileAuthFailure('验证码无效或已过期');
    final store = MemoryMobileSessionStore();
    final controller = MobileLoginController(
      repository,
      store,
      publicKey: () async => 'public-key',
    );

    await controller.requestCode(session.user.phone);
    await controller.verifyCode('000000');

    expect(controller.status, MobileLoginStatus.failure);
    expect(controller.errorMessage, '验证码无效或已过期');
    expect(store.value, isNull);
  });

  test('restores a persisted session without requesting another OTP', () async {
    final repository = FakeMobileRepository()..refreshResult = session;
    final store = MemoryMobileSessionStore()..value = session;
    final controller = MobileLoginController(
      repository,
      store,
      publicKey: () async => 'public-key',
    );

    await controller.restore();

    expect(repository.sendCalls, 0);
    expect(repository.refreshCalls, 1);
    expect(controller.status, MobileLoginStatus.signedIn);
    expect(controller.currentSession, session);
    expect(store.value, session);
  });

  test('clears an invalid persisted session and requires OTP again', () async {
    final repository = FakeMobileRepository()
      ..refreshFailure = const MobileAuthFailure('移动端会话已过期');
    final store = MemoryMobileSessionStore()..value = session;
    final controller = MobileLoginController(
      repository,
      store,
      publicKey: () async => 'public-key',
    );

    await controller.restore();

    expect(controller.status, MobileLoginStatus.failure);
    expect(controller.currentSession, isNull);
    expect(store.value, isNull);
    expect(controller.errorMessage, '移动端会话已过期');
  });
}
