import AppKit
import Combine
import CryptoKit
import ServiceManagement

enum DisplayMode: String, CaseIterable, Identifiable {
  case codex
  case customImage

  var id: String { rawValue }

  var title: String {
    switch self {
    case .codex: return "Codex 用量"
    case .customImage: return "自定义图片"
    }
  }
}

enum ImageRotationMode: String, CaseIterable, Identifiable {
  case sequential
  case random

  var id: String { rawValue }

  var title: String {
    switch self {
    case .sequential: return "顺序切换"
    case .random: return "随机切换"
    }
  }
}

struct CustomImageItem: Identifiable, Equatable {
  let storageURL: URL
  let name: String

  var id: String { storageURL.path }
}

@MainActor
final class AppModel: ObservableObject {
  @Published private(set) var snapshot: UsageSnapshot?
  @Published private(set) var previewImage: NSImage?
  @Published private(set) var displayMode: DisplayMode
  @Published private(set) var customImages: [CustomImageItem] = []
  @Published private(set) var currentCustomImageIndex = 0
  @Published private(set) var imageRotationMode: ImageRotationMode
  @Published private(set) var imageRotationIntervalSeconds: Int
  @Published private(set) var customImageContentMode: CustomImageContentMode
  @Published private(set) var isSyncing = false
  @Published private(set) var statusText = "等待首次同步"
  @Published private(set) var lastError: String?
  @Published private(set) var lastUploadDate: Date?
  @Published private(set) var lastRefreshDate: Date?
  @Published private(set) var launchAtLogin = false

  @Published var endpoint: String {
    didSet { defaults.set(endpoint, forKey: Keys.endpoint) }
  }

  @Published var safeAreaHeight: Double {
    didSet {
      defaults.set(safeAreaHeight, forKey: Keys.safeAreaHeight)
      updatePreview()
    }
  }

  @Published var jpegQuality: Double {
    didSet {
      defaults.set(jpegQuality, forKey: Keys.jpegQuality)
      updatePreview()
    }
  }

  @Published private(set) var refreshIntervalSeconds: Int

  private let defaults: UserDefaults
  private let codexClient: any CodexRateLimitFetching
  private let imageAPIClient: any ImageUploading
  private let customImageDirectory: URL
  private var schedulerTask: Task<Void, Never>?
  private var imageRotationTask: Task<Void, Never>?
  private var pendingModeActionTask: Task<Void, Never>?
  private var wakeObserver: NSObjectProtocol?
  private var lastUploadedHash: String?
  private var customSourceImages: [NSImage] = []
  private var hasStarted = false

  init(
    defaults: UserDefaults = .standard,
    codexClient: any CodexRateLimitFetching = CodexRateLimitClient(),
    imageAPIClient: any ImageUploading = ImageAPIClient(),
    customImageDirectory: URL? = nil
  ) {
    self.defaults = defaults
    self.codexClient = codexClient
    self.imageAPIClient = imageAPIClient
    self.customImageDirectory = customImageDirectory ?? Self.defaultCustomImageDirectory

    endpoint = defaults.string(forKey: Keys.endpoint) ?? "http://192.168.31.71/image/upload"
    refreshIntervalSeconds = defaults.object(forKey: Keys.refreshInterval) as? Int ?? 300
    displayMode = DisplayMode(
      rawValue: defaults.string(forKey: Keys.displayMode) ?? ""
    ) ?? .codex
    imageRotationMode = ImageRotationMode(
      rawValue: defaults.string(forKey: Keys.imageRotationMode) ?? ""
    ) ?? .sequential
    imageRotationIntervalSeconds = max(
      1, defaults.object(forKey: Keys.imageRotationInterval) as? Int ?? 10)
    customImageContentMode = CustomImageContentMode(
      rawValue: defaults.string(forKey: Keys.customImageContentMode) ?? ""
    ) ?? .fill

    let storedSafeArea = defaults.object(forKey: Keys.safeAreaHeight) as? Double
    safeAreaHeight = storedSafeArea ?? Double(UsageCardLayout.defaultSafeArea)

    let storedQuality = defaults.object(forKey: Keys.jpegQuality) as? Double
    jpegQuality = storedQuality ?? 0.9

    loadStoredCustomImages()

    launchAtLogin = SMAppService.mainApp.status == .enabled
    updatePreview()
    if displayMode == .customImage {
      statusText = customSourceImages.isEmpty ? "请选择图片" : "图片轮播待推送"
    }
  }

