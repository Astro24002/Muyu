import 'dart:typed_data';

import 'device_signing_key_android.dart' as platform;

abstract interface class DeviceSigningKey {
  Future<String> getOrCreatePublicKey();

  Future<Uint8List> sign(Uint8List payload);

  Future<void> deleteKey();
}

class DeviceSigningKeyUnavailable implements Exception {
  const DeviceSigningKeyUnavailable([this.message = '设备签名能力不可用']);

  final String message;

  @override
  String toString() => message;
}

DeviceSigningKey createDeviceSigningKey() => platform.createDeviceSigningKey();
