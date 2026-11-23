import 'dart:convert';
import 'dart:io';

import 'package:shelf/shelf.dart';
import 'package:shelf_router/shelf_router.dart';

import 'dev_backend_state.dart';

/// The contract routes (docs/modules/auth_module.md and tasks_module.md) and
/// the development ones, under `/dev`, which play "someone else".
/// Each request goes to the [log] on one line, with no body and no token.
Handler devBackendHandler(
  DevBackendState state, {
  void Function(String line)? log,
}) {
  final routes = _Routes(state);
  final router = Router()
    // get also serves the reachability probe's HEAD, with no body.
    ..get('/v1/health', routes.health)
    ..post('/v1/auth/register', routes.register)
    ..post('/v1/auth/sign-in', routes.signIn)
    ..post('/v1/auth/refresh', routes.refresh)
    ..post('/v1/auth/sign-out', routes.signOut)
    ..get('/v1/tasks', routes.listTasks)
    ..get('/v1/tasks/<id>', routes.getTask)
    ..put('/v1/tasks/<id>', routes.createTask)
    ..patch('/v1/tasks/<id>', routes.updateTask)
    ..get('/dev/state', routes.devState)
    ..post('/dev/tasks/<id>/edit', routes.devEdit)
    ..delete('/dev/tasks/<id>', routes.devDelete)
    ..post('/dev/reject-next', routes.devRejectNext)
    ..post('/dev/omit-version-next', routes.devOmitVersionNext)
    ..post('/dev/expire-tokens', routes.devExpireTokens)
    ..post('/dev/reset', routes.devReset);
  final pipeline = const Pipeline();
  return (log == null ? pipeline : pipeline.addMiddleware(_logLines(log)))
      .addHandler(router.call);
}

Middleware _logLines(void Function(String line) log) =>
    (inner) => (request) async {
      final response = await inner(request);
      log('${request.method} /${request.url} → ${response.statusCode}');
      return response;
    };

Response _json(int status, Object? body) => Response(
  status,
  body: body == null ? null : jsonEncode(body),
  headers: {
    if (body != null) HttpHeaders.contentTypeHeader: 'application/json',
  },
);

Response _error(int status, String code) => _json(status, {'code': code});

final class _Routes {
  _Routes(this._state);

  final DevBackendState _state;

  Response health(Request request) => _json(200, {'status': 'ok'});

  // ---- Authentication -----------------------------------------------

  Future<Response> register(Request request) async {
    final body = await _readJson(request);
    if (body case {
      'name': String name,
      'email': String email,
      'password': String password,
    } when name.trim().isNotEmpty && email.contains('@')) {
      final key = email.trim().toLowerCase();
      if (_state.users.containsKey(key)) {
        return _error(422, 'email_already_registered');
      }
      if (_weakPasswords.contains(password)) {
        return _error(422, 'weak_password');
      }
      final user = DevUser(
        id: _state.newUserId(),
        name: name.trim(),
        email: key,
        password: password,
        createdAt: _state.now(),
      );
      _state.users[key] = user;
      return _json(201, _authBody(user, _state.openSession(user)));
    }
    return _error(400, 'invalid_body');
  }

  Future<Response> signIn(Request request) async {
    final body = await _readJson(request);
    if (body case {'email': String email, 'password': String password}) {
      final user = _state.users[email.trim().toLowerCase()];
      if (user == null || user.password != password) {
        return _error(401, 'invalid_credentials');
      }
      return _json(200, _authBody(user, _state.openSession(user)));
    }
    return _error(400, 'invalid_body');
  }

  /// Trades both tokens; the old refresh token stops being valid.
  Future<Response> refresh(Request request) async {
    final body = await _readJson(request);
    if (body case {'refreshToken': String token}) {
      for (final session in _state.sessions) {
        if (session.refreshToken == token) {
          session
            ..accessToken = _state.newToken()
            ..refreshToken = _state.newToken()
            ..expiresAt = _state.now().add(_state.tokenTtl);
          return _json(200, {
            'accessToken': session.accessToken,
            'refreshToken': session.refreshToken,
            'expiresIn': _state.tokenTtl.inSeconds,
          });
        }
      }
      return _error(401, 'invalid_refresh_token');
    }
    return _error(400, 'invalid_body');
  }

  /// Always 204: the app erases the local session either way.
  Response signOut(Request request) {
    final token = _bearer(request);
    _state.sessions.removeWhere((session) => session.accessToken == token);
    return Response(204);
  }

