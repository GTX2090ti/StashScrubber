import Foundation

// MARK: - 网络核心（统一收口）
//
// 本文件把此前分散在 GraphQLClient / WiFiAutoSwitch / DiagnosticsView / RemoteImageView
// 中的四类重复逻辑收口为单一实现：
//   1. 端点解析与图片地址重写       → StashEndpoint
//   2. 错误人话翻译                → NetError
//   3. URLSession 会话与超时策略     → NetTransport
//   4. 带硬超时的轻量探测            → NetProbe
//   5. 网络请求日志（可复制）        → NetLog

// MARK: - 端点解析

enum StashEndpoint {
    /// 去掉首尾空白与尾斜杠；空串返回 nil
    static func normalize(_ base: String) -> String? {
        var s = base.trimmingCharacters(in: .whitespacesAndNewlines)
        while s.hasSuffix("/") { s.removeLast() }
        return s.isEmpty ? nil : s
    }

    /// 由基址构造 GraphQL 端点：自动补 /graphql（已含则不重复追加）
    static func graphqlURL(_ base: String) -> URL? {
        guard let s = normalize(base) else { return nil }
        let full = s.hasSuffix("/graphql") ? s : s + "/graphql"
        return URL(string: full)
    }

    /// 图片地址重写：主机与当前档案不一致时，改写为「档案基址 + 原路径与查询参数」，
    /// 使内网绝对地址在外网反代档案下也能加载。
    static func rewriteImage(_ raw: String, base: String) -> URL? {
        guard !raw.isEmpty, var comps = URLComponents(string: raw), comps.host != nil else { return nil }
        guard let bs = normalize(base),
              let bc = URLComponents(string: bs), bc.host != nil else { return comps.url }
        if comps.host == bc.host && comps.port == bc.port { return comps.url }
        var merged = bc
        merged.path = bc.path + comps.path
        merged.queryItems = comps.queryItems
        return merged.url
    }

    /// 是否为内网（私网）地址
    static func isLAN(_ urlString: String) -> Bool {
        let host = URL(string: urlString)?.host
            ?? URL(string: "http://" + urlString.trimmingCharacters(in: .whitespaces))?.host
            ?? ""
        return host.hasPrefix("192.168.") || host.hasPrefix("10.") || host.hasPrefix("172.")
    }
}

// MARK: - 错误翻译

enum NetError {
    /// 任务取消（页面切换 / 视图复用）不算错误
    static func isCancellation(_ error: Error) -> Bool {
        if error is CancellationError { return true }
        if let ue = error as? URLError, ue.code == .cancelled { return true }
        return false
    }

    /// 常见网络错误的「人话」翻译
    static func friendly(_ error: Error) -> String {
        if isCancellation(error) { return "已取消" }
        if let e = error as? StashAPIError { return e.errorDescription ?? "\(e)" }
        guard let ue = error as? URLError else { return error.localizedDescription }
        switch ue.code {
        case .timedOut: return "超时（连接或响应无进展）"
        case .cannotFindHost: return "DNS 解析失败（域名不存在或 DNS 挂了）"
        case .cannotConnectToHost: return "连接被拒（端口不通/服务未起）"
        case .networkConnectionLost: return "连接中断"
        case .notConnectedToInternet: return "无网络连接"
        case .dnsLookupFailed: return "DNS 查询失败"
        case .secureConnectionFailed, .serverCertificateUntrusted: return "TLS 握手失败（证书或中间设备拦截）"
        case .appTransportSecurityRequiresSecureConnection: return "ATS 拦截（需 HTTPS）"
        default: return ue.localizedDescription
        }
    }
}

// MARK: - URLSession 会话（统一超时策略）

enum NetTransport {
    /// 常规 API 会话：查询本身 <5s，20s 请求 / 60s 总时长足够让失败尽早显形
    static let api: URLSession = {
        let cfg = URLSessionConfiguration.default
        cfg.timeoutIntervalForRequest = 20
        cfg.timeoutIntervalForResource = 60
        cfg.requestCachePolicy = .reloadIgnoringLocalCacheData
        return URLSession(configuration: cfg)
    }()

    /// 图片会话：resource 是「总时长」上限（request 超时只是空闲计时，慢速滴流会一直续命），
    /// 30s 封底保证任何情况下转圈都会结束
    static let image: URLSession = {
        let cfg = URLSessionConfiguration.ephemeral
        cfg.timeoutIntervalForRequest = 15
        cfg.timeoutIntervalForResource = 30
        cfg.waitsForConnectivity = false
        cfg.httpMaximumConnectionsPerHost = 6
        return URLSession(configuration: cfg)
    }()

