# adapter_connectivity_connectivity_plus

Layer 1 of connectivity (is there any network interface?), with
connectivity_plus.

- **Contains:** `ConnectivityPlusNetworkInterfaceMonitor`
  (`NetworkInterfaceMonitor` port).
- **Never contains:** the question "does the backend answer?" (that is the
  `HttpReachabilityProbe`) or the decision of when to sync (that is the
  core's `SyncOrchestrator`).