  Map<String, Object?> _authBody(DevUser user, DevSession session) => {
    'user': user.toJson(),
    'accessToken': session.accessToken,
    'refreshToken': session.refreshToken,
    'expiresIn': _state.tokenTtl.inSeconds,
  };

  // ---- Tasks ----------------------------------------------------------

  Response listTasks(Request request) => _authenticated(request, (user) {
    final query = request.url.queryParameters;
    if (query['status'] != 'active') return _error(400, 'unsupported_status');
    final limit = (int.tryParse(query['limit'] ?? '') ?? 100).clamp(1, 100);
    final start = int.tryParse(query['cursor'] ?? '0') ?? 0;
    final active = [
      for (final task in _state.tasks.values)
        if (task.ownerId == user.id && task.status != 'archived') task,
    ]..sort(_byCreation);
    final page = active.skip(start).take(limit).toList();
    final next = start + page.length;
    return _json(200, {
      'items': [for (final task in page) task.toJson()],
      'nextCursor': next < active.length ? '$next' : null,
    });
  });

  Response getTask(Request request, String id) =>
      _authenticated(request, (user) {
        final task = _state.tasks[id];
        if (task == null || task.ownerId != user.id) {
          return _error(404, 'not_found');
        }
        return _json(200, task.toJson());
      });

  /// Creation with the app's id. Repeated by the same operation, it returns
  /// the task; with an id already used by another operation, it is a conflict.
  Future<Response> createTask(Request request, String id) =>
      _write(request, (user, body) {
        final operationId = body['operationId'];
        if (operationId is! String) return _error(400, 'invalid_body');
        final existing = _state.tasks[id];
        if (existing != null) {
          if (existing.ownerId == user.id &&
              existing.appliedOperations.contains(operationId)) {
            return _json(200, existing.toJson());
          }
          return _error(409, 'version_conflict');
        }
        final title = _validTitle(body['title']);
        final status = body['status'];
        final createdAt = DateTime.tryParse('${body['createdAt']}');
        if (title == null) return _error(422, 'invalid_title');
        if (!_statuses.contains(status) || createdAt == null) {
          return _error(400, 'invalid_body');
        }
        final task = DevTask(
          id: id,
          ownerId: user.id,
          title: title,
          status: status as String,
          createdAt: createdAt.toUtc(),
        )..appliedOperations.add(operationId);
        _state.tasks[id] = task;
        return _json(201, task.toJson());
      });

  /// Update and archiving, with the version the app saw.
  Future<Response> updateTask(Request request, String id) =>
      _write(request, (user, body) {
        final operationId = body['operationId'];
        final baseVersion = body['baseVersion'];
        if (operationId is! String || baseVersion is! int) {
          return _error(400, 'invalid_body');
        }
        final task = _state.tasks[id];
        if (task == null || task.ownerId != user.id) {
          return _error(404, 'not_found');
        }
        if (task.appliedOperations.contains(operationId)) {
          return _json(200, task.toJson());
        }
        if (baseVersion != task.version) {
          return _error(409, 'version_conflict');
        }
        final hasTitle = body.containsKey('title');
        final title = hasTitle ? _validTitle(body['title']) : null;
        if (hasTitle && title == null) return _error(422, 'invalid_title');
        final status = body['status'];
        if (status != null && !_statuses.contains(status)) {
          return _error(400, 'invalid_body');
        }
        task
          ..title = title ?? task.title
          ..status = (status as String?) ?? task.status
          ..version += 1
          ..appliedOperations.add(operationId);
        return _json(200, task.toJson());
      });

  /// What both writes have in common: the user, the refusal requested by the
  /// development route, and the Idempotency-Key. The same key with the same
  /// body gets the stored response; with another body, 422, as in the
  /// header's draft.
  Future<Response> _write(
    Request request,
    Response Function(DevUser user, Map<String, Object?> body) action,
  ) async {
    final raw = await request.readAsString();
    final user = _userOf(request);
    if (user == null) return _error(401, 'invalid_token');
    final key = request.headers['idempotency-key'];
    final slot = key == null ? null : '${user.id}/$key';
    if (_state.idempotency[slot] case final stored?) {
      return stored.requestBody == raw
          ? _json(stored.status, stored.body)
          : _error(422, 'idempotency_key_reused');
    }
    Response response;
    if (_state.rejectNext case final rejection?) {
      _state.rejectNext = null;
      response = _error(rejection.status, rejection.code);
    } else {
      final body = _decode(raw);
      response = body is Map<String, Object?>
          ? action(user, body)
          : _error(400, 'invalid_body');
      if (_state.omitVersionNext && response.statusCode < 300) {
        _state.omitVersionNext = false;
        final accepted = jsonDecode(await response.readAsString());
        if (accepted is Map<String, Object?>) accepted.remove('version');
        response = _json(response.statusCode, accepted);
      }
    }
    if (slot == null || response.statusCode >= 500) return response;
    // The response is read so it can be stored and built again.
    final text = await response.readAsString();
    final body = text.isEmpty ? null : jsonDecode(text);
    _state.idempotency[slot] = DevStoredResponse(
      raw,
      response.statusCode,
      body,
    );
    return _json(response.statusCode, body);
  }

