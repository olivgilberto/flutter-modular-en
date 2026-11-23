import 'dart:convert';

import 'package:shelf/shelf.dart';
import 'package:shelf_router/shelf_router.dart';

import 'api_port.dart';

/// The control port's routes (chapter 39): an integration test, running on
/// the device, takes the API down and brings it back with nobody at the
/// terminal. The control port is a different one, because the API's really closes.
///
/// - `POST /control/stop`: closes the API port (refused connections);
/// - `POST /control/start`: opens it again, with the same state;
/// - `GET /control/status`: says whether the API is up.
///
/// All three answer `{"open": true|false}`.
Handler controlHandler(ApiPort api, {void Function(String line)? log}) {
  Response status() => Response.ok(
    jsonEncode({'open': api.isOpen}),
    headers: {'content-type': 'application/json'},
  );

  final router = Router()
    ..post('/control/stop', (Request _) async {
      if (await api.close()) log?.call('control: down');
      return status();
    })
    ..post('/control/start', (Request _) async {
      if (await api.open()) log?.call('control: back');
      return status();
    })
    ..get('/control/status', (Request _) => status());
  return router.call;
}
