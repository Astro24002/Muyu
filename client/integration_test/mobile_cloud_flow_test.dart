import 'package:flutter_test/flutter_test.dart';
import 'package:flutter/material.dart';
import 'package:muyu_client/auth/mobile_auth_repository.dart';
import 'package:muyu_client/auth/mobile_login_controller.dart';
import 'package:muyu_client/auth/mobile_session_store.dart';
import 'package:muyu_client/models/user.dart';
import 'package:muyu_client/screens/mobile_phone_login_screen.dart';

class _MemoryStore implements MobileSessionStore {
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

class _FakeMobileApi implements MobileAuthRepository {
  @override
  Future<void> sendSms(String phone) async {}

  @override
  Future<MobileSession> verifySms({
    required String phone,
    required String code,
    required String publicKey,
  }) async => MobileSession(
    accessToken: 'access-token',
    refreshToken: 'refresh-token',
    deviceId: 'device-1',
    user: const User(
      id: 'user-1',
      phone: '+15550000001',
      nickname: 'A',
      avatarKey: '',
      role: 'member',
    ),
    expiresAt: DateTime.now().add(const Duration(hours: 1)),
  );

  @override
  Future<MobileSession> refresh() => throw UnimplementedError();

  @override
  Future<void> logout() async {}

  @override
  Future<User> me() => throw UnimplementedError();
}

void main() {
  testWidgets('mobile flow persists a verified session', (tester) async {
    final store = _MemoryStore();
    final controller = MobileLoginController(
      _FakeMobileApi(),
      store,
      publicKey: () async => 'public-key',
    );
    await tester.pumpWidget(MobilePhoneLoginScreen(controller: controller));

    await tester.enterText(find.byType(TextField).first, '+15550000001');
    await tester.tap(find.text('发送验证码'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField).last, '000000');
    await tester.tap(find.text('验证并登录'));
    await tester.pumpAndSettle();

    expect(controller.status, MobileLoginStatus.signedIn);
    expect(store.value?.accessToken, 'access-token');
  });
}
