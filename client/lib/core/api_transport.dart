import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

import '../models/workspace_change.dart';

class ApiRequest {
  const ApiRequest(
    this.method,
    this.path, {
    this.body,
    this.headers = const {},
  });

  final String method;
  final String path;
  final Map<String, Object?>? body;
  final Map<String, String> headers;
}

class ApiResponse {
  const ApiResponse({
    required this.statusCode,
    required this.body,
    required this.headers,
  });

  final int statusCode;
  final Object? body;
  final Map<String, String> headers;
}

abstract interface class ApiTransport {
  Future<ApiResponse> send(ApiRequest request);

  Stream<WorkspaceChanged> openWorkspaceHints();
}

abstract class HttpApiTransport implements ApiTransport {
  HttpApiTransport({required this.baseUrl, required this.client});

  final String baseUrl;
  final http.Client client;

  @override
  Future<ApiResponse> send(ApiRequest request) async {
    final headers = <String, String>{
      'accept': 'application/json',
      ...request.headers,
    };
    if (request.body != null) headers['content-type'] = 'application/json';
    final response = await client.send(
      http.Request(request.method, Uri.parse('$baseUrl${request.path}'))
        ..headers.addAll(headers)
        ..body = request.body == null ? '' : jsonEncode(request.body),
    );
    final result = await http.Response.fromStream(response);
    Object? body;
    if (result.body.isNotEmpty) body = jsonDecode(result.body);
    return ApiResponse(
      statusCode: result.statusCode,
      body: body,
      headers: result.headers,
    );
  }

  @override
  Stream<WorkspaceChanged> openWorkspaceHints() => const Stream.empty();
}
