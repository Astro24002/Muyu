import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:muyu_client/auth/token_store.dart';
import 'package:muyu_client/core/api_client.dart';
import 'package:muyu_client/devices/device_management_repository.dart';
import 'package:muyu_client/screens/device_management_screen.dart';
import 'package:muyu_client/workspace/device_repository.dart';

class StaticTokenStore implements TokenStore {
  @override
  Future<String?> readAccessToken() async => 'mobile-access';

  @override
  Future<String?> readRefreshToken() async => null;

  @override
  Future<void> write({
    required String accessToken,
    required String refreshToken,
  }) async {}

  @override
  Future<void> clear() async {}
}

DeviceSummary device({
  required String id,
  required bool current,
  String status = 'VERIFIED',
}) => DeviceSummary(
  id: id,
  platform: 'ANDROID',
  label: id,
  status: status,
  isCurrent: current,
  createdAt: DateTime.utc(2026, 8, 27),
  enrolledAt: DateTime.utc(2026, 8, 27),
  revokedAt: null,
);

class FakeDeviceManagementRepository implements DeviceManagementRepository {
  List<DeviceSummary> devices = [
    device(id: 'current-device', current: true),
    device(id: 'old-device', current: false),
  ];
  String? revoked;

  @override
  Future<List<DeviceSummary>> list() async => devices;

  @override
  Future<DeviceSummary> revoke(String deviceId) async {
    revoked = deviceId;
    final index = devices.indexWhere((item) => item.id == deviceId);
    devices[index] = device(id: deviceId, current: false, status: 'REVOKED');
    return devices[index];
  }
}

void main() {
  test('device management lists Android devices and revokes by id', () async {
    final requests = <http.Request>[];
    final repository = HttpDeviceManagementRepository(
      ApiClient(
        baseUrl: 'https://api.example',
        httpClient: MockClient((request) async {
          requests.add(request);
          if (request.method == 'GET') {
            return http.Response(
              jsonEncode([
                {
                  'id': 'device-1',
                  'platform': 'ANDROID',
                  'label': 'Pixel',
                  'status': 'VERIFIED',
                  'can_write': true,
                  'is_current': true,
                  'created_at': '2026-08-27T00:00:00Z',
                  'enrolled_at': '2026-08-27T00:00:00Z',
                  'revoked_at': null,
                },
              ]),
              200,
            );
          }
          return http.Response(
            jsonEncode({
              'id': 'device-2',
              'platform': 'ANDROID',
              'label': 'Tablet',
              'status': 'REVOKED',
              'can_write': false,
              'is_current': false,
              'created_at': '2026-08-27T00:00:00Z',
              'enrolled_at': '2026-08-27T00:00:00Z',
              'revoked_at': '2026-08-27T01:00:00Z',
            }),
            200,
          );
        }),
        tokenStore: StaticTokenStore(),
      ),
    );

    final devices = await repository.list();
    expect(devices.single.status, 'VERIFIED');
    expect(devices.single.canWrite, isTrue);
    final revoked = await repository.revoke('device-2');

    expect(requests.map((request) => request.url.path), [
      '/api/v1/devices',
      '/api/v1/devices/device-2/revoke',
    ]);
    expect(revoked.status, 'REVOKED');
    expect(revoked.canWrite, isFalse);
  });

  testWidgets(
    'current device has no revoke action and other devices require confirmation',
    (tester) async {
      final repository = FakeDeviceManagementRepository();
      await tester.pumpWidget(
        MaterialApp(home: DeviceManagementScreen(repository: repository)),
      );
      await tester.pumpAndSettle();

      expect(
        find.byKey(const Key('device-management-app-bar')),
        findsOneWidget,
      );

      expect(
        find.byKey(const Key('revoke-device-current-device')),
        findsNothing,
      );
      expect(find.byKey(const Key('revoke-device-old-device')), findsOneWidget);

      await tester.tap(find.byKey(const Key('revoke-device-old-device')));
      await tester.pumpAndSettle();
      expect(find.text('撤销设备'), findsOneWidget);
      expect(repository.revoked, isNull);

      await tester.tap(find.byKey(const Key('confirm-revoke-device')));
      await tester.pumpAndSettle();
      expect(repository.revoked, 'old-device');
      expect(find.textContaining('已撤销'), findsOneWidget);
    },
  );
}
