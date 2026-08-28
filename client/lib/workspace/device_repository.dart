import '../core/api_client.dart';

class DeviceSummary {
  const DeviceSummary({
    required this.id,
    required this.platform,
    required this.label,
    required this.status,
    bool? canWrite,
    required this.isCurrent,
    required this.createdAt,
    required this.enrolledAt,
    required this.revokedAt,
  }) : canWrite = canWrite ?? status == 'ACTIVE' || status == 'VERIFIED';

  final String id;
  final String platform;
  final String? label;
  final String status;
  final bool canWrite;
  final bool isCurrent;
  final DateTime createdAt;
  final DateTime? enrolledAt;
  final DateTime? revokedAt;

  factory DeviceSummary.fromJson(Map<String, dynamic> json) => DeviceSummary(
    id: json['id'] as String,
    platform: json['platform'] as String? ?? 'ANDROID',
    label: json['label'] as String?,
    status: json['status'] as String,
    canWrite: json['can_write'] as bool?,
    isCurrent: json['is_current'] as bool? ?? false,
    createdAt: DateTime.parse(json['created_at'] as String),
    enrolledAt: _date(json['enrolled_at']),
    revokedAt: _date(json['revoked_at']),
  );

  static DateTime? _date(Object? value) =>
      value == null ? null : DateTime.parse(value as String);
}

class DeviceRepositoryFailure implements Exception {
  const DeviceRepositoryFailure(this.message, {this.code, this.statusCode});

  final String message;
  final String? code;
  final int? statusCode;

  @override
  String toString() => message;
}

abstract interface class DeviceRepository {
  Future<List<DeviceSummary>> listDevices();
}

class HttpDeviceRepository implements DeviceRepository {
  HttpDeviceRepository(this._api);

  final ApiClient _api;

  @override
  Future<List<DeviceSummary>> listDevices() async {
    try {
      final value = await _api.request(
        'GET',
        '/api/v1/devices',
        authenticated: true,
      );
      return (value as List<dynamic>)
          .map((item) => DeviceSummary.fromJson(item as Map<String, dynamic>))
          .toList(growable: false);
    } on ApiException catch (error) {
      throw DeviceRepositoryFailure(
        error.message,
        code: error.code,
        statusCode: error.statusCode,
      );
    }
  }
}
