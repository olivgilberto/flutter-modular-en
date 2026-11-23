import 'package:get_it/get_it.dart';
import '../value_objects/task_title.dart';

/// Where a task stands. Archiving is the end: the task leaves the list.
enum TaskStatus { open, done, archived }

/// A user's task. Equality by id: the same task stays the same after
/// getting another title.
final class Task {
  const Task({
    required this.id,
    required this.title,
    required this.createdAt,
    this.status = TaskStatus.open,
  });

  /// Generated on the device, at creation time: the task exists before it
  /// reaches the backend, and resending the creation does not create another (chapter 32).
  final String id;
  final TaskTitle title;
  final TaskStatus status;

  /// In UTC. Sorts the list, newest first.
  final DateTime createdAt;

  bool get isDone => status == TaskStatus.done;
  bool get isArchived => status == TaskStatus.archived;

  Task rename(TaskTitle newTitle) => _copy(title: newTitle);
  Task complete() => _copy(status: TaskStatus.done);
  Task reopen() => _copy(status: TaskStatus.open);

  Task _copy({TaskTitle? title, TaskStatus? status}) => Task(
    id: id,
    title: title ?? this.title,
    createdAt: createdAt,
    status: status ?? this.status,
  );

  @override
  bool operator ==(Object other) => other is Task && other.id == id;

  @override
  int get hashCode => id.hashCode;
}
