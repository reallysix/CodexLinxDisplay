import Foundation

enum CodexClientError: LocalizedError {
  case executableNotFound
  case launchFailed(String)
  case connectionClosed
  case timedOut
  case server(String)
  case invalidResponse

  var errorDescription: String? {
    switch self {
    case .executableNotFound:
      return "未找到 Codex CLI，请安装或设置 CODEX_CLI_PATH。"
    case .launchFailed(let message):
      return "Codex 启动失败：\(message)"
    case .connectionClosed:
      return "Codex 数据连接意外关闭。"
    case .timedOut:
      return "读取 Codex 用量超时。"
    case .server(let message):
      return "Codex 返回错误：\(message)"
    case .invalidResponse:
      return "Codex 返回了无法识别的用量数据。"
    }
  }
}

final class CodexRateLimitClient: @unchecked Sendable {
  private let explicitExecutableURL: URL?

  init(executableURL: URL? = nil) {
    explicitExecutableURL = executableURL
  }

  func fetch() async throws -> UsageSnapshot {
    let executableURL = try resolveExecutableURL()

    return try await withCheckedThrowingContinuation { continuation in
      DispatchQueue.global(qos: .utility).async {
        do {
          continuation.resume(returning: try self.fetchBlocking(executableURL: executableURL))
        } catch {
          continuation.resume(throwing: error)
        }
      }
    }
  }

  func fetchSynchronously() throws -> UsageSnapshot {
    try fetchBlocking(executableURL: resolveExecutableURL())
  }

  private func fetchBlocking(executableURL: URL) throws -> UsageSnapshot {
    let process = Process()
    let inputPipe = Pipe()
    let outputPipe = Pipe()

    process.executableURL = executableURL
    process.arguments = ["app-server", "--stdio"]
    process.standardInput = inputPipe
    process.standardOutput = outputPipe
    process.standardError = FileHandle.nullDevice

    do {
      try process.run()
    } catch {
      throw CodexClientError.launchFailed(error.localizedDescription)
    }

    let timeoutLock = NSLock()
    var timedOut = false
    let timeout = DispatchWorkItem {
      timeoutLock.lock()
      timedOut = true
      timeoutLock.unlock()
      if process.isRunning {
        process.terminate()
      }
    }
    DispatchQueue.global(qos: .utility).asyncAfter(deadline: .now() + 12, execute: timeout)

    defer {
      timeout.cancel()
      try? inputPipe.fileHandleForWriting.close()
      try? outputPipe.fileHandleForReading.close()
      if process.isRunning {
        process.terminate()
      }
    }

    try send(
      [
        "method": "initialize",
        "id": 0,
        "params": [
          "clientInfo": [
            "name": "codex_linx_display",
            "title": "Codex Linx Display",
            "version": "0.1.0",
          ],
          "capabilities": ["experimentalApi": true],
        ],
      ], to: inputPipe.fileHandleForWriting)

    var buffer = Data()
    var didRequestRateLimits = false

    while true {
      let chunk = outputPipe.fileHandleForReading.availableData
      guard !chunk.isEmpty else {
        timeoutLock.lock()
        let didTimeOut = timedOut
        timeoutLock.unlock()
        throw didTimeOut ? CodexClientError.timedOut : CodexClientError.connectionClosed
      }
      buffer.append(chunk)

      while let newlineIndex = buffer.firstIndex(of: 0x0A) {
        let line = buffer[..<newlineIndex]
        buffer.removeSubrange(...newlineIndex)
        guard !line.isEmpty else { continue }

        let envelope = try JSONDecoder().decode(AppServerEnvelope.self, from: Data(line))

        if envelope.id == 0, !didRequestRateLimits {
          didRequestRateLimits = true
          try send(["method": "initialized", "params": [:]], to: inputPipe.fileHandleForWriting)
          try send(
            ["method": "account/rateLimits/read", "id": 1, "params": NSNull()],
            to: inputPipe.fileHandleForWriting)
          continue
        }

        if envelope.id == 1 {
          if let message = envelope.error?.message {
            throw CodexClientError.server(message)
          }
          guard let result = envelope.result else {
            throw CodexClientError.invalidResponse
          }
          return try makeSnapshot(from: result)
        }
      }
    }
  }

  private func makeSnapshot(from result: RateLimitResult) throws -> UsageSnapshot {
    let limits = result.rateLimitsByLimitId?["codex"] ?? result.rateLimits
    let windows = [limits?.primary, limits?.secondary].compactMap { $0 }
    guard
      let window = windows.max(by: { ($0.windowDurationMins ?? 0) < ($1.windowDurationMins ?? 0) })
    else {
      throw CodexClientError.invalidResponse
    }

    return UsageSnapshot(
      remainingPercent: max(0, min(100, 100 - window.usedPercent)),
      resetDate: window.resetsAt.map { Date(timeIntervalSince1970: TimeInterval($0)) },
      windowMinutes: window.windowDurationMins,
      availableResetCount: max(0, result.rateLimitResetCredits?.availableCount ?? 0),
      planType: limits?.planType
    )
  }

  private func send(_ object: [String: Any], to handle: FileHandle) throws {
    var data = try JSONSerialization.data(withJSONObject: object)
    data.append(0x0A)
    try handle.write(contentsOf: data)
  }

  private func resolveExecutableURL() throws -> URL {
    if let explicitExecutableURL,
      FileManager.default.isExecutableFile(atPath: explicitExecutableURL.path)
    {
      return explicitExecutableURL
    }

    var candidates: [String] = []
    if let environmentPath = ProcessInfo.processInfo.environment["CODEX_CLI_PATH"] {
      candidates.append(environmentPath)
    }
    candidates.append(contentsOf: [
      "/Applications/ChatGPT.app/Contents/Resources/codex",
      "/Applications/Codex.app/Contents/Resources/codex",
      "/opt/homebrew/bin/codex",
      "/usr/local/bin/codex",
    ])

    guard let path = candidates.first(where: FileManager.default.isExecutableFile(atPath:)) else {
      throw CodexClientError.executableNotFound
    }
    return URL(fileURLWithPath: path)
  }
}

private struct AppServerEnvelope: Decodable {
  let id: Int?
  let result: RateLimitResult?
  let error: AppServerError?
}

private struct AppServerError: Decodable {
  let message: String
}

private struct RateLimitResult: Decodable {
  let rateLimits: RateLimitSnapshot?
  let rateLimitsByLimitId: [String: RateLimitSnapshot]?
  let rateLimitResetCredits: ResetCreditSummary?
}

private struct RateLimitSnapshot: Decodable {
  let primary: RateLimitWindow?
  let secondary: RateLimitWindow?
  let planType: String?
}

private struct RateLimitWindow: Decodable {
  let usedPercent: Int
  let windowDurationMins: Int?
  let resetsAt: Int?
}

private struct ResetCreditSummary: Decodable {
  let availableCount: Int
}
