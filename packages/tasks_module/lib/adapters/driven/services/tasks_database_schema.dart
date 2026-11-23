import 'package:core/core.dart';

/// The tasks module's database (chapter 30). Rules for changing it:
///
/// - `createStatements` is always the complete schema of the current
///   version, for whoever installs the app now;
/// - every change bumps `version` and gets, in `migrations`, the statements
///   that lead from the previous version to it, including fixing data the
///   new rule would reject;
/// - a version that has reached any device never changes. The schema test
///   keeps a copy of each one and checks that a new install and an upgrade
///   end up in the same place.
///
/// Versions: 1, the tasks and the preferences (chapter 30); 2, the server
/// version on each task, the outbox, and the time of the last refresh
/// (chapter 31); 3, the operations the server refused, waiting for the
/// user's decision (chapter 32).
const tasksDatabaseSchema = DatabaseSchema(
  name: 'tasks.db',
  version: 3,
  createStatements: [
    // The version column stays at the end, where migration 2's ALTER TABLE
    // puts it: a new install and an upgrade have the same order.
    '''
    CREATE TABLE tasks (
      id TEXT PRIMARY KEY,
      title TEXT NOT NULL,
      status TEXT NOT NULL CHECK (status IN ('open', 'done', 'archived')),
      created_at INTEGER NOT NULL,
      version INTEGER NOT NULL DEFAULT 0
    )
    ''',
    'CREATE INDEX tasks_by_status ON tasks (status, created_at)',
    '''
    CREATE TABLE preferences (
      key TEXT PRIMARY KEY,
      value TEXT NOT NULL
    )
    ''',
    _createOutbox,
    _createOutboxIndex,
    _createSyncState,
    _createConflicts,
    _createConflictsIndex,
  ],
  migrations: {
    2: [
      'ALTER TABLE tasks ADD COLUMN version INTEGER NOT NULL DEFAULT 0',
      _createOutbox,
      _createOutboxIndex,
      _createSyncState,
      _enqueueVersion1Tasks,
    ],
    3: [_createConflicts, _createConflictsIndex],
  },
);

/// The outbox (chapter 12): one row per operation made on the device and
/// not yet accepted by the backend, written in the same transaction that
/// changes the task. The send order is the write order, the `rowid`.
const _createOutbox = '''
    CREATE TABLE outbox_pending_operations (
      id TEXT PRIMARY KEY,
      entity_id TEXT NOT NULL,
      operation TEXT NOT NULL CHECK (operation IN ('create', 'update', 'archive')),
      payload TEXT NOT NULL,
      base_version INTEGER,
      created_at INTEGER NOT NULL
    )
    ''';

const _createOutboxIndex =
    'CREATE INDEX outbox_by_entity ON outbox_pending_operations (entity_id)';

/// What the server refused (chapter 12): `conflict` for a version 409,
/// `rejected` for any other refusal. The operation leaves the queue and
/// comes here in the same transaction, as it was, until the user decides
/// (chapter 34). `operation_id` is unique: the second isolate that receives
/// the same refusal does not write another copy.
const _createConflicts = '''
    CREATE TABLE sync_conflicts (
      id TEXT PRIMARY KEY,
      operation_id TEXT NOT NULL UNIQUE,
      entity_id TEXT NOT NULL,
      kind TEXT NOT NULL CHECK (kind IN ('conflict', 'rejected')),
      status_code INTEGER NOT NULL,
      operation TEXT NOT NULL CHECK (operation IN ('create', 'update', 'archive')),
      payload TEXT NOT NULL,
      base_version INTEGER,
      created_at INTEGER NOT NULL
    )
    ''';

const _createConflictsIndex =
    'CREATE INDEX sync_conflicts_by_entity ON sync_conflicts (entity_id)';

/// When each list last came from the backend: the answer to "have I ever
/// loaded it?" and the basis of the TTL.
const _createSyncState = '''
    CREATE TABLE sync_state (
      key TEXT PRIMARY KEY,
      refreshed_at INTEGER NOT NULL
    )
    ''';

/// Migration 2's data fix. In version 1 the module did not talk to the
/// backend yet, and every stored task existed only on the device. Without
/// an operation in the queue, the first refresh would erase it, because it
/// does not come in the server's list. Each one gets the creation it was
/// missing, in the order it was created, in the same format the service writes.
const _enqueueVersion1Tasks = """
    INSERT INTO outbox_pending_operations
      (id, entity_id, operation, payload, base_version, created_at)
    SELECT
      lower(
        hex(randomblob(4)) || '-' || hex(randomblob(2)) || '-4' ||
        substr(hex(randomblob(2)), 2) || '-' ||
        substr('89ab', 1 + (random() & 3), 1) ||
        substr(hex(randomblob(2)), 2) || '-' || hex(randomblob(6))
      ),
      id,
      'create',
      json_object(
        'title', title,
        'status', status,
        'createdAt',
        strftime('%Y-%m-%dT%H:%M:%fZ', created_at / 1000.0, 'unixepoch')
      ),
      NULL,
      CAST(strftime('%s', 'now') AS INTEGER) * 1000
    FROM tasks
    ORDER BY created_at, id
    """;
