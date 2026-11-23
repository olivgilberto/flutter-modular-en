part of 'logout_bloc.dart';

/// States never override `==`: every emission reaches the screen.
sealed class LogoutState {
  const LogoutState();
}

final class LogoutInitial extends LogoutState {
  const LogoutInitial();
}

final class LogoutCheckInProgress extends LogoutState {
  const LogoutCheckInProgress();
}

final class LogoutCheckSuccess extends LogoutState {
  const LogoutCheckSuccess({required this.pendingChanges});

  /// How many changes made offline would be lost.
  final int pendingChanges;
}

/// The pending changes could not be counted.
final class LogoutCheckFailure extends LogoutState {
  const LogoutCheckFailure();
}

final class LogoutSubmitInProgress extends LogoutState {
  const LogoutSubmitInProgress();
}

/// The session is over. The View does not navigate: the host's redirect,
/// which observes the `SessionBloc`, leads to the sign-in.
final class LogoutSubmitSuccess extends LogoutState {
  const LogoutSubmitSuccess();
}

/// Cleaning up the local data failed. The session ended anyway, and the
/// error has already reached the crash log through the use case.
final class LogoutSubmitFailure extends LogoutState {
  const LogoutSubmitFailure();
}
