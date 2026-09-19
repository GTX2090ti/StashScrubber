import Foundation
import NetworkExtension
import SystemConfiguration

// MARK: - WiFi SSID 自动切换（内网 / 外网档案）
//
// SSID 获取优先级：
// 1. NEHotspotNetwork.current（需 Access WiFi Information 能力，普通签名下常返回 nil）
// 2. CNCopyCurrentNetworkInfo（需定位权限，Info.plist 已声明用途）
// 两者都拿不到时在界面显示状态提示，用户仍可手动切换档案。

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

    /// 当前 WiFi SSID（双通道探测，失败返回 nil）
    static func currentSSID() -> String? {
        if let n = NEHotspotNetwork.current, !n.ssid.isEmpty { return n.ssid }
        guard let ifaces = CNCopySupportedInterfaces() as? [String] else { return nil }
        for iface in ifaces {
            if let info = CNCopyCurrentNetworkInfo(iface as CFString) as? [String: Any],
               let ssid = info[kCNNetworkInfoKeySSID as String] as? String,
               !ssid.isEmpty {
                return ssid
            }
        }
        return nil
    }

    /// App 回到前台 / 手动检测时调用：按规则自动切换档案
    func checkAndSwitch(settings: AppSettings) {
        guard enabled, !rules.isEmpty else { return }
        let ssid = Self.currentSSID()
        lastSSID = ssid
        guard let ssid else {
            lastAction = "无法获取当前 WiFi 名称（请检查定位权限）"
            return
        }
        guard let rule = rules.first(where: { $0.ssid.caseInsensitiveCompare(ssid) == .orderedSame }),
              let target = settings.profiles.first(where: { $0.id == rule.profileID }) else { return }
        if settings.activeProfileID != rule.profileID {
            settings.switchTo(target)
            lastAction = "检测到 WiFi「\(ssid)」，已切换到「\(target.name)」"
        } else {
            lastAction = "当前 WiFi「\(ssid)」已对应「\(target.name)」"
        }
    }
}
