/// Chapter 42 draft: a new module through chapter 28's checklist.
library;

import 'package:get_it/get_it.dart';

export 'adapters/driving/l10n/notes_module_localizations.dart'
    show NotesModuleLocalizations;
export 'adapters/driving/routes/notes_module_routes.dart'
    show NoteRoutes, notesModuleRoutes;

/// Registers the module in the session scope. The draft has no domain or
/// data yet; the function exists so the host already has a place to call it.
void registerNotesModuleDependencies(GetIt getIt) {}
