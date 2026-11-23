/// Who owns the data the modules store on the device (chapter 32). Only
/// the user's opaque id, never a name or email: it is the minimum needed
/// to recognize someone else signing in, and it leaves with the data it
/// protects.
///
/// It survives an app restart, unlike the use case's memory: a session that
/// expired with unsent changes leaves the data on the device, and the next sign-in needs to know whose it is.
abstract interface class DataOwnerRepository {
  /// `null` when there is nobody's data on the device.
  Future<String?> currentOwner();

  Future<void> saveOwner(String userId);

  /// Called only after the data cleanup has finished.
  Future<void> clearOwner();
}
