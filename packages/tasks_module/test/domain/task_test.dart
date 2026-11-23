import 'package:flutter_test/flutter_test.dart';
import 'package:tasks_module/domain/entities/task.dart';
import 'package:tasks_module/domain/value_objects/task_title.dart';

void main() {
  final createdAt = DateTime.utc(2026, 10, 27, 9);
  final task = Task(
    id: 't-1',
    title: TaskTitle.parse('Buy bread'),
    createdAt: createdAt,
  );

  test('is born open', () {
    expect(task.status, TaskStatus.open);
    expect(task.isDone, isFalse);
    expect(task.isArchived, isFalse);
  });

  test('complete, reopen, and rename keep the id and the creation date', () {
    final done = task.complete();
    expect(done.isDone, isTrue);
    expect(done.reopen().status, TaskStatus.open);

    final renamed = task.rename(TaskTitle.parse('Buy bread and milk'));
    expect(renamed.title.value, 'Buy bread and milk');
    for (final changed in [done, renamed]) {
      expect(changed.id, task.id);
      expect(changed.createdAt, createdAt);
    }
  });

  test('equality by id', () {
    expect(task.rename(TaskTitle.parse('Another title')), task);
    expect(
      Task(id: 't-2', title: task.title, createdAt: createdAt),
      isNot(task),
    );
  });
}