  deinit {
    schedulerTask?.cancel()
    imageRotationTask?.cancel()
    pendingModeActionTask?.cancel()
    if let wakeObserver {
      NotificationCenter.default.removeObserver(wakeObserver)
    }
  }

  func start() {
    guard !hasStarted else { return }
    hasStarted = true

    wakeObserver = NSWorkspace.shared.notificationCenter.addObserver(
      forName: NSWorkspace.didWakeNotification,
      object: nil,
      queue: .main
    ) { [weak self] _ in
      Task { @MainActor in
        guard let self else { return }
        if self.displayMode == .codex {
          await self.synchronize(upload: true, forceUpload: true)
        } else {
          self.restartImageRotation(uploadImmediately: true)
        }
      }
    }

    if displayMode == .codex {
      restartScheduler(uploadImmediately: true)
    } else if !customSourceImages.isEmpty {
      restartImageRotation(uploadImmediately: true)
    }
  }

  func setRefreshInterval(_ seconds: Int) {
    guard refreshIntervalSeconds != seconds else { return }
    refreshIntervalSeconds = seconds
    defaults.set(seconds, forKey: Keys.refreshInterval)
    if displayMode == .codex {
      restartScheduler(uploadImmediately: false)
    }
  }

  func setImageRotationMode(_ mode: ImageRotationMode) {
    guard imageRotationMode != mode else { return }
    imageRotationMode = mode
    defaults.set(mode.rawValue, forKey: Keys.imageRotationMode)
    if displayMode == .customImage, hasStarted {
      restartImageRotation(uploadImmediately: false)
    }
  }

  func setImageRotationInterval(_ seconds: Int) {
    let clampedSeconds = max(1, min(3_600, seconds))
    guard imageRotationIntervalSeconds != clampedSeconds else { return }
    imageRotationIntervalSeconds = clampedSeconds
    defaults.set(clampedSeconds, forKey: Keys.imageRotationInterval)
    if displayMode == .customImage, hasStarted {
      restartImageRotation(uploadImmediately: false)
    }
  }

  func setCustomImageContentMode(_ mode: CustomImageContentMode) {
    guard customImageContentMode != mode else { return }
    customImageContentMode = mode
    defaults.set(mode.rawValue, forKey: Keys.customImageContentMode)
    lastUploadedHash = nil
    updatePreview()
    if displayMode == .customImage, hasStarted {
      scheduleCurrentModeAction()
    }
  }

  func setDisplayMode(_ mode: DisplayMode) {
    guard displayMode != mode else { return }

    displayMode = mode
    defaults.set(mode.rawValue, forKey: Keys.displayMode)
    lastUploadedHash = nil
    lastError = nil
    schedulerTask?.cancel()
    schedulerTask = nil
    imageRotationTask?.cancel()
    imageRotationTask = nil
    pendingModeActionTask?.cancel()
    updatePreview()

    if mode == .customImage {
      statusText = customSourceImages.isEmpty ? "请选择图片" : "Codex 刷新已暂停"
    } else {
      statusText = "准备读取 Codex"
    }

    if hasStarted {
      scheduleCurrentModeAction()
    }
  }

  func selectCustomImages(at urls: [URL]) {
    guard !urls.isEmpty else { return }

    let sourceImages = urls.compactMap { NSImage(contentsOf: $0) }
    guard sourceImages.count == urls.count else {
      lastError = "部分图片无法读取，请选择常见的图片格式。"
      statusText = "图片读取失败"
      return
    }

    do {
      let previousItems = customImages
      let storedURLs = try persistCustomImages(sourceImages)
      customImages = zip(storedURLs, urls).map {
        CustomImageItem(storageURL: $0.0, name: $0.1.lastPathComponent)
      }
      customSourceImages = storedURLs.compactMap { NSImage(contentsOf: $0) }
      currentCustomImageIndex = 0
      persistCustomImageManifest()
      removeStoredImages(previousItems)
      lastError = nil
    } catch {
      lastError = "无法保存所选图片：\(error.localizedDescription)"
      statusText = "图片保存失败"
      return
    }

    if displayMode != .customImage {
      setDisplayMode(.customImage)
    } else {
      lastUploadedHash = nil
      updatePreview()
      statusText = customImages.count > 1 ? "已准备 \(customImages.count) 张图片" : "图片已准备"
      if hasStarted {
        scheduleCurrentModeAction()
      }
    }
  }

