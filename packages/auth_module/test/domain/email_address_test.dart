import 'package:auth_module/domain/auth_failure.dart';
import 'package:auth_module/domain/value_objects/email_address.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('normalizes spaces and case', () {
    expect(EmailAddress.parse('  Ana@Example.com ').value, 'ana@example.com');
  });

  test('rejects what is not shaped like an email', () {
    for (final input in [
      'ana.example.com',
      'ana@',
      '@example.com',
      'a b@c.d',
    ]) {
      expect(
        () => EmailAddress.parse(input),
        throwsA(isA<InvalidEmailFailure>()),
        reason: input,
      );
    }
  });

  test('two emails with the same text are the same email', () {
    expect(
      EmailAddress.parse('ana@example.com'),
      EmailAddress.parse('ANA@example.com'),
    );
  });
}
