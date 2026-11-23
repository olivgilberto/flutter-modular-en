part of 'session_bloc.dart';

/// The four states the host knows. The three without fields are
/// constants: emitting the same one again notifies nobody.
sealed class SessionState {
  const SessionState();
}

/// Before the stored session is read, at boot.
final class SessionUnknown extends SessionState {
  const SessionUnknown();
}

final class SessionAuthenticated extends SessionState {
  const SessionAuthenticated();
}

/// Nobody signed in, or the session ended and the data is already erased.
final class SessionUnauthenticated extends SessionState {
  const SessionUnauthenticated();
}

/// The session died on the server, but there are changes made offline that
/// have not been sent yet (chapter 11). The data stays on the device and
/// the session scope stays open, waiting for the user's decision on the
/// sign-in screen: sign in again, to send them, or discard them.
final class SessionExpiredWithPendingChanges extends SessionState {
  const SessionExpiredWithPendingChanges({required this.pendingChanges});

  /// How many, or `null` when they could not be counted.
  final int? pendingChanges;
}
