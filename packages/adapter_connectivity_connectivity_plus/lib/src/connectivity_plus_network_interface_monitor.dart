import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:core/core.dart';

/// [NetworkInterfaceMonitor] with connectivity_plus. Answers only "is there
/// any network interface?"; whether the internet answers is up to the
/// [ReachabilityProbe]. `ConnectivityResult` never leaves this class.
final class ConnectivityPlusNetworkInterfaceMonitor
    implements NetworkInterfaceMonitor {
  ConnectivityPlusNetworkInterfaceMonitor({Connectivity? connectivity})
    : _connectivity = connectivity ?? Connectivity();

  final Connectivity _connectivity;

  @override
  Future<bool> hasNetworkInterface() async {
    try {
      return _hasInterface(await _connectivity.checkConnectivity());
    } on Exception {
      // Plugin failure: assume there is an interface and let the probe decide.
      return true;
    }
  }

  @override
  Stream<bool> get networkInterfaceChanges =>
      _connectivity.onConnectivityChanged.map(_hasInterface).distinct();

  static bool _hasInterface(List<ConnectivityResult> results) =>
      results.any((result) => result != ConnectivityResult.none);
}
