# tasks_module

Tasks for mobile_tasks, offline-first: the user creates, completes, and
archives tasks with or without a network, and the device is the list's first
source.

- **Contains:** the domain (`Task`, `TaskTitle`, the `TaskFailure` family),
  the application (the `TaskRepository` port and the `TaskUseCase`), and the
  driven side (chapter 30): the encrypted `tasks.db` database, opened through
  the `LocalDatabaseFactory` port, and `TaskClearableOnLogout`, registered in
  `core`'s `LogoutCleanerRegistry`. Since chapter 31, reading from the
  backend (`RestTaskService`, stale-while-revalidate in `TaskRepositoryImpl`)
  and the send queue, recorded with each write. Since chapter 32, sending
  (`TaskSyncableOutbox`, registered in the `OutboxRegistry`) and the
  rejections in `sync_conflicts`. The screens arrive in the following
  chapters.
- **Never contains:** a dependency on another module or on an `adapter_*`
  package, or technology that `core` abstracts.

Documentation: `docs/modules/tasks_module.md`.
