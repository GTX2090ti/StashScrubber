import Foundation
import NetworkExtension

// MARK: - WiFi SSID 自动切换（内网 / 外网档案）
//
// SSID 获取：NEHotspotNetwork.current，需 Access WiFi Information entitlement
// （entitlements 已声明；AltStore 重签后若丢失该权限，运行时返回 nil，
//  界面会显示「无法获取 SSID」提示，用户仍可手动切换档案）。

struct SSIDRule: Codable, Identifiable, Equatable {
    var id: UUID = UUID()
    var ssid: String
    var profileID: UUID
}

@MainActor
final class WiFiAutoSwitch: ObservableObject {
    static let shared = WiFiAutoSwitch()

    private static let rulesKey = "stash.wifiRules"
    private static let enabledKey = "stash.wifiAutoSwitchEnabled"

    @Published var enabled: Bool {
        didSet { UserDefaults.standard.set(enabled, forKey: Self.enabledKey) }
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
        if let n = try? await NEHotspotNetwork.fetchCurrent(), !n.ssid.isEmpty {
            return n.ssid
        }
        return nil
    }

    /// App 回到前台 / 手动检测时调用：按规则自动切换档案。
    /// 注意：NEHotspotNetwork.fetchCurrent 在蜂窝网络下（已授权定位时）可能返回
    /// 「最近连接过的 WiFi」而非当前网络，导致误判在家 → 必须先探测目标档案可达才切换。
    func checkAndSwitch(settings: AppSettings) async {
        guard enabled, !rules.isEmpty else { return }
        let ssid = await Self.fetchCurrentSSID()
        lastSSID = ssid
        guard let ssid else {
            lastAction = "无法获取当前 WiFi 名称（请检查定位权限）"
            return
        }
        guard let rule = rules.first(where: { $0.ssid.caseInsensitiveCompare(ssid) == .orderedSame }),
              let target = settings.profiles.first(where: { $0.id == rule.profileID }) else { return }
        if settings.activeProfileID == rule.profileID {
            lastAction = "当前 WiFi「\(ssid)」已对应「\(target.name)」"
            return
        }
        // 防误切：目标档案 3 秒内探测不到就不切，保持当前档案可用
        if await Self.probe(target) {
            settings.switchTo(target)
            lastAction = "检测到 WiFi「\(ssid)」，已切换到「\(target.name)」"
        } else {
            lastAction = "检测到 WiFi「\(ssid)」，但「\(target.name)」探测不可达（可能在流量下误判），保持当前档案"
        }
    }

    /// 轻量连通性探测：POST 一个最小查询，任何 HTTP 应答（含 401/400）都算可达；3 秒超时
    static func probe(_ profile: ServerProfile) async -> Bool {
        guard var comps = URLComponents(string: profile.url.trimmingCharacters(in: .whitespacesAndNewlines)),
              comps.host != nil else { return false }
        var path = comps.path
        if path.hasSuffix("/") { path.removeLast() }
        if path.hasSuffix("/graphql") { path = String(path.dropLast(8)) }
        comps.path = path + "/graphql"
        guard let url = comps.url else { return false }
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.timeoutInterval = 3
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        if !profile.apiKey.isEmpty { req.setValue(profile.apiKey, forHTTPHeaderField: "ApiKey") }
        req.httpBody = Data(#"{"query":"{ version { hash } }"}"#.utf8)
        do {
            _ = try await URLSession.shared.data(for: req)
            return true
        } catch {
            return false
        }
    }
}
