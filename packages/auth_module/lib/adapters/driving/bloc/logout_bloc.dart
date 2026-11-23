import 'package:bloc_concurrency/bloc_concurrency.dart';
import 'package:core/core.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../application/use_cases/auth_use_case.dart';

part 'logout_event.dart';
part 'logout_state.dart';

/// The ViewModel of the sign-out button. Two operations, each with its own
/// event: checking for unsent changes and the logout itself (chapter 11).
/// Between the two, the user decides, in the View.
///
/// Not `final`: the View tests mock it, like the other Blocs.
class LogoutBloc extends Bloc<LogoutEvent, LogoutState> {
  LogoutBloc({required AuthUseCase auth})
    : _auth = auth,
      super(const LogoutInitial()) {
    on<LogoutRequested>(_onRequested, transformer: droppable());
    on<LogoutConfirmed>(_onConfirmed, transformer: droppable());
  }

  final AuthUseCase _auth;

  Future<void> _onRequested(
    LogoutRequested event,
    Emitter<LogoutState> emit,
  ) async {
    emit(const LogoutCheckInProgress());
    try {
      emit(LogoutCheckSuccess(pendingChanges: await _auth.pendingChanges()));
    } on LocalDatabaseError {
      // Without knowing how many, the View asks the same way.
      emit(const LogoutCheckFailure());
    }
  }

  Future<void> _onConfirmed(
    LogoutConfirmed event,
    Emitter<LogoutState> emit,
  ) async {
    emit(const LogoutSubmitInProgress());
    try {
      await _auth.signOut();
      emit(const LogoutSubmitSuccess());
    } on ApiError {
      // The backend did not hear about it, but the local data is already
      // erased and the token forgotten: for the device, the session is over.
      emit(const LogoutSubmitSuccess());
    } on LocalDatabaseError {
      emit(const LogoutSubmitFailure());
    }
  }
}
