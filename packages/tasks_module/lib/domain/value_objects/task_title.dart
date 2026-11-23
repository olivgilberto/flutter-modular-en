import '../task_failure.dart';

/// A task's title, which only exists if it is neither empty nor too long.
final class TaskTitle {
  const TaskTitle._(this.value);

  /// Trims the spaces at the ends. The length is counted in code points,
  /// the same count as the backend's: a composed emoji may count as more than one.
  factory TaskTitle.parse(String input) {
    final trimmed = input.trim();
    if (trimmed.isEmpty) throw const EmptyTaskTitleFailure();
    if (trimmed.runes.length > maxLength) {
      throw const TaskTitleTooLongFailure();
    }
    return TaskTitle._(trimmed);
  }

  /// Agreed with the backend.
  static const maxLength = 200;

  final String value;

  @override
  bool operator ==(Object other) => other is TaskTitle && other.value == value;

  @override
  int get hashCode => value.hashCode;

  @override
  String toString() => value;
}
