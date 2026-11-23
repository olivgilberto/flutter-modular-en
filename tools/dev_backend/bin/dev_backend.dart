import 'dart:convert';
import 'dart:io';

import 'package:dev_backend/dev_backend.dart';
import 'package:shelf/shelf_io.dart' as shelf_io;

/// `dart run tools/dev_backend/bin/dev_backend.dart [--port 8080]
/// [--token-minutes 15] [--control-port 8081]`, from the workspace root
/// (chapter 35). It only listens on the local interface: nothing outside
/// this machine reaches it.
///
/// In the terminal, `stop` closes the port without losing the state, like a
/// backend that is down, and `start` opens it again. With `--control-port`,
/// the same two actions also arrive over HTTP, on a separate port, for the
/// chapter 39 integration tests.
Future<void> main(List<String> args) async {
  final port = _option(args, '--port') ?? 8080;
  final tokenMinutes = _option(args, '--token-minutes') ?? 15;
  final controlPort = _option(args, '--control-port');
  final state = DevBackendState(tokenTtl: Duration(minutes: tokenMinutes));
  void log(String line) => stdout.writeln(_stamp(line));
  final api = ApiPort(devBackendHandler(state, log: log), port);
  await api.open();
  stdout
    ..writeln('dev_backend at http://127.0.0.1:$port')
    ..writeln(
      'Everything in memory: ending the process erases accounts and tasks.',
    )
    ..writeln(
      'Type "stop" to take the backend down and "start" to '
      'bring it back, with the same state.',
    )
    ..writeln(
      '"Someone else" routes: GET /dev/state, '
      'POST /dev/tasks/<id>/edit, DELETE /dev/tasks/<id>, '
      'POST /dev/reject-next, POST /dev/omit-version-next, '
      'POST /dev/expire-tokens, POST /dev/reset',
    );
  if (controlPort != null) {
    await shelf_io.serve(
      controlHandler(api, log: log),
      InternetAddress.loopbackIPv4,
      controlPort,
    );
    stdout.writeln(
      'control at http://127.0.0.1:$controlPort: POST /control/stop, '
      'POST /control/start, GET /control/status',
    );
  }

  await for (final line
      in stdin.transform(utf8.decoder).transform(const LineSplitter())) {
    switch (line.trim()) {
      case 'stop' when api.isOpen:
        await api.close();
        log('down: connections refused');
      case 'start' when !api.isOpen:
        await api.open();
        log('back at http://127.0.0.1:$port');
      case '':
        break;
      default:
        stdout.writeln('Commands: stop, start.');
    }
  }
}

int? _option(List<String> args, String name) {
  final index = args.indexOf(name);
  if (index < 0 || index + 1 >= args.length) return null;
  return int.tryParse(args[index + 1]);
}

String _stamp(String line) {
  final now = DateTime.now();
  String two(int n) => n.toString().padLeft(2, '0');
  return '${two(now.hour)}:${two(now.minute)}:${two(now.second)} $line';
}
