import 'package:adapter_logging_crashlytics/adapter_logging_crashlytics.dart';
import 'package:firebase_crashlytics/firebase_crashlytics.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

final class _MockCrashlytics extends Mock implements FirebaseCrashlytics {}

void main() {
  late _MockCrashlytics crashlytics;
  late CrashlyticsAppLogger logger;
  final error = StateError('failed');
  final stackTrace = StackTrace.current;

  setUp(() {
    crashlytics = _MockCrashlytics();
    logger = CrashlyticsAppLogger(crashlytics: crashlytics);
  });

  test('log becomes a breadcrumb', () {
    when(() => crashlytics.log('opened the list')).thenAnswer((_) async {});

    logger.log('opened the list');

    verify(() => crashlytics.log('opened the list')).called(1);
  });

  test('error becomes a non-fatal error, with the reason', () {
    when(
      () => crashlytics.recordError(error, stackTrace, reason: 'outbox tasks'),
    ).thenAnswer((_) async {});

    logger.error('outbox tasks', error, stackTrace);

    verify(
      () => crashlytics.recordError(error, stackTrace, reason: 'outbox tasks'),
    ).called(1);
  });

  test('fatal becomes a fatal error', () {
    when(
      () => crashlytics.recordError(error, stackTrace, fatal: true),
    ).thenAnswer((_) async {});

    logger.fatal(error, stackTrace);

    verify(
      () => crashlytics.recordError(error, stackTrace, fatal: true),
    ).called(1);
  });

  test('setUserId(null) clears the identifier', () {
    when(() => crashlytics.setUserIdentifier('')).thenAnswer((_) async {});

    logger.setUserId(null);

    verify(() => crashlytics.setUserIdentifier('')).called(1);
  });
}
