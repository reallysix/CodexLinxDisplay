# Codex 屏显 for Linx68

一个常驻 macOS 菜单栏的小工具：可以将本机 Codex 用量卡片或自定义图片推送到 Linx68 键盘的图像 API。

![Codex 屏显设置界面](docs/images/settings.png)

## 功能

- 显示 Codex 本周剩余用量、可用重置次数和自动重置时间。
- 可切换到“自定义图片”模式，一次选择多张图片后按顺序或随机方式定时轮播，同时暂停 Codex 用量读取。
- 图片自动输出为 `142 × 428`，可选择铺满画面的“填充裁剪”或保留完整内容的“完整显示”。
- 切回“Codex 用量”模式时会立即读取并推送一次，随后恢复定时更新。
- 输出固定为 `142 × 428` 的 JPEG；Codex 卡片顶部默认保留 `56px` 给键盘天气、Wi-Fi 与电量状态栏，自定义图片默认全屏显示。
- 自定义图像 API 地址、推送间隔、JPEG 质量和两种模式各自的顶部布局；秒数和像素值既可直接输入，也可用上下箭头微调。
- 支持立即测试、后台定时推送和登录时自动启动。
- 菜单栏与设置页均可点击“检查更新”，发现新版本后可直接下载并安装。
- 原生 SwiftUI 菜单栏 App，不需要额外服务器。

<p align="center">
  <img src="docs/images/keyboard-card.jpg" width="142" alt="Linx68 键盘屏幕卡片">
</p>

## v0.3 系列更新

- 支持一次添加多张自定义图片，并按设定秒数顺序或随机轮播；随机模式不会连续显示同一张图片。
- 增加“填充裁剪”和“完整显示”两种图片适配方式，上传任意常见分辨率的图片后自动输出为 `142 × 428`。
- Codex 卡片与自定义图片使用独立的顶部布局设置：Codex 默认预留 `56px` 状态栏安全区，自定义图片默认 `0px` 全屏显示。
- 多图切换间隔、Codex 顶部安全区和图片顶部留白均可直接输入数值，同时保留上下箭头用于微调；超出有效范围的输入会自动修正。
- 优化更新后的启动体验：新版本首次启动以及再次打开后台应用时，都会主动显示设置窗口。

## 系统要求

- macOS 14 或更高版本，支持 Apple 芯片和 Intel Mac。
- 已登录的 Codex App 或 Codex CLI。
- Mac 与键盘位于同一局域网，键盘固件已开启图像 API。

## 安装

1. 从 [Releases](https://github.com/reallysix/CodexLinxDisplay/releases/latest) 下载最新的 `CodexLinxDisplay-*.dmg`。
2. 打开 DMG，将 `CodexLinxDisplay.app` 拖入“应用程序”。
3. 启动 App；首次推送时允许 macOS 的“本地网络”权限。

当前预览版尚未经 Apple 公证。如果 macOS 阻止首次启动，请在尝试打开 App 后前往“系统设置 → 隐私与安全性”，点击“仍要打开”。详见 [Apple 官方说明](https://support.apple.com/zh-cn/102445)。

App 不显示在 Dock 中，启动后请在菜单栏找到竖屏图标。
安装新版本后的首次启动会自动显示设置窗口；如果 App 已在后台运行，再次从“应用程序”中打开也会显示设置窗口。

## 使用

1. 打开“设置”，填写键盘图像接口。Linx68 的默认示例为：

   ```text
   http://192.168.31.71/image/upload
   ```

2. 在“显示内容”中选择模式：

   - `Codex 用量`：立即读取并推送一次，之后按设定间隔自动更新。顶部安全区可在 `44–80px` 之间直接输入，默认值为 `56px`。
   - `自定义图片`：点击“选择图片…”可一次选择多张，切换间隔可在 `1–3600` 秒之间直接输入，并可选择顺序或随机轮播。图片默认全屏推送，也可在 `0–80px` 之间单独设置顶部留白；此时 Codex 自动刷新暂停。

   图片不需要预先调整为设备分辨率。照片建议使用“填充裁剪”，截图、海报和带文字图片建议使用“完整显示”；分辨率过小的原图可以显示，但放大后可能变模糊。

3. 点击“立即推送当前内容”可手动重新发送。设备应收到一张 `Content-Type: image/jpeg` 的 POST 请求。
4. 需要常驻时可打开“登录时自动启动”。

接口地址会因设备网络而变化，请以键盘当前显示或固件页面为准。

## 软件更新

App 使用 [Sparkle](https://sparkle-project.org/) 检查 GitHub Releases。点击菜单栏或设置页中的“检查更新”；有新版本时，Sparkle 会展示更新说明并完成下载、验证和安装。

## 隐私

Codex 用量在本机读取并渲染。App 不上传 Codex 凭据；它只会把生成后的 JPEG 或用户选中的图片发送到配置的图像 API，并访问 GitHub Release 更新源。选中的图片会在 App 的 Application Support 目录各保存一份本地副本，用于重启后继续轮播。

## 本地构建

需要 Xcode 16+ 与 [XcodeGen](https://github.com/yonaskolb/XcodeGen)：

```bash
brew install xcodegen
xcodegen generate
xcodebuild \
  -project CodexLinxDisplay.xcodeproj \
  -scheme CodexLinxDisplay \
  -configuration Debug \
  -derivedDataPath .build \
  test
```

生成本地 DMG、更新 ZIP 与 Sparkle 清单：

```bash
./scripts/build-release.sh
./scripts/generate-appcast.sh
```

## 维护者发布

推送形如 `v0.2.0` 的 tag 会触发 `.github/workflows/release.yml`，完成通用架构构建、Developer ID 签名、Apple 公证、Sparkle 签名与 GitHub Release 上传。正式发布前需在仓库配置以下 Actions Secrets：

同时将 Actions 变量 `ENABLE_SIGNED_RELEASES` 设为 `true`。未配置时，标签只用于手动发布预览版，不会运行正式签名工作流。

- `BUILD_CERTIFICATE_BASE64`
- `P12_PASSWORD`
- `KEYCHAIN_PASSWORD`
- `DEVELOPER_ID_APPLICATION`
- `APPLE_ID`
- `APPLE_TEAM_ID`
- `APPLE_APP_SPECIFIC_PASSWORD`
- `SPARKLE_PRIVATE_KEY`

Sparkle 私钥已按账户 `com.olivia.CodexLinxDisplay` 保存在创建者的 macOS 钥匙串中，可用依赖包内的 `generate_keys --account com.olivia.CodexLinxDisplay -x <文件>` 导出后写入 GitHub Secret。私钥文件不要提交到仓库。

发布前同步修改 `project.yml` 中的 `CFBundleShortVersionString` 与 `CFBundleVersion`，更新 `CHANGELOG.md`，然后创建对应 tag。

## 说明

这是面向 Linx68 图像 API 的非官方工具，与 OpenAI 或键盘厂商无隶属关系。
