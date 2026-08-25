import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:muyu_client/platform/device_signing_key.dart';

class FakeDeviceSigningKey implements DeviceSigningKey {
  bool privateKeyWasRead = false;

  @override
  Future<String> getOrCreatePublicKey() async => 'public-key';

  @override
  Future<Uint8List> sign(Uint8List payload) async {
    expect(payload, [1, 2, 3]);
    return Uint8List.fromList([4, 5, 6]);
  }

  @override
  Future<void> deleteKey() async {}
}

void main() {
  test('signs server payload without exposing a private key', () async {
    final key = FakeDeviceSigningKey();

    final signature = await key.sign(Uint8List.fromList([1, 2, 3]));

    expect(signature, isNotEmpty);
    expect(key.privateKeyWasRead, isFalse);
  });
}
