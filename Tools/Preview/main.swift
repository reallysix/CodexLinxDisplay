import AppKit
import Foundation

let arguments = Array(CommandLine.arguments.dropFirst())
let useLiveData = arguments.contains("--live")
let outputPath = arguments.first(where: { $0 != "--live" }) ?? "./codex-linx-preview.jpg"

_ = NSApplication.shared

do {
  let snapshot = useLiveData ? try CodexRateLimitClient().fetchSynchronously() : .sample
  if useLiveData {
    let window = snapshot.windowMinutes.map(String.init) ?? "nil"
    let resetDate = snapshot.resetDate?.description ?? "nil"
    print(
      "Live usage: remaining=\(snapshot.remainingPercent), window=\(window), resets=\(snapshot.availableResetCount), resetDate=\(resetDate)"
    )
  }
  let rendered = try MainActor.assumeIsolated {
    try UsageCardRenderer.render(
      snapshot: snapshot,
      safeAreaHeight: UsageCardLayout.defaultSafeArea,
      jpegQuality: 0.9
    )
  }
  try rendered.data.write(to: URL(fileURLWithPath: outputPath), options: .atomic)
  print(
    "Rendered \(rendered.pixelWidth)x\(rendered.pixelHeight), \(rendered.data.count) bytes -> \(outputPath)"
  )
} catch {
  FileHandle.standardError.write(
    Data("Preview export failed: \(error.localizedDescription)\n".utf8))
  exit(1)
}
