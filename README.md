# StashScrubber-Harmony

StashScrubber 的鸿蒙版（纯血鸿蒙 NEXT，ArkTS / ArkUI），Stash 媒体库管理客户端。

> 本仓库是 [StashScrubber](https://github.com/GTX2090ti/StashScrubber)（iOS SwiftUI 版）的鸿蒙重写版，功能对齐 iOS 版，WiFi 自动切换不做。

## 功能

- 登录：档案名 + 内网/外网双地址 + API Key，实测连接
- 三大列表：短片 / 演员 / 工作室（单页 120 条 + 翻页栏 + 搜索 + 排序）
- 详情页：短片（工作室/演员/标签/简介）、演员、工作室、标签
- 网络层：GraphQL 统一超时（10s / 长请求 120s）、链路失败自动重试一次、网络日志一键复制
- 图片：封面/头像直接加载，自动改写地址（内外网主机不一致）

## 编译（本地 DevEco Studio）

1. 安装 DevEco Studio 5.0+（含 HarmonyOS SDK，API 12 及以上）
2. 用 DevEco Studio 打开本仓库根目录
3. 工程自动 Sync；如 SDK 版本不符，把根 `build-profile.json5` 中 `compatibleSdkVersion` 改为你本机 SDK 版本（如 `6.0.0(20)`）
4. 菜单 Build → Build Hap(s)/APP(s) → 生成 HAP
5. 真机调试：登录华为账号，配置自动签名后 Run

## 目录结构

```
AppScope/                 应用级配置（bundleName、图标）
entry/src/main/ets/
├── entryability/         EntryAbility
├── pages/                页面（登录/主框架/列表/详情）
├── common/               通用组件（SceneCard）
├── model/                Stash 数据模型
└── net/                  网络层（GraphQL 客户端、档案存储、网络日志）
```

## 版本

v1.0.0 · 适配 HarmonyOS 6+（鸿蒙 NEXT）
