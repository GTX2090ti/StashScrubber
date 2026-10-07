# StashScrubber iOS 构建说明（iOS Build Guide）

本工程为 StashScrubber 的 Flutter 跨平台源码（iOS / HarmonyOS 双平台）。以下为 iOS 构建步骤。

## 1. 前置条件（在 Mac 上）

- macOS 13+（Ventura 或更新）
- Xcode 15+（App Store 安装，首次运行需同意许可并安装命令行工具）
- Flutter SDK（版本 ≥ 3.24，本工程依赖 Dart ^3.9.2）
  - 安装：`git clone -b stable https://github.com/flutter/flutter.git ~/flutter` 后把 `~/flutter/bin` 加入 PATH，运行 `flutter doctor`
- CocoaPods：`sudo gem install cocoapods`（或 `brew install cocoapods`）
- 一个 Apple ID（真机运行需要；上架 App Store 需要付费开发者账号 $99/年）

## 2. 一次性环境检查

```bash
flutter doctor
```
确认 `Xcode`、`CocoaPods`、`Connected device`（连上 iPhone）三项均为绿色。

## 3. 获取依赖

```bash
cd stash_scrubber_ios
flutter pub get
cd ios && pod install && cd ..
```

## 4. 真机构建（推荐，先跑通）

```bash
# 连上 iPhone，信任此电脑（手机弹窗点"信任"）
flutter build ios --release --no-codesign
```
该命令产出 `build/ios/iphoneos/*.app`（未签名，仅验证编译通过）。

签名并安装到真机（个人 Apple ID 免费签名，7 天有效）：
```bash
flutter build ios --release
flutter install
```
或打开 Xcode：
```bash
open ios/Runner.xcworkspace
```
在 Xcode 中：Signing & Capabilities → Team 选择你的 Apple ID → 修改 Bundle Identifier
（当前为 `com.gtx2090ti.stashscrubber`，免费账号建议改成自己唯一的，如 `com.<你的id>.stashscrubber`）→ 选择你的 iPhone → Run。

## 5. 版本号

三处同步修改（与鸿蒙版一致的习惯）：
- `pubspec.yaml` → `version: 1.6.57+567`（前者 CFBundleShortVersionString，后者 CFBundleVersion）
- iOS 构建会自动读取 pubspec 版本，无需手动改 Info.plist。

## 6. App 图标

图标位于 `ios/Runner/Assets.xcassets/AppIcon.appiconset/`，当前为默认生成的 StashScrubber（SS）图标。
替换方法：用 1024×1024 PNG 覆盖 `Icon-App-1024x1024@1x.png`，在 Xcode 中右键 AppIcon → "App 图标源" 选 Assets，或直接用 Xcode 的 AppIcon 编辑器拖入各尺寸。

## 7. 网络权限说明（已配置）

`ios/Runner/Info.plist` 已包含：
- `NSAppTransportSecurity → NSAllowsArbitraryLoads = true`：允许访问 HTTP 内网（如 `http://192.168.2.180:9999`）与自签名 HTTPS 服务器
- `NSLocalNetworkUsageDescription`：iOS 14+ 访问局域网（内网 Stash 服务器）必需，首次连接会弹权限提示，需允许

## 8. 常见问题

- `pod install` 报错：升级 CocoaPods（`sudo gem update cocoapods`）或清缓存 `pod cache clean --all`
- 真机运行报 "Unable to launch"：检查手机"设置 → 通用 → VPN 与设备管理"中信任开发者证书
- 免费签名 7 天过期：重新 `flutter build ios` 安装一次即可
- 连不上内网服务器：确认 iPhone 与 Stash 服务器同一局域网，且首次连接时允许"本地网络"权限

## 9. 发布（上架 App Store）

需要付费开发者账号。`flutter build ipa` 后通过 Xcode Organizer / Transporter 上传，或按 Xcode 引导完成 Archive → Upload。
