import 'package:test/test.dart';
import 'package:workspace_lints/workspace_lints.dart';

Package pkg(String name) =>
    Package(name: name, path: 'packages/$name', dependencies: const {});

final workspace = [pkg('core'), pkg('auth_module'), pkg('tasks_module')];

const owners = '''
# Owners per module (chapter 42)
*                       @platform
/packages/auth_module/  @team-account
/packages/tasks_module/ @team-tasks
''';

const index = '''
## Modules
- [auth_module](modules/auth_module.md)
- [tasks_module](modules/tasks_module.md)
''';

ModuleRecords records({
  Set<String> docs = const {'auth_module', 'tasks_module'},
  String architecture = index,
  String codeOwners = owners,
}) => ModuleRecords(
  moduleDocs: docs,
  architecture: architecture,
  codeOwners: parseCodeOwners(codeOwners),
);

List<String> check(ModuleRecords r, [List<Package>? packages]) =>
    moduleRecordViolations(packages ?? workspace, 'mobile_tasks', r);

void main() {
  test('modules with a page, index entry, and owner pass', () {
    expect(check(records()), isEmpty);
  });

  test('a new module with nothing shows up three times', () {
    final found = check(records(), [...workspace, pkg('notes_module')]);
    expect(found, hasLength(3));
    expect(found, everyElement(startsWith('notes_module: ')));
  });

  test('the page must be in the architecture index', () {
    final found = check(
      records(architecture: '- [auth_module](modules/auth_module.md)'),
    );
    expect(found, [
      'tasks_module: docs/architecture.md does not point to '
          'modules/tasks_module.md',
    ]);
  });

  test('a page with no module is rejected', () {
    final found = check(
      records(docs: {'auth_module', 'tasks_module', 'cart_module'}),
    );
    expect(found, [
      'docs/modules/cart_module.md: there is no cart_module module in the '
          'workspace',
    ]);
  });

  test('the general owner is not enough: each module has its own line', () {
    final found = check(
      records(codeOwners: '* @platform\n/packages/auth_module/ @team-account'),
    );
    expect(found, hasLength(1));
    expect(found.single, startsWith('tasks_module: no line of its own'));
  });

  test('the last line that reaches the module wins, as on GitHub', () {
    final found = check(records(codeOwners: '$owners\n/packages/ @platform'));
    expect(found, hasLength(2));
  });

  test('a line with no owner is rejected', () {
    final found = check(
      records(
        codeOwners:
            '/packages/auth_module/ @team-account\n'
            '/packages/tasks_module/',
      ),
    );
    expect(found, [
      'tasks_module: the /packages/tasks_module/ line in CODEOWNERS has no owner',
    ]);
  });

  test('parsing ignores comments and empty lines', () {
    expect(parseCodeOwners(owners).map((r) => r.pattern), [
      '*',
      '/packages/auth_module/',
      '/packages/tasks_module/',
    ]);
    expect(parseCodeOwners(owners).last.owners, ['@team-tasks']);
  });
}
