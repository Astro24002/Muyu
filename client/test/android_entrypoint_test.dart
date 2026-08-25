import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('Flutter entrypoint only contains Android runtime wiring', () {
    final main = File('lib/main.dart').readAsStringSync();
    final app = File('lib/app.dart').readAsStringSync();
    final httpClient = File('lib/platform/api_http_client.dart')
        .readAsStringSync();

    expect(main, isNot(contains('kIsWeb')));
    expect(main, isNot(contains('WebSessionController')));
    expect(app, isNot(contains('AppPlatform.web')));
    expect(app, isNot(contains('WebSessionController')));
    expect(httpClient, isNot(contains('dart.library.js_interop')));
    expect(httpClient, isNot(contains('BrowserClient')));
  });
}
