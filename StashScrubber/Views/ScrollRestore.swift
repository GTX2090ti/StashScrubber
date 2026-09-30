import SwiftUI

// MARK: - 通用滚动位置记录与恢复（部署目标 iOS 16）
//
// iOS 16 不能用 `.scrollPosition(id:)` / `ScrollPosition`（iOS 17+），只能用
// ScrollViewReader + 坐标探针。范式固定为：
//   ① 卡片 `.id(...)`，背面零尺寸 GeometryReader 上报 `frame(in: .named(space)).minY`
//      到 PreferenceKey（字典 merge）
//   ② ScrollView 声明 `.coordinateSpace(name:)`；同一页面里多个滚动容器必须各用
//      独立的坐标空间名 + 独立 PreferenceKey
//   ③ onPreferenceChange 里算「顶部可见项」，写进本类的引用类型实例 —— 滚动中每秒写
//      几十次，进 @Published 会导致整个网格重绘
//   ④ 从详情返回时调用 `restore(_:exists:)`
//
// 为什么「延迟 0.08s 后 scrollTo 一次」不够用（v1.5.19 的老写法，真机返回仍回顶部）：
//   · NavigationStack 返回时根列表的 ScrollView 可能被重建：滚动位置归零，探针随即把
//     「新位置（第一项，minY≈0）」上报回来，把锚点覆盖成第一项 —— 此后即使 scrollTo
//     成功，滚的也是第一项，表现就是「返回后仍停在最上面」。
//   · `.onChange(of: path.count)` 若挂在条件分支（if/else）上，分支 identity 变化会让
//     修饰符重建、基准值被重置为当前值，`1 → 0` 的变化不再产生回调，恢复根本不会执行。
//   因此这里做三件事：**恢复期间锁定锚点**（拒绝上报覆盖）+ **多阶段重试直到到位**
//   + 入口同时挂 `onChange(of: path.count)` 与 `onAppear`，任一生效即可。
//
// v1.5.21 补：**分页「加载更多」同样会重置偏移**（表现：点一下「加载更多」就跳回最上面）。
//   追加数据也是一次内容变化，SwiftUI 可能把偏移重置为 0；更糟的是零尺寸探针会随即把
//   「第一项」上报回来 —— 锚点一旦被改写，之后无论恢复多少次都只能恢复到第一项。
//   所以追加场景必须走同一条路：请求期间 `freeze()`（拒绝上报覆盖锚点），
//   数据落地后 `restore(holdSeconds:)` 守一段时间，期间任何「被推到顶部下方」的上报都拉回。

/// 滚动位置锚点：记录列表「顶部可见项」，用于从详情页返回时恢复原位。
/// 只在主线程访问（均来自 SwiftUI 视图回调），故标注 `@unchecked Sendable`
/// 以允许在 `DispatchQueue.main` 的延迟闭包里捕获。
final class ScrollMemory: @unchecked Sendable {
    /// 判定「已滚过顶部」时容许的浮点误差（pt）
    private static let edge: CGFloat = 4
    /// 恢复重试间隔（秒）：要够密，才能让某一次恰好落在转场动画结束之后
    private static let retryInterval: Double = 0.06
    /// 基础恢复窗口（秒）：首次立即执行 + 按 0.06s 步进 ≈ 0.55s，
    /// 覆盖 push/pop 转场（约 0.35s）与 LazyVGrid 首帧渲染。
    /// 窗口内「锚点项没有上报」会被当作「还没渲染出来」而继续重试。
    private static let recoverWindow: Double = 1.2
    /// 「已回到顶部」的容差（pt）
    private static let topTolerance: CGFloat = 3

    /// 顶部可见项（仅在列表可见且未处于恢复期时更新）
    private(set) var topID: String?
    /// 进入详情页瞬间冻结的锚点
    private(set) var frozenID: String?
    /// 最近一轮探针上报，恢复时用于判断是否已回到位
    private var latest: [String: CGFloat] = [:]
    /// 列表已被详情页覆盖（或正在恢复）：拒绝上报覆盖 topID
    private var suspended = false
    private var restoring = false

