# StashScrubber（鸿蒙版）

Stash 媒体库的鸿蒙 NEXT 原生客户端（Flutter），兼容 **Stash 0.31.x**。

[English Readme](README_EN.md) | [下载 Releases](https://github.com/GTX2090ti/StashScrubber-Harmony/releases)

---

## 功能总览

### 短片
- 双排横版卡片：封面、时长、分辨率、收藏星标、字幕角标（检测到外挂字幕显示「字幕」）
- 无限滚动加载，返回保持进入位置，无翻页按钮
- 合并搜索：标题 / 路径 / 详情 + 演员名 + 标签 + 工作室
- 排序：添加时间 / 修改时间 / 标题 / 文件大小 / 时长 / 评分 / 工作室等（0.31.1 新枚举）
- 筛选：评分 / 日期 / 时长 / 收藏 / 工作室 / 演员 / 标签（支持多选 + 搜索）
- 多选批量：收藏、评分、标签、合并、生成封面、全选
- 详情页：封面、信息、演员 / 工作室 / 标签跳转、编辑、削刮、生成封面、收藏

### 演员 / 工作室 / 标签
- 卡片列表 + 无限滚动 + 搜索
- 演员详情：基本信息、别名（默认 5 个，可查看更多）、相关短片
- 添加（列表页）/ 删除（详情页，带确认）
- 编辑：基本信息、标签（多选 + 搜索）、新建标签 / 工作室自动查重

### 削刮（元数据刮削）
- 三种模式：片段削刮 / 名称削刮 / URL 削刮
- 源：本地刮削器 + Stash-box（StashDB 等）；片段模式自动用本地演员名搜索 box
- 预览：名称 / 别名 / 出生日期 / 国籍 / 三围 / 从业年限 / 标签 + 图片，「应用并写回」置顶
- 演员削刮默认保留原名；写回兼容 0.31.1（height_cm / alias_list）

### 扫描 / 任务 / 生成
- 扫描：全部或选择二级文件夹，可选生成封面 / 视频预览 / 预览缩略图 / 感知哈希等
- Stash 任务队列：实时显示扫描 / 生成 / 清理任务进度
- 生成封面：详情页单部 / 多选批量 / 任务页全局（0.31.1 metadataGenerate + sceneIDs）

### 服务器与设置
- 多服务器档案：内网 / 外网地址 + API Key，按延迟自动选路
- 服务器相关设置收敛到二级菜单
- 诊断页：档案 / 选路 / 延迟 / Stash 版本

---

## 安装

- 未签名 HAP：`hdc install -r StashScrubber-Flutter-vX.Y.Z-unsigned.hap`
  （或使用 DevEco Studio 配调试签名安装）
- 需要 HarmonyOS NEXT（API 18+）

## 下载

Releases: <https://github.com/GTX2090ti/StashScrubber-Harmony/releases>

## 开发

```bash
flutter pub get        # 拉依赖
flutter analyze        # 静态分析
cd ohos && hvigorw assembleHap -p product=default -p buildMode=release   # 编译 HAP
```

## 版本历史

- **v1.6.46**：短片生成封面（详情页 + 多选批量）；Stash-box 片段削刮；演员削刮默认保留原名；演员详情别名显示（5 个 + 查看更多）；短片封面字幕角标；演员 / 工作室添加与删除；修复演员详情 422（Performer.alias_list）
- 更早版本：底部导航、无限滚动、翻页按钮删除、收藏、排序新枚举、削刮 0.31.1 字段兼容、中文本地化复制粘贴等

> 说明：本仓库自 v1.6.46 起存放 Flutter 版完整源码；更早的 ArkTS 版代码保留在 git 历史中（tag v1.6.1 及之前）。

