enum ConnectivityStatus {
  /// Not checked yet (boot): no notice, no sync.
  unknown,

  /// No network interface (airplane mode, Wi-Fi and mobile data off).
  offline,

  /// There is an interface, but the backend does not answer (Wi-Fi without
  /// internet, captive portal).
  noInternet,

  /// The backend answers.
  online,
}

/// Layer 1: is there any network interface? Cheap, driven by system
/// events; says nothing about the internet.
abstract interface class NetworkInterfaceMonitor {
  Future<bool> hasNetworkInterface();

  /// Emits whenever interface availability changes.
  Stream<bool> get networkInterfaceChanges;
}

/// Layer 2: does the backend answer? Any HTTP response counts as
/// reachable; only transport failures do not. Never throws.
abstract interface class ReachabilityProbe {
  Future<bool> isBackendReachable();
}

/// Combines both layers into a [ConnectivityStatus], for the host's notice
/// and for the [SyncOrchestrator]. It is only a hint: no action is blocked
/// because of it.
abstract interface class ConnectivityService {
  ConnectivityStatus get status;
  Stream<ConnectivityStatus> get statusChanges;

  /// Starts listening to interface changes and checks once. Never awaited
  /// at boot, because it may go to the network.
  Future<void> start();

  /// Reevaluates both layers now.
  Future<ConnectivityStatus> check();

  Future<void> dispose();
}
