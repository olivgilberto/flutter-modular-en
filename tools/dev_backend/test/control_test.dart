import 'dart:convert';
import 'dart:io';

import 'package:dev_backend/dev_backend.dart';
import 'package:shelf/shelf.dart';
import 'package:test/test.dart';

/// The control port (chapter 39): the API really closes, with refused
/// connections, and comes back with the same state.
void main() {
  late int port;
  late ApiPort api;
  late Handler control;
  late HttpClient client;

  setUp(() async {
    // A free port, picked by the system and released right away: ApiPort
    // must always reopen on the same one.
    final probe = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
    port = probe.port;
    await probe.close();
    api = ApiPort(devBackendHandler(DevBackendState()), port);
    await api.open();
    control = controlHandler(api);
    client = HttpClient();
  });

  tearDown(() async {
    client.close(force: true);
    await api.close();
  });

  Future<Map<String, Object?>> send(String method, String path) async {
    final response = await control(
      Request(method, Uri.parse('http://127.0.0.1$path')),
    );
    expect(response.statusCode, 200);
    return jsonDecode(await response.readAsString()) as Map<String, Object?>;
  }

  Future<int> health() async {
    final request = await client.getUrl(
      Uri.parse('http://127.0.0.1:$port/v1/health'),
    );
    final response = await request.close();
    await response.drain<void>();
    return response.statusCode;
  }

  test(
    'stop refuses connections, and start comes back with the same state',
    () async {
      final register = await client.postUrl(
        Uri.parse('http://127.0.0.1:$port/v1/auth/register'),
      );
      register.headers.contentType = ContentType.json;
      register.write(
        jsonEncode({
          'name': 'Ana',
          'email': 'ana@example.com',
          'password': 'correct-horse-battery-staple',
        }),
      );
      expect((await register.close()).statusCode, 201);

      expect(await send('POST', '/control/stop'), {'open': false});
      await expectLater(health(), throwsA(isA<SocketException>()));
      expect(await send('GET', '/control/status'), {'open': false});

      expect(await send('POST', '/control/start'), {'open': true});
      expect(await health(), 200);
      final again = await client.postUrl(
        Uri.parse('http://127.0.0.1:$port/v1/auth/register'),
      );
      again.headers.contentType = ContentType.json;
      again.write(
        jsonEncode({
          'name': 'Ana',
          'email': 'ana@example.com',
          'password': 'correct-horse-battery-staple',
        }),
      );
      final response = await again.close();
      await response.drain<void>();
      // The account is still there: the same email is refused.
      expect(response.statusCode, 422);
    },
  );

  test('repeated stop and start change nothing', () async {
    await send('POST', '/control/start');
    expect(await health(), 200);
    await send('POST', '/control/stop');
    expect(await send('POST', '/control/stop'), {'open': false});
  });
}
