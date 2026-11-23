import 'package:flutter/widgets.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:get_it/get_it.dart';

import '../bloc/login_bloc.dart';
import '../session/session_bloc.dart';
import '../views/login_view.dart';

/// The entry point of the `auth.login` route: gets a new Bloc and hands it
/// to the View, with the expired-session notice when there is one
/// (chapter 29). The Pages and `LogoutButton` are the only points on the
/// driving side that look up `get_it`.
final class LoginPage extends StatelessWidget {
  const LoginPage({super.key});

  @override
  Widget build(BuildContext context) {
    final session = GetIt.instance<SessionBloc>();
    return BlocProvider<LoginBloc>(
      create: (_) => GetIt.instance<LoginBloc>(),
      // The SessionBloc belongs to the base scope and outlives the screen: it
      // is only read here, never closed by it.
      child: BlocBuilder<SessionBloc, SessionState>(
        bloc: session,
        builder: (context, state) => LoginView(
          expiredSession: state is SessionExpiredWithPendingChanges
              ? state
              : null,
          onDiscard: () => session.add(const SessionDiscardRequested()),
        ),
      ),
    );
  }
}
