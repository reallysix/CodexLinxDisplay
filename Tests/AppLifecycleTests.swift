import AppKit
import XCTest

@testable import CodexLinxDisplay

final class AppLifecycleTests: XCTestCase {
  func testSettingsAreShownForFirstLaunchAndVersionChanges() {
    XCTAssertTrue(
      LaunchVisibilityPolicy.shouldShowSettings(
        currentVersion: "0.3.1",
        lastPresentedVersion: nil
      ))
    XCTAssertTrue(
      LaunchVisibilityPolicy.shouldShowSettings(
        currentVersion: "0.3.1",
        lastPresentedVersion: "0.3.0"
      ))
    XCTAssertFalse(
      LaunchVisibilityPolicy.shouldShowSettings(
        currentVersion: "0.3.1",
        lastPresentedVersion: "0.3.1"
      ))
  }

  @MainActor
  func testStatusItemUsesAVisibleFixedWidthButton() {
    let model = AppModel()
    let controller = StatusItemController(
      model: model,
      updater: FakeUpdater(),
      showSettings: {}
    )

    XCTAssertEqual(controller.statusItem.length, NSStatusItem.squareLength)
    XCTAssertTrue(controller.statusItem.isVisible)
    XCTAssertNotNil(controller.statusItem.button)
    XCTAssertNotNil(controller.statusItem.button?.image)
    XCTAssertEqual(controller.statusItem.button?.imagePosition, .imageOnly)
  }
}

@MainActor
private final class FakeUpdater: UpdateChecking {
  let currentVersion = "0.3.1"

  func checkForUpdates() {}
}
