import 'dart:io';

import 'package:http/http.dart' as http;
import 'package:http/io_client.dart';

/// The real network client: dart:io sockets, like Dio's default adapter,
/// with the connection timeout.
http.Client ioClient({required Duration connectionTimeout}) =>
    IOClient(HttpClient()..connectionTimeout = connectionTimeout);
