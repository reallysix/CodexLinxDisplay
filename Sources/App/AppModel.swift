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

@MainActor
final class AppModel: ObservableObject {
  @Published private(set) var snapshot: UsageSnapshot?
  @Published private(set) var previewImage: NSImage?
  @Published private(set) var displayMode: DisplayMode
  @Published private(set) var customImageName: String?
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
  private var pendingModeActionTask: Task<Void, Never>?
  private var wakeObserver: NSObjectProtocol?
  private var lastUploadedHash: String?
  private var customSourceImage: NSImage?
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

    let storedSafeArea = defaults.object(forKey: Keys.safeAreaHeight) as? Double
    safeAreaHeight = storedSafeArea ?? Double(UsageCardLayout.defaultSafeArea)

    let storedQuality = defaults.object(forKey: Keys.jpegQuality) as? Double
    jpegQuality = storedQuality ?? 0.9

    if let path = defaults.string(forKey: Keys.customImagePath),
      let image = NSImage(contentsOfFile: path)
    {
      customSourceImage = image
      customImageName =
        defaults.string(forKey: Keys.customImageName)
        ?? URL(fileURLWithPath: path).lastPathComponent
    }

    launchAtLogin = SMAppService.mainApp.status == .enabled
    updatePreview()
    if displayMode == .customImage {
      statusText = customSourceImage == nil ? "请选择一张图片" : "图片模式待推送"
    }
  }

  deinit {
    schedulerTask?.cancel()
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
          await self.uploadCustomImage(forceUpload: true)
        }
      }
    }

    if displayMode == .codex {
      restartScheduler(uploadImmediately: true)
    } else if customSourceImage != nil {
      scheduleCurrentModeAction()
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

  func setDisplayMode(_ mode: DisplayMode) {
    guard displayMode != mode else { return }

    displayMode = mode
    defaults.set(mode.rawValue, forKey: Keys.displayMode)
    lastUploadedHash = nil
    lastError = nil
    schedulerTask?.cancel()
    schedulerTask = nil
    pendingModeActionTask?.cancel()
    updatePreview()

    if mode == .customImage {
      statusText = customSourceImage == nil ? "请选择一张图片" : "Codex 刷新已暂停"
    } else {
      statusText = "准备读取 Codex"
    }

    if hasStarted {
      scheduleCurrentModeAction()
    }
  }

  func selectCustomImage(at url: URL) {
    guard let image = NSImage(contentsOf: url) else {
      lastError = "无法读取所选图片，请选择常见的图片格式。"
      statusText = "图片读取失败"
      return
    }

    do {
      let storedURL = try persistCustomImage(image)
      customSourceImage = image
      customImageName = url.lastPathComponent
      defaults.set(storedURL.path, forKey: Keys.customImagePath)
      defaults.set(url.lastPathComponent, forKey: Keys.customImageName)
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
      statusText = "图片已准备"
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
        statusText = customSourceImage == nil ? "请选择一张图片" : "Codex 刷新已暂停"
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
        statusText = customSourceImage == nil ? "请选择一张图片" : "Codex 刷新已暂停"
      }
    }
  }

  func uploadCustomImage(forceUpload: Bool) async {
    guard displayMode == .customImage, !isSyncing else { return }
    guard let customSourceImage else {
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
        image: customSourceImage,
        safeAreaHeight: safeAreaHeight,
        jpegQuality: jpegQuality
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
      statusText = "图片推送成功 · HTTP \(result.statusCode)"
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
        guard let customSourceImage else {
          previewImage = nil
          return
        }
        previewImage = try CustomImageRenderer.render(
          image: customSourceImage,
          safeAreaHeight: safeAreaHeight,
          jpegQuality: jpegQuality
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
        await self.uploadCustomImage(forceUpload: true)
      }
    }
  }

  private func persistCustomImage(_ image: NSImage) throws -> URL {
    guard let tiffData = image.tiffRepresentation,
      let bitmap = NSBitmapImageRep(data: tiffData),
      let pngData = bitmap.representation(using: .png, properties: [:])
    else {
      throw UsageCardRendererError.encodingFailed
    }

    try FileManager.default.createDirectory(
      at: customImageDirectory,
      withIntermediateDirectories: true
    )
    let storedURL = customImageDirectory.appendingPathComponent("custom-image.png")
    try pngData.write(to: storedURL, options: .atomic)
    return storedURL
  }

  private enum Keys {
    static let endpoint = "imageAPIEndpoint"
    static let refreshInterval = "refreshIntervalSeconds"
    static let safeAreaHeight = "safeAreaHeight"
    static let jpegQuality = "jpegQuality"
    static let displayMode = "displayMode"
    static let customImagePath = "customImagePath"
    static let customImageName = "customImageName"
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
