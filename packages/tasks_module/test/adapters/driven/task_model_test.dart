import 'package:flutter_test/flutter_test.dart';
import 'package:tasks_module/adapters/driven/models/task_model.dart';
import 'package:tasks_module/domain/entities/task.dart';
import 'package:tasks_module/domain/task_failure.dart';
import 'package:tasks_module/domain/value_objects/task_title.dart';

void main() {
  final row = <String, Object?>{
    'id': 't-1',
    'title': 'Buy bread',
    'status': 'done',
    'created_at': DateTime.utc(2026, 10, 27, 9).millisecondsSinceEpoch,
    'version': 4,
  };

  test(
    'the row becomes the task, and the task goes back to the same row, with the version '
    'zeroed for one that has not talked to the backend yet',
    () {
      final model = TaskModel.fromMap(row);
      final task = model.toEntity();

      expect(model.version, 4);
      expect(task.id, 't-1');
      expect(task.title, TaskTitle.parse('Buy bread'));
      expect(task.status, TaskStatus.done);
      expect(task.createdAt, DateTime.utc(2026, 10, 27, 9));
      expect(task.createdAt.isUtc, isTrue);
      expect(TaskModel.fromEntity(task).toMap(), {...row, 'version': 0});
    },
  );

  test('a missing column, or one of another type, is a FormatException', () {
    expect(
      () => TaskModel.fromMap({...row}..remove('status')),
      throwsFormatException,
    );
    expect(
      () => TaskModel.fromMap({...row, 'created_at': '2026-10-27'}),
      throwsFormatException,
    );
  });

  test('an unknown status or a title the domain rejects does not '
      'become a task', () {
    expect(
      () => TaskModel.fromMap({...row, 'status': 'deleted'}).toEntity(),
      throwsFormatException,
    );
    expect(
      () => TaskModel.fromMap({...row, 'title': '  '}).toEntity(),
      throwsA(isA<EmptyTaskTitleFailure>()),
    );
  });

  group('the backend\'s task', () {
    final json = <String, Object?>{
      'id': 't-1',
      'title': 'Buy bread',
      'status': 'open',
      'createdAt': '2026-10-27T09:00:00.000Z',
      'version': 3,
      'ownerId': 'u-1',
    };

    test('becomes the same model the database stores, ignoring the extras', () {
      final model = TaskModel.fromJson(json);

      expect(model.toMap(), {
        'id': 't-1',
        'title': 'Buy bread',
        'status': 'open',
        'created_at': DateTime.utc(2026, 10, 27, 9).millisecondsSinceEpoch,
        'version': 3,
      });
    });

    test('a date without a time zone, or malformed, is a FormatException', () {
      expect(
        () => TaskModel.fromJson({...json, 'createdAt': '2026-10-27T09:00:00'}),
        throwsFormatException,
      );
      expect(
        () => TaskModel.fromJson({...json, 'createdAt': 'yesterday'}),
        throwsFormatException,
      );
      expect(
        () => TaskModel.fromJson({...json}..remove('version')),
        throwsFormatException,
      );
    });
  });
}
