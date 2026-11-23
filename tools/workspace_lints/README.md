# workspace_lints

Repository tools, never a dependency of another package.

- `bin/check_dependencies.dart`: reads each workspace member's
  `pubspec.yaml` and checks the `dependencies` section against the rule for
  the role the package name declares (chapter 15 of the book). Run by the
  Melos `check-deps` script, at the root.
  Since chapter 42, it also checks each feature module's records
  (`lib/src/module_records.dart`): the page in `docs/modules/`, the line in
  the "Modules" index of `docs/architecture.md`, and a line of its own in
  `.github/CODEOWNERS` (the last one that reaches the module, as on GitHub);
  and it rejects a module page that is not in the workspace.
- `lib/main.dart`: the analyzer plugin (chapter 40), declared in the root
  `analysis_options.yaml`, with two lint rules:
  - `get_it_outside_edges`: `get_it` only in `lib/bootstrap/` (the host's
    composition root), in `lib/[package].dart` (each module's entry point),
    in `lib/adapters/driving/pages/`, and outside `lib/` (tests);
  - `layer_imports`: domain without application, adapters, or Flutter;
    application without adapters or Flutter; driving without driven or
    `application/ports/`; driven without driving.
  Violations show up in the IDE and in the root `dart analyze`. The tests, in
  `test/rules/`, use `analyzer_testing`: for each rule, files that violate it
  and files that do not.
