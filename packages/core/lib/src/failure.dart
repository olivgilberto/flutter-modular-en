/// Base of every error the user can act on. Each module declares its own
/// sealed family on top of it (chapter 9).
abstract interface class Failure implements Exception {}