    /// 绕过系统代理的直连会话（诊断对比用）：可区分「系统代理吊死」与「本地网络权限挂起」
    static let direct: URLSession = {
        let cfg = URLSessionConfiguration.ephemeral
        cfg.connectionProxyDictionary = [:]
        cfg.timeoutIntervalForRequest = 6
        cfg.timeoutIntervalForResource = 10
        cfg.waitsForConnectivity = false
        return URLSession(configuration: cfg)
    }()
}

// MARK: - 轻量探测（诊断 / WiFi 切换共用）

enum NetProbe {
    struct Result: Sendable {
        var status: Int?
        var latency: Double = 0
        var raw: Data?
        var snippet: String?
        var byteCount: Int?
        var contentType: String?
        var error: String?
        /// 由硬超时兜底产生的占位结果（探测任务本身可能永不返回）
        var hardTimedOut = false

        var reachable: Bool { error == nil }

        func describe() -> String {
            var parts: [String] = []
            if let status { parts.append("HTTP \(status)") }
            parts.append(String(format: "%.2f", latency) + "s")
            if let snippet { parts.append(snippet) }
            return parts.joined(separator: " · ")
        }

        func describeImage(url: String) -> String {
            var parts: [String] = []
            if let status { parts.append("HTTP \(status)") }
            if let b = byteCount { parts.append(NetLog.byteText(b)) }
            if let ct = contentType { parts.append(ct) }
            parts.append(String(format: "%.2f", latency) + "s")
            return parts.joined(separator: " · ") + "\n地址：\(url)"
        }
    }

    /// 硬超时包装：URLSession 自身超时在「本地网络权限挂起」等场景会失灵，
    /// 到点强制取消探测任务并返回占位结果，保证调用方（诊断页）绝不整体吊死。
    static func hardTimeout(_ seconds: Double,
                            category: NetCategory = .diag,
                            title: String,
                            url: String? = nil,
                            _ op: @escaping @Sendable () async -> Result) async -> Result {
        let out = await withTaskGroup(of: Result.self) { g -> Result in
            g.addTask { await op() }
            g.addTask {
                try? await Task.sleep(nanoseconds: UInt64(seconds * 1_000_000_000))
                var r = Result(latency: seconds,
                               error: "硬超时 \(Int(seconds))s（探测无响应，已强制终止）")
                r.hardTimedOut = true
                return r
            }
            let first = await g.next() ?? Result(error: "无结果")
            g.cancelAll()
            return first
        }
        // 仅硬超时兜底时补记日志：探测任务自身可能永不返回，无法自行记录
        if out.hardTimedOut {
            NetLog.shared.record(category: category, level: .error, title: title,
                                 method: "POST", url: url, ms: seconds * 1000,
                                 message: out.error ?? "硬超时")
        }
        return out
    }

