import SwiftUI

struct SettingsView: View {
  @ObservedObject var model: AppModel
  let updater: UpdaterController

  private let intervals = [60, 300, 600, 1_800]

  var body: some View {
    HStack(alignment: .top, spacing: 22) {
      VStack(alignment: .leading, spacing: 12) {
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

            Button("测试并立即推送") {
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
            LabeledContent("上次刷新", value: model.lastRefreshText)
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

        UsageCardView(
          snapshot: model.snapshot ?? .sample,
          safeAreaHeight: model.safeAreaHeight
        )
        .overlay(alignment: .top) {
          Text("状态栏安全区")
            .font(.system(size: 8, weight: .medium))
            .foregroundStyle(.white.opacity(0.35))
            .padding(.top, 8)
        }
        .shadow(color: .black.opacity(0.25), radius: 12, y: 6)

        Text("142 × 428 · 顶部 \(Int(model.safeAreaHeight))px 留空")
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
}
