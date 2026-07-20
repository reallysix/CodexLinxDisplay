import AppKit
import SwiftUI
import UniformTypeIdentifiers

struct MenuBarContentView: View {
  @ObservedObject var model: AppModel
  let updater: UpdaterController

  var body: some View {
    VStack(alignment: .leading, spacing: 14) {
      header

      usageSummary

      Divider()

      VStack(alignment: .leading, spacing: 5) {
        Label(
          model.statusText,
          systemImage: model.lastError == nil ? "checkmark.circle" : "exclamationmark.triangle"
        )
        .foregroundStyle(model.lastError == nil ? Color.secondary : Color.orange)

        Text("上次推送：\(model.lastUploadText)")
          .font(.caption)
          .foregroundStyle(.secondary)

        if let error = model.lastError {
          Text(error)
            .font(.caption)
            .foregroundStyle(.red)
            .fixedSize(horizontal: false, vertical: true)
        }
      }

      HStack {
        if model.displayMode == .codex {
          Button {
            model.refreshOnly()
          } label: {
            Label("刷新", systemImage: "arrow.clockwise")
          }
          .disabled(model.isSyncing)
        } else {
          Button {
            chooseCustomImages()
          } label: {
            Label("选择图片", systemImage: "photo.on.rectangle.angled")
          }
          .disabled(model.isSyncing)
        }

        Button {
          model.pushNow()
        } label: {
          Label("立即推送", systemImage: "paperplane")
        }
        .buttonStyle(.borderedProminent)
        .disabled(
          model.isSyncing
            || (model.displayMode == .customImage && model.customImages.isEmpty)
        )

        Spacer()
      }

      Divider()

      HStack {
        SettingsLink {
          Label("设置", systemImage: "gearshape")
        }

        Button {
          updater.checkForUpdates()
        } label: {
          Label("检查更新", systemImage: "arrow.down.circle")
        }

        Spacer()

        Button("退出") {
          NSApplication.shared.terminate(nil)
        }
      }
    }
    .padding(16)
    .frame(width: 320)
  }

  private var header: some View {
    HStack {
      ZStack {
        RoundedRectangle(cornerRadius: 8)
          .fill(Color.accentColor.opacity(0.16))
          .frame(width: 36, height: 36)
        Image(systemName: "rectangle.portrait")
          .font(.system(size: 18, weight: .semibold))
          .foregroundStyle(Color.accentColor)
      }

      VStack(alignment: .leading, spacing: 2) {
        Text("Codex 屏显")
          .font(.headline)
        Text(model.displayMode == .codex ? "Linx68 后台用量卡片" : "Linx68 自定义图片")
          .font(.caption)
          .foregroundStyle(.secondary)
      }

      Spacer()

      if model.isSyncing {
        ProgressView()
          .controlSize(.small)
      }
    }
  }

  private var usageSummary: some View {
    Group {
      if model.displayMode == .codex {
        HStack(spacing: 10) {
          summaryCell(
            title: model.snapshot?.windowTitle ?? "剩余用量",
            value: model.snapshot.map { "\($0.remainingPercent)%" } ?? "--"
          )
          summaryCell(
            title: "可用重置",
            value: model.snapshot.map { "\($0.availableResetCount) 次" } ?? "--"
          )
        }
      } else {
        VStack(alignment: .leading, spacing: 5) {
          Label(model.customImageName ?? "尚未选择图片", systemImage: "photo.on.rectangle.angled")
            .font(.headline)
            .lineLimit(1)
            .truncationMode(.middle)

          Text(
            model.customImages.count > 1
              ? "\(model.customImagePositionText) · \(model.imageRotationMode.title) · 每 \(model.imageRotationIntervalSeconds) 秒"
              : "Codex 自动刷新已暂停"
          )
            .font(.caption)
            .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(10)
        .background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: 10))
      }
    }
  }

  private func summaryCell(title: String, value: String) -> some View {
    VStack(alignment: .leading, spacing: 4) {
      Text(title)
        .font(.caption)
        .foregroundStyle(.secondary)
      Text(value)
        .font(.title2.bold())
    }
    .frame(maxWidth: .infinity, alignment: .leading)
    .padding(10)
    .background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: 10))
  }

  private func chooseCustomImages() {
    let panel = NSOpenPanel()
    panel.title = "选择要轮播显示的图片"
    panel.prompt = "选择图片"
    panel.allowedContentTypes = [.image]
    panel.allowsMultipleSelection = true
    panel.canChooseDirectories = false

    if panel.runModal() == .OK {
      model.selectCustomImages(at: panel.urls)
    }
  }
}
