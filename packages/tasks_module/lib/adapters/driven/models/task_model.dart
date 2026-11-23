import '../../../domain/entities/task.dart';
import '../../../domain/value_objects/task_title.dart';

/// A task as the backend delivers it and as the `tasks` table stores it.
/// Hand-written serialization, in both formats.
final class TaskModel {
  const TaskModel({
    required this.id,
    required this.title,
    required this.status,
    required this.createdAt,
    this.version = 0,
  });

  /// A task created or changed on the device. The server version is not the
  /// domain's business: whoever writes looks it up in the database (chapter 31).
  factory TaskModel.fromEntity(Task task) => TaskModel(
    id: task.id,
    title: task.title.value,
    status: task.status.name,
    createdAt: task.createdAt.millisecondsSinceEpoch,
  );

  /// An item of the backend's list. Extra keys are ignored; a missing one,
  /// or one of another type, is a [FormatException].
  factory TaskModel.fromJson(Object? json) {
    if (json case {
      'id': String id,
      'title': String title,
      'status': String status,
      'createdAt': String createdAt,
      'version': int version,
    }) {
      final created = DateTime.tryParse(createdAt);
      if (created == null || !created.isUtc) {
        throw FormatException('Date out of format: $createdAt');
      }
      return TaskModel(
        id: id,
        title: title,
        status: status,
        createdAt: created.millisecondsSinceEpoch,
        version: version,
      );
    }
    throw const FormatException('Backend task out of format');
  }

  /// A row of the table. A missing column, or one of another type, is a
  /// [FormatException].
  factory TaskModel.fromMap(Map<String, Object?> row) {
    if (row case {
      'id': String id,
      'title': String title,
      'status': String status,
      'created_at': int createdAt,
      'version': int version,
    }) {
      return TaskModel(
        id: id,
        title: title,
        status: status,
        createdAt: createdAt,
        version: version,
      );
    }
    throw const FormatException('Stored task out of format');
  }

  final String id;
  final String title;

  /// The name of a [TaskStatus]: open, done, or archived.
  final String status;

  /// Milliseconds since 1970, in UTC.
  final int createdAt;

  /// The version the backend gave the task; 0 while it only exists on the
  /// device. It is the basis of conflict detection (chapter 34).
  final int version;

  Map<String, Object?> toMap() => {
    'id': id,
    'title': title,
    'status': status,
    'created_at': createdAt,
    'version': version,
  };

  /// May throw `TaskFailure`, for a title the domain rejects, and
  /// [FormatException], for an unknown status: the caller decides what that
  /// means, because the data came from outside the domain (chapter 9).
  Task toEntity() => Task(
    id: id,
    title: TaskTitle.parse(title),
    status: _statuses[status] ?? (throw FormatException('Status $status')),
    createdAt: DateTime.fromMillisecondsSinceEpoch(createdAt, isUtc: true),
  );

  static final _statuses = TaskStatus.values.asNameMap();
}
