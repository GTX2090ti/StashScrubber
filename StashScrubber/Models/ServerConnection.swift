import Foundation

// MARK: - 服务器连接（一条连接 = 一个服务 + 内网 / 外网两个地址）
//
// 按「飞牛音乐」的连接配置模板重构：
//   地址类型（内外网都有 / 仅内网 / 仅外网）
//   + 外网地址（主机 + 端口 + HTTPS）
//   + 内网地址（主机 + 端口 + HTTPS）
//   + 「优先使用内网地址」开关（内网不可用时自动切到外网）
// 取代此前「每个地址一条独立档案、靠 WiFi 规则或手动切换」的做法——
// 后者在离网 / 回家时必须手动干预，且无法表达「同一服务的两个入口」。

// MARK: 地址类型

enum AddressKind: String, Codable, CaseIterable, Identifiable {
    case both, lan, wan

    var id: String { rawValue }

    var label: String {
        switch self {
        case .both: return "内外网都有"
        case .lan: return "仅内网"
        case .wan: return "仅外网"
        }
    }
}

// MARK: 地址槽位（实际生效的那一侧）

enum AddressSlot: String, Codable, CaseIterable, Identifiable {
    case lan, wan

    var id: String { rawValue }

    /// 短名：内网 / 外网
    var label: String { self == .lan ? "内网" : "外网" }

    /// 全名：内网地址 / 外网地址
    var fullLabel: String { self == .lan ? "内网地址" : "外网地址" }

    var icon: String { self == .lan ? "house" : "globe" }

    var opposite: AddressSlot { self == .lan ? .wan : .lan }
}

// MARK: 连接模型

struct ServerConnection: Codable, Identifiable, Equatable {
    var id: UUID = UUID()
    var name: String = "Stash 服务器"
    var kind: AddressKind = .both

    var lanHost: String = ""
    var lanPort: String = ""
    var lanHTTPS: Bool = false

    var wanHost: String = ""
    var wanPort: String = ""
    var wanHTTPS: Bool = true

    /// 优先使用内网地址（内网不可用时自动切换到外网）
    var preferLAN: Bool = true
    var apiKey: String = ""
    var lastSync: Date?

    init(id: UUID = UUID(),
         name: String = "Stash 服务器",
         kind: AddressKind = .both,
         lanHost: String = "",
         lanPort: String = "",
         lanHTTPS: Bool = false,
         wanHost: String = "",
         wanPort: String = "",
         wanHTTPS: Bool = true,
         preferLAN: Bool = true,
         apiKey: String = "",
         lastSync: Date? = nil) {
        self.id = id
        self.name = name
        self.kind = kind
        self.lanHost = lanHost
        self.lanPort = lanPort
        self.lanHTTPS = lanHTTPS
        self.wanHost = wanHost
        self.wanPort = wanPort
        self.wanHTTPS = wanHTTPS
        self.preferLAN = preferLAN
        self.apiKey = apiKey
        self.lastSync = lastSync
    }

    // 手写解码：字段用 decodeIfPresent + 默认值兜底，
    // 以后新增字段时旧版本持久化数据仍可解出，不会因缺键整条配置丢失。
    enum CodingKeys: String, CodingKey {
        case id, name, kind
        case lanHost, lanPort, lanHTTPS
        case wanHost, wanPort, wanHTTPS
        case preferLAN, apiKey, lastSync
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = (try? c.decode(UUID.self, forKey: .id)) ?? UUID()
        name = (try? c.decode(String.self, forKey: .name)) ?? "Stash 服务器"
        kind = (try? c.decode(AddressKind.self, forKey: .kind)) ?? .both
        lanHost = (try? c.decode(String.self, forKey: .lanHost)) ?? ""
        lanPort = (try? c.decode(String.self, forKey: .lanPort)) ?? ""
        lanHTTPS = (try? c.decode(Bool.self, forKey: .lanHTTPS)) ?? false
        wanHost = (try? c.decode(String.self, forKey: .wanHost)) ?? ""
        wanPort = (try? c.decode(String.self, forKey: .wanPort)) ?? ""
        wanHTTPS = (try? c.decode(Bool.self, forKey: .wanHTTPS)) ?? true
        preferLAN = (try? c.decode(Bool.self, forKey: .preferLAN)) ?? true
        apiKey = (try? c.decode(String.self, forKey: .apiKey)) ?? ""
        lastSync = try? c.decode(Date.self, forKey: .lastSync)
    }

    // MARK: - 地址拼装 / 拆解

    /// 拼装地址。host 栏允许两种写法：
    ///   1. 只写主机（可含路径前缀）：`192.168.2.210` / `nas.example.com/stash`
    ///   2. 直接粘贴完整 URL：`https://nas.example.com:9988/stash`（其 scheme 与端口优先）
    /// 端口栏非空时覆盖。
    static func compose(host: String, port: String, https: Bool) -> String? {
        var h = host.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !h.isEmpty else { return nil }

        var scheme: String?
        if let r = h.range(of: "://") {
            scheme = String(h[h.startIndex..<r.lowerBound]).lowercased()
            h = String(h[r.upperBound...])
        }
        // 去掉 user:pass@ 前缀
        if let at = h.lastIndex(of: "@") { h = String(h[h.index(after: at)...]) }

        var path = ""
        if let slash = h.firstIndex(of: "/") {
            path = String(h[slash...])
            h = String(h[..<slash])
        }

        var hostPart = h
        var portPart = port.trimmingCharacters(in: .whitespacesAndNewlines)
        // host 内嵌的 :端口 仅在端口栏留空时采用（端口栏更明确，优先）
        if portPart.isEmpty, !h.contains("]"), let colon = h.lastIndex(of: ":") {
            let p = String(h[h.index(after: colon)...])
            if !p.isEmpty, p.allSatisfy({ $0.isNumber }) {
                portPart = p
                hostPart = String(h[..<colon])
            }
        }
        guard !hostPart.isEmpty else { return nil }

        let sch = scheme ?? (https ? "https" : "http")
        var out = sch + "://" + hostPart
        if !portPart.isEmpty { out += ":" + portPart }
        out += path
        while out.hasSuffix("/") { out.removeLast() }
        guard !out.isEmpty else { return nil }
        return out
    }

