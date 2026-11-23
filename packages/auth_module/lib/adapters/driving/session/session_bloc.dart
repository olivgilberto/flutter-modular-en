import 'dart:async';

import 'package:core/core.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../application/use_cases/auth_use_case.dart';

part 'session_event.dart';
part 'session_state.dart';

/// The session state the module publishes to the host (chapter 11). It is
/// authentication's contract with the host, instead of the token: it only
/// changes to [SessionUnauthenticated] after the data cleanup has finished.
///
/// It lives in the base scope, from boot to the end of the app, and listens
/// to the use case from birth: a sign-in made on any screen arrives here
/// without the screen knowing this Bloc exists.
final class SessionBloc extends Bloc<SessionEvent, SessionState> {
  SessionBloc({required AuthUseCase auth})
    : _auth = auth,
      super(const SessionUnknown()) {
    on<SessionRestoreRequested>(_onRestoreRequested);
    on<_SignedInChanged>(
      (event, emit) => emit(
        event.signedIn
            ? const SessionAuthenticated()
            : const SessionUnauthenticated(),
      ),
    );
    on<_SessionExpired>(_onExpired);
    on<SessionDiscardRequested>(_onDiscardRequested);
    _subscriptions = [
      auth.watchSignedIn().listen(
        (signedIn) => add(_SignedInChanged(signedIn)),
      ),
      auth.watchSessionExpired().listen((_) => add(const _SessionExpired())),
    ];
  }

  final AuthUseCase _auth;
  late final List<StreamSubscription<Object?>> _subscriptions;

  /// The use case publishes the result in `watchSignedIn`. An unreadable
  /// session database becomes "no session": the user signs in again.
  Future<void> _onRestoreRequested(
    SessionRestoreRequested event,
    Emitter<SessionState> emit,
  ) async {
    try {
      await _auth.restoreSession();
    } on LocalDatabaseError {
      emit(const SessionUnauthenticated());
    }
  }

  /// The refresh was refused: the session has already died on the server,
  /// and there is no way to ask for confirmation first (chapter 11). With no
  /// pending changes, it ends here. With some, the Bloc waits for the
  /// user's decision, and the data stays on the device until then.
  Future<void> _onExpired(
    _SessionExpired event,
    Emitter<SessionState> emit,
  ) async {
    final int pending;
    try {
      pending = await _auth.pendingChanges();
    } on LocalDatabaseError {
      // Without knowing how many, the user decides: nothing is erased without them.
      emit(const SessionExpiredWithPendingChanges(pendingChanges: null));
      return;
    }
    if (pending > 0) {
      emit(SessionExpiredWithPendingChanges(pendingChanges: pending));
      return;
    }
    await _end();
  }

  /// The user preferred to discard the changes rather than sign in again.
  Future<void> _onDiscardRequested(
    SessionDiscardRequested event,
    Emitter<SessionState> emit,
  ) => _end();

  /// The use case publishes the end of the session, which arrives as
  /// [SessionUnauthenticated], even when the cleanup fails.
  Future<void> _end() async {
    try {
      await _auth.endExpiredSession();
    } on LocalDatabaseError {
      // Already went to the crash log through the use case.
    }
  }

  @override
  Future<void> close() async {
    for (final subscription in _subscriptions) {
      await subscription.cancel();
    }
    return super.close();
  }
}
