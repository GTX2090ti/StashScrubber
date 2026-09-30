import SwiftUI

// MARK: - 应用入口（苹果原生外观，自动跟随系统浅色/深色）

@main
struct StashScrubberApp: App {
    // 注意：模块内自定义的 Scene 模型结构体会遮蔽 SwiftUI.Scene 协议，此处须全限定
    @Environment(\.scenePhase) private var scenePhase
    /// 记录上一次 scenePhase，用于区分「真正从后台回前台」vs「被短暂打断后回到 active」
    /// （下拉控制中心 / 通知横幅 / Face ID 弹窗会让 active→inactive→active，App 并未进后台，
    /// 此时连接还活着，盲目重建会让会话抖动、日志刷屏）
    @State private var lastPhase: ScenePhase = .active

    var body: some SwiftUI.Scene {
        WindowGroup {
            RootGate()
                .environmentObject(AppSettings.shared)
                .onChange(of: scenePhase) { phase in
                    defer { lastPhase = phase }
                    // 只有「从 .background 回到 .active」才重建会话
                    // （.inactive → .active 是控制中心/通知等短暂打断，连接未断，不重建）
                    guard phase == .active, lastPhase == .background else { return }
                    NetTransport.resetAPI(reason: "App 从后台回前台，重建 API 会话")
                    NetTransport.resetImage(reason: "App 从后台回前台，重建图片会话")
                    Task {
                        await AppSettings.shared.autoSelectSlot()
                    }
                }
        }
    }
}

// 登录门禁：未完成服务器初始化（API Key 登入）时展示登录页
struct RootGate: View {
    @AppStorage("stash.serverSetupDone") private var serverSetupDone = false

    var body: some View {
        if serverSetupDone {
            RootView()
        } else {
            LoginView()
        }
    }
}

// MARK: - 运行时服务器档案（由 ServerConnection + 生效地址槽位解析而来）
//
// 保留此结构体是为了让 GraphQLClient / 探测 / 延迟监测 / WiFi 切换的调用点
// 不必关心「一条连接两个地址」的细节——它们只需要一个可用基址 + 一个名称。

struct ServerProfile: Codable, Identifiable, Equatable {
    var id: UUID = UUID()
    var name: String          // 连接名（可带「· 内网 / · 外网」后缀）
    var url: String           // 已解析出的基址，如 http://192.168.2.210:9999
    var apiKey: String        // Stash 设置 → 安全 → API Key，可留空
}

// MARK: - 根视图：iPhone 用 TabView，iPad 用双栏 SplitView（均为原生组件）

enum AppSection: Hashable {
    case scenes, performers, studios, settings
}

struct RootView: View {
    @EnvironmentObject private var settings: AppSettings
    @Environment(\.horizontalSizeClass) private var hSize

    var body: some View {
        Group {
            if hSize == .compact {
                TabRootView()
            } else {
                SplitRootView()
            }
        }
        // 启动后按「地址类型 + 优先内网」做一次选路（内网 60 秒内有缓存则直接复用）
        .task { await settings.autoSelectSlot() }
    }
}

struct TabRootView: View {
    @State private var selection: AppSection = .scenes
    @State private var tabRefreshTick = 0

    var body: some View {
        TabView(selection: $selection) {
            ScenesView(refreshTick: tabRefreshTick)
                .tabItem { Label("短片", systemImage: "film") }
                .tag(AppSection.scenes)
            PerformersView(refreshTick: tabRefreshTick)
                .tabItem { Label("演员", systemImage: "person.2") }
                .tag(AppSection.performers)
            StudiosView(refreshTick: tabRefreshTick)
                .tabItem { Label("工作室", systemImage: "building.2") }
                .tag(AppSection.studios)
            SettingsView()
                .tabItem { Label("设置", systemImage: "gearshape") }
                .tag(AppSection.settings)
        }
        .onChange(of: selection) { _ in
            tabRefreshTick += 1
        }
    }
}

struct SplitRootView: View {
    @State private var selection: AppSection? = .scenes

