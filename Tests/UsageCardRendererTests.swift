import AppKit
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

  @MainActor
  func testCustomImageIsCroppedToDeviceSizeWithDarkSafeArea() throws {
    let source = NSImage(size: NSSize(width: 320, height: 180))
    source.lockFocus()
    NSColor.systemRed.setFill()
    NSRect(x: 0, y: 0, width: 320, height: 180).fill()
    source.unlockFocus()

    let rendered = try CustomImageRenderer.render(
      image: source,
      safeAreaHeight: UsageCardLayout.defaultSafeArea,
      jpegQuality: 0.9
    )

    XCTAssertEqual(rendered.pixelWidth, 142)
    XCTAssertEqual(rendered.pixelHeight, 428)
    XCTAssertLessThanOrEqual(rendered.data.count, 512 * 1_024)

    let bitmap = try XCTUnwrap(NSBitmapImageRep(data: rendered.data))
    let safeAreaColor = try XCTUnwrap(bitmap.colorAt(x: 71, y: 10)?.usingColorSpace(.deviceRGB))
    let contentColor = try XCTUnwrap(bitmap.colorAt(x: 71, y: 200)?.usingColorSpace(.deviceRGB))
    XCTAssertLessThan(safeAreaColor.redComponent, 0.1)
    XCTAssertGreaterThan(contentColor.redComponent, 0.7)
  }
}
