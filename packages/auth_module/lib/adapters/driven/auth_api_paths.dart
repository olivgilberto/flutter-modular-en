/// The authentication backend paths, all under one version.
/// No other file in the module writes a path.
abstract final class AuthApiPaths {
  static const version = '/v1';

  static const signIn = '$version/auth/sign-in';
  static const register = '$version/auth/register';
  static const refresh = '$version/auth/refresh';
  static const signOut = '$version/auth/sign-out';
}