    var body: some View {
        NavigationSplitView {
            List(selection: $selection) {
                NavigationLink(value: AppSection.scenes) {
                    Label("短片", systemImage: "film")
                }
                NavigationLink(value: AppSection.performers) {
                    Label("演员", systemImage: "person.2")
                }
                NavigationLink(value: AppSection.studios) {
                    Label("工作室", systemImage: "building.2")
                }
                NavigationLink(value: AppSection.settings) {
                    Label("设置", systemImage: "gearshape")
                }
            }
            .navigationTitle("Stash 削刮")
            .navigationSplitViewColumnWidth(min: 170, ideal: 200, max: 260)
        } detail: {
            switch selection {
            case .scenes: ScenesView()
            case .performers: PerformersView()
            case .studios: StudiosView()
            case .settings: SettingsView()
            case nil:
                EmptyStateView(title: "未选择板块", hint: "从侧边栏选择 短片 / 演员 / 工作室 / 设置")
            }
        }
    }
}

// MARK: - 连接与选路（UserDefaults 持久化）
//
// 模型说明见 Models/ServerConnection.swift：
//   一条 ServerConnection = 一个服务 + 内网地址 + 外网地址 + 地址类型 + 「优先使用内网地址」。
// 生效地址由 activeSlot 决定，autoSelectSlot() 负责「优先内网、内网不可达则自动切外网」。
// 旧版「每个地址一条独立档案」的持久化数据会在首次启动时自动迁移为一条双地址连接。

@MainActor
final class AppSettings: ObservableObject {
    static let shared = AppSettings()

    private static let connKey = "stash.connections"
    private static let activeConnKey = "stash.activeConnectionID"
    private static let pinnedSlotKey = "stash.pinnedSlot"
    /// 锁定是否由 WiFi 规则设置：离开该 WiFi 后必须自动解除，否则会被永久钉在不可达的一侧
    private static let pinnedByRuleKey = "stash.pinnedSlotByRule"
    // 旧版键：迁移后保留不删，便于回退旧版本 App
    private static let legacyProfilesKey = "stash.profiles"
    private static let legacyActiveKey = "stash.activeProfileID"

    @Published var connections: [ServerConnection] {
        didSet { persistConnections() }
    }
    @Published var activeConnectionID: UUID? {
        didSet { persistActive() }
    }
    /// 当前生效的地址槽位（内网 / 外网）
    @Published private(set) var activeSlot: AddressSlot = .lan
    /// 被 WiFi 规则或手动锁定的槽位；nil 表示按「优先使用内网地址」自动决定
    @Published private(set) var pinnedSlot: AddressSlot? {
        didSet {
            UserDefaults.standard.set(pinnedSlot?.rawValue, forKey: Self.pinnedSlotKey)
        }
    }
    /// 锁定来源是否为 WiFi 规则。规则锁定必须在离开该 WiFi 时自动解除，
    /// 否则用户出门后会被永久钉在不可达的内网地址上（「突然连不上」的典型成因）。
    @Published private(set) var pinnedByRule = false {
        didSet {
            UserDefaults.standard.set(pinnedByRule, forKey: Self.pinnedByRuleKey)
        }
    }
    /// 最近一次选路结论（设置页 / 诊断页展示）
    @Published private(set) var lastSwitchReason: String?