  // ---- Development: "someone else" ----------------------------------

  Response devState(Request request) => _json(200, {
    'users': [for (final user in _state.users.values) user.toJson()],
    'tasks': [
      for (final task in _state.tasks.values)
        {...task.toJson(), 'ownerId': task.ownerId},
    ],
  });

  /// Someone else changes the task: the version goes up, with no app operation.
  Future<Response> devEdit(Request request, String id) async {
    final task = _state.tasks[id];
    if (task == null) return _error(404, 'not_found');
    final body = _decode(await request.readAsString());
    if (body is! Map<String, Object?>) return _error(400, 'invalid_body');
    final title = body.containsKey('title') ? _validTitle(body['title']) : null;
    if (body.containsKey('title') && title == null) {
      return _error(422, 'invalid_title');
    }
    final status = body['status'];
    if (status != null && !_statuses.contains(status)) {
      return _error(400, 'invalid_body');
    }
    task
      ..title = title ?? task.title
      ..status = (status as String?) ?? task.status
      ..version += 1;
    return _json(200, task.toJson());
  }

  /// Someone else deletes the task.
  Response devDelete(Request request, String id) =>
      _state.tasks.remove(id) == null
      ? _error(404, 'not_found')
      : Response(204);

  Future<Response> devRejectNext(Request request) async {
    final body = _decode(await request.readAsString());
    _state.rejectNext = switch (body) {
      {'status': int status, 'code': String code} => DevRejection(
        status: status,
        code: code,
      ),
      {'code': String code} => DevRejection(code: code),
      _ => const DevRejection(),
    };
    return Response(204);
  }

  /// The next accepted write answers without the version (chapter 38).
  Response devOmitVersionNext(Request request) {
    _state.omitVersionNext = true;
    return Response(204);
  }

  Response devExpireTokens(Request request) {
    _state.expireTokens();
    return Response(204);
  }

  Response devReset(Request request) {
    _state.reset();
    return Response(204);
  }

  // ---- Helpers --------------------------------------------------------

  Response _authenticated(Request request, Response Function(DevUser) action) {
    final user = _userOf(request);
    return user == null ? _error(401, 'invalid_token') : action(user);
  }

  /// The user of a valid access token.
  DevUser? _userOf(Request request) {
    final token = _bearer(request);
    final session = token == null ? null : _state.sessionOf(token);
    return session == null ? null : _state.userById(session.userId);
  }

  static String? _bearer(Request request) {
    final header = request.headers[HttpHeaders.authorizationHeader];
    if (header == null || !header.startsWith('Bearer ')) return null;
    return header.substring('Bearer '.length);
  }

  static Future<Object?> _readJson(Request request) async =>
      _decode(await request.readAsString());

  static Object? _decode(String raw) {
    if (raw.isEmpty) return null;
    try {
      return jsonDecode(raw);
    } on FormatException {
      return null;
    }
  }

  /// The same rule as the app's TaskTitle: spaces at the ends trimmed, from
  /// 1 to 200 code points.
  static String? _validTitle(Object? value) {
    if (value is! String) return null;
    final title = value.trim();
    final length = title.runes.length;
    return length == 0 || length > 200 ? null : title;
  }

  static int _byCreation(DevTask a, DevTask b) {
    final byDate = a.createdAt.compareTo(b.createdAt);
    return byDate != 0 ? byDate : a.id.compareTo(b.id);
  }

  static const _statuses = {'open', 'done', 'archived'};

  /// The passwords the backend rejects as compromised. A real backend
  /// checks a list of leaked passwords (chapter 20).
  static const _weakPasswords = {'very-weak-password', '123456789012345'};
}
