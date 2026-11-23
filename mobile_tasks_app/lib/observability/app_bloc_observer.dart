import 'package:bloc/bloc.dart';
import 'package:core/core.dart';

/// The fourth path to the crash log (chapter 14). An error that escapes an
/// event handler reaches the Bloc's `onError` and from there the
/// [AppLogger], as a non-fatal error: it does not bring the app down, but it is a bug.
/// The host installs it; no module knows the observer.
final class AppBlocObserver extends BlocObserver {
  const AppBlocObserver(this._logger);

  final AppLogger _logger;

  @override
  void onError(BlocBase<dynamic> bloc, Object error, StackTrace stackTrace) {
    _logger.error('bloc ${bloc.runtimeType}', error, stackTrace);
    super.onError(bloc, error, stackTrace);
  }
}
