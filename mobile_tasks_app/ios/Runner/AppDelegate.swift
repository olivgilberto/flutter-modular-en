import Flutter
import UIKit
import workmanager_apple

@main
@objc class AppDelegate: FlutterAppDelegate, FlutterImplicitEngineDelegate {
  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    excludeLocalDatabasesFromBackup()
    registerBackgroundSync()
    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }

  /// Chapter 32: syncing the queues with the app closed. The identifier is
  /// WorkmanagerSyncScheduler.taskName, the same as the Info.plist's
  /// BGTaskSchedulerPermittedIdentifiers key; the frequency, the adapter's.
  /// iOS decides when to run: the value is only the minimum between two
  /// runs. The task runs on an engine of its own, without the plugins,
  /// which need to be registered on it.
  private func registerBackgroundSync() {
    WorkmanagerPlugin.setPluginRegistrantCallback { registry in
      GeneratedPluginRegistrant.register(with: registry)
    }
    WorkmanagerPlugin.registerPeriodicTask(
      withIdentifier: "outbox_sync",
      frequency: NSNumber(value: 60 * 60)
    )
  }

  /// Chapter 30: the modules' databases stay out of iCloud and computer
  /// backups. The folder is SqlcipherLocalDatabaseFactory.directoryName,
  /// inside Application Support. The flag goes on the folder, created here
  /// if it does not exist yet, and is set again on every app launch,
  /// because some file operations undo it.
  private func excludeLocalDatabasesFromBackup() {
    let fileManager = FileManager.default
    guard
      var directory = fileManager.urls(
        for: .applicationSupportDirectory, in: .userDomainMask
      ).first?.appendingPathComponent("local_databases", isDirectory: true)
    else { return }
    do {
      try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
      var values = URLResourceValues()
      values.isExcludedFromBackup = true
      try directory.setResourceValues(values)
    } catch {
      NSLog("local_databases excluded from backup: failed (\(error))")
    }
  }

  func didInitializeImplicitFlutterEngine(_ engineBridge: FlutterImplicitEngineBridge) {
    GeneratedPluginRegistrant.register(with: engineBridge.pluginRegistry)
  }
}
