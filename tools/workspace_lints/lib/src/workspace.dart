import 'dart:io';

import 'package:yaml/yaml.dart';

final class Package {
  const Package({
    required this.name,
    required this.path,
    required this.dependencies,
  });

  final String name;

  /// Path relative to the root, as it is in the workspace: list.
  final String path;

  /// Only the dependencies section; dev_dependencies do not cross boundaries.
  final Set<String> dependencies;
}

final class Workspace {
  const Workspace({required this.project, required this.packages});

  /// The name: from the root pubspec.yaml, which names the host ([project]_app).
  final String project;
  final List<Package> packages;

  Set<String> get toolNames => {
    for (final p in packages)
      if (p.path.startsWith('tools/')) p.name,
  };

  static Workspace read(Directory root) {
    final pubspec = _load('${root.path}/pubspec.yaml');
    final members = (pubspec['workspace'] as List?)?.cast<String>() ?? const [];
    return Workspace(
      project: pubspec['name'] as String,
      packages: [
        for (final path in members)
          _package(path, _load('${root.path}/$path/pubspec.yaml')),
      ],
    );
  }

  static YamlMap _load(String path) =>
      loadYaml(File(path).readAsStringSync()) as YamlMap;

  static Package _package(String path, YamlMap pubspec) => Package(
    name: pubspec['name'] as String,
    path: path,
    dependencies: {
      ...?(pubspec['dependencies'] as YamlMap?)?.keys.cast<String>(),
    },
  );
}
