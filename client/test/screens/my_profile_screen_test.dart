import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:muyu_client/auth/mobile_session_store.dart';
import 'package:muyu_client/models/user.dart';
import 'package:muyu_client/screens/my_profile_screen.dart';
import 'package:muyu_client/workspace/device_repository.dart';

class FakeDeviceRepository implements DeviceRepository {
  @override
  Future<List<DeviceSummary>> listDevices() async => [
    DeviceSummary(
      id: 'device-1',
      platform: 'ANDROID',
      label: 'Pixel 8',
      status: 'ACTIVE',
      isCurrent: true,
      createdAt: DateTime.utc(2026, 8, 27),
      enrolledAt: DateTime.utc(2026, 8, 27),
      revokedAt: null,
    ),
  ];
}

void main() {
  testWidgets('shows profile and the long-term logged-in device', (
    tester,
  ) async {
    const session = MobileSession(
      accessToken: 'access',
      refreshToken: 'refresh',
      deviceId: 'device-1',
      user: User(
        id: 'user-1',
        phone: '+8613800138000',
        nickname: 'Muyu',
        avatarKey: '',
        role: 'member',
      ),
      expiresAt: null,
    );

    await tester.pumpWidget(
      MaterialApp(
        home: MyProfileScreen(
          session: session,
          repository: FakeDeviceRepository(),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('我的'), findsOneWidget);
    expect(find.text('+86******8000'), findsOneWidget);
    expect(find.text('登录设备'), findsOneWidget);
    expect(find.text('Pixel 8'), findsOneWidget);
    expect(find.text('当前设备'), findsOneWidget);
    expect(find.textContaining('长期绑定'), findsOneWidget);
  });

  testWidgets('places Web QR authorization in the AppBar only', (tester) async {
    const session = MobileSession(
      accessToken: 'access',
      refreshToken: 'refresh',
      deviceId: 'device-1',
      user: User(
        id: 'user-1',
        phone: '+8613800138000',
        nickname: 'Muyu',
        avatarKey: '',
        role: 'member',
      ),
      expiresAt: null,
    );
    var tapped = false;

    await tester.pumpWidget(
      MaterialApp(
        home: MyProfileScreen(
          session: session,
          repository: FakeDeviceRepository(),
          onWebQrLogin: () => tapped = true,
        ),
      ),
    );
    await tester.pumpAndSettle();

    final qr = find.byKey(const Key('profile-web-qr-login'));
    expect(qr, findsOneWidget);
    expect(tester.widget<IconButton>(qr).onPressed, isNotNull);
    expect(
      find.ancestor(of: qr, matching: find.byType(ListTile)),
      findsNothing,
    );
    await tester.tap(qr);
    expect(tapped, isTrue);
  });
}
