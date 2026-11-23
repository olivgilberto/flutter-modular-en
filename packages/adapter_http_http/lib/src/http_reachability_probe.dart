import 'package:core/core.dart';
import 'package:http/http.dart' as http;

import 'io_client.dart';

/// [ReachabilityProbe] with the http package: a `HEAD` on the backend's
/// health endpoint, in a client of its own, with no token, no retry, and a
/// short timeout. Any HTTP response, even 4xx or 5xx, counts as reachable;
/// only transport failures do not.
final class HttpReachabilityProbe implements ReachabilityProbe {
  HttpReachabilityProbe({
    required String baseUrl,
    required this.path,
    Duration timeout = const Duration(seconds: 3),
    http.Client? client,
  }) : _baseUrl = baseUrl.endsWith('/')
           ? baseUrl.substring(0, baseUrl.length - 1)
           : baseUrl,
       _timeout = timeout,
       _client = client ?? ioClient(connectionTimeout: timeout);

  /// The health endpoint: light, unauthenticated, and never touching the database.
  final String path;
  final String _baseUrl;
  final Duration _timeout;
  final http.Client _client;

  @override
  Future<bool> isBackendReachable() async {
    try {
      await _client.head(Uri.parse('$_baseUrl$path')).timeout(_timeout);
      return true;
    } on Exception {
      return false;
    }
  }
}
