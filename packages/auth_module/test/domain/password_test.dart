import 'package:auth_module/domain/auth_failure.dart';
import 'package:auth_module/domain/value_objects/password.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('accepts 15 characters with no composition rules', () {
    expect(Password.parse('correcthorsebat').value, hasLength(15));
  });

  test('rejects fewer than 15 characters', () {
    expect(
      () => Password.parse('correcthorseba'),
      throwsA(isA<WeakPasswordFailure>()),
    );
  });

  test('counts code points, not UTF-16 units', () {
    // Seven emoji are 14 UTF-16 units, but only 7 characters.
    expect(
      () => Password.parse('🐴🔋📎🐴🔋📎🐴'),
      throwsA(isA<WeakPasswordFailure>()),
    );
    expect(
      Password.parse('🐴🔋📎🐴🔋📎🐴🔋📎🐴🔋📎🐴🔋📎').value.runes,
      hasLength(15),
    );
  });

  test('keeps the password as typed, spaces included', () {
    expect(Password.parse(' horse battery ').value, ' horse battery ');
  });

  test('rejects more than 128 characters', () {
    expect(
      () => Password.parse('a' * 129),
      throwsA(isA<WeakPasswordFailure>()),
    );
  });

  test('never shows up in a log', () {
    final password = Password.parse('correct-horse-battery-staple');

    expect('$password', isNot(contains('horse')));
  });
}
