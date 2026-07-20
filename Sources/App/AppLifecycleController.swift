import AppKit
import Combine
import SwiftUI

enum LaunchVisibilityPolicy {
  static func shouldShowSettings(
    currentVersion: String,
    lastPresentedVersion: String?
  ) -> Bool {
    currentVersion != lastPresentedVersion
  }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
  let model = AppModel()
  let updater = UpdaterController()

  private let defaults = UserDefaults.standard
  private var statusItemController: StatusItemController?
  private lazy var settingsWindowController = SettingsWindowController(
    model: model,
    updater: updater
  )

  func applicationDidFinishLaunching(_ notification: Notification) {
    NSApplication.shared.setActivationPolicy(.accessory)

    statusItemController = StatusItemController(
      model: model,
      updater: updater,
      showSettings: { [weak self] in
        self?.showSettings()
      }
    )
    model.start()

    let currentVersion = updater.currentVersion
    let lastPresentedVersion = defaults.string(forKey: Keys.lastPresentedVersion)
    if LaunchVisibilityPolicy.shouldShowSettings(
      currentVersion: currentVersion,
      lastPresentedVersion: lastPresentedVersion
    ) {
      defaults.set(currentVersion, forKey: Keys.lastPresentedVersion)
      DispatchQueue.main.async { [weak self] in
        self?.showSettings()
      }
    }
  }

  func applicationShouldHandleReopen(
    _ sender: NSApplication,
    hasVisibleWindows flag: Bool
  ) -> Bool {
    showSettings()
    return false
  }

  func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
    false
  }

  private func showSettings() {
    settingsWindowController.showSettings()
  }

  private enum Keys {
    static let lastPresentedVersion = "lastPresentedVersion"
  }
}

@MainActor
final class StatusItemController: NSObject {
  let statusItem: NSStatusItem

  private let statusBar: NSStatusBar
  private let model: AppModel
  private let popover = NSPopover()
  private var modelCancellable: AnyCancellable?

  init(
    model: AppModel,
    updater: any UpdateChecking,
    showSettings: @escaping () -> Void,
    statusBar: NSStatusBar = .system
  ) {
    self.model = model
    self.statusBar = statusBar
    statusItem = statusBar.statusItem(withLength: NSStatusItem.squareLength)

    super.init()

    let content = MenuBarContentView(
      model: model,
      updater: updater,
      showSettings: showSettings
    )
    popover.behavior = .transient
    popover.animates = false
    popover.contentViewController = NSHostingController(rootView: content)

    statusItem.behavior = []
    statusItem.isVisible = true
    if let button = statusItem.button {
      button.imagePosition = .imageOnly
      button.target = self
      button.action = #selector(togglePopover)
    }
    updateStatusItem()

    modelCancellable = model.objectWillChange.sink { [weak self] in
      DispatchQueue.main.async {
        self?.updateStatusItem()
      }
    }
  }

  deinit {
    statusBar.removeStatusItem(statusItem)
  }

  @objc private func togglePopover() {
    guard let button = statusItem.button else { return }

    if popover.isShown {
      popover.performClose(nil)
    } else {
      popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
      NSApplication.shared.activate(ignoringOtherApps: true)
    }
  }

  private func updateStatusItem() {
    guard let button = statusItem.button else { return }

    let symbolName = model.displayMode == .customImage ? "photo" : "rectangle.portrait"
    let image = NSImage(
      systemSymbolName: symbolName,
      accessibilityDescription: "Codex 屏显"
    )
    image?.isTemplate = true
    button.image = image
    button.toolTip = statusDescription
  }

  private var statusDescription: String {
    if model.displayMode == .customImage {
      return "Codex 屏显 · 图片显示"
    }
    if let snapshot = model.snapshot {
      return "Codex 屏显 · 剩余 \(snapshot.remainingPercent)%"
    }
    return "Codex 屏显"
  }
}

@MainActor
final class SettingsWindowController: NSWindowController {
  private static let frameAutosaveName = "CodexLinxDisplay.SettingsWindow"

  init(model: AppModel, updater: any UpdateChecking) {
    let contentViewController = NSHostingController(
      rootView: SettingsView(model: model, updater: updater)
    )
    let window = NSWindow(contentViewController: contentViewController)
    window.title = "Codex 屏显设置"
    window.styleMask = [.titled, .closable, .miniaturizable]
    window.tabbingMode = .disallowed
    window.isReleasedWhenClosed = false
    window.setFrameAutosaveName(Self.frameAutosaveName)

    super.init(window: window)

    if !window.setFrameUsingName(Self.frameAutosaveName) {
      window.center()
    }
  }

  @available(*, unavailable)
  required init?(coder: NSCoder) {
    nil
  }

  func showSettings() {
    showWindow(nil)
    window?.makeKeyAndOrderFront(nil)
    NSApplication.shared.activate(ignoringOtherApps: true)
  }
}
