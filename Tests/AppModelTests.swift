import AppKit
import XCTest

@testable import CodexLinxDisplay

final class AppModelTests: XCTestCase {
  @MainActor
  func testCustomImageModePausesCodexAndSwitchingBackRefreshesImmediately() async throws {
    let suiteName = "AppModelTests.\(UUID().uuidString)"
    let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
    defaults.removePersistentDomain(forName: suiteName)
    defer { defaults.removePersistentDomain(forName: suiteName) }

    let codexClient = FakeCodexClient()
    let imageClient = FakeImageClient()
    let imageDirectory = FileManager.default.temporaryDirectory
      .appendingPathComponent("codex-linx-storage-\(UUID().uuidString)", isDirectory: true)
    defer { try? FileManager.default.removeItem(at: imageDirectory) }
    let model = AppModel(
      defaults: defaults,
      codexClient: codexClient,
      imageAPIClient: imageClient,
      customImageDirectory: imageDirectory
    )

    model.start()
    let initialSyncCompleted = await waitUntil {
      let fetchCount = await codexClient.fetchCount
      let uploadCount = await imageClient.uploadCount
      return fetchCount == 1 && uploadCount == 1
    }
    XCTAssertTrue(initialSyncCompleted)

    let imageURL = try makeTemporaryImage()
    defer { try? FileManager.default.removeItem(at: imageURL) }
    model.selectCustomImage(at: imageURL)

    let customUploadCompleted = await waitUntil {
      await imageClient.uploadCount == 2
    }
    XCTAssertTrue(customUploadCompleted)
    XCTAssertEqual(model.displayMode, .customImage)
    XCTAssertTrue(
      FileManager.default.fileExists(
        atPath: imageDirectory.appendingPathComponent("custom-image.png").path))

    model.refreshOnly()
    try await Task.sleep(nanoseconds: 100_000_000)
    let pausedFetchCount = await codexClient.fetchCount
    XCTAssertEqual(pausedFetchCount, 1)

    model.setDisplayMode(.codex)
    let codexResumeCompleted = await waitUntil {
      let fetchCount = await codexClient.fetchCount
      let uploadCount = await imageClient.uploadCount
      return fetchCount == 2 && uploadCount == 3
    }
    XCTAssertTrue(codexResumeCompleted)
    XCTAssertEqual(model.displayMode, .codex)
  }

  @MainActor
  private func makeTemporaryImage() throws -> URL {
    let image = NSImage(size: NSSize(width: 320, height: 180))
    image.lockFocus()
    NSColor.systemBlue.setFill()
    NSRect(x: 0, y: 0, width: 320, height: 180).fill()
    image.unlockFocus()

    let tiffData = try XCTUnwrap(image.tiffRepresentation)
    let bitmap = try XCTUnwrap(NSBitmapImageRep(data: tiffData))
    let pngData = try XCTUnwrap(bitmap.representation(using: .png, properties: [:]))
    let url = FileManager.default.temporaryDirectory
      .appendingPathComponent("codex-linx-test-\(UUID().uuidString).png")
    try pngData.write(to: url, options: .atomic)
    return url
  }

  private func waitUntil(
    _ condition: @escaping () async -> Bool
  ) async -> Bool {
    for _ in 0..<100 {
      if await condition() { return true }
      try? await Task.sleep(nanoseconds: 20_000_000)
    }
    return false
  }
}

private actor FakeCodexClient: CodexRateLimitFetching {
  private(set) var fetchCount = 0

  func fetch() async throws -> UsageSnapshot {
    fetchCount += 1
    return .sample
  }
}

private actor FakeImageClient: ImageUploading {
  private(set) var uploadCount = 0

  func upload(_ imageData: Data, endpoint: String) async throws -> ImageUploadResult {
    uploadCount += 1
    return ImageUploadResult(statusCode: 200, responseText: "OK")
  }
}
