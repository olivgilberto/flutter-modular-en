import 'package:go_router/go_router.dart';

import '../pages/login_page.dart';
import '../pages/register_page.dart';

/// The module's route names and paths, in the format `[module].[screen]` and
/// `/[module]/[screen]`. The names are part of the module's public contract
/// (docs/modules/auth_module.md): the host uses them in the redirect.
abstract final class AuthRoutes {
  static const prefix = '/auth';
  static const login = 'auth.login';
  static const loginPath = '$prefix/login';
  static const register = 'auth.register';
  static const registerPath = '$prefix/register';
}

/// The list the host spreads into the `GoRouter` (chapter 28). The module
/// never registers routes in a global router, and the list cannot be
/// changed by whoever receives it.
final List<RouteBase> authModuleRoutes = List.unmodifiable([
  GoRoute(
    name: AuthRoutes.login,
    path: AuthRoutes.loginPath,
    builder: (context, state) => const LoginPage(),
  ),
  GoRoute(
    name: AuthRoutes.register,
    path: AuthRoutes.registerPath,
    builder: (context, state) => const RegisterPage(),
  ),
]);
