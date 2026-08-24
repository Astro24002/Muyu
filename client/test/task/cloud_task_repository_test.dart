import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:muyu_client/core/api_client.dart';
import 'package:muyu_client/task/cloud_task_repository.dart';

void main() {
  test(
    'mutation sends request id and field versions to authoritative API',
    () async {
      late http.Request request;
      final repository = CloudTaskRepository(
        ApiClient(
          baseUrl: 'https://api.example',
          httpClient: MockClient((incoming) async {
            request = incoming;
            return http.Response(jsonEncode({'id': 'task-1'}), 200);
          }),
        ),
      );

      await repository.update(
        'task-1',
        fields: {'title': 'New title'},
        fieldVersions: {'title': 4},
        requestId: 'request-1',
      );

      final body = jsonDecode(request.body) as Map<String, dynamic>;
      expect(request.url.path, '/api/v1/tasks/task-1');
      expect(request.headers['x-request-id'], 'request-1');
      expect(body['field_versions'], {'title': 4});
      expect(body['title'], 'New title');
    },
  );
}
