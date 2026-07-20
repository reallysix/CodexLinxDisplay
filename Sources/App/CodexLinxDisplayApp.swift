import SwiftUI

@main
@MainActor
struct CodexLinxDisplayApp: App {
  @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

  var body: some Scene {
    Settings {
      SettingsView(model: appDelegate.model, updater: appDelegate.updater)
    }
    .windowResizability(.contentSize)
  }
}
