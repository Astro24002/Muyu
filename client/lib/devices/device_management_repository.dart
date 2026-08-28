import '../core/api_client.dart';
import '../workspace/device_repository.dart';

abstract interface class DeviceManagementRepository {
  Future<List<DeviceSummary>> list();

  Future<DeviceSummary> revoke(String deviceId);
}

class DeviceManagementFailure implements Exception {
  const DeviceManagementFailure(this.message, {this.code, this.statusCode});

  final String message;
  final String? code;
  final int? statusCode;

  @override
  String toString() => message;
}

class HttpDeviceManagementRepository implements DeviceManagementRepository {
  HttpDeviceManagementRepository(this._api);

  final ApiClient _api;

  @override
  Future<List<DeviceSummary>> list() async {
    try {
      final value = await _api.request(
        'GET',
        '/api/v1/devices',
        authenticated: true,
      );
      if (value is! List<dynamic>) {
        throw const FormatException('device list is not an array');
      }
      return value
          .whereType<Map<String, dynamic>>()
          .map(DeviceSummary.fromJson)
          .where((device) => device.platform.toUpperCase() == 'ANDROID')
          .toList(growable: false);
    } on ApiException catch (error) {
      throw DeviceManagementFailure(
        error.message,
        code: error.code,
        statusCode: error.statusCode,
      );
    } on FormatException {
      throw const DeviceManagementFailure('设备列表格式无效');
    }
  }

  @override
  Future<DeviceSummary> revoke(String deviceId) async {
    try {
      final value = await _api.request(
        'POST',
        '/api/v1/devices/$deviceId/revoke',
        authenticated: true,
      );
      if (value is! Map<String, dynamic>) {
        throw const FormatException('device response is not an object');
      }
      return DeviceSummary.fromJson(value);
    } on ApiException catch (error) {
      throw DeviceManagementFailure(
        error.message,
        code: error.code,
        statusCode: error.statusCode,
      );
    } on FormatException {
      throw const DeviceManagementFailure('设备响应格式无效');
    }
  }
}
