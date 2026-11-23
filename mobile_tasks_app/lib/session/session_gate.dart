import 'dart:async';

import 'package:auth_module/auth_module.dart';
import 'package:core/core.dart';
import 'package:flutter/foundation.dart';

/// What the host does with the session state auth_module publishes
/// (chapter 11): it makes sure the session scope is open when someone
/// signs in, renews the scope when the session ends and only then notifies
/// the router, and keeps it as it is when the session expires with unsent
/// changes (chapter 32). The host observes the state, never the token.
///
/// It receives the state and the stream, not the `SessionBloc`, so it can
/// be tested without the module assembled.
final class SessionGate extends ChangeNotifier {
  SessionGate({
    required SessionState initial,
    required Stream<SessionState> changes,
    required void Function() onSignedIn,
    required Future<void> Function() onSignedOut,
  }) : _state = initial,
       _onSignedIn = onSignedIn,
       _onSignedOut = onSignedOut {
    _subscription = changes.listen(_apply);
    if (initial is SessionAuthenticated) onSignedIn();
  }

  final void Function() _onSignedIn;
  final Future<void> Function() _onSignedOut;
  late final StreamSubscription<SessionState> _subscription;
  SessionState _state;
  final _known = Completer<void>();
  var _disposed = false;

  /// What the redirect checks. Until the stored session has been read, the
  /// answer is "no": the worst case is the sign-in appearing and leaving on its own.
  bool get authenticated => _state is SessionAuthenticated;

  Future<void> _apply(SessionState state) async {
    _state = state;
    switch (state) {
      case SessionAuthenticated():
        _onSignedIn();
      case SessionUnauthenticated():
        await _onSignedOut();
      case SessionExpiredWithPendingChanges():
        // The scope stays open: the previous session's data and queues wait
        // for the user's decision on the sign-in screen (chapter 29).
        break;
      case SessionUnknown():
        return;
    }
    if (!_known.isCompleted) _known.complete();
    // Closing the scope is async, and the app may have ended during it.
    if (!_disposed) notifyListeners();
  }

  /// The end of boot step 5: waits for the stored session, with the same
  /// timeout as the other steps. Once the time is up, the app opens with no
  /// session, and the redirect moves the user on when the read finishes.
  Future<void> waitUntilKnown({
    required Duration timeout,
    required AppLogger logger,
  }) async {
    if (_state is! SessionUnknown) return;
    try {
      await _known.future.timeout(timeout);
    } on TimeoutException {
      logger.log('boot: stored session not read in time');
    }
  }

  @override
  void dispose() {
    _disposed = true;
    unawaited(_subscription.cancel());
    super.dispose();
  }
}
