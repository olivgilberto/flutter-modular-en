import 'package:flutter_test/flutter_test.dart';
import 'package:tasks_module/domain/task_failure.dart';
import 'package:tasks_module/domain/value_objects/task_title.dart';

void main() {
  test('trims the spaces at the ends', () {
    expect(TaskTitle.parse('  Buy bread \n').value, 'Buy bread');
  });

  test('empty, or only spaces, is not a title', () {
    expect(() => TaskTitle.parse(''), throwsA(isA<EmptyTaskTitleFailure>()));
    expect(
      () => TaskTitle.parse(' \t '),
      throwsA(isA<EmptyTaskTitleFailure>()),
    );
  });

  test('the limit counts code points, after the spaces are trimmed', () {
    final atLimit = 'a' * TaskTitle.maxLength;
    expect(TaskTitle.parse('  $atLimit  ').value, atLimit);
    expect(
      () => TaskTitle.parse('${atLimit}a'),
      throwsA(isA<TaskTitleTooLongFailure>()),
    );
    // An emoji outside the basic plane counts as one code point and two
    // UTF-16 units: 200 of them fit.
    expect(TaskTitle.parse('🙂' * TaskTitle.maxLength).value.length, 400);
  });

  test('two titles with the same text are equal', () {
    expect(
      TaskTitle.parse('Pay the power bill'),
      TaskTitle.parse(' Pay the power bill'),
    );
  });
}
