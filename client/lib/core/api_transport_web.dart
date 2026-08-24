import 'package:http/http.dart' as http;

import 'api_transport.dart';

class WebApiTransport extends HttpApiTransport {
  WebApiTransport({required super.baseUrl, http.Client? client})
    : super(client: client ?? http.Client());
}
