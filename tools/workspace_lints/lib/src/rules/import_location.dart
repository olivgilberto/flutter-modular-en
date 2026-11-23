import 'package:analyzer/analysis_rule/rule_context.dart';
import 'package:analyzer/dart/ast/ast.dart';
import 'package:path/path.dart' as p;

/// Where the analyzed file is and where an import or export points, both
/// as paths relative to the package root ("lib/domain/task.dart"). The
/// plugin's two rules decide by those paths only: the package's folder name
/// is the package name in the workspace (chapter 16).
final class ImportLocation {
  ImportLocation._(this.packageName, this.file);

  /// `null` when the file is not in a package.
  static ImportLocation? of(RuleContext context) {
    final package = context.package;
    if (package == null) return null;
    final unit = context.currentUnit ?? context.definingUnit;
    final root = package.root.path;
    return ImportLocation._(
      p.basename(root),
      p.posix.joinAll(p.split(p.relative(unit.file.path, from: root))),
    );
  }

  final String packageName;

  /// The file, relative to the package root.
  final String file;

  /// The target of [directive] inside the same package, relative to its
  /// root, or `null` when the target is from another package or from `dart:`.
  String? targetInPackage(NamespaceDirective directive) {
    final uri = directive.uri.stringValue;
    if (uri == null) return null;
    final ownPrefix = 'package:$packageName/';
    if (uri.startsWith(ownPrefix)) {
      return 'lib/${uri.substring(ownPrefix.length)}';
    }
    if (uri.contains(':')) return null;
    return p.posix.normalize(p.posix.join(p.posix.dirname(file), uri));
  }

  /// The package of a `package:` import, or `null`.
  static String? packageOf(NamespaceDirective directive) {
    final uri = directive.uri.stringValue;
    if (uri == null || !uri.startsWith('package:')) return null;
    final rest = uri.substring('package:'.length);
    final slash = rest.indexOf('/');
    return slash < 0 ? rest : rest.substring(0, slash);
  }
}