    /// GraphQL 探测：任何 HTTP 应答（含 401/400）都算链路可达，仅网络层异常才记 error
    static func graphql(base: String, apiKey: String, query: String, timeout: Double,
                        session: URLSession = NetTransport.api,
                        category: NetCategory = .diag,
                        title: String? = nil) async -> Result {
        let label = title ?? "GraphQL 探测"
        guard let url = StashEndpoint.graphqlURL(base) else {
            NetLog.shared.record(category: category, level: .error, title: label, message: "地址无效：\(base)")
            return Result(error: "地址无效")
        }
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.timeoutInterval = timeout
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        if !apiKey.isEmpty { req.setValue(apiKey, forHTTPHeaderField: "ApiKey") }
        req.httpBody = try? JSONSerialization.data(withJSONObject: ["query": query, "variables": [:]])

        let t0 = Date()
        do {
            let (data, resp) = try await session.data(for: req)
            let ms = Date().timeIntervalSince(t0) * 1000
            var out = Result(status: (resp as? HTTPURLResponse)?.statusCode,
                             latency: Date().timeIntervalSince(t0),
                             raw: data)
            if let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
                if let errs = obj["errors"] as? [[String: Any]],
                   let msg = errs.first?["message"] as? String {
                    out.snippet = "GraphQL 错误: " + msg
                } else if let d = obj["data"] as? [String: Any],
                          let v = d["version"] as? [String: Any],
                          let ver = v["version"] as? String {
                    out.snippet = "Stash " + ver
                }
            }
            NetLog.shared.record(category: category, level: .info, title: label,
                                 method: "POST", url: url.absoluteString,
                                 status: out.status, ms: ms, bytes: data.count,
                                 message: out.snippet)
            return out
        } catch {
            let ms = Date().timeIntervalSince(t0) * 1000
            if NetError.isCancellation(error) {
                return Result(latency: ms / 1000, error: "已取消")
            }
            let msg = NetError.friendly(error)
            NetLog.shared.record(category: category, level: .error, title: label,
                                 method: "POST", url: url.absoluteString, ms: ms, message: msg)
            return Result(latency: ms / 1000, error: msg)
        }
    }

    /// 图片 GET 探测：非 2xx、或 Content-Type 不是图片都算失败
    static func image(urlString: String, apiKey: String, timeout: Double,
                      session: URLSession = NetTransport.image,
                      category: NetCategory = .diag,
                      title: String? = nil) async -> Result {
        let label = title ?? "图片探测"
        guard let url = URL(string: urlString) else {
            return Result(error: "地址无效")
        }
        var req = URLRequest(url: url)
        req.timeoutInterval = timeout
        if !apiKey.isEmpty { req.setValue(apiKey, forHTTPHeaderField: "ApiKey") }
        let t0 = Date()
        do {
            let (data, resp) = try await session.data(for: req)
            let ms = Date().timeIntervalSince(t0) * 1000
            let http = resp as? HTTPURLResponse
            let ct = http?.value(forHTTPHeaderField: "Content-Type") ?? "-"
            var out = Result(status: http?.statusCode, latency: ms / 1000,
                             byteCount: data.count, contentType: ct)
            if let http, !(200...299).contains(http.statusCode) {
                out.error = "HTTP \(http.statusCode)"
            } else if !ct.lowercased().contains("image") {
                out.error = "返回的不是图片（Content-Type: \(ct)）"
            }
            if let e = out.error {
                NetLog.shared.record(category: category, level: .error, title: label,
                                     url: url.absoluteString, status: out.status, ms: ms,
                                     bytes: data.count, message: e)
            } else {
                NetLog.shared.record(category: category, level: .info, title: label,
                                     url: url.absoluteString, status: out.status, ms: ms,
                                     bytes: data.count, message: ct)
            }
            return out
        } catch {
            let ms = Date().timeIntervalSince(t0) * 1000
            if NetError.isCancellation(error) {
                return Result(latency: ms / 1000, error: "已取消")
            }
            let msg = NetError.friendly(error)
            NetLog.shared.record(category: category, level: .error, title: label,
                                 url: urlString, ms: ms, message: msg)
            return Result(latency: ms / 1000, error: msg)
        }
    }

    /// 从 findScenes 响应中取第一张短片截图地址
    static func firstScreenshot(_ data: Data?) -> String? {
        guard let data else { return nil }
        struct R: Decodable {
            struct P: Decodable { let screenshot: String? }
            struct S: Decodable { let paths: P? }
            struct F: Decodable { let scenes: [S]? }
            let findScenes: F?
        }
        guard let r = try? JSONDecoder().decode(R.self, from: data) else { return nil }
        return r.findScenes?.scenes?.first?.paths?.screenshot
    }
}

// MARK: - 网络日志（内存环形缓冲，支持一键复制）

enum NetCategory: String, CaseIterable, Identifiable {
    case graphql = "GraphQL"
    case image = "图片"
    case wifi = "WiFi"
    case diag = "诊断"
    case auth = "登录"

    var id: String { rawValue }

    var icon: String {
        switch self {
        case .graphql: return "arrow.left.arrow.right"
        case .image: return "photo"
        case .wifi: return "wifi"
        case .diag: return "stethoscope"
        case .auth: return "key"
        }
    }
}

enum NetLevel: String {
    case info, warn, error

    var tag: String {
        switch self {
        case .info: return "INFO"
        case .warn: return "WARN"
        case .error: return "ERROR"
        }
    }
}

/// 网络请求日志中心：任意线程可写，主线程发布，供日志页展示与复制。
/// 日志仅保存在内存中（容量上限见 capacity），重启后清空——反馈问题时请先复制。
final class NetLog: ObservableObject, @unchecked Sendable {
    static let shared = NetLog()
    static let capacity = 600

    /// 是否记录图片成功请求（默认关：列表滚动会产生大量噪音）
    static let verboseImageKey = "stash.netLogVerboseImage"
    static var verboseImage: Bool { UserDefaults.standard.bool(forKey: verboseImageKey) }

