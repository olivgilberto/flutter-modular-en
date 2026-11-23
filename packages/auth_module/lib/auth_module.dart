/// The authentication module. The host sees the registration function, the
/// list of routes, their names, the session state, the sign-out button,
/// and the translations (chapter 37); nothing else.
library;

import 'package:core/core.dart';
import 'package:get_it/get_it.dart';

import 'adapters/driven/auth_token_provider.dart';
import 'adapters/driven/services/rest_auth_service.dart';
import 'adapters/driven/services/rest_auth_token_service.dart';
import 'adapters/driven/services/sqlite_auth_session_service.dart';
import 'adapters/driven/services/sqlite_data_owner_service.dart';
import 'adapters/driving/bloc/login_bloc.dart';
import 'adapters/driving/bloc/logout_bloc.dart';
import 'adapters/driving/bloc/register_bloc.dart';
import 'adapters/driving/session/session_bloc.dart';
import 'application/ports/auth_repository.dart';
import 'application/ports/data_owner_repository.dart';
import 'application/use_cases/auth_use_case.dart';

export 'adapters/driving/l10n/auth_module_localizations.dart'
    show AuthModuleLocalizations;
export 'adapters/driving/pages/logout_button.dart' show LogoutButton;
export 'adapters/driving/routes/auth_module_routes.dart'
    show AuthRoutes, authModuleRoutes;
export 'adapters/driving/session/session_bloc.dart'
    show
        SessionAuthenticated,
        SessionBloc,
        SessionDiscardRequested,
        SessionEvent,
        SessionExpiredWithPendingChanges,
        SessionRestoreRequested,
        SessionState,
        SessionUnauthenticated,
        SessionUnknown;

/// Registers the module in the base scope, after the `core` adapters
/// (chapter 10). Only this function knows the concrete classes.
void registerAuthModuleDependencies(GetIt getIt) {
  final session = AuthTokenProvider(
    local: SqliteAuthSessionService(
      databaseFactory: getIt<LocalDatabaseFactory>(),
    ),
    remote: RestAuthTokenService(apiClient: getIt<ApiClient>()),
  );
  getIt
    ..registerSingleton<TokenProvider>(session)
    ..registerLazySingleton<AuthRepository>(
      () => RestAuthService(apiClient: getIt<ApiClient>(), session: session),
    )
    ..registerLazySingleton<DataOwnerRepository>(
      () => SqliteDataOwnerService(
        databaseFactory: getIt<LocalDatabaseFactory>(),
      ),
    )
    ..registerLazySingleton<AuthUseCase>(
      () => AuthUseCase(
        repository: getIt<AuthRepository>(),
        owner: getIt<DataOwnerRepository>(),
        cleaners: getIt<LogoutCleanerRegistry>(),
        outboxes: getIt<OutboxRegistry>(),
        logger: getIt<AppLogger>(),
        analytics: getIt<AppAnalytics>(),
      ),
    )
    // Factories: each time the screen opens it gets a new Bloc, which the
    // Page's BlocProvider closes when the screen leaves the tree.
    ..registerFactory<LoginBloc>(() => LoginBloc(auth: getIt<AuthUseCase>()))
    ..registerFactory<RegisterBloc>(
      () => RegisterBloc(auth: getIt<AuthUseCase>()),
    )
    ..registerFactory<LogoutBloc>(() => LogoutBloc(auth: getIt<AuthUseCase>()))
    // Just one, from boot to the end of the app: the host observes it (chapter 28).
    ..registerLazySingleton<SessionBloc>(
      () => SessionBloc(auth: getIt<AuthUseCase>()),
      dispose: (bloc) => bloc.close(),
    );
}
