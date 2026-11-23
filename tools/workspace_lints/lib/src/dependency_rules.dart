import 'workspace.dart';

enum Role { core, designSystem, adapter, module, app, tool }

/// The role comes from the name (section 15.4). Null: the name declares no role.
Role? roleOf(String name, String path, String project) => switch (name) {
  _ when path.startsWith('tools/') => Role.tool,
  'core' => Role.core,
  'design_system' => Role.designSystem,
  _ when name == '${project}_app' => Role.app,
  _ when name.startsWith('adapter_') => Role.adapter,
  _ when name.endsWith('_module') => Role.module,
  _ => null,
};

/// Each adapter's technology family. A new adapter only gets through after
/// it is added here, in the same pull request that creates it.
const adapterFamilies = {
  'adapter_http_http': {'http'},
  'adapter_db_sqlcipher': {
    'sqflite_sqlcipher',
    'flutter_secure_storage',
    'path_provider',
  },
  'adapter_logging_crashlytics': {'firebase_core', 'firebase_crashlytics'},
  'adapter_analytics_firebase': {'firebase_core', 'firebase_analytics'},
  'adapter_sync_workmanager': {'workmanager'},
  'adapter_prefs_shared_preferences': {'shared_preferences'},
  'adapter_connectivity_connectivity_plus': {'connectivity_plus'},
};

/// Technologies the core abstracts: a module never declares them. They are
/// the adapters' families, with no second list in which to forget one: the
/// hand-written list, until chapter 36, let `flutter_secure_storage` and
/// `path_provider` through.
bool isAbstracted(String dep) =>
    adapterFamilies.values.any((family) => family.contains(dep)) ||
    retiredTechnologies.contains(dep) ||
    dep.startsWith('firebase_');

/// Technologies of adapters that left the workspace. With the adapter, the
/// family leaves, and the technology would stop being rejected in a module:
/// Dio, replaced by the http package in chapter 41, stays out of the modules.
const retiredTechnologies = {'dio'};

List<String> violations(Package p, String project, Set<String> tools) {
  final found = <String>[];
  void forbid(bool Function(String dep) rule, String why) {
    for (final dep in p.dependencies.where(rule)) {
      found.add('${p.name} depends on $dep: $why');
    }
  }

  bool isModule(String d) => d.endsWith('_module');
  bool isAdapter(String d) => d.startsWith('adapter_');

  forbid(tools.contains, 'tools are never a dependency');
  switch (roleOf(p.name, p.path, project)) {
    case null:
      found.add('${p.name}: the name does not declare the package\'s role');
    case Role.core:
      forbid((_) => true, 'the core only depends on the SDK');
    case Role.designSystem:
      forbid(
        (d) => d == 'core' || isModule(d) || isAdapter(d),
        'the design_system knows neither ports nor features',
      );
    case Role.adapter:
      final family = adapterFamilies[p.name];
      if (family == null) {
        found.add('${p.name}: adapter with no registered technology family');
      } else {
        forbid(
          (d) => d != 'core' && d != 'flutter' && !family.contains(d),
          'outside the adapter\'s technology family',
        );
      }
    case Role.module:
      forbid(
        (d) => isModule(d) || isAdapter(d) || isAbstracted(d),
        'a module only reaches other technologies through the core ports',
      );
    case Role.app || Role.tool:
      break;
  }
  return found;
}
