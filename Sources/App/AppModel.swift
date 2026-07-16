import AppKit
import Combine
import CryptoKit
import ServiceManagement

@MainActor
final class AppModel: ObservableObject {
  @Published private(set) var snapshot: UsageSnapshot?
  @Published private(set) var previewImage: NSImage?
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
  private let codexClient: CodexRateLimitClient
  private let imageAPIClient: ImageAPIClient
  private var schedulerTask: Task<Void, Never>?
  private var wakeObserver: NSObjectProtocol?
  private var lastUploadedHash: String?
  private var hasStarted = false

  init(
    defaults: UserDefaults = .standard,
    codexClient: CodexRateLimitClient = CodexRateLimitClient(),
    imageAPIClient: ImageAPIClient = ImageAPIClient()
  ) {
    self.defaults = defaults
    self.codexClient = codexClient
    self.imageAPIClient = imageAPIClient

    endpoint = defaults.string(forKey: Keys.endpoint) ?? "http://192.168.31.71/image/upload"
    refreshIntervalSeconds = defaults.object(forKey: Keys.refreshInterval) as? Int ?? 300

    let storedSafeArea = defaults.object(forKey: Keys.safeAreaHeight) as? Double
    safeAreaHeight = storedSafeArea ?? Double(UsageCardLayout.defaultSafeArea)

    let storedQuality = defaults.object(forKey: Keys.jpegQuality) as? Double
    jpegQuality = storedQuality ?? 0.9

    launchAtLogin = SMAppService.mainApp.status == .enabled
    updatePreview()
  }

  deinit {
    schedulerTask?.cancel()
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
        await self?.synchronize(upload: true, forceUpload: true)
      }
    }

    restartScheduler(uploadImmediately: true)
  }

  func setRefreshInterval(_ seconds: Int) {
    guard refreshIntervalSeconds != seconds else { return }
    refreshIntervalSeconds = seconds
    defaults.set(seconds, forKey: Keys.refreshInterval)
    restartScheduler(uploadImmediately: false)
  }

  func refreshOnly() {
    Task { await synchronize(upload: false, forceUpload: false) }
  }

  func pushNow() {
    Task { await synchronize(upload: true, forceUpload: true) }
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
    guard !isSyncing else { return }
    isSyncing = true
    lastError = nil
    statusText = upload ? "正在同步并推送…" : "正在读取 Codex…"

    defer { isSyncing = false }

    do {
      let latestSnapshot = try await codexClient.fetch()
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
      lastError = error.localizedDescription
      statusText = "同步失败"
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
    schedulerTask = Task { [weak self] in
      guard let self else { return }
      if uploadImmediately {
        await self.synchronize(upload: true, forceUpload: true)
      }

      while !Task.isCancelled {
        let interval = self.refreshIntervalSeconds
        try? await Task.sleep(nanoseconds: UInt64(interval) * 1_000_000_000)
        guard !Task.isCancelled else { return }
        await self.synchronize(upload: true, forceUpload: false)
      }
    }
  }

  private func updatePreview() {
    do {
      previewImage = try UsageCardRenderer.render(
        snapshot: snapshot ?? .sample,
        safeAreaHeight: safeAreaHeight,
        jpegQuality: jpegQuality
      ).image
    } catch {
      lastError = error.localizedDescription
    }
  }

  private enum Keys {
    static let endpoint = "imageAPIEndpoint"
    static let refreshInterval = "refreshIntervalSeconds"
    static let safeAreaHeight = "safeAreaHeight"
    static let jpegQuality = "jpegQuality"
  }

  private static let dateTimeFormatter: DateFormatter = {
    let formatter = DateFormatter()
    formatter.locale = Locale(identifier: "zh_CN")
    formatter.dateFormat = "M月d日 HH:mm:ss"
    return formatter
  }()
}
