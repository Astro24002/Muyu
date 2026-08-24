import 'package:flutter_test/flutter_test.dart';
import 'package:muyu_client/auth/web_login_repository.dart';
import 'package:muyu_client/auth/web_session_controller.dart';
import 'package:muyu_client/screens/web_qr_login_screen.dart';

class _ApprovedWebApi implements WebLoginApi {
  var exchangeCalled = false;

  @override
  Future<WebLoginChallenge> createChallenge(String browserProof) async =>
      WebLoginChallenge(
        challengeId: 'challenge-1',
        qrPayload: '{"version":1}',
        origin: 'https://muyu.example',
        safetyCode: '123456',
        expiresAt: DateTime.now().add(const Duration(minutes: 2)),
      );

  @override
  Future<String> status(String challengeId) async => 'APPROVED';

  @override
  Future<void> exchange(String challengeId, String browserProof) async {
    exchangeCalled = true;
  }
}

void main() {
  testWidgets('web QR screen exchanges an approved challenge', (tester) async {
    final api = _ApprovedWebApi();
    final controller = WebSessionController(api);
    await tester.pumpWidget(WebQrLoginScreen(controller: controller));
    await tester.pumpAndSettle();

    expect(find.text('安全码 123456'), findsOneWidget);
    await tester.tap(find.text('检查授权状态'));
    await tester.pumpAndSettle();

    expect(api.exchangeCalled, isTrue);
    expect(controller.status, WebSessionStatus.signedIn);
  });
}
