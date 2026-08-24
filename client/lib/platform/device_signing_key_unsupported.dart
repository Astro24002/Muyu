import 'dart:typed_data';

import 'device_signing_key.dart';

DeviceSigningKey createDeviceSigningKey() => UnsupportedDeviceSigningKey();

class UnsupportedDeviceSigningKey implements DeviceSigningKey {
  @override
  Future<String> getOrCreatePublicKey() async =>
      throw const DeviceSigningKeyUnavailable();

  @override
  Future<Uint8List> sign(Uint8List payload) async =>
      throw const DeviceSigningKeyUnavailable();

  @override
  Future<void> deleteKey() async => throw const DeviceSigningKeyUnavailable();
}