    private init() {
        let d = UserDefaults.standard
        var list: [ServerConnection] = []
        var restoredActive: UUID?
        var restoredPin: AddressSlot?

        if let data = d.data(forKey: Self.connKey),
           let saved = try? JSONDecoder().decode([ServerConnection].self, from: data), !saved.isEmpty {
            list = saved
            if let s = d.string(forKey: Self.activeConnKey) { restoredActive = UUID(uuidString: s) }
        } else if let data = d.data(forKey: Self.legacyProfilesKey),
                  let old = try? JSONDecoder().decode([ServerProfile].self, from: data), !old.isEmpty {
            // 旧版扁平档案 → 一条双地址连接（原有内外网两条自动合并）
            let m = Self.migrate(old, legacyActiveID: d.string(forKey: Self.legacyActiveKey).flatMap(UUID.init(uuidString:)))
            list = m.connections
            restoredActive = m.activeID
            restoredPin = m.pinnedSlot
        } else {
            list = [Self.freshDefault()]
        }

        if let s = d.string(forKey: Self.pinnedSlotKey), let p = AddressSlot(rawValue: s) { restoredPin = p }

        connections = list
        activeConnectionID = restoredActive ?? list.first?.id
        pinnedSlot = restoredPin
        // 没有锁定就谈不上「规则锁定」；锁定时沿用持久化的来源标记
        pinnedByRule = (restoredPin != nil) && d.bool(forKey: Self.pinnedByRuleKey)
        let active = list.first { $0.id == activeConnectionID } ?? list.first
        activeSlot = restoredPin ?? (active?.preferredSlot ?? .lan)

        // 初始化阶段属性观察器不触发，这里显式落盘（迁移后立刻写入新格式）
        persistConnections()
        persistActive()
        UserDefaults.standard.set(pinnedSlot?.rawValue, forKey: Self.pinnedSlotKey)
        UserDefaults.standard.set(pinnedByRule, forKey: Self.pinnedByRuleKey)

        // 连续链路失败 → 自动重新选路（自愈）：
        // 「用一段时间后突然连不上」不再只能靠用户去设置页手动点重新选路
        NetHealth.shared.onRepeatedFailure = { [weak self] reason in
            Task { @MainActor in
                await self?.recoverFromFailure(reason)
            }
        }
    }

    // MARK: 默认值 / 迁移

    private static func freshDefault() -> ServerConnection {
        ServerConnection(name: "Stash 服务器", kind: .both,
                         lanHost: "192.168.2.210", lanPort: "9999", lanHTTPS: false,
                         wanHost: "", wanPort: "", wanHTTPS: true,
                         preferLAN: true, apiKey: "")
    }

    private struct Migration {
        var connections: [ServerConnection]
        var activeID: UUID?
        var pinnedSlot: AddressSlot?
    }

    private static func migrate(_ old: [ServerProfile], legacyActiveID: UUID?) -> Migration {
        let lan = old.first { StashEndpoint.isLAN($0.url) }
        let wan = old.first { !StashEndpoint.isLAN($0.url) }
        var out: [ServerConnection] = []
        var activeID: UUID?
        var pin: AddressSlot?

        if let lan, let wan {
            let l = ServerConnection.split(lan.url)
            let w = ServerConnection.split(wan.url)
            let c = ServerConnection(name: "Stash 服务器", kind: .both,
                                     lanHost: l.host, lanPort: l.port, lanHTTPS: l.https,
                                     wanHost: w.host, wanPort: w.port, wanHTTPS: w.https,
                                     preferLAN: true,
                                     apiKey: lan.apiKey.isEmpty ? wan.apiKey : lan.apiKey)
            out.append(c)
            activeID = c.id
            // 旧版激活的是外网档案 → 保留「不优先内网」的意图
            if legacyActiveID == wan.id { pin = .wan }
        }

        for p in old where p.id != lan?.id && p.id != wan?.id {
            let s = ServerConnection.split(p.url)
            let isLAN = StashEndpoint.isLAN(p.url)
            let c = ServerConnection(name: p.name, kind: isLAN ? .lan : .wan,
                                     lanHost: isLAN ? s.host : "",
                                     lanPort: isLAN ? s.port : "",
                                     lanHTTPS: isLAN && s.https,
                                     wanHost: isLAN ? "" : s.host,
                                     wanPort: isLAN ? "" : s.port,
                                     wanHTTPS: !isLAN && s.https,
                                     apiKey: p.apiKey)
            out.append(c)
            if legacyActiveID == p.id { activeID = c.id }
        }

        if activeID == nil { activeID = out.first?.id }
        return Migration(connections: out, activeID: activeID, pinnedSlot: pin)
    }

    // MARK: 持久化

    private func persistConnections() {
        if let data = try? JSONEncoder().encode(connections) {
            UserDefaults.standard.set(data, forKey: Self.connKey)
        }
    }

    private func persistActive() {
        UserDefaults.standard.set(activeConnectionID?.uuidString, forKey: Self.activeConnKey)
    }

    // MARK: 读取

    var activeConnection: ServerConnection? {
        connections.first { $0.id == activeConnectionID } ?? connections.first
    }

