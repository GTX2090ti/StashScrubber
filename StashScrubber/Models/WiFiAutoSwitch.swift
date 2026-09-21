import Foundation
import NetworkExtension

// MARK: - WiFi SSID 自动切换（按 SSID 锁定连接 / 内网·外网地址）
//
// 新模型下「内外网切换」默认已由 AppSettings.autoSelectSlot() 自动完成
// （优先内网、内网不可达切外网）。本规则用于**主动覆盖**该自动策略，典型场景：
//   · 在家固定走内网（防止偶发探测失败误切外网）
//   · 连公司 WiFi 时固定走外网（家里内网不可达，避免每次都要等内网超时）
//   · 指定切换到另一条连接（多台 Stash 时）
//
// SSID 获取：NEHotspotNetwork.current，需 Access WiFi Information entitlement
// （entitlements 已声明；AltStore 重签后若丢失该权限，运行时返回 nil，
//  界面会显示「无法获取 SSID」提示，用户仍可手动切换）。
// 连通性探测与会话策略统一走 LatencyMonitor / NetProbe（NetworkCore.swift）。

struct SSIDRule: Codable, Identifiable, Equatable {
    var id: UUID = UUID()
    var ssid: String
    var profileID: UUID
    /// 锁定到某一侧地址；nil = 交给「优先内网 + 自动兜底」处理
    var slot: AddressSlot?
}

@MainActor
final class WiFiAutoSwitch: ObservableObject {
    static let shared = WiFiAutoSwitch()

    private static let rulesKey = "stash.wifiRules"
    private static let enabledKey = "stash.wifiAutoSwitchEnabled"

    @Published var enabled: Bool {
        didSet {
            UserDefaults.standard.set(enabled, forKey: Self.enabledKey)
            NetLog.shared.record(category: .wifi, level: .info, title: "自动切换",
                                 message: enabled ? "已开启" : "已关闭")
        }
    }
    @Published var rules: [SSIDRule] {
        didSet {
            if let data = try? JSONEncoder().encode(rules) {
                UserDefaults.standard.set(data, forKey: Self.rulesKey)
            }
        }
    }
    @Published var lastSSID: String?
    @Published var lastAction: String?

    private init() {
        enabled = UserDefaults.standard.object(forKey: Self.enabledKey) as? Bool ?? false
        if let data = UserDefaults.standard.data(forKey: Self.rulesKey),
           let r = try? JSONDecoder().decode([SSIDRule].self, from: data) {
            rules = r
        } else {
            rules = []
        }
    }

    /// 当前 WiFi SSID（iOS 14+ 官方通道）
    /// 运行时需同时满足：Access WiFi Information 权限 + （精确定位授权 / 曾用 NEHotspotConfiguration 配网 / 有活跃 VPN）之一，
    /// 不满足时返回 nil，由界面提示，用户仍可手动切换档案。
    static func fetchCurrentSSID() async -> String? {
        if let n = await NEHotspotNetwork.fetchCurrent(), !n.ssid.isEmpty {
            return n.ssid
        }
        return nil
    }

    /// App 回到前台 / 手动检测时调用：按规则锁定连接与地址。
    /// 注意：NEHotspotNetwork.fetchCurrent 在蜂窝网络下（已授权定位时）可能返回
    /// 「最近连接过的 WiFi」而非当前网络，导致误判在家 → 锁定前必须先探测目标地址可达。
    func checkAndSwitch(settings: AppSettings) async {
        guard enabled, !rules.isEmpty else { return }
        let ssid = await Self.fetchCurrentSSID()
        lastSSID = ssid
        guard let ssid else {
            // 读不到 SSID = 规则无法判定当前位置：解除「规则锁定」，退回自动选路。
            // 否则一旦离开规则 WiFi，用户会被永久钉在那一侧不可达的地址上。
            let released = settings.releaseRulePin(reason: "无法获取当前 WiFi 名称，已解除规则锁定并交给自动选路")
            lastAction = released
                ? "无法获取当前 WiFi 名称（请检查定位权限），已解除规则锁定"
                : "无法获取当前 WiFi 名称（请检查定位权限）"
            NetLog.shared.record(category: .wifi, level: .warn, title: "自动切换",
                                 message: lastAction ?? "")
            if released { await settings.autoSelectSlot() }
            return
        }
        guard let rule = rules.first(where: { $0.ssid.caseInsensitiveCompare(ssid) == .orderedSame }) else {
            // 无匹配规则：说明已离开规则 WiFi → 解除规则锁定（手动锁定不动）
            let released = settings.releaseRulePin(reason: "当前 WiFi「\(ssid)」无匹配规则，已解除规则锁定")
            lastAction = released
                ? "当前 WiFi「\(ssid)」无匹配规则，已解除规则锁定并交给自动选路"
                : "当前 WiFi「\(ssid)」无匹配规则，保持自动选路"
            if released { await settings.autoSelectSlot() }
            return
        }

        // 1) 规则指定了别的连接 → 先切连接
        if let target = settings.connections.first(where: { $0.id == rule.profileID }),
           settings.activeConnection?.id != target.id {
            settings.switchToConnection(target.id)
        }

        guard let conn = settings.activeConnection else { return }

        // 2) 规则要求锁定某一侧地址：先探测可达，避免蜂窝下误判导致「锁到不可用地址」
        if let slot = rule.slot {
            guard let url = conn.url(for: slot) else {
                lastAction = "规则要求使用\(slot.label)地址，但当前连接未配置该地址，保持自动选路"
                NetLog.shared.record(category: .wifi, level: .warn, title: "自动切换",
                                     message: lastAction ?? "")
                await settings.autoSelectSlot()
                return
            }
            let st = await LatencyMonitor.shared.measure(url: url, apiKey: conn.apiKey,
                                                         name: "\(conn.name) · \(slot.label)",
                                                         force: true)
            if st.isReachable {
                settings.pin(slot, byRule: true)
                lastAction = "检测到 WiFi「\(ssid)」，已锁定\(slot.label)地址（\(st.text)）"
                NetLog.shared.record(category: .wifi, level: .info, title: "自动切换",
                                     message: lastAction ?? "")
            } else {
                lastAction = "检测到 WiFi「\(ssid)」，但\(slot.label)地址探测不可达（可能在流量下误判），保持自动选路"
                NetLog.shared.record(category: .wifi, level: .warn, title: "自动切换",
                                     message: lastAction ?? "")
            }
            await settings.autoSelectSlot()
            return
        }

        // 3) 规则只指定连接：清掉「规则锁定」，交回「优先内网 + 自动兜底」（手动锁定不动）
        settings.releaseRulePin(reason: "规则「\(ssid)」未指定地址，已解除规则锁定")
        lastAction = "检测到 WiFi「\(ssid)」，已使用「\(conn.name)」并自动选路"
        NetLog.shared.record(category: .wifi, level: .info, title: "自动切换",
                             message: lastAction ?? "")
        await settings.autoSelectSlot()
    }
}
