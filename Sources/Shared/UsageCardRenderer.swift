import AppKit
import SwiftUI

enum CustomImageContentMode: String, CaseIterable, Identifiable {
  case fill
  case fit

  var id: String { rawValue }

  var title: String {
    switch self {
    case .fill: return "填充裁剪"
    case .fit: return "完整显示"
    }
  }
}

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
enum CustomImageRenderer {
  static func render(
    image: NSImage,
    topInset: CGFloat,
    jpegQuality: Double,
    contentMode: CustomImageContentMode = .fill
  ) throws -> RenderedUsageCard {
    let clampedTopInset = max(0, min(UsageCardLayout.maximumSafeArea, topInset))
    let contentHeight = UsageCardLayout.height - clampedTopInset

    let view = VStack(spacing: 0) {
      Color.black
        .frame(width: UsageCardLayout.width, height: clampedTopInset)

      Group {
        switch contentMode {
        case .fill:
          Image(nsImage: image)
            .resizable()
            .scaledToFill()
        case .fit:
          Image(nsImage: image)
            .resizable()
            .scaledToFit()
        }
      }
      .frame(width: UsageCardLayout.width, height: contentHeight)
      .background(Color.black)
      .clipped()
    }
    .frame(width: UsageCardLayout.width, height: UsageCardLayout.height)
    .background(Color.black)

    let renderer = ImageRenderer(content: view)
    renderer.proposedSize = ProposedViewSize(
      width: UsageCardLayout.width, height: UsageCardLayout.height)
    renderer.scale = 1
    renderer.isOpaque = true

    guard let cgImage = renderer.cgImage else {
      throw UsageCardRendererError.renderFailed
    }
    return try makeRenderedImage(cgImage: cgImage, jpegQuality: jpegQuality)
  }
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
    return try makeRenderedImage(cgImage: cgImage, jpegQuality: jpegQuality)
  }
}

private func makeRenderedImage(
  cgImage: CGImage,
  jpegQuality: Double
) throws -> RenderedUsageCard {
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
