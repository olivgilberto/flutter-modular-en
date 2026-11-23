import 'dart:io';

import 'package:shelf/shelf.dart';
import 'package:shelf/shelf_io.dart' as shelf_io;

/// The API port, which closes and opens again without losing the state: a
/// backend that is down, from the app's point of view, refuses connections
/// (chapter 35). The terminal's `stop`/`start` and the chapter 39 control
/// port use the same piece.
final class ApiPort {
  ApiPort(this._handler, this.port);

  final Handler _handler;

  /// The port, always on the local interface.
  final int port;

  HttpServer? _server;

  bool get isOpen => _server != null;

  /// Opens the port. Returns `false` if it was already open.
  Future<bool> open() async {
    if (_server != null) return false;
    _server = await shelf_io.serve(
      _handler,
      InternetAddress.loopbackIPv4,
      port,
    );
    return true;
  }

  /// Closes the port and drops the open connections. Returns `false` if it
  /// was already closed.
  Future<bool> close() async {
    final server = _server;
    if (server == null) return false;
    _server = null;
    await server.close(force: true);
    return true;
  }
}
