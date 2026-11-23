import 'package:adapter_http_http/adapter_http_http.dart';
import 'package:test/test.dart';

import 'fakes.dart';

void main() {
  HttpReachabilityProbe probeWith(Responder responder) => HttpReachabilityProbe(
    baseUrl: 'https://api.example.com',
    path: '/health',
    client: FakeServer([responder]).client,
  );

  test('any HTTP response counts as reachable, even 503', () async {
    expect(
      await probeWith((_) => json(503, '{}')).isBackendReachable(),
      isTrue,
    );
  });

  test('a transport failure does not count', () async {
    expect(await probeWith(offline).isBackendReachable(), isFalse);
  });
}
