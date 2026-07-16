import SwiftUI

@main
@MainActor
struct CodexLinxDisplayApp: App {
  @StateObject private var model: AppModel
  private let updater: UpdaterController

  init() {
    let model = AppModel()
    let updater = UpdaterController()
    _model = StateObject(wrappedValue: model)
    self.updater = updater
    model.start()
  }

  var body: some Scene {
    MenuBarExtra {
      MenuBarContentView(model: model, updater: updater)
    } label: {
      if let snapshot = model.snapshot {
        Label("Codex \(snapshot.remainingPercent)%", systemImage: "rectangle.portrait")
      } else {
        Label("Codex 屏显", systemImage: "rectangle.portrait")
      }
    }
    .menuBarExtraStyle(.window)

    Settings {
      SettingsView(model: model, updater: updater)
    }
    .windowResizability(.contentSize)
  }
}
