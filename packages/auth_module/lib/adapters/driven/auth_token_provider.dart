import 'dart:async';

import 'package:core/core.dart';

import 'auth_session_store.dart';
import 'models/auth_model.dart';
import 'services/auth_session_local_service.dart';
import 'services/auth_token_remote_service.dart';

/// The app's session. To the `core`, a [TokenProvider]: it signs requests
/// and refreshes the token. To the module, an [AuthSessionStore]: it stores
/// the session at sign-in and erases it at logout. One instance, two roles
/// (chapter 8), registered by the module's function.
final class AuthTokenProvider implements TokenProvider, AuthSessionStore {
  AuthTokenProvider({
    required AuthSessionLocalService local,
    required AuthTokenRemoteService remote,
  }) : _local = local,
       _remote = remote;

  final AuthSessionLocalService _local;
  final AuthTokenRemoteService _remote;
  final _expirations = StreamController<void>.broadcast();

  AuthModel? _session;

  /// The stored session is read from the database once; after that, memory
  /// follows every write. A read that failed is forgotten, so the next one
  /// tries again.
  Future<void>? _loading;

  Future<String?>? _refreshing;

  @override
  Future<String?> currentToken() async => (await current())?.accessToken;

  /// Concurrent calls share the same refresh (chapter 11).
  @override
  Future<String?> refreshToken() =>
      _refreshing ??= _renew().whenComplete(() => _refreshing = null);

  Future<String?> _renew() async {
    final session = await current();
    if (session == null) return null;
    try {
      final tokens = await _remote.renew(session.refreshToken);
      final renewed = session.withTokens(
        accessToken: tokens.accessToken,
        refreshToken: tokens.refreshToken,
      );
      await save(renewed);
      return renewed.accessToken;
    } on ApiError catch (error) {
      // With no network, the session goes on: the refresh tries again later.
      if (error.kind != ApiErrorKind.rejected) rethrow;
      await clear();
      _expirations.add(null);
      return null;
    }
  }

  Future<void> _loaded() => _loading ??= _local
      .read()
      .then<void>((stored) => _session = stored)
      .catchError((Object error, StackTrace stackTrace) {
        _loading = null;
        Error.throwWithStackTrace(error, stackTrace);
      });

  @override
  Future<AuthModel?> current() async {
    await _loaded();
    return _session;
  }

  @override
  Future<void> save(AuthModel session) async {
    await _loaded();
    await _local.write(session);
    _session = session;
  }

  @override
  Future<void> clear() async {
    await _loaded();
    _session = null;
    await _local.delete();
  }

  @override
  Stream<void> get expirations => _expirations.stream;
}
