import 'package:test/test.dart';
import 'package:workspace_lints/workspace_lints.dart';

Package pkg(String name, List<String> deps, {String? path}) => Package(
  name: name,
  path: path ?? 'packages/$name',
  dependencies: deps.toSet(),
);

List<String> check(Package p) =>
    violations(p, 'mobile_tasks', {'workspace_lints'});

void main() {
  test('a module does not declare another module', () {
    expect(check(pkg('tasks_module', ['core', 'auth_module'])), hasLength(1));
  });

  test('the core declares nothing', () {
    expect(check(pkg('core', ['meta'])), hasLength(1));
    expect(check(pkg('core', [])), isEmpty);
  });

  test('a module does not get around a port', () {
    expect(check(pkg('tasks_module', ['core', 'http'])), hasLength(1));
    expect(
      check(pkg('tasks_module', ['core', 'firebase_analytics'])),
      hasLength(1),
    );
  });

  test('every technology in an adapter family is abstracted by the core '
      '(chapter 36)', () {
    for (final dep in adapterFamilies.values.expand((family) => family)) {
      expect(
        check(pkg('tasks_module', ['core', dep])),
        hasLength(1),
        reason: dep,
      );
    }
    // The ones the module actually uses are still allowed.
    expect(
      check(
        pkg('tasks_module', [
          'core',
          'design_system',
          'flutter',
          'get_it',
          'flutter_bloc',
          'bloc_concurrency',
          'go_router',
        ]),
      ),
      isEmpty,
    );
  });

  test('a retired technology stays out of the modules (chapter 41)', () {
    expect(adapterFamilies.values.any((f) => f.contains('dio')), isFalse);
    expect(check(pkg('tasks_module', ['core', 'dio'])), hasLength(1));
  });

  test('an adapter stays in its family', () {
    expect(check(pkg('adapter_http_http', ['core', 'http'])), isEmpty);
    expect(
      check(pkg('adapter_http_http', ['core', 'http', 'get_it'])),
      hasLength(1),
    );
    expect(check(pkg('adapter_http_http', ['core', 'dio'])), hasLength(1));
    expect(check(pkg('adapter_cache_hive', ['core', 'hive'])), hasLength(1));
  });

  test('a name with no role is rejected', () {
    expect(check(pkg('common', [])), hasLength(1));
  });

  test('the host may depend on everything', () {
    expect(
      check(
        pkg('mobile_tasks_app', ['core', 'tasks_module', 'adapter_http_http']),
      ),
      isEmpty,
    );
  });

  test('tools are never a dependency', () {
    expect(check(pkg('mobile_tasks_app', ['workspace_lints'])), hasLength(1));
  });
}
