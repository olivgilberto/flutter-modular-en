import 'dart:convert';
import 'dart:io';

/// The dev_backend as seen from the device (chapters 35 and 39): the API
/// port, to read and clear the state, and the control port, to take the API
/// down and bring it back. On the iOS simulator, 127.0.0.1 is the Mac's; on
/// the Android emulator, the integration script connects both ports with
/// adb reverse.
final class DevBackendClient {
  DevBackendClient({
    this.api = 'http://127.0.0.1:8080',
    this.control = 'http://127.0.0.1:8081',
  });

  final String api;
  final String control;
  final HttpClient _http = HttpClient();

  /// Erases accounts, sessions, and tasks: each test starts from scratch.
  Future<void> reset() => _send('POST', '$api/dev/reset');

  /// Closes the API port: the app starts seeing refused connections.
  Future<void> stop() => _send('POST', '$control/control/stop');

  /// Opens the API port again, with the same state.
  Future<void> start() => _send('POST', '$control/control/start');

  /// The tasks the server keeps, from any user.
  Future<List<Map<String, Object?>>> tasks() async {
    final body = await _send('GET', '$api/dev/state');
    final state = jsonDecode(body) as Map<String, Object?>;
    return (state['tasks']! as List).cast<Map<String, Object?>>();
  }

  /// The status, on the server, of the task with that title; `null` if it
  /// did not get there.
  Future<String?> statusOf(String title) async {
    for (final task in await tasks()) {
      if (task['title'] == title) return task['status'] as String?;
    }
    return null;
  }

  void close() => _http.close(force: true);

  Future<String> _send(String method, String url) async {
    final request = await _http.openUrl(method, Uri.parse(url));
    final response = await request.close();
    final body = await response.transform(utf8.decoder).join();
    if (response.statusCode >= 300) {
      throw HttpException('$method $url → ${response.statusCode}: $body');
    }
    return body;
  }
}
