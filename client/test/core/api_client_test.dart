import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:muyu_client/core/api_client.dart';

void main() {
  test('contract survives custom headers, refresh and retry', () async {
    final requests = <http.Request>[];
    final api = ApiClient(
      baseUrl: 'https://example.test',
      httpClient: MockClient((request) async {
        requests.add(request);
        return http.Response('{}', requests.length == 1 ? 401 : 200);
      }),
    );
    await api.request(
      'POST',
      '/api/v1/tasks',
      body: {'request_id': 'stable'},
      headers: {'x-muyu-client-contract': 'old', 'Idempotency-Key': 'stable'},
      authenticated: true,
      refreshTokens: () async {
        await api.request('POST', '/api/v1/auth/refresh');
      },
    );
    expect(requests, hasLength(3));
    for (final request in requests) {
      expect(request.headers['x-muyu-client-contract'], '2026-09-v1');
    }
    expect(requests.first.body, requests.last.body);
    expect(requests.last.headers['Idempotency-Key'], 'stable');
  });
}