    /// 拆解地址为（主机，端口，是否 HTTPS）；主机部分保留路径前缀，便于回填编辑框
    static func split(_ raw: String) -> (host: String, port: String, https: Bool) {
        var s = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !s.isEmpty else { return ("", "", false) }
        var https = false
        if let r = s.range(of: "://") {
            https = String(s[s.startIndex..<r.lowerBound]).lowercased() == "https"
            s = String(s[r.upperBound...])
        }
        if let at = s.lastIndex(of: "@") { s = String(s[s.index(after: at)...]) }

        var path = ""
        if let slash = s.firstIndex(of: "/") {
            path = String(s[slash...])
            s = String(s[..<slash])
        }
        var host = s
        var port = ""
        if !s.contains("]"), let colon = s.lastIndex(of: ":") {
            let p = String(s[s.index(after: colon)...])
            if !p.isEmpty, p.allSatisfy({ $0.isNumber }) {
                port = p
                host = String(s[..<colon])
            }
        }
        return (host + path, port, https)
    }

    // MARK: - 解析出的地址

    var lanURL: String? { Self.compose(host: lanHost, port: lanPort, https: lanHTTPS) }
    var wanURL: String? { Self.compose(host: wanHost, port: wanPort, https: wanHTTPS) }

    var hasLAN: Bool { lanURL != nil }
    var hasWAN: Bool { wanURL != nil }

    /// 当前地址类型下可用的槽位（按 内网 → 外网 顺序）
    var availableSlots: [AddressSlot] {
        var out: [AddressSlot] = []
        switch kind {
        case .both:
            if hasLAN { out.append(.lan) }
            if hasWAN { out.append(.wan) }
        case .lan:
            if hasLAN { out.append(.lan) }
        case .wan:
            if hasWAN { out.append(.wan) }
        }
        return out
    }

    func url(for slot: AddressSlot) -> String? {
        guard availableSlots.contains(slot) else { return nil }
        return slot == .lan ? lanURL : wanURL
    }

    /// 优先槽位：按地址类型 + 「优先使用内网地址」决定
    var preferredSlot: AddressSlot? {
        let slots = availableSlots
        switch kind {
        case .lan: return slots.contains(.lan) ? .lan : slots.first
        case .wan: return slots.contains(.wan) ? .wan : slots.first
        case .both:
            let first: AddressSlot = preferLAN ? .lan : .wan
            if slots.contains(first) { return first }
            return slots.first
        }
    }

    /// 备选槽位（优先项不可达时的兜底）
    var fallbackSlot: AddressSlot? {
        guard let p = preferredSlot else { return nil }
        return availableSlots.first { $0 != p }
    }

    // MARK: - 运行时档案（兼容既有调用：GraphQLClient / 探测 / 延迟监测均按此取址）

    func resolvedProfile(slot: AddressSlot, qualifiedName: Bool = false) -> ServerProfile? {
        guard let u = url(for: slot) else { return nil }
        let n = qualifiedName ? "\(name) · \(slot.label)" : name
        return ServerProfile(id: id, name: n, url: u, apiKey: apiKey)
    }

    /// 按「优先地址」生成的档案（列表 / 兼容旧接口用）
    var canonicalProfile: ServerProfile? {
        guard let slot = preferredSlot else { return nil }
        return resolvedProfile(slot: slot)
    }

    // MARK: - 展示

    /// 展示用地址：去掉 scheme，保留 主机:端口 与路径（模板风格：192.168.2.210:5666）
    func displayURL(for slot: AddressSlot) -> String? {
        guard let u = url(for: slot) else { return nil }
        var s = u
        for p in ["https://", "http://"] where s.hasPrefix(p) {
            s = String(s.dropFirst(p.count))
        }
        return s
    }

    /// 列表卡片摘要：如「内网 192.168.2.210:9999 · 外网 nas.example.com:9988」
    var summaryAddress: String {
        let slots = availableSlots
        guard !slots.isEmpty else { return "未配置地址" }
        return slots.map { "\($0.label) \(displayURL(for: $0) ?? "-")" }.joined(separator: " · ")
    }

    var hasAPIKey: Bool { !apiKey.trimmingCharacters(in: .whitespaces).isEmpty }

    var lastSyncText: String {
        guard let lastSync else { return "尚未同步" }
        let f = RelativeDateTimeFormatter()
        f.locale = Locale(identifier: "zh_CN")
        f.unitsStyle = .short
        return f.localizedString(for: lastSync, relativeTo: Date())
    }
}