  func refreshOnly() {
    guard displayMode == .codex else {
      statusText = "图片模式下 Codex 刷新已暂停"
      return
    }
    Task { await synchronize(upload: false, forceUpload: false) }
  }

  func pushNow() {
    if displayMode == .codex {
      Task { await synchronize(upload: true, forceUpload: true) }
    } else {
      scheduleCurrentModeAction()
    }
  }

  func updateLaunchAtLogin(_ enabled: Bool) {
    do {
      if enabled {
        try SMAppService.mainApp.register()
      } else {
        try SMAppService.mainApp.unregister()
      }
      launchAtLogin = enabled
      lastError = nil
    } catch {
      launchAtLogin = SMAppService.mainApp.status == .enabled
      lastError = "无法修改开机启动：\(error.localizedDescription)"
      statusText = "设置失败"
    }
  }

  func synchronize(upload: Bool, forceUpload: Bool) async {
    guard displayMode == .codex, !isSyncing else { return }
    isSyncing = true
    lastError = nil
    statusText = upload ? "正在同步并推送…" : "正在读取 Codex…"

    defer { isSyncing = false }

    do {
      let latestSnapshot = try await codexClient.fetch()
      guard displayMode == .codex else {
        statusText = customSourceImages.isEmpty ? "请选择图片" : "Codex 刷新已暂停"
        return
      }

      snapshot = latestSnapshot
      lastRefreshDate = Date()

      let rendered = try UsageCardRenderer.render(
        snapshot: latestSnapshot,
        safeAreaHeight: safeAreaHeight,
        jpegQuality: jpegQuality
      )
      previewImage = rendered.image

      guard upload else {
        statusText = "用量已刷新"
        return
      }

      let hash = SHA256.hash(data: rendered.data).map { String(format: "%02x", $0) }.joined()
      if !forceUpload, hash == lastUploadedHash {
        statusText = "数据未变化"
        return
      }

      let result = try await imageAPIClient.upload(rendered.data, endpoint: endpoint)
      lastUploadedHash = hash
      lastUploadDate = Date()
      statusText = "推送成功 · HTTP \(result.statusCode)"
    } catch {
      if displayMode == .codex {
        lastError = error.localizedDescription
        statusText = "同步失败"
      } else {
        lastError = nil
        statusText = customSourceImages.isEmpty ? "请选择图片" : "Codex 刷新已暂停"
      }
    }
  }

  func uploadCustomImage(forceUpload: Bool) async {
    guard displayMode == .customImage, !isSyncing else { return }
    guard let currentCustomSourceImage else {
      lastError = "请先选择要显示的图片。"
      statusText = "尚未选择图片"
      return
    }

    isSyncing = true
    lastError = nil
    statusText = "正在推送图片…"
    defer { isSyncing = false }

    do {
      let rendered = try CustomImageRenderer.render(
        image: currentCustomSourceImage,
        safeAreaHeight: safeAreaHeight,
        jpegQuality: jpegQuality,
        contentMode: customImageContentMode
      )
      previewImage = rendered.image

      let hash = SHA256.hash(data: rendered.data).map { String(format: "%02x", $0) }.joined()
      if !forceUpload, hash == lastUploadedHash {
        statusText = "图片未变化"
        return
      }

      guard displayMode == .customImage else { return }
      let result = try await imageAPIClient.upload(rendered.data, endpoint: endpoint)
      guard displayMode == .customImage else { return }
      lastUploadedHash = hash
      lastUploadDate = Date()
      statusText = "图片 \(customImagePositionText) 推送成功 · HTTP \(result.statusCode)"
    } catch {
      if displayMode == .customImage {
        lastError = error.localizedDescription
        statusText = "图片推送失败"
      }
    }
  }

