import 'package:analyzer/analysis_rule/analysis_rule.dart';
import 'package:analyzer/analysis_rule/rule_context.dart';
import 'package:analyzer/analysis_rule/rule_visitor_registry.dart';
import 'package:analyzer/dart/ast/ast.dart';
import 'package:analyzer/dart/ast/visitor.dart';
import 'package:analyzer/error/error.dart';

import 'import_location.dart';

/// The arrows point inward (chapters 2 and 15): each layer of a module only
/// imports the inner ones. The module's entry file is left out, because it
/// is the module's composition root and knows all of them.
final class LayerImports extends AnalysisRule {
  LayerImports()
    : super(
        name: 'layer_imports',
        description: 'Each layer of a module only imports the inner layers.',
      );

  static const LintCode code = LintCode(
    'layer_imports',
    "The '{0}' layer cannot import '{1}'.",
    correctionMessage:
        'The arrows point inward: the domain at the center, the application '
        'around it, and the adapters, driving and driven, at the edge, without '
        'importing each other.',
  );

  @override
  LintCode get diagnosticCode => code;

  /// For each layer, what it cannot import: folders of the same package
  /// (relative to its root) and packages; `flutter` also covers the
  /// `flutter_*` ones.
  static const forbidden =
      <String, ({List<String> folders, List<String> packages})>{
        'lib/domain/': (
          folders: ['lib/application/', 'lib/adapters/'],
          packages: ['flutter'],
        ),
        'lib/application/': (folders: ['lib/adapters/'], packages: ['flutter']),
        'lib/adapters/driving/': (
          folders: ['lib/adapters/driven/', 'lib/application/ports/'],
          packages: [],
        ),
        'lib/adapters/driven/': (
          folders: ['lib/adapters/driving/'],
          packages: [],
        ),
      };

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
}

final class _Visitor extends SimpleAstVisitor<void> {
  _Visitor(this.rule, this.context);

  final LayerImports rule;
  final RuleContext context;

  @override
  void visitImportDirective(ImportDirective node) => _check(node);

  @override
  void visitExportDirective(ExportDirective node) => _check(node);

  void _check(NamespaceDirective node) {
    final location = ImportLocation.of(context);
    if (location == null) return;
    for (final MapEntry(key: layer, value: rules)
        in LayerImports.forbidden.entries) {
      if (!location.file.startsWith(layer)) continue;
      final package = ImportLocation.packageOf(node);
      if (package != null &&
          package != location.packageName &&
          rules.packages.any(
            (name) => package == name || package.startsWith('${name}_'),
          )) {
        rule.reportAtNode(node.uri, arguments: [layer, 'package:$package']);
        return;
      }
      final target = location.targetInPackage(node);
      if (target == null) return;
      for (final folder in rules.folders) {
        if (target.startsWith(folder)) {
          rule.reportAtNode(node.uri, arguments: [layer, folder]);
          return;
        }
      }
    }
  }
}
