import 'package:core/core.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:tasks_module/adapters/driven/services/rest_task_service.dart';
import 'package:tasks_module/adapters/driven/task_api_paths.dart';

final class _MockApiClient extends Mock implements ApiClient {}

Map<String, Object?> _item(String id, {String title = 'A task'}) => {
  'id': id,
  'title': title,
  'status': 'open',
  'createdAt': '2026-10-27T09:00:00.000Z',
  'version': 1,
};

void main() {
  late _MockApiClient api;
  late RestTaskService service;

  setUpAll(() => registerFallbackValue(<String, String>{}));

  setUp(() {
    api = _MockApiClient();
    service = RestTaskService(apiClient: api, pageSize: 2);
  });

  /// The backend answers the page requested by the cursor (`null` on the first).
  void pages(Map<String?, Object?> byCursor) {
    when(
      () => api.get(TaskApiPaths.tasks, query: any(named: 'query')),
    ).thenAnswer((invocation) async {
      final query = invocation.namedArguments[#query] as Map<String, String>;
      return byCursor[query['cursor']];
    });
  }

  List<Map<String, String>> queries() => [
    for (final call in verify(
      () => api.get(TaskApiPaths.tasks, query: captureAny(named: 'query')),
    ).captured)
      call as Map<String, String>,
  ];

  test(
    'follows the cursor to the last page and returns the whole list',
    () async {
      pages({
        null: {
          'items': [_item('t-1'), _item('t-2')],
          'nextCursor': 'c-2',
        },
        'c-2': {
          'items': [_item('t-3')],
          'nextCursor': null,
        },
      });

      final tasks = await service.fetchActiveTasks();

      expect([for (final task in tasks) task.id], ['t-1', 't-2', 't-3']);
      expect(queries(), [
        {'status': 'active', 'limit': '2'},
        {'status': 'active', 'limit': '2', 'cursor': 'c-2'},
      ]);
    },
  );

  test('a page that fails brings the whole fetch down', () async {
    when(
      () => api.get(TaskApiPaths.tasks, query: any(named: 'query')),
    ).thenAnswer((invocation) async {
      final query = invocation.namedArguments[#query] as Map<String, String>;
      if (query['cursor'] == 'c-2') {
        throw const ApiError(ApiErrorKind.unreachable);
      }
      return {
        'items': [_item('t-1')],
        'nextCursor': 'c-2',
      };
    });

    await expectLater(
      service.fetchActiveTasks(),
      throwsA(
        isA<ApiError>().having((e) => e.kind, 'kind', ApiErrorKind.unreachable),
      ),
    );
  });

  test('a malformed response, or a task the domain rejects, is an '
      'invalid-response ApiError', () async {
    final invalid = isA<ApiError>().having(
      (e) => e.kind,
      'kind',
      ApiErrorKind.invalidResponse,
    );

    pages({
      null: {'items': 'nothing'},
    });
    await expectLater(service.fetchActiveTasks(), throwsA(invalid));

    pages({
      null: {
        'items': [_item('t-1', title: '  ')],
        'nextCursor': null,
      },
    });
    await expectLater(service.fetchActiveTasks(), throwsA(invalid));
  });

  test(
    'a repeated cursor stops the fetch, instead of spinning forever',
    () async {
      pages({
        null: {
          'items': [_item('t-1')],
          'nextCursor': 'c-2',
        },
        'c-2': {
          'items': [_item('t-2')],
          'nextCursor': 'c-2',
        },
      });

      await expectLater(
        service.fetchActiveTasks(),
        throwsA(
          isA<ApiError>().having(
            (e) => e.kind,
            'kind',
            ApiErrorKind.invalidResponse,
          ),
        ),
      );
    },
  );

  group('a single task (chapter 34)', () {
    final path = TaskApiPaths.task('t-1');

    test('fetches the server version by id', () async {
      when(() => api.get(path)).thenAnswer(
        (_) async => {
          ..._item('t-1', title: 'Pay the power bill'),
          'version': 7,
        },
      );

      final task = await service.fetchTask('t-1');

      expect(task?.title, 'Pay the power bill');
      expect(task?.version, 7);
    });

    test('404 is the task deleted on the server, not a failure', () async {
      when(
        () => api.get(path),
      ).thenThrow(const ApiError(ApiErrorKind.rejected, statusCode: 404));

      expect(await service.fetchTask('t-1'), isNull);
    });

    test('the other failures stay failures', () async {
      when(
        () => api.get(path),
      ).thenThrow(const ApiError(ApiErrorKind.unreachable));

      await expectLater(
        service.fetchTask('t-1'),
        throwsA(
          isA<ApiError>().having(
            (e) => e.kind,
            'kind',
            ApiErrorKind.unreachable,
          ),
        ),
      );
    });

    test('a malformed response, or one the domain rejects, is '
        'invalidResponse', () async {
      for (final body in [
        null,
        {'id': 't-1'},
        {..._item('t-1'), 'title': '   '},
      ]) {
        when(() => api.get(path)).thenAnswer((_) async => body);

        await expectLater(
          service.fetchTask('t-1'),
          throwsA(
            isA<ApiError>().having(
              (e) => e.kind,
              'kind',
              ApiErrorKind.invalidResponse,
            ),
          ),
        );
      }
    });
  });
}
