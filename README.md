# StashScrubber — iOS 原生 Stash 元数据削刮客户端

SwiftUI 编写的 iOS 原生应用，远程控制 Stash 服务端的元数据削刮，并对已削刮结果做查看、编辑与写回。
纯系统组件 UI（自动跟随系统浅色/深色模式），无任何第三方依赖，iPhone / iPad 双端响应式适配。

## 功能

| 能力 | 说明 |
|---|---|
| 场景（短片）削刮 | 片段削刮（按现有信息 + 指定刮削器）/ URL 削刮 / 关键词搜索削刮 |
| 工作室削刮 | 片段削刮 / URL 削刮 / 关键词搜索削刮；独立工作室板块（列表/详情/相关场景） |
| 标签（TAG） | 削刮结果中的多个标签自动识别、比对并写回；独立标签板块（全部标签浏览 + 带标签的场景） |
| 演员削刮 | 片段削刮 / URL 削刮 / 关键词搜索削刮 |
| 元数据编辑 | 标题、日期、评分、简介、工作室、演员、标签、URL（场景）；演员全档案字段；图片字段 —— 保存即通过 GraphQL 写回 |
| 削刮结果预览 | 应用前逐字段对比「当前值 → 新值」，只写非空字段，库内不存在的 演员/标签/工作室 自动创建 |
| 内网/外网 | 多服务器档案 + 工具栏一键切换；支持 HTTPS 与路径前缀（适配 Nginx/Caddy 反代） |
| 场景筛选器 | 多选工作室/演员/标签（任一或全部）、评分下限、已整理、O 计数、时长、分辨率、日期范围，交互对齐 Stash WebUI |
| 场景详情 | 文件路径展示（可选中 + 复制）、标题点击编辑实时更新、工作室名可点击跳转 |
| 版本号 | MARKETING_VERSION 随发版更新，构建号 = CI run number 自动递增 |

## 目录结构

```
StashScrubber/
├── project.yml                      # XcodeGen 工程定义（TARGETED_DEVICE_FAMILY=1,2 + AppIcon）
└── StashScrubber/
    ├── App/StashScrubberApp.swift   # 入口、iPhone(TabView)/iPad(SplitView) 根视图、服务器档案、设置页
    ├── Networking/GraphQLClient.swift  # 轻量 GraphQL 客户端（ApiKey 头、错误聚合）
    ├── Networking/StashAPI.swift    # 全部 GraphQL 查询/变更/削刮/写回/自动建实体
    ├── Models/StashModels.swift     # Scene / Studio / Performer / Tag / Scraper / 更新输入
    ├── Models/ScrapedModels.swift   # Scraped* 削刮结果模型、统一包装、对比快照
    ├── Assets.xcassets/             # AppIcon（1024x1024 单尺寸）
    └── Views/                       # 列表、详情、通用削刮面板、编辑表单、组件
```

## 构建

要求：Xcode 15+，iOS 16.0+ 部署目标，真机或模拟器均可。

方式 A（推荐，XcodeGen）：
```bash
cd StashScrubber
xcodegen generate     # 生成 StashScrubber.xcodeproj
open StashScrubber.xcodeproj
```

方式 B（手工）：Xcode 新建 iOS App 项目（Storyboard 关闭、SwiftUI 生命周期），把 `StashScrubber/` 目录下所有 `.swift` 拖入工程，Info.plist 增加 `NSAppTransportSecurity → NSAllowsArbitraryLoads = YES`（内网 HTTP 必须），并增加 `NSLocalNetworkUsageDescription`（iOS 14+ 访问内网地址必须声明，文案随意），General → Supported Destinations 同时勾选 iPhone 与 iPad。

签名后即可真机运行。

## 服务器配置

1. 打开「设置」标签（iPad 在侧栏「设置」），添加/编辑服务器档案：
   - 内网：`http://<NAS-IP>:9999`（Stash 默认端口，按实际改）
   - 外网：`https://stash.example.com/stash`（任意路径前缀均可，端点自动追加 `/graphql`）
2. 若 Stash 启用了 API Key（设置 → 安全），必须填入对应档案。
3. 点「测试连接」验证，会返回 Stash 版本号。
4. 各列表页左上角「服务器」菜单可随时一键切换内外网档案。

### 外网访问的三种方式

| 方式 | 做法 | 注意 |
|---|---|---|
| 反向代理 | Nginx/Caddy 把域名反代到 Stash:9999，强烈建议加 HTTPS + Basic Auth/IP 白名单 | App 中 URL 填域名（可含路径前缀），填 API Key |
| WireGuard/Tailscale | 手机入 VPN 后直接访问内网地址 | App 中加一个同内网地址的档案即可 |
| 端口转发 | 路由器转发到 NAS | 明文 HTTP，不推荐 |

## 对接的 Stash GraphQL（v0.27+ 统一刮削器 schema，已按本套 Stash 实测适配）

- 查询：`findScenes` / `findScene` / `findStudios` / `findStudio` / `findTags` / `findPerformers` / `findPerformer` / `allStudios` / `allPerformers` / `allTags` / `listScrapers(types:)`
- 削刮：`scrapeSingleScene` / `scrapeSingleStudio` / `scrapeSinglePerformer`（片段与 URL）、`queryScrapeSceneQuery` / `queryScrapeStudioQuery` / `queryScrapePerformerQuery`（关键词）、`scrapePerformerURL`
- 写回：`sceneUpdate` / `studioUpdate` / `performerUpdate`
- 自动创建：`performerCreate` / `tagCreate` / `studioCreate`（削刮结果里库内没有的实体）

## 常见问题

- **削刮无结果**：先确认服务端该刮削器可用（Stash 设置 → 元数据提供者），并看 Stash 日志；本 App 的报错提示也会带出服务端 GraphQL 错误原文。
- **列表空/连接失败**：检查档案 URL（必须能访问 `/graphql`）、API Key；HTTP 内网地址依赖 ATS 放行（工程已配置）。
- **图片不显示**：Stash 截图/缩略图请求会自动附带 ApiKey 头；确认 API Key 与服务端一致。

## 验证清单（真机）

1. 设置 → 测试连接 → 显示 `连接成功 · Stash x.xx.x`
2. 场景列表加载出网格、搜索生效、下拉刷新
3. 任一场景 → 削刮 → 片段削刮选一个刮削器 → 预览差异 → 应用并写回 → 详情刷新出新值
4. 场景 → 编辑 → 改标题/评分/演员 → 保存 → 服务端 WebUI 中确认已写回
5. 工作室、演员重复 3、4；标签页确认能浏览并点开带标签的场景
6. 切换到外网档案重复 2~5
