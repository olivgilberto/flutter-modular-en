# adapter_db_sqlcipher

Each module's encrypted local database, with SQLCipher.

- **Contains:** `SqlcipherLocalDatabaseFactory` (`LocalDatabaseFactory`
  port), which opens one database per module with its own key stored in
  secure storage, and `SqlcipherLocalDatabase` (`LocalDatabase` port).
- **Never contains:** a module's tables, queries, or migrations (each module
  declares its own in a `DatabaseSchema`), or the get_it registration. No
  driver exception leaves this package: every failure becomes
  `LocalDatabaseError`.
