import 'package:analyzer/analysis_rule/analysis_rule.dart';
import 'package:analyzer/analysis_rule/rule_context.dart';
import 'package:analyzer/analysis_rule/rule_visitor_registry.dart';
import 'package:analyzer/dart/ast/ast.dart';
import 'package:analyzer/dart/ast/visitor.dart';
import 'package:analyzer/error/error.dart';

import 'import_location.dart';

/// `get_it` only at the edges (chapters 10 and 15): the host's composition
/// root (`lib/bootstrap/`), each module's entry file (`lib/[package].dart`),
/// the Pages (`lib/adapters/driving/pages/`), and the tests. Anywhere else,
/// it becomes a service locator, and the class starts hiding what it
/// depends on.
final class GetItOutsideEdges extends AnalysisRule {
  GetItOutsideEdges()
    : super(
        name: 'get_it_outside_edges',
        description:
            'get_it only in the composition root, in each module\'s entry '
            'file, in the Pages, and in the tests.',
      );

  static const LintCode code = LintCode(
    'get_it_outside_edges',
    "get_it cannot be imported in '{0}'.",
    correctionMessage:
        'Receive the dependency through the constructor; what resolves from get_it is '
        'the composition root, the module\'s entry file, or a Page.',
  );

  @override
  LintCode get diagnosticCode => code;

  @override
  void registerNodeProcessors(
    RuleVisitorRegistry registry,
    RuleContext context,
  ) {
    final visitor = _Visitor(this, context);
    registry
      ..addImportDirective(this, visitor)
      ..addExportDirective(this, visitor);
  }

  /// Whether [file], relative to the root of the [packageName] package, may use get_it.
  static bool isEdge(String packageName, String file) =>
      !file.startsWith('lib/') ||
      file == 'lib/$packageName.dart' ||
      file.startsWith('lib/bootstrap/') ||
      file.startsWith('lib/adapters/driving/pages/');
}

final class _Visitor extends SimpleAstVisitor<void> {
  _Visitor(this.rule, this.context);

  final GetItOutsideEdges rule;
  final RuleContext context;

  @override
  void visitImportDirective(ImportDirective node) => _check(node);

  @override
  void visitExportDirective(ExportDirective node) => _check(node);

  void _check(NamespaceDirective node) {
    if (ImportLocation.packageOf(node) != 'get_it') return;
    final location = ImportLocation.of(context);
    if (location == null) return;
    if (GetItOutsideEdges.isEdge(location.packageName, location.file)) return;
    rule.reportAtNode(node.uri, arguments: [location.file]);
  }
}
