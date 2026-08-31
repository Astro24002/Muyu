import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:muyu_client/platform/device_signing_key.dart';
import 'package:muyu_client/screens/web_qr_scanner_screen.dart';
import 'package:muyu_client/workspace/device_authorization_repository.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('enables approval after a valid QR scan is loaded', (
    tester,
  ) async {
    final platform = FakeMobileScannerPlatform();
    final previousPlatform = MobileScannerPlatform.instance;
    MobileScannerPlatform.instance = platform;
    addTearDown(() => MobileScannerPlatform.instance = previousPlatform);

    await tester.pumpWidget(
      MaterialApp(
        home: WebQrScannerScreen(
          repository: FakeDeviceAuthorizationRepository(),
          signingKey: FakeDeviceSigningKey(),
        ),
      ),
    );
    await tester.pump();

    final capture = const BarcodeCapture(
      barcodes: [
        Barcode(
          rawValue: '{"version":1,"challenge_id":"challenge-1","scan_nonce":"nonce-1","origin":"https://muyu.bkverse.space","expires_at":"2099-01-01T00:00:00Z"}',
        ),
      ],
    );
    tester.widget<MobileScanner>(find.byType(MobileScanner)).onDetect!(capture);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    expect(find.text('批准登录'), findsOneWidget);
    expect(find.text('处理中...'), findsNothing);
    final approve = tester.widget<FilledButton>(
      find.widgetWithText(FilledButton, '批准登录'),
    );
    expect(approve.onPressed, isNotNull);
    await tester.pumpWidget(const SizedBox());
    await tester.pump();
  });
}

class FakeDeviceAuthorizationRepository
    implements DeviceAuthorizationRepository {
  @override
  Future<List<DeviceAuthorizationRequest>> listRequests() async => const [];

  @override
  Future<void> reject(String requestId) async {}

  @override
  Future<DeviceAuthorizationRequest> scanWebQr(String qrPayload) async =>
      DeviceAuthorizationRequest(
        id: 'challenge-1',
        safetyCode: '123456',
        expiresAt: DateTime.utc(2099),
        status: 'PENDING',
        origin: 'https://muyu.bkverse.space',
        signaturePayload: 'c2lnbmF0dXJl',
      );

  @override
  Future<DeviceAuthorizationRequest> createDeviceRequest(String publicKey) =>
      throw UnimplementedError();

  @override
  Future<DeviceAuthorizationRequest> beginApproval(String requestId) =>
      throw UnimplementedError();

  @override
  Future<void> approve(
    String requestId, {
    required DeviceSigningKey signingKey,
    required String signaturePayload,
  }) => throw UnimplementedError();

  @override
  Future<void> approveWebLogin(
    DeviceAuthorizationRequest request, {
    required DeviceSigningKey signingKey,
  }) => throw UnimplementedError();
}

class FakeDeviceSigningKey implements DeviceSigningKey {
  @override
  Future<String> getOrCreatePublicKey() async => 'public-key';

  @override
  Future<Uint8List> sign(Uint8List payload) async => Uint8List(0);

  @override
  Future<void> deleteKey() async {}
}

class FakeMobileScannerPlatform extends MobileScannerPlatform {
  final StreamController<BarcodeCapture> _barcodeController =
      StreamController<BarcodeCapture>.broadcast();

  @override
  Stream<BarcodeCapture?> get barcodesStream => _barcodeController.stream;

  @override
  Stream<TorchState> get torchStateStream =>
      Stream.value(TorchState.unavailable);

  @override
  Stream<double> get zoomScaleStateStream => Stream.value(1);

  @override
  Future<MobileScannerViewAttributes> start(StartOptions startOptions) async =>
      const MobileScannerViewAttributes(
        cameraDirection: CameraFacing.back,
        currentTorchMode: TorchState.unavailable,
        size: Size(200, 200),
        numberOfCameras: 1,
      );

  @override
  Widget buildCameraView() => const SizedBox.square(dimension: 100);

  @override
  Future<void> stop() async {}

  void addBarcode(BarcodeCapture capture) => _barcodeController.add(capture);

  @override
  Future<void> dispose() => _barcodeController.close();
}
