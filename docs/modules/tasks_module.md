# tasks_module

## Scope
The user's tasks, offline-first: create, rename, complete, reopen, and
archive, with or without a network. Chapter 30: domain, application, and the
device database. Chapter 31: reading from the backend
(stale-while-revalidate) and the send queue recorded together with each
write. Chapter 32: sending the queue (TaskSyncableOutbox, in the
OutboxRegistry) and the rejections stored in sync_conflicts. Chapter 34: the
screens (list, edit, and conflicts), the exported routes, and resolving the
rejections.

## Architecture
- domain/: Task (equality by id, id generated on the device, createdAt in
  UTC), TaskStatus (open, done, archived), TaskTitle (value object with
  parse: leading and trailing spaces removed, 1 to 200 code points), and the
  sealed TaskFailure family (EmptyTaskTitleFailure,
  TaskTitleTooLongFailure, TaskNotFoundFailure). TaskConflict (chapter 34:
  id, reason, the task as it is on the device, and the time of the
  rejection; equality by id), TaskConflictReason (versionConflict, rejected),
  and TaskConflictChoice (keepMine, keepServer, discard, redo).
- application/: the TaskRepository port and the TaskUseCase. An archived
  task is not in the list: changing it is TaskNotFoundFailure.
  refreshTasks() is the "pull to refresh". findTask() returns null for an
  archived one. watchConflicts(), serverVersion(), and resolveConflict(): a
  choice that does not fit the reason is an ArgumentError (a defect in the
  caller).
- adapters/driven/: TaskRepositoryImpl (stale-while-revalidate),
  RestTaskService (backend, by cursor), SqliteTaskService (database, queue,
  and rejections), TaskModel (backend and database), TaskClearableOnLogout,
  and newUuidV4 (UUID v4 with Random.secure(), for tasks, operations, and
  rejections). sync/: TaskSyncableOutbox (implements core's
  SyncableOutbox), TaskOperation, and the internal interfaces
  TaskOutboxQueue and TaskConflictStore, which SqliteTaskService
  implements.
- adapters/driving/ (chapter 34): TaskListBloc, TaskEditBloc, and
  TaskConflictsBloc (factories in get_it, a new Bloc per screen), the Pages
  (the only places that query get_it), the Views, and the routes
  (TaskRoutes, tasksModuleRoutes). Strings in the module's ARBs (chapter
  37), in adapters/driving/l10n: tasks_module_en.arb (template) and
  tasks_module_pt.arb, generating TasksModuleLocalizations, exported by the
  entry file. The task's status goes to the ARB by the TaskStatus value's
  name, in a select.

## Navigation (chapter 34)
The module exports TaskRoutes and tasksModuleRoutes (an immutable list), in
the same name format as auth_module:

| Name | Path | Screen |
| --- | --- | --- |
| tasks.list | /tasks | list: create, complete and reopen, show completed, pull to refresh, conflicts notice |
| tasks.edit | /tasks/edit/:taskId | rename and archive (with confirmation); closes when the change is on the device |
| tasks.conflicts | /tasks/conflicts | the rejections, with the device's version and the server's |

The host decides where the list goes (the start screen redirects to
/tasks) and puts the routes inside a frame of its own (a ShellRoute with
the sign-out button). The module knows neither auth_module nor the host.

