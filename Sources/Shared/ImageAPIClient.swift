import Foundation

enum ImageAPIError: LocalizedError {
  case invalidURL
  case invalidResponse
  case connectionFailed
  case timedOut
  case networkUnavailable
  case transport(String)
  case rejected(Int, String)

  var errorDescription: String? {
    switch self {
    case .invalidURL:
      return "图像 API 地址无效。"
    case .invalidResponse:
      return "图像 API 没有返回有效的 HTTP 响应。"
    case .connectionFailed:
      return "无法连接键盘，请确认设备在线且 API 地址正确。"
    case .timedOut:
      return "连接键盘超时，请检查局域网和设备地址。"
    case .networkUnavailable:
      return "当前无法访问局域网；首次运行时请允许“本地网络”权限。"
    case .transport(let message):
      return "图像上传失败：\(message)"
    case .rejected(let code, let message):
      return message.isEmpty ? "图像 API 返回 HTTP \(code)。" : "图像 API 返回 HTTP \(code)：\(message)"
    }
  }
}

struct ImageUploadResult {
  let statusCode: Int
  let responseText: String
}

struct ImageAPIClient {
  func upload(_ imageData: Data, endpoint: String) async throws -> ImageUploadResult {
    guard let url = URL(string: endpoint),
      ["http", "https"].contains(url.scheme?.lowercased() ?? "")
    else {
      throw ImageAPIError.invalidURL
    }

    var request = URLRequest(url: url, timeoutInterval: 20)
    request.httpMethod = "POST"
    request.setValue("image/jpeg", forHTTPHeaderField: "Content-Type")
    request.httpBody = imageData

    let data: Data
    let response: URLResponse
    do {
      (data, response) = try await URLSession.shared.data(for: request)
    } catch let error as URLError {
      switch error.code {
      case .cannotConnectToHost, .cannotFindHost, .networkConnectionLost:
        throw ImageAPIError.connectionFailed
      case .timedOut:
        throw ImageAPIError.timedOut
      case .notConnectedToInternet, .dataNotAllowed:
        throw ImageAPIError.networkUnavailable
      default:
        throw ImageAPIError.transport(error.localizedDescription)
      }
    } catch {
      throw ImageAPIError.transport(error.localizedDescription)
    }
    guard let httpResponse = response as? HTTPURLResponse else {
      throw ImageAPIError.invalidResponse
    }

    let responseText =
      String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
    guard (200..<300).contains(httpResponse.statusCode) else {
      throw ImageAPIError.rejected(httpResponse.statusCode, responseText)
    }

    return ImageUploadResult(statusCode: httpResponse.statusCode, responseText: responseText)
  }
}
