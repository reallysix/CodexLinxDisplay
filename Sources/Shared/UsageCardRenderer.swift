import AppKit
import SwiftUI

enum UsageCardRendererError: LocalizedError {
  case renderFailed
  case encodingFailed
  case invalidDimensions
  case fileTooLarge(Int)

  var errorDescription: String? {
    switch self {
    case .renderFailed:
      return "无法生成屏幕图片。"
    case .encodingFailed:
      return "无法编码 JPEG 图片。"
    case .invalidDimensions:
      return "屏幕图片尺寸不是 142×428。"
    case .fileTooLarge(let bytes):
      return "屏幕图片为 \(bytes) 字节，超过 512KB 限制。"
    }
  }
}

struct RenderedUsageCard {
  let data: Data
  let image: NSImage
  let pixelWidth: Int
  let pixelHeight: Int
}

@MainActor
enum UsageCardRenderer {
  static func render(
    snapshot: UsageSnapshot?,
    safeAreaHeight: CGFloat,
    jpegQuality: Double
  ) throws -> RenderedUsageCard {
    let view = UsageCardView(snapshot: snapshot, safeAreaHeight: safeAreaHeight)
      .frame(width: UsageCardLayout.width, height: UsageCardLayout.height)

    let renderer = ImageRenderer(content: view)
    renderer.proposedSize = ProposedViewSize(
      width: UsageCardLayout.width, height: UsageCardLayout.height)
    renderer.scale = 1
    renderer.isOpaque = true

    guard let cgImage = renderer.cgImage else {
      throw UsageCardRendererError.renderFailed
    }
    guard cgImage.width == Int(UsageCardLayout.width), cgImage.height == Int(UsageCardLayout.height)
    else {
      throw UsageCardRendererError.invalidDimensions
    }

    let representation = NSBitmapImageRep(cgImage: cgImage)
    guard
      let data = representation.representation(
        using: .jpeg,
        properties: [.compressionFactor: max(0.5, min(1, jpegQuality))]
      )
    else {
      throw UsageCardRendererError.encodingFailed
    }
    guard data.count <= 512 * 1_024 else {
      throw UsageCardRendererError.fileTooLarge(data.count)
    }

    return RenderedUsageCard(
      data: data,
      image: NSImage(cgImage: cgImage, size: NSSize(width: cgImage.width, height: cgImage.height)),
      pixelWidth: cgImage.width,
      pixelHeight: cgImage.height
    )
  }
}
