import 'package:flutter_test/flutter_test.dart';
import 'package:muyu_client/auth/mobile_session_store.dart';
import 'package:muyu_client/models/user.dart';

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

void main() {
  test('replaces only the user while preserving mobile credentials', () async {
    final store = _MemoryStore()
      ..value = MobileSession(
        accessToken: 'access',
        refreshToken: 'refresh',
        deviceId: 'device-1',
        user: const User(
          id: 'user-1',
          phone: '+8613800138000',
          nickname: '旧名称',
          avatarKey: '',
          role: 'member',
        ),
        expiresAt: DateTime.utc(2026, 9, 3),
      );

    await store.replaceUser(
      const User(
        id: 'user-1',
        phone: '+8613800138000',
        nickname: '新名称',
        avatarKey: '',
        role: 'member',
      ),
    );

    expect(store.value!.user.nickname, '新名称');
    expect(store.value!.accessToken, 'access');
    expect(store.value!.refreshToken, 'refresh');
    expect(store.value!.deviceId, 'device-1');
    expect(store.value!.expiresAt, DateTime.utc(2026, 9, 3));
  });
}
