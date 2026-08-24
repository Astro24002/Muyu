import 'package:flutter_test/flutter_test.dart';
import 'package:muyu_client/auth/web_login_repository.dart';
import 'package:muyu_client/auth/web_session_controller.dart';

class FakeWebLoginApi implements WebLoginApi {
  int exchangeCalls = 0;
  String? exchangedProof;

  @override
  Future<WebLoginChallenge> createChallenge(String browserProof) async =>
      WebLoginChallenge(
        challengeId: 'challenge-1',
        qrPayload: '{}',
        origin: 'https://muyu.example',
        safetyCode: '123456',
        expiresAt: DateTime.now().add(const Duration(minutes: 2)),
      );

  @override
  Future<String> status(String challengeId) async => 'APPROVED';

  @override
  Future<void> exchange(String challengeId, String browserProof) async {
    exchangeCalls++;
    exchangedProof = browserProof;
  }
}

void main() {
  test('exchanges a browser proof once and discards it on logout', () async {
    final api = FakeWebLoginApi();
    final controller = WebSessionController(api);

    await controller.start();
    await controller.poll();
    await controller.poll();

    expect(api.exchangeCalls, 1);
    expect(api.exchangedProof, isNotEmpty);
    controller.logout();
    expect(controller.status, WebSessionStatus.signedOut);
  });
}
