import 'package:flutter/widgets.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:get_it/get_it.dart';

import '../bloc/logout_bloc.dart';
import '../views/logout_view.dart';

/// The entry point for logout, exported for the screen frame the host
/// builds (chapter 29). It is not a route: signing out is an action, not a
/// screen. Like a Page, it only gets the Bloc and hands it to the View.
final class LogoutButton extends StatelessWidget {
  const LogoutButton({super.key});

  @override
  Widget build(BuildContext context) {
    return BlocProvider<LogoutBloc>(
      create: (_) => GetIt.instance<LogoutBloc>(),
      child: const LogoutView(),
    );
  }
}
