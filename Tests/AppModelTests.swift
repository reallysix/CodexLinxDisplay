import AppKit
import XCTest

@testable import CodexLinxDisplay

final class AppModelTests: XCTestCase {
  @MainActor
  func testLayoutSettingsAreIndependentAndCustomImagesDefaultToNoTopInset() throws {
    let suiteName = "AppModelTests.\(UUID().uuidString)"
    let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
    defaults.removePersistentDomain(forName: suiteName)
    defer { defaults.removePersistentDomain(forName: suiteName) }

    defaults.set(68.0, forKey: "safeAreaHeight")

    let model = AppModel(defaults: defaults)
    XCTAssertEqual(model.codexSafeAreaHeight, 68)
    XCTAssertEqual(model.customImageTopInset, 0)

    model.setCodexSafeAreaHeight(60)
    model.setCustomImageTopInset(12)

    let restoredModel = AppModel(defaults: defaults)
    XCTAssertEqual(restoredModel.codexSafeAreaHeight, 60)
    XCTAssertEqual(restoredModel.customImageTopInset, 12)

    restoredModel.setCodexSafeAreaHeight(1)
    restoredModel.setCustomImageTopInset(1_000)
    restoredModel.setImageRotationInterval(0)
    XCTAssertEqual(restoredModel.codexSafeAreaHeight, 44)
    XCTAssertEqual(restoredModel.customImageTopInset, 80)
    XCTAssertEqual(restoredModel.imageRotationIntervalSeconds, 1)
  }

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
    model.selectCustomImages(at: [imageURL])

    let customUploadCompleted = await waitUntil {
      await imageClient.uploadCount == 2
    }
    XCTAssertTrue(customUploadCompleted)
    XCTAssertEqual(model.displayMode, .customImage)
    XCTAssertEqual(model.customImages.count, 1)
    XCTAssertTrue(FileManager.default.fileExists(atPath: model.customImages[0].storageURL.path))

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
  func testMultipleImagesPersistAndRotationNeverRepeatsCurrentImage() throws {
    let suiteName = "AppModelTests.\(UUID().uuidString)"
    let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
    defaults.removePersistentDomain(forName: suiteName)
    defer { defaults.removePersistentDomain(forName: suiteName) }

    let imageDirectory = FileManager.default.temporaryDirectory
      .appendingPathComponent("codex-linx-storage-\(UUID().uuidString)", isDirectory: true)
    defer { try? FileManager.default.removeItem(at: imageDirectory) }
    let urls = try [
      makeTemporaryImage(color: .systemRed),
      makeTemporaryImage(color: .systemGreen),
      makeTemporaryImage(color: .systemBlue),
    ]
    defer { urls.forEach { try? FileManager.default.removeItem(at: $0) } }

    let model = AppModel(defaults: defaults, customImageDirectory: imageDirectory)
    model.selectCustomImages(at: urls)

    XCTAssertEqual(model.customImages.count, 3)
    XCTAssertEqual(model.currentCustomImageIndex, 0)
    model.advanceCustomImage()
    XCTAssertEqual(model.currentCustomImageIndex, 1)

    model.setImageRotationMode(.random)
    for _ in 0..<50 {
      let previousIndex = model.currentCustomImageIndex
      model.advanceCustomImage()
      XCTAssertNotEqual(model.currentCustomImageIndex, previousIndex)
    }

    let restoredModel = AppModel(defaults: defaults, customImageDirectory: imageDirectory)
    XCTAssertEqual(restoredModel.customImages.map(\.name), model.customImages.map(\.name))
    XCTAssertEqual(restoredModel.currentCustomImageIndex, model.currentCustomImageIndex)
  }

  @MainActor
  func testCustomImageSchedulerAdvancesAndUploadsNextImage() async throws {
    let suiteName = "AppModelTests.\(UUID().uuidString)"
    let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
    defaults.removePersistentDomain(forName: suiteName)
    defer { defaults.removePersistentDomain(forName: suiteName) }

    let imageClient = FakeImageClient()
    let imageDirectory = FileManager.default.temporaryDirectory
      .appendingPathComponent("codex-linx-storage-\(UUID().uuidString)", isDirectory: true)
    defer { try? FileManager.default.removeItem(at: imageDirectory) }
    let urls = try [
      makeTemporaryImage(color: .systemPurple),
      makeTemporaryImage(color: .systemOrange),
    ]
    defer { urls.forEach { try? FileManager.default.removeItem(at: $0) } }

    let model = AppModel(
      defaults: defaults,
      imageAPIClient: imageClient,
      customImageDirectory: imageDirectory
    )
    model.selectCustomImages(at: urls)
    model.setImageRotationInterval(1)
    model.start()

    let secondUploadCompleted = await waitUntil(timeoutIterations: 150) {
      await imageClient.uploadCount >= 2
    }
    XCTAssertTrue(secondUploadCompleted)
    XCTAssertEqual(model.currentCustomImageIndex, 1)
  }

  @MainActor
  private func makeTemporaryImage(color: NSColor = .systemBlue) throws -> URL {
    let image = NSImage(size: NSSize(width: 320, height: 180))
    image.lockFocus()
    color.setFill()
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
    timeoutIterations: Int = 100,
    _ condition: @escaping () async -> Bool
  ) async -> Bool {
    for _ in 0..<timeoutIterations {
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
