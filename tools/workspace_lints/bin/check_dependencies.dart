import 'dart:io';

import 'package:workspace_lints/workspace_lints.dart';

/// Run by the check-deps script, at the workspace root.
void main() {
  final workspace = Workspace.read(Directory.current);
  final found = [
    for (final p in workspace.packages)
      ...violations(p, workspace.project, workspace.toolNames),
    // Chapter 42: each module's page, index entry, and owner.
    ...moduleRecordViolations(
      workspace.packages,
      workspace.project,
      ModuleRecords.read(Directory.current),
    ),
  ];
  if (found.isEmpty) {
    final modules = workspace.packages
        .where((p) => roleOf(p.name, p.path, workspace.project) == Role.module)
        .length;
    stdout.writeln(
      'Boundaries between packages: no violation in ${workspace.packages.length} package(s). '
      'Modules with a page, index entry, and owner: $modules.',
    );
    return;
  }
  found.forEach(stderr.writeln);
  exit(1);
}
