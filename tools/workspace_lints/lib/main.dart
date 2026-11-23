import 'package:analysis_server_plugin/plugin.dart';
import 'package:analysis_server_plugin/registry.dart';

import 'src/rules/get_it_outside_edges.dart';
import 'src/rules/layer_imports.dart';

/// The workspace's analyzer plugin (chapters 15 and 40). The analyzer
/// generates code that imports this file and uses the [plugin] variable.
final plugin = WorkspaceLintsPlugin();

final class WorkspaceLintsPlugin extends Plugin {
  @override
  String get name => 'workspace_lints';

  /// Lint rules come off by default: the root analysis_options.yaml turns
  /// each one on, under plugins > workspace_lints > diagnostics.
  @override
  void register(PluginRegistry registry) {
    registry
      ..registerLintRule(GetItOutsideEdges())
      ..registerLintRule(LayerImports());
  }
}