  var lastUploadText: String {
    guard let lastUploadDate else { return "尚未推送" }
    return Self.dateTimeFormatter.string(from: lastUploadDate)
  }

  var customImageName: String? {
    currentCustomImage?.name
  }

  var customImagePositionText: String {
    guard !customImages.isEmpty else { return "0/0" }
    return "\(currentCustomImageIndex + 1)/\(customImages.count)"
  }

  var currentCustomImage: CustomImageItem? {
    guard customImages.indices.contains(currentCustomImageIndex) else { return nil }
    return customImages[currentCustomImageIndex]
  }

  var lastRefreshText: String {
    guard let lastRefreshDate else { return "尚未刷新" }
    return Self.dateTimeFormatter.string(from: lastRefreshDate)
  }

  private func restartScheduler(uploadImmediately: Bool) {
    schedulerTask?.cancel()
    guard displayMode == .codex else {
      schedulerTask = nil
      return
    }

    schedulerTask = Task { [weak self] in
      guard let self else { return }
      if uploadImmediately {
        await self.synchronize(upload: true, forceUpload: true)
      }

      while !Task.isCancelled {
        let interval = self.refreshIntervalSeconds
        try? await Task.sleep(nanoseconds: UInt64(interval) * 1_000_000_000)
        guard !Task.isCancelled, self.displayMode == .codex else { return }
        await self.synchronize(upload: true, forceUpload: false)
      }
    }
  }

  private func restartImageRotation(uploadImmediately: Bool) {
    imageRotationTask?.cancel()
    guard displayMode == .customImage, !customSourceImages.isEmpty else {
      imageRotationTask = nil
      return
    }

    imageRotationTask = Task { [weak self] in
      guard let self else { return }
      if uploadImmediately {
        await self.uploadCustomImage(forceUpload: true)
      }

      guard self.customSourceImages.count > 1 else { return }
      while !Task.isCancelled {
        let interval = self.imageRotationIntervalSeconds
        do {
          try await Task.sleep(nanoseconds: UInt64(interval) * 1_000_000_000)
        } catch {
          return
        }
        guard !Task.isCancelled, self.displayMode == .customImage else { return }
        self.advanceCustomImage()
        await self.uploadCustomImage(forceUpload: true)
      }
    }
  }

  func advanceCustomImage() {
    guard customImages.count > 1 else { return }

    switch imageRotationMode {
    case .sequential:
      currentCustomImageIndex = (currentCustomImageIndex + 1) % customImages.count
    case .random:
      var nextIndex = Int.random(in: 0..<(customImages.count - 1))
      if nextIndex >= currentCustomImageIndex {
        nextIndex += 1
      }
      currentCustomImageIndex = nextIndex
    }

    defaults.set(currentCustomImageIndex, forKey: Keys.currentCustomImageIndex)
    lastUploadedHash = nil
    updatePreview()
  }

  private func updatePreview() {
    do {
      switch displayMode {
      case .codex:
        previewImage = try UsageCardRenderer.render(
          snapshot: snapshot ?? .sample,
          safeAreaHeight: safeAreaHeight,
          jpegQuality: jpegQuality
        ).image
      case .customImage:
        guard let currentCustomSourceImage else {
          previewImage = nil
          return
        }
        previewImage = try CustomImageRenderer.render(
          image: currentCustomSourceImage,
          safeAreaHeight: safeAreaHeight,
          jpegQuality: jpegQuality,
          contentMode: customImageContentMode
        ).image
      }
    } catch {
      lastError = error.localizedDescription
    }
  }

  private func scheduleCurrentModeAction() {
    pendingModeActionTask?.cancel()
    let expectedMode = displayMode

    pendingModeActionTask = Task { [weak self] in
      guard let self else { return }
      while self.isSyncing {
        do {
          try await Task.sleep(nanoseconds: 50_000_000)
        } catch {
          return
        }
      }
      guard !Task.isCancelled, self.displayMode == expectedMode else { return }

      if expectedMode == .codex {
        self.restartScheduler(uploadImmediately: true)
      } else {
        self.restartImageRotation(uploadImmediately: true)
      }
    }
  }