## Resolving rejections (chapter 34)
The server version is fetched (GET /v1/tasks/{id}; 404 means "deleted
there") when the screen opens and again at the moment of the decision,
because it may have changed in between. Each decision erases the rejection
and the task's operations that were waiting for it, in the same
transaction:

| Reason | Decision | What happens | Needs a network |
| --- | --- | --- | --- |
| versionConflict | Keep mine | a new operation with the device's task, on the server's current version; deleted there, it comes back as a creation with the same id; deleted there and archived here, it leaves the device | yes |
| versionConflict | Keep the server's | stores the server version; deleted there, it leaves the device | yes |
| rejected | Redo | like "Keep the server's", and opens the task's screen for the user to act again | yes |
| rejected | Discard | the change goes away; the list wins and refreshes behind the scenes | no |

With no network, the screen shows the notice and nothing changes on the
device. The list shows how many rejections are waiting, without blocking
anything.

## Reading (chapter 31)
- With no stored list (empty sync_state), the first one comes from the
  network before the database is observed; a failure arrives as a Stream
  error.
- With a stored list within the TTL (5 minutes for the active list), only
  the database answers. Expired, or with the stored time in the future, the
  database answers right away and the network refreshes behind the scenes;
  a network failure disappears (the interceptor already logged it), a
  database one goes to the AppLogger as "tasks refresh".
- Simultaneous refreshes share the same trip to the network.
- The backend's list replaces the device's, except the tasks with an
  operation in the queue or an open rejection, which stay as they are; those
  that did not come, with neither, leave the device.

## Contract with the backend
GET /v1/tasks?status=active&limit=100[&cursor=...] answers
{"items": [{"id", "title", "status", "createdAt" (ISO 8601 in UTC),
"version"}], "nextCursor": "..." | null}. The app follows the cursor to the
end and only stores the whole list; a page that fails brings down the fetch;
a repeated cursor is an invalid response. An item the domain rejects is an
ApiError invalidResponse.

GET /v1/tasks/{id} (chapter 34) answers the task in the same format as an
item; 404 means deleted on the server, and RestTaskService returns null.

Sending (chapter 32), all with Idempotency-Key = the operation id:
- PUT /v1/tasks/{id} with {"title", "status", "createdAt", "operationId"}:
  creates with the app's id.
- PATCH /v1/tasks/{id} with {"title", "status", "baseVersion",
  "operationId"} (change) or {"status": "archived", "baseVersion",
  "operationId"} (archive).
- Success answers the task with "version" (the new one). The backend
  records the operationId with the change and answers 200 to a resend of the
  same operation already applied.
- A version 409 comes with {"code": "version_conflict"}; a 409 without that
  code (for example, the same key still being processed) is treated as "try
  later".

## The tasks.db database
Opened through LocalDatabaseFactory: SQLCipher, a 256-bit key in secure
storage, file in Application Support/local_databases, out of backups (the
host's rules). Schema in
lib/adapters/driven/services/tasks_database_schema.dart.
- Version 1 (chapter 30): tasks (id, title, status with CHECK, created_at
  in UTC milliseconds) with the tasks_by_status index, and preferences.
- Version 2 (chapter 31): tasks.version (the server version, 0 while it
  exists only on the device), outbox_pending_operations (operation id,
  entity_id, operation create/update/archive with CHECK, JSON payload,
  base_version, created_at; send order by rowid) with the outbox_by_entity
  index, and sync_state (key, refreshed_at). The migration queues the
  creation of each version 1 task, which was never sent.
- Version 3 (chapter 32): sync_conflicts (id, unique operation_id,
  entity_id, kind conflict/rejected with CHECK, status_code, operation,
  payload, base_version, created_at) with the sync_conflicts_by_entity
  index.

Rules for change: createStatements is always the full schema of the current
version; every change bumps the version and adds to migrations the commands
that take the previous one to it (including data fixes); a version that
reached any device never changes. The tasks_database_schema_test test keeps
a copy of each published version and checks that a fresh install equals the
copy of the current version, that each old version reaches it through the
migrations, and that migration 2 preserves the data and fills the queue.

A row the domain rejects (invalid title, unknown status) arrives as a
LocalDatabaseError: the data was written by the app, not by the user
(chapter 9).

## Send queue
Each write records the task and the operation in the same transaction:
create (payload title, status, and createdAt), update (title and status,
with the version the user was seeing), and archive. After writing, the
repository asks the queue to go up, without waiting (a database failure in
that send goes to the AppLogger as "tasks outbox").

TaskSyncableOutbox (chapter 32) is registered in the OutboxRegistry by the
registration function, the same instance the repository triggers. sync():
one send at a time in each isolate; it walks the queue in recording order,
skips the tasks with an open rejection, and gives each response an outcome:

| Response | Operation |
| --- | --- |
| 2xx with version | leaves the queue; the task stores the version; the task's following operations use it as their base |
| 2xx without version | leaves the queue; "tasks outbox response" in the AppLogger |
| no connection, 5xx, unreadable response, 401, 429, 409 without version_conflict | stays; the round stops (sync() returns true) |
| 404 on an archive | leaves: what it wanted has already happened |
| 409 version_conflict | sync_conflicts, kind conflict |
| other 4xx | sync_conflicts, kind rejected |

pendingCount() adds up the queue and the open rejections: it is the number
sign-out shows. The rejections wait for the user's decision (chapter 34).

## Preferences
"Show completed" belongs to the user, not the device: it lives in tasks.db's
preferences table and is erased on sign-out with the tasks, the queue, the
rejections, and sync_state. core's AppPreferences stores only what belongs to
the device (theme, language) and survives sign-out.

## Wiring in the host
Steps 1 to 3 of the checklist (chapter 28): workspace member, host
dependency, and registerTasksModuleDependencies in the session scope's init.
Step 7 (chapter 32): the queue in the OutboxRegistry, also sent by the
host's outboxSyncDispatcher with the app closed. Step 4 (chapter 34):
tasksModuleRoutes in createAppRouter, inside the host's frame, and the start
screen redirecting to TaskRoutes.listPath. Step 6 (chapter 37):
TasksModuleLocalizations.delegate in app.dart's moduleLocalizationsDelegates
list.

## Boundaries (chapter 36)
The pubspec.yaml declares core, design_system, flutter, get_it,
flutter_bloc, bloc_concurrency, and go_router, and, since chapter 37,
flutter_localizations and intl, which only the generated translation class
uses, on the driving side. No other module, no adapter, and no technology
that core abstracts. Every capability that seems to require another package
arrives through a core port:

| Capability | Core port the module uses | Who implements it | Who wires it |
| --- | --- | --- | --- |
| Authenticated calls and token refresh | ApiClient | HttpApiClient, which reads auth_module's TokenProvider on every send (chapter 41) | host |
| Encrypted database | LocalDatabaseFactory, LocalDatabase, DatabaseSchema | adapter_db_sqlcipher | host |
| Cleanup on sign-out | ClearableOnLogout, LogoutCleanerRegistry | auth_module calls clearAll() | the module's registration function |
| Pending changes on sign-out and sending the queue | SyncableOutbox, OutboxRegistry | core's OutboxSyncWorker | the module's registration function |
| Sending with the app closed and when the network returns | none beyond the OutboxRegistry | adapter_sync_workmanager, SyncOrchestrator | host |
| Crash reporting | AppLogger | adapter_logging_crashlytics | host |
| Errors | ApiError, LocalDatabaseError, Failure | core | — |

The module does not use TokenProvider, ConnectivityService, SyncScheduler,
AppPreferences, or AppAnalytics. By layer: domain imports only core
(Failure); application imports only core, since chapter 38, for
AppAnalytics; adapters/driven imports core and dart:async, dart:convert,
and dart:math; adapters/driving imports core, design_system, Flutter,
flutter_bloc, bloc_concurrency, go_router, get_it only in the Pages, and,
only in the generated translation class in adapters/driving/l10n
(chapter 37), flutter_localizations and intl; the entry file imports core and
get_it. The layers point inward, and driving and driven do not import each
other. test/architecture/imports_test.dart checks all of this in the files;
check-deps checks the pubspec.yaml, and depend_on_referenced_packages blocks
importing an undeclared package.

## Tests
Domain and application with mocktail; the repository with the remote and
local services simulated; RestTaskService with a simulated ApiClient; the
driven side on the computer's SQLite (sqflite_common_ffi), with a test
LocalDatabaseFactory that opens as the adapter does (full schema or
migrations, real transactions, driver errors as LocalDatabaseError); the
whole module through the registration function, in a session scope, with the
backend simulated in the ApiClient. TaskSyncableOutbox over the real
SqliteTaskService and a simulated ApiClient: one test per response outcome.
Chapter 33: with the network down (every ApiClient throwing unreachable),
creating, renaming, completing, reopening, archiving, and changing the
preference work, the list comes from the database, the operations wait in
the queue, and only refreshTasks() (the refresh gesture) returns the error.
The module never reads the ConnectivityService. Chapter 36:
test/architecture/imports_test.dart, each layer's imports read from the
files. Chapter 34: the Blocs with a simulated TaskUseCase; the Views with
simulated Blocs (MockBloc) and a GoRouter with the neighboring routes; the
Pages through the routes, with the simulated Blocs in get_it;
SqliteTaskService on each decision; and a conflict triggered on purpose in
the whole module: two edits with no network, the version 409, the conflicts
screen, and "Keep mine", which resends everything in a single operation on
the server version.
Chapter 39: each View also with the system font at 1.0, 2.0, and 3.0, on a
375 × 667 point phone (test/support/text_scale.dart): nothing overflows and
the main actions are reachable. The list is a single scroll (conflicts
notice, field, and tasks in a CustomScrollView), and the notice has the
"Resolve" button below the text. On the device, the module is exercised by
the host's integration tests (happy path and offline flow).

## Product events (chapter 38)
The TaskUseCase receives the AppAnalytics and logs, after each operation
that succeeds and without waiting: tasks_task_created, tasks_task_renamed,
tasks_task_completed, tasks_task_reopened, tasks_task_archived, and
tasks_conflict_resolved (reason and choice parameters, the enums' names).
No event carries the task's title or id. Viewed screens are logged by the
host, by route name (tasks.list, tasks.edit, tasks.conflicts).
