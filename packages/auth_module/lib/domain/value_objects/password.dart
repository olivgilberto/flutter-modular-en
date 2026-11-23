import '../auth_failure.dart';

/// A password that meets the product's policy, the one in NIST SP 800-63B-4
/// for a password as the single factor: at least 15 characters, counted as
/// Unicode code points, and no composition rules. The list of compromised
/// passwords is checked by the backend.
final class Password {
  const Password._(this.value);

  /// Never trims spaces or changes case: the password is exactly what the
  /// user typed.
  factory Password.parse(String input) {
    final length = input.runes.length;
    if (length < minLength || length > maxLength) {
      throw const WeakPasswordFailure();
    }
    return Password._(input);
  }

  static const minLength = 15;

  /// The standard asks to accept at least 64; the limit exists so that
  /// nobody sends a huge text to the backend.
  static const maxLength = 128;

  final String value;

  @override
  bool operator ==(Object other) => other is Password && other.value == value;

  @override
  int get hashCode => value.hashCode;

  /// Never the value: a `Password` printed in a log cannot leak the password.
  @override
  String toString() => 'Password(***)';
}