    /// 当前生效的地址（未配置时为 空串）
    var activeAddress: String {
        guard let c = activeConnection else { return "" }
        return c.url(for: activeSlot) ?? c.canonicalProfile?.url ?? ""
    }

    // 兼容旧调用点的只读别名
    var serverURL: String { activeAddress }
    var apiKey: String { activeConnection?.apiKey ?? "" }
    var activeProfileID: UUID? { activeConnectionID }

    /// 每个连接按其「优先地址」暴露一条运行时档案（兼容旧接口）
    var profiles: [ServerProfile] { connections.compactMap { $0.canonicalProfile } }

    /// 按生效地址解析出的运行时档案
    var activeProfile: ServerProfile? {
        guard let c = activeConnection else { return nil }
        return c.resolvedProfile(slot: activeSlot) ?? c.canonicalProfile
    }

    /// 视图刷新键：连接或生效地址变化都应重新拉数据
    var reloadKey: String {
        "\(activeConnectionID?.uuidString ?? "-")|\(activeAddress)"
    }

    /// 当前是否由 WiFi 规则 / 手动锁定地址
    var isSlotPinned: Bool { pinnedSlot != nil }

    func makeClient() throws -> GraphQLClient {
        guard let c = activeConnection else {
            throw StashAPIError.badURL("请先在设置中配置 Stash 服务器地址")
        }
        guard let url = c.url(for: activeSlot) ?? c.canonicalProfile?.url, !url.isEmpty else {
            throw StashAPIError.badURL("「\(c.name)」未配置可用地址，请在 设置 → 服务器连接 中填写内网或外网地址")
        }
        return try GraphQLClient(baseURL: url, apiKey: c.apiKey, profileName: c.name)
    }

    func connection(_ id: UUID) -> ServerConnection? {
        connections.first { $0.id == id }
    }

    // MARK: 写入

    func mutate(_ id: UUID, _ change: (inout ServerConnection) -> Void) {
        guard let i = connections.firstIndex(where: { $0.id == id }) else { return }
        change(&connections[i])
    }

    func upsert(_ c: ServerConnection) {
        if let i = connections.firstIndex(where: { $0.id == c.id }) {
            connections[i] = c
        } else {
            connections.append(c)
        }
    }

    func addConnection(_ c: ServerConnection) {
        connections.append(c)
        activeConnectionID = c.id
        unpin()
        activeSlot = c.preferredSlot ?? .lan
        Task { await autoSelectSlot(force: true) }
    }

    func deleteConnection(_ c: ServerConnection) {
        connections.removeAll { $0.id == c.id }
        if activeConnectionID == c.id {
            activeConnectionID = connections.first?.id
            activeSlot = activeConnection?.preferredSlot ?? .lan
            unpin()
        }
    }

    func switchToConnection(_ id: UUID) {
        guard connections.contains(where: { $0.id == id }) else { return }
        activeConnectionID = id
        unpin()
        activeSlot = activeConnection?.preferredSlot ?? .lan
        // 切换服务器后立即重建会话，避免旧连接池吊死请求
        NetTransport.resetAPI(reason: "切换到\(activeConnection?.name ?? "新连接")，重建 API 会话")
        NetTransport.resetImage(reason: "切换到\(activeConnection?.name ?? "新连接")，重建图片会话")
        Task { await autoSelectSlot(force: true) }
    }

    /// 兼容旧调用：按运行时档案切换连接
    func switchTo(_ p: ServerProfile) { switchToConnection(p.id) }

    /// 锁定到某一侧地址。
    /// - Parameter byRule: true 表示由 WiFi 规则设置——离开该 WiFi 时必须能自动解除；
    ///   手动锁定（工具栏菜单）则一直保留，直到用户自己切回自动。
    func pin(_ slot: AddressSlot, byRule: Bool = false) {
        guard let c = activeConnection, c.availableSlots.contains(slot) else { return }
        pinnedSlot = slot
        pinnedByRule = byRule
        activeSlot = slot
        lastSwitchReason = byRule ? "WiFi 规则指定使用\(slot.label)地址"
                                  : "已手动指定使用\(slot.label)地址"
        NetLog.shared.record(category: .diag, level: .info, title: "地址切换",
                             message: lastSwitchReason ?? "")
    }

