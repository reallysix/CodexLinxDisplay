import XCTest

@testable import CodexLinxDisplay

final class UsageCardRendererTests: XCTestCase {
  @MainActor
  func testPopulatedCardHasDeviceDimensionsAndSizeLimit() throws {
    let rendered = try UsageCardRenderer.render(
      snapshot: .sample,
      safeAreaHeight: UsageCardLayout.defaultSafeArea,
      jpegQuality: 0.9
    )

    XCTAssertEqual(rendered.pixelWidth, 142)
    XCTAssertEqual(rendered.pixelHeight, 428)
    XCTAssertLessThanOrEqual(rendered.data.count, 512 * 1_024)
  }

  @MainActor
  func testEmptyCardAlsoRenders() throws {
    let rendered = try UsageCardRenderer.render(
      snapshot: nil,
      safeAreaHeight: UsageCardLayout.defaultSafeArea,
      jpegQuality: 0.9
    )

    XCTAssertEqual(rendered.pixelWidth, 142)
    XCTAssertEqual(rendered.pixelHeight, 428)
  }

  func testDefaultSafeAreaLeavesRoomForFirmwareStatusBar() {
    XCTAssertEqual(UsageCardLayout.defaultSafeArea, 56)
    XCTAssertGreaterThanOrEqual(UsageCardLayout.defaultSafeArea, UsageCardLayout.minimumSafeArea)
  }
}
