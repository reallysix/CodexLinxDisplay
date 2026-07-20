import AppKit
import SwiftUI
import UniformTypeIdentifiers

struct SettingsView: View {
  @ObservedObject var model: AppModel
  let updater: any UpdateChecking

  private let intervals = [60, 300, 600, 1_800]

  var body: some View {
    HStack(alignment: .top, spacing: 22) {
      ScrollView {
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
                  Button(model.customImages.isEmpty ? "选择图片…" : "重新选择…") {
                    chooseCustomImages()
                  }

                  Text(
                    model.customImages.isEmpty
                      ? "尚未选择图片"
                      : "已选择 \(model.customImages.count) 张 · 当前 \(model.customImagePositionText)"
                  )
                  .lineLimit(1)
                  .foregroundStyle(.secondary)

                  Spacer()
                }

                if let name = model.customImageName {
                  LabeledContent("当前图片", value: name)
                    .lineLimit(1)
                }

                if model.customImages.count > 1 {
                  Picker(
                    "切换方式",
                    selection: Binding(
                      get: { model.imageRotationMode },
                      set: { model.setImageRotationMode($0) }
                    )
                  ) {
                    ForEach(ImageRotationMode.allCases) { mode in
                      Text(mode.title).tag(mode)
                    }
                  }
                  .pickerStyle(.segmented)

                  integerStepper(
                    title: "切换间隔",
                    value: Binding(
                      get: { model.imageRotationIntervalSeconds },
                      set: { model.setImageRotationInterval($0) }
                    ),
                    range: 1...3_600,
                    unit: "秒"
                  )
                }

                Picker(
                  "图片适配",
                  selection: Binding(
                    get: { model.customImageContentMode },
                    set: { model.setCustomImageContentMode($0) }
                  )
                ) {
                  ForEach(CustomImageContentMode.allCases) { mode in
                    Text(mode.title).tag(mode)
                  }
                }
                .pickerStyle(.segmented)

                Text(
                  model.customImageContentMode == .fill
                    ? "自动放大并居中裁剪，画面铺满；适合照片。"
                    : "完整保留画面，空余区域填黑；适合截图和带文字图片。"
                )
                .font(.caption)
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)

                Text("无需限制原图分辨率；输出固定为 142×428。过小图片放大后可能变模糊。")
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
              .disabled(
                model.isSyncing
                  || (model.displayMode == .customImage && model.customImages.isEmpty)
              )
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
                Text("图片模式下不读取 Codex 用量；多图按上方轮播间隔推送。")
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
              if model.displayMode == .codex {
                integerStepper(
                  title: "Codex 顶部安全区",
                  value: Binding(
                    get: { Int(model.codexSafeAreaHeight) },
                    set: { model.setCodexSafeAreaHeight($0) }
                  ),
                  range: 44...80,
                  unit: "px"
                )
              } else {
                integerStepper(
                  title: "图片顶部留白",
                  value: Binding(
                    get: { Int(model.customImageTopInset) },
                    set: { model.setCustomImageTopInset($0) }
                  ),
                  range: 0...80,
                  unit: "px"
                )

                Text("自定义图片通常设为 0px；只有需要避让键盘状态栏时再增加。")
                  .font(.caption)
                  .foregroundStyle(.secondary)
                  .frame(maxWidth: .infinity, alignment: .leading)
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
        .frame(width: 398)
        .padding(.trailing, 6)
      }
      .frame(width: 408, height: 680)

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
          if previewTopInset > 0 {
            Text(model.displayMode == .codex ? "状态栏安全区" : "图片顶部留白")
              .font(.system(size: 8, weight: .medium))
              .foregroundStyle(.white.opacity(0.35))
              .padding(.top, 8)
          }
        }
        .shadow(color: .black.opacity(0.25), radius: 12, y: 6)

        Text(previewLayoutDescription)
          .font(.caption)
          .foregroundStyle(.secondary)
      }
      .frame(width: 160)
    }
    .padding(20)
    .frame(width: 630, height: 720, alignment: .top)
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

  private func integerStepper(
    title: String,
    value: Binding<Int>,
    range: ClosedRange<Int>,
    unit: String
  ) -> some View {
    Stepper(value: value, in: range, step: 1) {
      HStack {
        Text(title)
        Spacer()
        TextField("", value: value, format: .number)
          .textFieldStyle(.roundedBorder)
          .multilineTextAlignment(.trailing)
          .monospacedDigit()
          .frame(width: 58)
          .accessibilityLabel(title)
        Text(unit)
          .foregroundStyle(.secondary)
      }
    }
  }

  private var previewTopInset: Double {
    model.displayMode == .codex ? model.codexSafeAreaHeight : model.customImageTopInset
  }

  private var previewLayoutDescription: String {
    if model.displayMode == .codex {
      return "Codex 用量 · 顶部 \(Int(model.codexSafeAreaHeight))px 安全区"
    }
    if model.customImageTopInset == 0 {
      return "自定义图片 · 全屏显示"
    }
    return "自定义图片 · 顶部 \(Int(model.customImageTopInset))px 留白"
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
