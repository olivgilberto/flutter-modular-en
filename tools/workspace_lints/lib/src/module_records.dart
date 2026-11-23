import 'dart:io';

import 'dependency_rules.dart';
import 'workspace.dart';

/// What the repository keeps about the modules outside the code (chapter 42):
/// each one's page, the architecture index, and the owner.
final class ModuleRecords {
  const ModuleRecords({
    required this.moduleDocs,
    required this.architecture,
    required this.codeOwners,
  });

  /// The files in docs/modules/, without the .md.
  final Set<String> moduleDocs;

  /// The text of docs/architecture.md.
  final String architecture;

  /// The lines of .github/CODEOWNERS, in file order.
  final List<OwnerRule> codeOwners;

  static ModuleRecords read(Directory root) {
    final docs = Directory('${root.path}/docs/modules');
    final owners = File('${root.path}/.github/CODEOWNERS');
    return ModuleRecords(
      moduleDocs: {
        if (docs.existsSync())
          for (final f in docs.listSync().whereType<File>())
            if (f.path.endsWith('.md'))
              f.uri.pathSegments.last.replaceAll('.md', ''),
      },
      architecture: _readOrEmpty(File('${root.path}/docs/architecture.md')),
      codeOwners: parseCodeOwners(_readOrEmpty(owners)),
    );
  }

  static String _readOrEmpty(File f) =>
      f.existsSync() ? f.readAsStringSync() : '';
}

typedef OwnerRule = ({String pattern, List<String> owners});

/// One rule per line: the pattern and the owners. Comments and empty lines
/// are left out.
List<OwnerRule> parseCodeOwners(String text) => [
  for (final line in text.split('\n'))
    if (line.trim().isNotEmpty && !line.trimLeft().startsWith('#'))
      (
        pattern: line.trim().split(RegExp(r'\s+')).first,
        owners: line.trim().split(RegExp(r'\s+')).skip(1).toList(),
      ),
];

/// On GitHub, the last line whose pattern reaches the path wins. Here, only
/// the patterns the repository uses: `*` and folders from the root.
OwnerRule? effectiveRule(String path, List<OwnerRule> rules) {
  OwnerRule? found;
  for (final rule in rules) {
    final p = rule.pattern;
    if (p == '*' ||
        (p.startsWith('/') && p.endsWith('/') && '/$path/'.startsWith(p))) {
      found = rule;
    }
  }
  return found;
}

/// Each feature module has a page, an index entry, and an owner of its own;
/// each module page matches a module in the workspace.
List<String> moduleRecordViolations(
  List<Package> packages,
  String project,
  ModuleRecords records,
) {
  final modules = [
    for (final p in packages)
      if (roleOf(p.name, p.path, project) == Role.module) p,
  ];
  final found = <String>[];
  for (final m in modules) {
    if (!records.moduleDocs.contains(m.name)) {
      found.add('${m.name}: docs/modules/${m.name}.md is missing');
    }
    if (!records.architecture.contains('modules/${m.name}.md')) {
      found.add(
        '${m.name}: docs/architecture.md does not point to modules/${m.name}.md',
      );
    }
    final rule = effectiveRule(m.path, records.codeOwners);
    if (rule == null || rule.pattern != '/${m.path}/') {
      found.add(
        '${m.name}: no line of its own in .github/CODEOWNERS '
        '(/${m.path}/ last among those that reach the module)',
      );
    } else if (rule.owners.isEmpty) {
      found.add('${m.name}: the /${m.path}/ line in CODEOWNERS has no owner');
    }
  }
  final names = {for (final m in modules) m.name};
  for (final doc in records.moduleDocs.difference(names)) {
    found.add('docs/modules/$doc.md: there is no $doc module in the workspace');
  }
  return found;
}