    /// 解除锁定（内部统一入口，保证来源标记一并复位）
    private func unpin() {
        pinnedSlot = nil
        pinnedByRule = false
    }

    /// 取消锁定，回到「优先内网、自动兜底」
    func clearPin() {
        unpin()
        Task { await autoSelectSlot(force: true) }
    }

    /// 离开规则 WiFi 时的解锁：仅解除「由 WiFi 规则设置」的锁定，不动手动锁定。
    /// - Returns: 是否真的解除了一次规则锁定（供日志/界面提示）
    @discardableResult
    func releaseRulePin(reason: String) -> Bool {
        guard pinnedByRule else { return false }
        let old = pinnedSlot
        unpin()
        lastSwitchReason = reason
        NetLog.shared.record(category: .wifi, level: .info, title: "解除地址锁定", message: reason)
        if old != nil { Task { await autoSelectSlot(force: true) } }
        return true
    }

    /// 记录一次成功同步（列表页成功拉到数据时调用）
    func markSynced() {
        guard let i = connections.firstIndex(where: { $0.id == activeConnectionID }) else { return }
        if let t = connections[i].lastSync, Date().timeIntervalSince(t) < 60 { return }
        connections[i].lastSync = Date()
    }

    /// 首次登录初始化：用登录页填写的内外网地址建立一条连接
    func applyFirstSetup(lanURL: String, wanURL: String, apiKey: String) {
        let lan = lanURL.trimmingCharacters(in: .whitespaces)
        let wan = wanURL.trimmingCharacters(in: .whitespaces)
        let l = ServerConnection.split(lan)
        let w = ServerConnection.split(wan)

        var c = ServerConnection(name: "Stash 服务器", apiKey: apiKey)
        c.lanHost = l.host; c.lanPort = l.port; c.lanHTTPS = l.https
        c.wanHost = w.host; c.wanPort = w.port; c.wanHTTPS = w.https

        if lan.isEmpty {
            c.kind = .wan
        } else if wan.isEmpty {
            c.kind = .lan
        } else {
            c.kind = .both
        }
        c.preferLAN = (c.kind != .wan)

        connections = [c]
        activeConnectionID = c.id
        unpin()
        activeSlot = c.preferredSlot ?? .lan
    }

    // MARK: 选路（优先内网，不可达自动切外网）

    /// 依据「地址类型 + 锁定槽位 + 优先内网」，实测优先地址可达性后确定生效地址。
    /// 优先地址不可达且未被锁定 → 自动兜底到另一侧。结果写入网络日志。
    func autoSelectSlot(force: Bool = false) async {
        guard let c = activeConnection else { return }
        let slots = c.availableSlots
        guard !slots.isEmpty else {
            activeSlot = .lan
            lastSwitchReason = "「\(c.name)」未配置可用地址"
            return
        }

        // 锁定的一侧已被删除 / 地址类型已排除 → 自动解除锁定（含来源标记）
        if let pin = pinnedSlot, !slots.contains(pin) { unpin() }

        // 1) 期望槽位：单侧配置 > WiFi 规则锁定 > 优先内网
        let target: AddressSlot
        if slots.count == 1 {
            target = slots[0]
        } else if let pin = pinnedSlot, slots.contains(pin) {
            target = pin
        } else {
            target = c.preferredSlot ?? slots[0]
        }

        // 2) 实测优先地址
        let first = await LatencyMonitor.shared.measure(url: c.url(for: target) ?? "",
                                                        apiKey: c.apiKey,
                                                        name: "\(c.name) · \(target.label)",
                                                        force: force)
        if first.isReachable {
            apply(slot: target, reason: "使用\(target.label)地址（\(first.text)）")
            markSynced()
            return
        }

        // 另一个测速正在进行（工具栏菜单 / 设置页并发触发）→ 结果未知，不做兜底误判
        if first.isProbing {
            apply(slot: target, reason: "测速进行中，暂用\(target.label)地址")
            return
        }

        // 3) 自动兜底：仅当未被锁定且确实配置了另一侧
        if pinnedSlot == nil, let fb = c.fallbackSlot {
            let second = await LatencyMonitor.shared.measure(url: c.url(for: fb) ?? "",
                                                             apiKey: c.apiKey,
                                                             name: "\(c.name) · \(fb.label)",
                                                             force: force)
            if second.isReachable {
                apply(slot: fb, reason: "\(target.label)地址不可达（\(first.detail ?? first.text)），已自动切到\(fb.label)")
                markSynced()
                return
            }
            if second.isProbing {
                apply(slot: target, reason: "另一侧测速进行中，暂用\(target.label)地址")
                return
            }
            apply(slot: target, reason: "内网与外网地址均不可达，请检查网络或地址配置")
            return
        }

        apply(slot: target, reason: "\(target.label)地址不可达（\(first.detail ?? first.text)）")
    }

