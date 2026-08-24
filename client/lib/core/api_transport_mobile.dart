import 'package:http/http.dart' as http;

import '../auth/mobile_session_store.dart';
import 'api_transport.dart';

class MobileApiTransport extends HttpApiTransport {
  MobileApiTransport({
    required super.baseUrl,
    required this.sessionStore,
    http.Client? client,
  }) : super(client: client ?? http.Client());

  final MobileSessionStore sessionStore;

  @override
  Future<ApiResponse> send(ApiRequest request) async {
    final session = await sessionStore.read();
    final headers = <String, String>{...request.headers};
    if (session != null) {
      headers['authorization'] = 'Bearer ${session.accessToken}';
    }
    return super.send(
      ApiRequest(
        request.method,
        request.path,
        body: request.body,
        headers: headers,
      ),
    );
  }
}
