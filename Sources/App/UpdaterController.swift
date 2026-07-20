import Sparkle

@MainActor
protocol UpdateChecking: AnyObject {
  func checkForUpdates()
  var currentVersion: String { get }
}

@MainActor
final class UpdaterController: UpdateChecking {
  private let controller: SPUStandardUpdaterController

  init() {
    controller = SPUStandardUpdaterController(
      startingUpdater: true,
      updaterDelegate: nil,
      userDriverDelegate: nil
    )
  }

  func checkForUpdates() {
    controller.checkForUpdates(nil)
  }

  var currentVersion: String {
    Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "未知"
  }
}
