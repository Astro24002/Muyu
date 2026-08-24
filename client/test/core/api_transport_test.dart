import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:muyu_client/auth/mobile_session_store.dart';
import 'package:muyu_client/core/api_transport.dart';
import 'package:muyu_client/core/api_transport_mobile.dart';
import 'package:muyu_client/core/api_transport_web.dart';
import 'package:muyu_client/models/user.dart';

const mobileSession = MobileSession(
  accessToken: 'mobile-token',
  refreshToken: 'refresh-token',
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
  test('mobile transport sends bearer credentials only', () async {
    late http.Request request;
    final transport = MobileApiTransport(
      baseUrl: 'https://api.example',
      client: MockClient((incoming) async {
        request = incoming;
        return http.Response(jsonEncode({'ok': true}), 200);
      }),
      sessionStore: _Store(mobileSession),
    );

    await transport.send(const ApiRequest('GET', '/api/v1/me'));

    expect(request.headers['authorization'], 'Bearer mobile-token');
    expect(request.headers['cookie'], isNull);
  });

  test('web transport never reads or sends mobile credentials', () async {
    late http.Request request;
    final transport = WebApiTransport(
      baseUrl: 'https://muyu.example',
      client: MockClient((incoming) async {
        request = incoming;
        return http.Response(jsonEncode({'ok': true}), 200);
      }),
    );

    await transport.send(const ApiRequest('GET', '/api/v1/me'));

    expect(request.headers['authorization'], isNull);
    expect(request.headers['cookie'], isNull);
  });
}

class _Store implements MobileSessionStore {
  _Store(this.value);
  final MobileSession value;

  @override
  Future<MobileSession?> read() async => value;

  @override
  Future<void> write(MobileSession session) async {}

  @override
  Future<void> clear() async {}
}
