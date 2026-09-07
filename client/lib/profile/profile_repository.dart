import '../core/api_client.dart';
import '../models/user.dart';

abstract interface class ProfileRepository {
  Future<User> updateDisplayName(String? displayName);
}

class ProfileRepositoryFailure implements Exception {
  const ProfileRepositoryFailure(this.message, {this.code, this.statusCode});

  final String message;
  final String? code;
  final int? statusCode;

  @override
  String toString() => message;
}

class HttpProfileRepository implements ProfileRepository {
  HttpProfileRepository(this._api);

  final ApiClient _api;

  @override
  Future<User> updateDisplayName(String? displayName) async {
    try {
      final value = await _api.request(
        'PATCH',
        '/api/v1/me',
        body: {'display_name': displayName},
        authenticated: true,
      );
      if (value is! Map<String, dynamic>) {
        throw const FormatException('profile response is not an object');
      }
      return User.fromJson(value);
    } on ApiException catch (error) {
      throw ProfileRepositoryFailure(
        error.message,
        code: error.code,
        statusCode: error.statusCode,
      );
    } on FormatException {
      throw const ProfileRepositoryFailure('个人资料响应格式无效');
    }
  }
}