  private func persistCustomImages(_ images: [NSImage]) throws -> [URL] {
    try FileManager.default.createDirectory(
      at: customImageDirectory,
      withIntermediateDirectories: true
    )

    var storedURLs: [URL] = []
    do {
      for (index, image) in images.enumerated() {
        guard let tiffData = image.tiffRepresentation,
          let bitmap = NSBitmapImageRep(data: tiffData),
          let pngData = bitmap.representation(using: .png, properties: [:])
        else {
          throw UsageCardRendererError.encodingFailed
        }

        let filename = String(
          format: "custom-image-%03d-%@.png", index + 1, UUID().uuidString)
        let storedURL = customImageDirectory.appendingPathComponent(filename)
        try pngData.write(to: storedURL, options: .atomic)
        storedURLs.append(storedURL)
      }
      return storedURLs
    } catch {
      for url in storedURLs {
        try? FileManager.default.removeItem(at: url)
      }
      throw error
    }
  }

  private func persistCustomImageManifest() {
    defaults.set(customImages.map { $0.storageURL.path }, forKey: Keys.customImagePaths)
    defaults.set(customImages.map(\.name), forKey: Keys.customImageNames)
    defaults.set(currentCustomImageIndex, forKey: Keys.currentCustomImageIndex)

    defaults.set(customImages.first?.storageURL.path, forKey: Keys.customImagePath)
    defaults.set(customImages.first?.name, forKey: Keys.customImageName)
  }

  private func loadStoredCustomImages() {
    var paths = defaults.stringArray(forKey: Keys.customImagePaths) ?? []
    var names = defaults.stringArray(forKey: Keys.customImageNames) ?? []

    if paths.isEmpty, let legacyPath = defaults.string(forKey: Keys.customImagePath) {
      paths = [legacyPath]
      names = [
        defaults.string(forKey: Keys.customImageName)
          ?? URL(fileURLWithPath: legacyPath).lastPathComponent
      ]
    }

    for (index, path) in paths.enumerated() {
      guard let image = NSImage(contentsOfFile: path) else { continue }
      let url = URL(fileURLWithPath: path)
      customImages.append(
        CustomImageItem(
          storageURL: url,
          name: names.indices.contains(index) ? names[index] : url.lastPathComponent
        ))
      customSourceImages.append(image)
    }

    let storedIndex = defaults.object(forKey: Keys.currentCustomImageIndex) as? Int ?? 0
    currentCustomImageIndex = customImages.indices.contains(storedIndex) ? storedIndex : 0
  }

  private func removeStoredImages(_ items: [CustomImageItem]) {
    let directory = customImageDirectory.standardizedFileURL
    let retainedPaths = Set(customImages.map { $0.storageURL.standardizedFileURL.path })
    for item in items {
      let url = item.storageURL.standardizedFileURL
      guard url.deletingLastPathComponent() == directory,
        !retainedPaths.contains(url.path)
      else { continue }
      try? FileManager.default.removeItem(at: url)
    }
  }

  private var currentCustomSourceImage: NSImage? {
    guard customSourceImages.indices.contains(currentCustomImageIndex) else { return nil }
    return customSourceImages[currentCustomImageIndex]
  }

  private enum Keys {
    static let endpoint = "imageAPIEndpoint"
    static let refreshInterval = "refreshIntervalSeconds"
    static let safeAreaHeight = "safeAreaHeight"
    static let jpegQuality = "jpegQuality"
    static let displayMode = "displayMode"
    static let customImagePath = "customImagePath"
    static let customImageName = "customImageName"
    static let customImagePaths = "customImagePaths"
    static let customImageNames = "customImageNames"
    static let currentCustomImageIndex = "currentCustomImageIndex"
    static let imageRotationMode = "imageRotationMode"
    static let imageRotationInterval = "imageRotationIntervalSeconds"
    static let customImageContentMode = "customImageContentMode"
  }

  private static let defaultCustomImageDirectory = FileManager.default
    .urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
    .appendingPathComponent("CodexLinxDisplay", isDirectory: true)

  private static let dateTimeFormatter: DateFormatter = {
    let formatter = DateFormatter()
    formatter.locale = Locale(identifier: "zh_CN")
    formatter.dateFormat = "M月d日 HH:mm:ss"
    return formatter
  }()
}
