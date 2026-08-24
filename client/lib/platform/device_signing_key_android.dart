import 'dart:convert';

import 'package:flutter/services.dart';

import 'device_signing_key.dart';

class AndroidDeviceSigningKey implements DeviceSigningKey {
  AndroidDeviceSigningKey([MethodChannel? channel])
    : _channel = channel ?? const MethodChannel('muyu/device-signing-key');

  final MethodChannel _channel;

  @override
  Future<String> getOrCreatePublicKey() async {
    final value = await _channel.invokeMethod<String>('getOrCreatePublicKey');
    if (value == null || value.isEmpty) {
      throw const DeviceSigningKeyUnavailable('设备公钥为空');
    }
    return value;
  }

  @override
  Future<Uint8List> sign(Uint8List payload) async {
    final value = await _channel.invokeMethod<String>('sign', {
      'payload': base64Encode(payload),
    });
    if (value == null || value.isEmpty) {
      throw const DeviceSigningKeyUnavailable('设备签名为空');
    }
    return base64Decode(value);
  }

  @override
  Future<void> deleteKey() => _channel.invokeMethod<void>('deleteKey');
}

DeviceSigningKey createDeviceSigningKey() => AndroidDeviceSigningKey();
