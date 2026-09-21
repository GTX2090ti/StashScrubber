import Foundation
import SwiftUI

// MARK: - 地址延迟监测（内网 / 外网）
//
// 按地址（URL）而非档案索引：一条连接有内网 / 外网两个地址，两者需要各自独立测速，
// 这样连接列表、连接详情（内网地址 / 外网地址两行）与工具栏切换菜单可以显示同一份结果。
//
// 设计要点：
//   1. 探测复用 NetProbe + NetProbe.hardTimeout（5s 到点强制终止），UI 绝不会因探测吊住
//   2. 查询用最小的 `{ version { version } }`，不给 Stash 增加负担，顺带取回版本号
//   3. 结果缓存 60 秒（地址变化即视为过期），进入页面自动测速不会反复打网络
//   4. 多个地址并发探测，同一地址同一时刻只跑一个探测（in-flight 去重）
//   5. 探测过程写入网络日志（类别「诊断」），排障时可回溯
//   6. 状态读写加锁、@Published 只在主线程更新（与 NetLog 同一套约定）

/// 单个地址的延迟状态
enum LatencyState: Equatable {
    case idle
    case probing
    case ok(ms: Int, note: String?)
    case failed(String)

    var isProbing: Bool {
        if case .probing = self { return true }
        return false
    }

    var isReachable: Bool {
        if case .ok = self { return true }
        return false
    }

    var ms: Int? {
        if case .ok(let ms, _) = self { return ms }
        return nil
    }

    /// 徽标主文案
    var text: String {
        switch self {
        case .idle: return "未测速"
        case .probing: return "测速中…"
        case .ok(let ms, _):
            if ms < 1000 { return "\(ms) ms" }
            return String(format: "%.2f s", Double(ms) / 1000)
        case .failed: return "不可达"
        }
    }

    /// 补充说明（失败原因 / Stash 版本）
    var detail: String? {
        switch self {
        case .ok(_, let note): return note
        case .failed(let msg): return msg
        default: return nil
        }
    }

    /// 延迟分级配色：<150ms 优 / <400ms 良 / 更慢偏慢 / 失败不可达
    var color: Color {
        switch self {
        case .idle, .probing:
            return .secondary
        case .ok(let ms, _):
            if ms < 150 { return .green }
            if ms < 400 { return .yellow }
            return .orange
        case .failed:
            return .red
        }
    }
}

/// 延迟徽标：状态圆点 + 数值胶囊
struct LatencyBadge: View {
    let state: LatencyState

    var body: some View {
        HStack(spacing: 4) {
            if state.isProbing {
                ProgressView().controlSize(.mini)
            } else {
                Circle()
                    .fill(state.color)
                    .frame(width: 6, height: 6)
            }
            Text(state.text)
                .font(.caption2)
                .monospacedDigit()
                .foregroundStyle(state.isProbing ? Color.secondary : state.color)
        }
        .padding(.horizontal, 7)
        .padding(.vertical, 3)
        .background(Capsule().fill((state.isProbing ? Color.secondary : state.color).opacity(0.14)))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("延迟 \(state.text)")
    }
}

final class LatencyMonitor: ObservableObject, @unchecked Sendable {
    static let shared = LatencyMonitor()

    /// 结果新鲜期：超过后再次触发时才重测
    static let freshness: TimeInterval = 60
    /// 单地址硬超时（秒）：到点强制终止探测
    static let hardTimeout: Double = 5

    /// 主线程镜像（供 SwiftUI 观察变化），键为地址（URL）
    @Published private(set) var states: [String: LatencyState] = [:]

    private let lock = NSLock()
    private var store: [String: LatencyState] = [:]
    private var probedAt: [String: Date] = [:]
    private var inFlight: Set<String> = []

    private init() {}

    // MARK: - 读取

    func state(for url: String) -> LatencyState {
        lock.lock()
        defer { lock.unlock() }
        return store[url] ?? .idle
    }

    // MARK: - 触发探测（即发即忘，供视图 .task 调用）

    /// 并发探测全部连接的可用地址（内网 / 外网各一条）；新鲜结果跳过，`force` 为真时全部重测
    func probeConnections(_ list: [ServerConnection], force: Bool = false) {
        for c in list {
            for slot in c.availableSlots {
                guard let u = c.url(for: slot) else { continue }
                if force || isStale(u) {
                    Task { _ = await measure(url: u, apiKey: c.apiKey,
                                             name: "\(c.name) · \(slot.label)", force: true) }
                }
            }
        }
    }

    /// 并发探测若干运行时档案（兼容旧调用）
    func probeAll(_ profiles: [ServerProfile], force: Bool = false) {
        for p in profiles where force || isStale(p.url) {
            Task { _ = await measure(url: p.url, apiKey: p.apiKey, name: p.name, force: true) }
        }
    }

    // MARK: - 测速（返回结果，供自动兜底 / 测试连接复用）

    /// 测一个地址：命中新鲜缓存直接返回（`force` 为真时强制重测）
    @discardableResult
    func measure(url: String, apiKey: String, name: String, force: Bool = false) async -> LatencyState {
        guard !url.trimmingCharacters(in: .whitespaces).isEmpty else {
            update(.failed("未配置地址"), for: url)
            return .failed("未配置地址")
        }
        if !force {
            let existing = state(for: url)
            if existing.isReachable || existing == .probing, !isStale(url) { return existing }
        }
        guard beginFlight(url) else {
            // 同一地址已有探测在跑：等它出结果再返回，避免调用方拿到「测速中」而误判为不可达
            for _ in 0..<12 {
                try? await Task.sleep(nanoseconds: 500_000_000)
                let s = state(for: url)
                if !s.isProbing { return s }
            }
            return state(for: url)
        }
        if state(for: url) == .idle { update(.probing, for: url) }

        let r = await NetProbe.hardTimeout(Self.hardTimeout, category: .diag,
                                           title: "延迟测速 · \(name)", url: url) {
            await NetProbe.graphql(base: url, apiKey: apiKey,
                                   query: "{ version { version } }",
                                   timeout: Self.hardTimeout - 1,
                                   category: .diag,
                                   title: "延迟测速 · \(name)")
        }

        endFlight(url)
        let out: LatencyState
        if let err = r.error {
            out = .failed(err)
        } else {
            out = .ok(ms: Int((r.latency * 1000).rounded()), note: r.snippet)
        }
        update(out, for: url)
        return out
    }

    /// 清空全部结果（下次进入页面自动重测）
    func reset() {
        lock.lock()
        store.removeAll()
        probedAt.removeAll()
        lock.unlock()
        let empty: [String: LatencyState] = [:]
        DispatchQueue.main.async { self.states = empty }
    }

    // MARK: - 内部状态（全部在 lock 内访问）

    private func isStale(_ url: String) -> Bool {
        lock.lock()
        defer { lock.unlock() }
        if inFlight.contains(url) { return false }
        guard let t = probedAt[url] else { return true }
        return Date().timeIntervalSince(t) > Self.freshness
    }

    private func beginFlight(_ url: String) -> Bool {
        lock.lock()
        defer { lock.unlock() }
        if inFlight.contains(url) { return false }
        inFlight.insert(url)
        return true
    }

    private func endFlight(_ url: String) {
        lock.lock()
        inFlight.remove(url)
        probedAt[url] = Date()
        lock.unlock()
    }

    private func update(_ s: LatencyState, for url: String) {
        lock.lock()
        store[url] = s
        let snap = store
        lock.unlock()
        DispatchQueue.main.async { self.states = snap }
    }
}