    /// 是否要求「已滚过顶部」才记录锚点。
    /// 详情页网格上方还有标题 / 简介区，页面停在顶部时全部卡片都位于屏幕下方，
    /// 这种情形不应记录（否则会把「停在标题区」误恢复成「网格第一项贴顶」，反而多跳一次）。
    private let requiresTopCrossed: Bool

    init(requiresTopCrossed: Bool = false) {
        self.requiresTopCrossed = requiresTopCrossed
    }

    // MARK: - 记录

    /// 探针上报入口：推算顶部可见项并写入锚点
    func accept(_ offsets: [String: CGFloat]) {
        guard !offsets.isEmpty else { return }
        latest = offsets
        guard !suspended, !restoring else { return }
        let crossed = offsets.filter { $0.value <= Self.edge }
        if let top = crossed.max(by: { $0.value < $1.value })?.key {
            topID = top
        } else if !requiresTopCrossed, let first = offsets.min(by: { $0.value < $1.value })?.key {
            topID = first
        }
    }

    /// 内容整体变化（换连接 / 搜索 / 排序 / 方向 / 过滤 / 视图模式切换 / 实体变化）：
    /// 锚点作废，避免按旧数据恢复
    func clear() {
        topID = nil
        frozenID = nil
        latest = [:]
        restoring = false
        suspended = false
    }

    // MARK: - 冻结与恢复

    /// 列表即将被详情页覆盖 / 离开前台：冻结当前锚点并停止接受上报
    func freeze() {
        if let t = topID { frozenID = t }
        suspended = true
    }

    /// 从详情返回 / 分页追加后：把锚点项滚回顶部。
    /// pop 之后布局尚未落定、LazyVGrid 可能还没渲染出目标项，单次 scrollTo 会被忽略
    /// （表现就是「返回后仍在最上面」），故按拍步进、重试到窗口结束。
    /// - Parameter holdSeconds: 到位后**继续守护**的时长。追加数据（加载更多）时
    ///   SwiftUI 可能在数据落地后若干帧才重置偏移，守护期内一旦探针上报显示锚点项
    ///   已被推到顶部下方，就立刻拉回。返回场景传 0 即可。
    func restore(_ proxy: ScrollViewProxy, holdSeconds: Double = 0, exists: (String) -> Bool) {
        guard !restoring else { return }              // 已在恢复中（onAppear 与 onChange 可能同时触发）
        guard let id = frozenID ?? topID, exists(id) else {
            endRestore()
            return
        }
        restoring = true
        latest = [:]                                 // 先清空：只有「本拍之后」的上报才算数
        let now = Date()
        step(proxy, id: id,
             recoverUntil: now.addingTimeInterval(Self.recoverWindow),
             deadline: now.addingTimeInterval(Self.recoverWindow + max(0, holdSeconds)))
    }

    /// 单拍：
    /// - 探针**有上报**且锚点项被推到顶部下方 → 说明偏移被重置了，立刻拉回；
    ///   只处理「正偏离」—— 用户自己往下滑会让锚点项跑到视口上方（负值），那是他的意愿，不该干预
    /// - 探针**无上报** → 恢复窗口内视作「目标项还没渲染出来」，继续重试；
    ///   过了窗口（守护期）则说明位置稳定，不再打扰
    private func step(_ proxy: ScrollViewProxy, id: String, recoverUntil: Date, deadline: Date) {
        let now = Date()
        if now >= deadline { endRestore(); return }
        let reported = latest[id]
        let needScroll: Bool
        if let y = reported {
            needScroll = y > Self.topTolerance
        } else {
            needScroll = now < recoverUntil
        }
        if needScroll {
            var t = Transaction()
            t.disablesAnimations = true              // 关动画：避免「先回顶部再滑下来」的闪动
            withTransaction(t) { proxy.scrollTo(id, anchor: .top) }
            latest = [:]
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + Self.retryInterval) { [weak self] in
            guard let self, self.restoring else { return }
            self.step(proxy, id: id, recoverUntil: recoverUntil, deadline: deadline)
        }
    }

    /// 恢复结束（到位或放弃）：恢复正常上报
    func endRestore() {
        restoring = false
        suspended = false
        frozenID = nil
        latest = [:]
    }
}
