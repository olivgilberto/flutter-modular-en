import 'package:auth_module/domain/entities/user.dart';
import 'package:auth_module/domain/value_objects/email_address.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final ana = User(
    id: 'u-1',
    name: 'Ana',
    email: EmailAddress.parse('ana@example.com'),
  );

  test('equality by id', () {
    expect(ana.rename('Ana Smith'), ana);
  });

  test('renaming creates another object with the same id and email', () {
    final renamed = ana.rename('Ana Smith');

    expect(renamed.name, 'Ana Smith');
    expect(renamed.email, ana.email);
    expect(ana.name, 'Ana');
  });
}
