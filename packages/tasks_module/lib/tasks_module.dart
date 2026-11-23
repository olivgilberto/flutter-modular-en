/// The tasks module. The host sees the registration function, the list of
/// routes and their names (chapter 34), and the translations (chapter 37); nothing else.
library;

import 'package:core/core.dart';
import 'package:get_it/get_it.dart';

import 'adapters/driven/services/rest_task_service.dart';
import 'adapters/driven/services/sqlite_task_service.dart';
import 'adapters/driven/services/task_local_service.dart';
import 'adapters/driven/sync/task_syncable_outbox.dart';
import 'adapters/driven/task_clearable_on_logout.dart';
import 'adapters/driven/task_repository_impl.dart';
import 'adapters/driven/uuid_v4.dart';
import 'adapters/driving/bloc/task_conflicts_bloc.dart';
import 'adapters/driving/bloc/task_edit_bloc.dart';
import 'adapters/driving/bloc/task_list_bloc.dart';
import 'application/ports/task_repository.dart';
import 'application/use_cases/task_use_case.dart';

export 'adapters/driving/l10n/tasks_module_localizations.dart'
    show TasksModuleLocalizations;
export 'adapters/driving/routes/tasks_module_routes.dart'
    show TaskRoutes, tasksModuleRoutes;

/// Registers the module in the session scope, which the host opens at boot
/// and renews at the end of every session (chapter 32): nothing from here
/// survives into the next session. Only this function knows the concrete
/// classes, and nothing is opened here: the database opens on first use.
void registerTasksModuleDependencies(GetIt getIt) {
  DateTime now() => DateTime.now().toUtc();
  final local = SqliteTaskService(
    databaseFactory: getIt<LocalDatabaseFactory>(),
    newOperationId: () => newUuidV4(),
    now: now,
  );
  final outbox = TaskSyncableOutbox(
    apiClient: getIt<ApiClient>(),
    queue: local,
    conflicts: local,
    logger: getIt<AppLogger>(),
  );
  getIt
    ..registerSingleton<TaskLocalService>(
      local,
      dispose: (_) => local.dispose(),
    )
    ..registerLazySingleton<TaskRepository>(
      () => TaskRepositoryImpl(
        remote: RestTaskService(apiClient: getIt<ApiClient>()),
        local: getIt<TaskLocalService>(),
        outbox: outbox,
        logger: getIt<AppLogger>(),
        now: now,
      ),
    )
    ..registerLazySingleton<TaskUseCase>(
      () => TaskUseCase(
        repository: getIt<TaskRepository>(),
        newId: () => newUuidV4(),
        now: now,
        analytics: getIt<AppAnalytics>(),
      ),
    )
    // Factories: each time a screen opens it gets a new Bloc, which the
    // Page's BlocProvider closes when the screen leaves the tree.
    ..registerFactory<TaskListBloc>(
      () => TaskListBloc(tasks: getIt<TaskUseCase>()),
    )
    ..registerFactory<TaskEditBloc>(
      () => TaskEditBloc(tasks: getIt<TaskUseCase>()),
    )
    ..registerFactory<TaskConflictsBloc>(
      () => TaskConflictsBloc(tasks: getIt<TaskUseCase>()),
    );
  // The registries belong to the base scope; the end of the session scope
  // empties them. The queue signed up is the same one the repository triggers.
  getIt<LogoutCleanerRegistry>().register(TaskClearableOnLogout(local));
  getIt<OutboxRegistry>().register(outbox);
}
