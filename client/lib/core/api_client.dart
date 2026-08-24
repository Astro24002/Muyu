import 'dart:convert';

import 'package:http/http.dart' as http;

import '../auth/token_store.dart';

class ApiException implements Exception {
  const ApiException({
    required this.statusCode,
    required this.code,
    required this.message,
    this.details,
  });

  final int statusCode;
  final String code;
  final String message;
  final Object? details;
}

class ApiClient {
  ApiClient({
    required String baseUrl,
    required this.httpClient,
    this.tokenStore,
  }) : _baseUrl = baseUrl.replaceFirst(RegExp(r'/$'), '');

  final String _baseUrl;
  final http.Client httpClient;
  final TokenStore? tokenStore;

  Future<Object?> request(
    String method,
    String path, {
    Map<String, Object?>? body,
    Map<String, String>? headers,
    bool authenticated = false,
    Future<void> Function()? refreshTokens,
  }) async {
    try {
      var response = await _send(
        method,
        path,
        body: body,
        requestHeaders: headers,
        authenticated: authenticated,
      );
      if (response.statusCode == 401 &&
          authenticated &&
          refreshTokens != null) {
        await refreshTokens();
        response = await _send(
          method,
          path,
          body: body,
          requestHeaders: headers,
          authenticated: true,
        );
      }
      if (response.statusCode < 200 || response.statusCode >= 300) {
        throw _exceptionFrom(response);
      }
      if (response.body.isEmpty) return null;
      return jsonDecode(response.body);
    } on ApiException {
      rethrow;
    } on http.ClientException {
      throw const ApiException(
        statusCode: 0,
        code: 'NETWORK_ERROR',
        message: '网络连接失败，请稍后重试',
      );
    }
  }

  Future<http.Response> _send(
    String method,
    String path, {
    Map<String, Object?>? body,
    Map<String, String>? requestHeaders,
    required bool authenticated,
  }) async {
    final headers = <String, String>{'accept': 'application/json'};
    if (requestHeaders != null) headers.addAll(requestHeaders);
    if (body != null) headers['content-type'] = 'application/json';
    if (authenticated) {
      final accessToken = await tokenStore?.readAccessToken();
      if (accessToken != null) headers['authorization'] = 'Bearer $accessToken';
    }
    final request = http.Request(method, Uri.parse('$_baseUrl$path'))
      ..headers.addAll(headers);
    if (body != null) request.body = jsonEncode(body);
    final streamed = await httpClient.send(request);
    return http.Response.fromStream(streamed);
  }

  ApiException _exceptionFrom(http.Response response) {
    try {
      final value = jsonDecode(response.body);
      if (value is Map<String, dynamic>) {
        return ApiException(
          statusCode: response.statusCode,
          code: value['code'] as String? ?? 'REQUEST_FAILED',
          message: value['message'] as String? ?? '请求失败',
          details: value['details'],
        );
      }
    } on FormatException {
      // Fall through to a stable client-side error.
    }
    return ApiException(
      statusCode: response.statusCode,
      code: 'REQUEST_FAILED',
      message: '请求失败，请稍后重试',
    );
  }
}