    struct Entry: Identifiable, Equatable {
        let id = UUID()
        let date: Date
        let category: NetCategory
        let level: NetLevel
        let title: String
        var method: String?
        var url: String?
        var status: Int?
        var ms: Double?
        var bytes: Int?
        var message: String?

        var summary: String {
            var parts: [String] = []
            if let status { parts.append("HTTP \(status)") }
            if let ms { parts.append(String(format: "%.0fms", ms)) }
            if let bytes { parts.append(NetLog.byteText(bytes)) }
            if let message, !message.isEmpty { parts.append(message) }
            return parts.joined(separator: " · ")
        }

        /// 可复制文本块
        var block: String {
            var s = "[\(NetLog.fullFormatter.string(from: date))] \(level.tag) \(category.rawValue) | \(title)"
            var line: [String] = []
            if let method { line.append(method) }
            if let url { line.append(url) }
            if let status { line.append("HTTP \(status)") }
            if let ms { line.append(String(format: "%.0fms", ms)) }
            if let bytes { line.append(NetLog.byteText(bytes)) }
            if !line.isEmpty { s += "\n    " + line.joined(separator: "  ") }
            if let message, !message.isEmpty {
                s += "\n    " + message.replacingOccurrences(of: "\n", with: " | ")
            }
            return s
        }
    }

    private let lock = NSLock()
    private var buffer: [Entry] = []

    /// 图片失败折叠：网格内几十张图同时失败时，同 URL 同原因只留一条
    private let dedupeLock = NSLock()
    private var lastImageFailKey: String?
    private var lastImageFailAt = Date.distantPast
    private static let imageFailWindow: TimeInterval = 5

    /// 主线程读取（视图绑定）
    @Published private(set) var entries: [Entry] = []
    @Published private(set) var errorCount = 0

    private init() {}

    static let timeFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "HH:mm:ss"
        return f
    }()

    static let fullFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd HH:mm:ss"
        return f
    }()

    static func byteText(_ n: Int) -> String {
        if n < 1024 { return "\(n)B" }
        if n < 1024 * 1024 { return String(format: "%.1fKB", Double(n) / 1024) }
        return String(format: "%.1fMB", Double(n) / 1_048_576)
    }

    // MARK: 写入

    func record(category: NetCategory, level: NetLevel, title: String,
                method: String? = nil, url: String? = nil, status: Int? = nil,
                ms: Double? = nil, bytes: Int? = nil, message: String? = nil) {
        add(Entry(date: Date(), category: category, level: level, title: title,
                  method: method, url: url, status: status, ms: ms, bytes: bytes, message: message))
    }

    func add(_ e: Entry) {
        // 图片连续失败折叠（避免整屏图片刷屏淹没其它日志）
        if e.category == .image, e.level != .info {
            let sig = (e.url ?? "") + "|" + (e.message ?? "")
            dedupeLock.lock()
            let dup = (lastImageFailKey == sig) && (e.date.timeIntervalSince(lastImageFailAt) < Self.imageFailWindow)
            if !dup {
                lastImageFailKey = sig
                lastImageFailAt = e.date
            }
            dedupeLock.unlock()
            if dup { return }
        }

        lock.lock()
        buffer.append(e)
        if buffer.count > Self.capacity {
            buffer.removeFirst(buffer.count - Self.capacity)
        }
        let snap = buffer
        lock.unlock()
        DispatchQueue.main.async {
            self.entries = snap
            self.errorCount = snap.reduce(0) { $0 + ($1.level == .error ? 1 : 0) }
        }
    }

    // MARK: 读取 / 导出

    func snapshot() -> [Entry] {
        lock.lock()
        defer { lock.unlock() }
        return buffer
    }

    func clear() {
        lock.lock()
        buffer.removeAll()
        lock.unlock()
        DispatchQueue.main.async {
            self.entries = []
            self.errorCount = 0
        }
    }

    /// 导出为可复制的纯文本
    static func exportText(_ list: [Entry]) -> String {
        let head = "Stash 削刮 · 网络日志（共 \(list.count) 条，错误 \(list.filter { $0.level == .error }.count) 条）\n"
            + "导出时间：\(fullFormatter.string(from: Date()))\n"
            + String(repeating: "-", count: 32)
        guard !list.isEmpty else { return head + "\n（无记录）" }
        return head + "\n" + list.map(\.block).joined(separator: "\n")
    }
}