    private func apply(slot: AddressSlot, reason: String) {
        let changed = activeSlot != slot
        activeSlot = slot
        lastSwitchReason = reason
        // 每次选定地址都从零开始计失败次数：否则刚切过去就被上一侧的失败计数拖进自愈
        NetHealth.shared.reset()
        if changed {
            NetLog.shared.record(category: .diag, level: .info, title: "地址切换", message: reason)
        }
    }

    // MARK: 失败自愈（连续链路失败后自动重新选路）

    /// 连续请求失败（由 NetHealth 计数触发）后的自愈：
    /// 优先验证「另一侧」地址，可达就切过去；若已被锁定则只记录结论。
    /// 触发频率由 NetHealth 的阈值（连续 2 次）与冷却（20 秒）控制，不会来回抖动。
    func recoverFromFailure(_ reason: String) async {
        guard let c = activeConnection else { return }
        // 先清掉半死连接池：数据流量下基站切换会让 TCP 连接半死，
        // 不重建会话的话切地址也没用——新请求还是卡在旧连接上
        NetTransport.resetAPI(reason: "连续失败（\(reason)），重建 API 会话")
        NetTransport.resetImage(reason: "连续失败（\(reason)），重建图片会话")
        // 只配了一侧地址：没有可切换的目标，仅刷新一次可达性供 UI 显示
        guard c.availableSlots.count > 1 else {
            if let u = c.url(for: activeSlot) {
                await LatencyMonitor.shared.measure(url: u, apiKey: c.apiKey,
                                                     name: "\(c.name) · \(activeSlot.label)",
                                                     force: true)
            }
            return
        }

        NetLog.shared.record(category: .diag, level: .warn, title: "自动重试",
                             message: "连续请求失败（\(reason)），准备重新选路")

        // 手动锁定：尊重用户意图，只更新结论不去翻面
        if pinnedSlot != nil, !pinnedByRule {
            lastSwitchReason = "已手动锁定\(activeSlot.label)地址（连续失败：\(reason)）"
            return
        }
        // WiFi 规则锁定但当前地址已连续失败（多半是已经离开那个网络，而 SSID 没认出来）
        // → 解除规则锁定，让它自动兜底到另一侧，避免被永久钉在不可达地址上
        if pinnedByRule {
            let old = activeSlot.label
            unpin()
            NetLog.shared.record(category: .diag, level: .warn, title: "解除地址锁定",
                                 message: "\(old)地址连续失败，解除 WiFi 规则锁定后自动重新选路")
        }

        if let other = c.availableSlots.first(where: { $0 != activeSlot }),
           let otherURL = c.url(for: other) {
            let r = await LatencyMonitor.shared.measure(url: otherURL, apiKey: c.apiKey,
                                                        name: "\(c.name) · \(other.label)",
                                                        force: true)
            if r.isReachable {
                apply(slot: other, reason: "原地址连续失败，已自动切到\(other.label)（\(r.text)）")
                markSynced()
                return
            }
        }

        // 另一侧也不可达：走一次完整选路，更新结论与失败原因
        await autoSelectSlot(force: true)
    }
}

// MARK: - 服务器快速切换菜单（各列表页工具栏共用）
//
// 菜单列出「连接 × 可用地址」，点选即锁定到该地址（例：在家想强制走外网、或出门锁外网）；
// 顶部提供「恢复自动选择」，回到「优先内网、内网不可达自动切外网」。

