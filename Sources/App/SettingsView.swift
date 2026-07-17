import AppKit
import SwiftUI
import UniformTypeIdentifiers

struct SettingsView: View {
  @ObservedObject var model: AppModel
  let updater: UpdaterController

  private let intervals = [60, 300, 600, 1_800]

  var body: some View {
    HStack(alignment: .top, spacing: 22) {
      VStack(alignment: .leading, spacing: 12) {
        settingsSection("显示内容") {
          VStack(spacing: 8) {
            Picker(
              "显示模式",
              selection: Binding(
                get: { model.displayMode },
                set: { model.setDisplayMode($0) }
              )
            ) {
              ForEach(DisplayMode.allCases) { mode in
                Text(mode.title).tag(mode)
              }
            }
            .pickerStyle(.segmented)

            if model.displayMode == .customImage {
              HStack {
                Button("选择图片…") {
                  chooseCustomImage()
                }

                Text(model.customImageName ?? "尚未选择图片")
                  .lineLimit(1)
                  .truncationMode(.middle)
                  .foregroundStyle(.secondary)

                Spacer()
              }

              Text("图片会自动裁切并保留顶部状态栏；Codex 用量刷新已暂停。")
                .font(.caption)
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)
            } else {
              Text("切换到 Codex 时会立即读取并推送一次，之后按刷新间隔自动更新。")
                .font(.caption)
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
          }
        }

        settingsSection("设备接口") {
          VStack(spacing: 8) {
            TextField("图像 API 地址", text: $model.endpoint)
              .textFieldStyle(.roundedBorder)

            HStack {
              Text("请求格式")
              Spacer()
              Text("POST · image/jpeg")
                .foregroundStyle(.secondary)
            }

            Button("立即推送当前内容") {
              model.pushNow()
            }
            .disabled(model.isSyncing)
            .frame(maxWidth: .infinity, alignment: .leading)
          }
        }

        settingsSection("后台刷新") {
          VStack(spacing: 8) {
            Picker(
              "刷新间隔",
              selection: Binding(
                get: { model.refreshIntervalSeconds },
                set: { model.setRefreshInterval($0) }
              )
            ) {
              ForEach(intervals, id: \.self) { seconds in
                Text(intervalTitle(seconds)).tag(seconds)
              }
            }
            .disabled(model.displayMode == .customImage)

            if model.displayMode == .customImage {
              Text("图片模式下不读取 Codex 用量。")
                .font(.caption)
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)
            }

            Toggle(
              "登录时自动启动",
              isOn: Binding(
                get: { model.launchAtLogin },
                set: { model.updateLaunchAtLogin($0) }
              )
            )
          }
        }

        settingsSection("屏幕布局") {
          VStack(spacing: 8) {
            Stepper(value: $model.safeAreaHeight, in: 44...80, step: 1) {
              HStack {
                Text("顶部状态栏安全区")
                Spacer()
                Text("\(Int(model.safeAreaHeight)) px")
                  .foregroundStyle(.secondary)
              }
            }

            HStack {
              Text("JPEG 质量")
              Slider(value: $model.jpegQuality, in: 0.5...1, step: 0.05)
              Text("\(Int(model.jpegQuality * 100))%")
                .monospacedDigit()
                .foregroundStyle(.secondary)
                .frame(width: 38, alignment: .trailing)
            }
          }
        }

        settingsSection("运行状态") {
          VStack(spacing: 8) {
            LabeledContent("状态", value: model.statusText)
            Divider()
            LabeledContent("上次 Codex 刷新", value: model.lastRefreshText)
            Divider()
            LabeledContent("上次推送", value: model.lastUploadText)

            if let error = model.lastError {
              Divider()
              Text(error)
                .font(.caption)
                .foregroundStyle(.red)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
          }
        }

        settingsSection("软件更新") {
          HStack {
            Text("当前版本 \(updater.currentVersion)")
              .foregroundStyle(.secondary)

            Spacer()

            Button("检查更新") {
              updater.checkForUpdates()
            }
          }
        }
      }
      .frame(width: 408)

      VStack(spacing: 10) {
        Text("键盘预览")
          .font(.headline)

        Group {
          if let previewImage = model.previewImage {
            Image(nsImage: previewImage)
              .resizable()
              .interpolation(.high)
          } else {
            ZStack {
              Color(red: 8 / 255, green: 11 / 255, blue: 18 / 255)
              VStack(spacing: 8) {
                Image(systemName: "photo")
                  .font(.title2)
                Text("请选择图片")
                  .font(.caption)
              }
              .foregroundStyle(.white.opacity(0.65))
            }
          }
        }
        .frame(width: UsageCardLayout.width, height: UsageCardLayout.height)
        .clipped()
        .overlay(alignment: .top) {
          Text("状态栏安全区")
            .font(.system(size: 8, weight: .medium))
            .foregroundStyle(.white.opacity(0.35))
            .padding(.top, 8)
        }
        .shadow(color: .black.opacity(0.25), radius: 12, y: 6)

        Text("\(model.displayMode.title) · 顶部 \(Int(model.safeAreaHeight))px 留空")
          .font(.caption)
          .foregroundStyle(.secondary)
      }
      .frame(width: 160)
    }
    .padding(20)
    .frame(width: 630, alignment: .top)
    .fixedSize(horizontal: false, vertical: true)
  }

  private func settingsSection<Content: View>(
    _ title: String,
    @ViewBuilder content: () -> Content
  ) -> some View {
    VStack(alignment: .leading, spacing: 6) {
      Text(title)
        .font(.headline)
      GroupBox {
        content()
          .padding(2)
      }
      .frame(maxWidth: .infinity)
    }
  }

  private func intervalTitle(_ seconds: Int) -> String {
    if seconds < 60 { return "\(seconds) 秒" }
    return "\(seconds / 60) 分钟"
  }

  private func chooseCustomImage() {
    let panel = NSOpenPanel()
    panel.title = "选择要显示在键盘上的图片"
    panel.prompt = "选择图片"
    panel.allowedContentTypes = [.image]
    panel.allowsMultipleSelection = false
    panel.canChooseDirectories = false

    if panel.runModal() == .OK, let url = panel.url {
      model.selectCustomImage(at: url)
    }
  }
}
