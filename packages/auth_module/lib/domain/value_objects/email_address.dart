import '../auth_failure.dart';

/// An email that only exists if it is shaped like an email. The validation
/// is deliberately permissive: the real confirmation is the message the
/// backend sends to the address.
final class EmailAddress {
  const EmailAddress._(this.value);

  /// Trims spaces at the ends and lowercases, a business rule agreed
  /// with the backend.
  factory EmailAddress.parse(String input) {
    final normalized = input.trim().toLowerCase();
    if (!_pattern.hasMatch(normalized)) throw const InvalidEmailFailure();
    return EmailAddress._(normalized);
  }

  static final _pattern = RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$');

  final String value;

  @override
  bool operator ==(Object other) =>
      other is EmailAddress && other.value == value;

  @override
  int get hashCode => value.hashCode;

  @override
  String toString() => value;
}