struct ServerSwitcherMenu: View {
    @EnvironmentObject private var settings: AppSettings
    @ObservedObject private var latency = LatencyMonitor.shared

    var body: some View {
        Menu {
            if settings.isSlotPinned {
                Button {
                    settings.clearPin()
                } label: {
                    Label("恢复自动选择（优先内网）", systemImage: "arrow.triangle.2.circlepath")
                }
                Divider()
            }
            ForEach(settings.connections) { c in
                Section(c.name) {
                    ForEach(c.availableSlots, id: \.self) { slot in
                        Button {
                            if settings.activeConnection?.id != c.id {
                                settings.switchToConnection(c.id)
                            }
                            settings.pin(slot)
                        } label: {
                            itemLabel(connection: c, slot: slot)
                        }
                    }
                }
            }
            Divider()
            Button {
                latency.probeConnections(settings.connections, force: true)
                Task { await settings.autoSelectSlot(force: true) }
            } label: {
                Label("重新测速并选路", systemImage: "arrow.clockwise")
            }
        } label: {
            Label(menuTitle, systemImage: "server.rack")
        }
        .task { latency.probeConnections(settings.connections) }
    }

    /// 菜单项：连接名 · 内网/外网 + 延迟；当前生效项带勾选，不可达带警示图标
    @ViewBuilder
    private func itemLabel(connection c: ServerConnection, slot: AddressSlot) -> some View {
        let st = latency.state(for: c.url(for: slot) ?? "")
        let isCurrent = settings.activeConnection?.id == c.id && settings.activeSlot == slot
        let title = "\(slot.label) · \(c.displayURL(for: slot) ?? "-") · \(st.text)"
        if isCurrent {
            Label(title, systemImage: "checkmark")
        } else if case .failed = st {
            Label(title, systemImage: "exclamationmark.triangle")
        } else {
            Text(title)
        }
    }

    /// 工具栏标题：连接名 · 生效地址侧 + 延迟
    private var menuTitle: String {
        guard let c = settings.activeConnection else { return "未配置" }
        let st = latency.state(for: settings.activeAddress)
        switch st {
        case .idle, .probing: return "\(c.name) · \(settings.activeSlot.label)"
        default: return "\(c.name) · \(settings.activeSlot.label) · \(st.text)"
        }
    }
}

// MARK: - 设置页导航路由（value 型链接统一在栈根注册，避免嵌套 isPresented 造成闪跳）

enum SettingsRoute: Hashable {
    case connectionDetail(UUID)
    case connectionConfig(UUID)
    case diagnostics
    case netLog
}

// MARK: - 设置页

struct SettingsView: View {
    @EnvironmentObject private var settings: AppSettings
    @AppStorage("stash.serverSetupDone") private var serverSetupDone = false
    @AppStorage(ImageCache.enabledKey) private var cacheEnabled = true
    @AppStorage(ImageCache.limitMBKey) private var cacheLimitMB = ImageCache.defaultLimitMB
    @ObservedObject private var cache = ImageCache.shared
    @ObservedObject private var latency = LatencyMonitor.shared
    @State private var showAdd = false

    var body: some View {
        NavigationStack {
            Form {
                connectionSection
                networkSection
                cacheSection
                accountSection
                aboutSection
            }
            .navigationTitle("设置")
            .task { latency.probeConnections(settings.connections) }
            .onAppear { cache.refreshUsage() }
            .onChange(of: cacheLimitMB) { _ in
                cache.trimNow()   // 改小上限后立刻淘汰
            }
            .onChange(of: cacheEnabled) { on in
                if on { cache.refreshUsage() }
            }
            .sheet(isPresented: $showAdd) {
                AddConnectionSheet { settings.addConnection($0) }
            }
            // 路由统一注册在栈根：详情页 / 配置页内一律用 NavigationLink(value:)
            .navigationDestination(for: SettingsRoute.self) { route in
                switch route {
                case .connectionDetail(let id): ConnectionDetailView(connectionID: id)
                case .connectionConfig(let id): ConnectionConfigView(connectionID: id)
                case .diagnostics: DiagnosticsView()
                case .netLog: NetLogView()
                }
            }
        }
    }

    // MARK: 服务器连接

    @ViewBuilder
    private var connectionSection: some View {
        Section {
            ForEach(settings.connections) { c in
                NavigationLink(value: SettingsRoute.connectionDetail(c.id)) {
                    ConnectionRow(connection: c,
                                  isActive: c.id == settings.activeConnection?.id,
                                  activeSlot: settings.activeSlot,
                                  latency: latency)
                }
                .swipeActions {
                    Button(role: .destructive) {
                        settings.deleteConnection(c)
                    } label: {
                        Label("删除", systemImage: "trash")
                    }
                }
            }
            Button {
                showAdd = true
            } label: {
                Label("添加连接", systemImage: "plus")
            }
            Button {
                latency.probeConnections(settings.connections, force: true)
                Task { await settings.autoSelectSlot(force: true) }
            } label: {
                Label("重新测速并选路", systemImage: "arrow.clockwise")
            }
        } header: {
            Text("服务器连接")
        } footer: {
            VStack(alignment: .leading, spacing: 6) {
                if let r = settings.lastSwitchReason {
                    Text("当前：\(settings.activeSlot.label)地址 · \(r)")
                }
                Text("一条连接可同时配置内网与外网两个地址：开启「优先使用内网地址」后，App 在启动/回到前台时实测内网地址，不可达则自动切到外网；无需手动切换。地址类型可限定只用其中一侧。点击连接进入详情可查看地址、测试连接。")
            }
        }
    }

    // MARK: 网络

    @ViewBuilder
    private var networkSection: some View {
        Section {
            NavigationLink(value: SettingsRoute.diagnostics) {
                Label("网络诊断", systemImage: "stethoscope")
            }
            NavigationLink(value: SettingsRoute.netLog) {
                Label("网络日志（可复制）", systemImage: "doc.text.magnifyingglass")
            }
        } header: {
            Text("网络")
        } footer: {
            Text("按 WiFi 名称（SSID）可强制锁定内网/外网地址，规则支持增删改；回到前台时自动检测。网络日志记录每次请求的结果，可一键复制用于排障。")
        }
    }

    // MARK: 图片缓存

    @ViewBuilder
    private var cacheSection: some View {
        Section {
            Toggle("启用图片缓存", isOn: $cacheEnabled)
            Picker("缓存上限", selection: $cacheLimitMB) {
                ForEach(ImageCache.limitOptions, id: \.self) { mb in
                    Text(ImageCache.limitLabel(mb)).tag(mb)
                }
            }
            .disabled(!cacheEnabled)
            LabeledContent("当前占用") {
                Text(cacheEnabled
                     ? "\(NetLog.byteText(Int(cache.diskBytes))) · \(cache.diskCount) 张"
                     : "已关闭")
                    .foregroundStyle(.secondary)
            }
            Button(role: .destructive) {
                cache.clear()
            } label: {
                Label("清空图片缓存", systemImage: "trash")
            }
            .disabled(!cacheEnabled || (cache.diskCount == 0 && cache.diskBytes == 0))
        } header: {
            Text("图片缓存")
        } footer: {
            Text("缓存已加载的封面与头像，滚动列表不重复下载；智能裁剪结果一并缓存，不再重复计算。超出上限时按「最久未使用」自动淘汰。关闭后不再读写缓存（已占空间不会自动释放，可手动清空）。")
        }
    }

    // MARK: 账号

    @ViewBuilder
    private var accountSection: some View {
        Section {
            Button(role: .destructive) {
                serverSetupDone = false
            } label: {
                Label("重置服务器配置（返回登录页）", systemImage: "arrow.counterclockwise")
            }
        } header: {
            Text("账号")
        } footer: {
            Text("返回登录页后需重新填写内外网地址与 API Key；登录会实测连接，密钥错误会被直接拦截。")
        }
    }

    @ViewBuilder
    private var aboutSection: some View {
        Section("说明") {
            LabeledContent("版本", value: "1.5.42")
            LabeledContent("适配", value: "iPhone / iPad · iOS 16+")
        }
    }
}
