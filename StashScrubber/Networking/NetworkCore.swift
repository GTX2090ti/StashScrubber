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

    /// 是否为「链路层」失败：只有这类失败才值得重新选路
    /// （业务错误 401 / GraphQL errors / 解析失败说明链路是通的，换了地址也没用）
    static func isConnectivity(_ error: Error) -> Bool {
        if error is NetTimeout { return true }
        guard let ue = error as? URLError else { return false }
        switch ue.code {
        case .timedOut, .cannotFindHost, .cannotConnectToHost, .networkConnectionLost,
             .notConnectedToInternet, .dnsLookupFailed, .secureConnectionFailed,
             .serverCertificateUntrusted, .dataNotAllowed, .internationalRoamingOff,
             .callIsActive, .resourceUnavailable:
            return true
        default:
            return false
        }
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

// MARK: - 硬超时（请求兜底）

/// 请求在硬超时窗口内未返回时抛出
struct NetTimeout: LocalizedError {
    let seconds: Double
    let op: String

    var errorDescription: String? {
        "请求超时（\(op) 超过 \(Int(seconds))s 无响应，已强制中断）"
    }
}

/// 硬超时包装后的 HTTP 响应（用具名结构体而非元组，避免泛型参数上的 Sendable 兼容问题）
struct NetHTTPResult: Sendable {
    var data: Data
    var status: Int?
    /// 响应 Content-Type（原始大小写，调用方自行 lowercased）
    var contentType: String? = nil
}

/// 只允许一次 resume 的闸门：请求完成 / 硬超时 / 取消 三方竞争时保证 continuation 只恢复一次
private final class OneShotGate<T: Sendable>: @unchecked Sendable {
    private let lock = NSLock()
    private var done = false

    func tryResume(_ cont: CheckedContinuation<T, Error>, _ result: Result<T, Error>) -> Bool {
        lock.lock()
        if done {
            lock.unlock()
            return false
        }
        done = true
        lock.unlock()
        cont.resume(with: result)
        return true
    }
}

/// 取消回调挂载点：任务的 onCancel 可能早于 continuation 建立，这里抹平顺序问题
private final class CancelLatch: @unchecked Sendable {
    private let lock = NSLock()
    private var fired = false
    private var onFired: (() -> Void)?

    func mount(_ h: @escaping () -> Void) {
        lock.lock()
        if fired {
            lock.unlock()
            h()
            return
        }
        onFired = h
        lock.unlock()
    }

    func fire() {
        lock.lock()
        fired = true
        let h = onFired
        onFired = nil
        lock.unlock()
        h?()
    }
}

/// 给任意异步请求套一层硬超时。
///
/// 为什么不能只靠 URLSession 的超时：`timeoutIntervalForRequest` 只统计「请求发出后的空闲」，
/// 当连接池被吊死的连接占满、网络路径切换（WiFi↔蜂窝）、本地网络权限挂起时，请求会卡在
/// **排队等连接**，这段等待不计入超时 —— 表现就是「用一段时间后突然一直转圈」且永不自愈。
///
/// 实现用「非结构化任务 + 一次性闸门」而不是 TaskGroup：TaskGroup 退出时会等待所有子任务结束，
/// 若被吊死的请求不响应取消，调用方仍会被拖住，兜底就白做了。这里超时即返回，
/// 丢弃的请求由 `onTimeout` 重建会话来清理（invalidateAndCancel 会取消该会话的全部在途请求）。
enum NetCall {
    static func deadline<T: Sendable>(
        _ seconds: Double,
        op: String,
        onTimeout: (@Sendable () -> Void)? = nil,
        _ body: @escaping @Sendable () async throws -> T
    ) async throws -> T {
        let gate = OneShotGate<T>()
        let latch = CancelLatch()
        return try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { (cont: CheckedContinuation<T, Error>) in
                latch.mount { _ = gate.tryResume(cont, .failure(CancellationError())) }

                // 用 detached：避免继承主 actor，保证计时器一定会准时触发
                Task.detached(priority: .userInitiated) {
                    do {
                        let v = try await body()
                        _ = gate.tryResume(cont, .success(v))
                    } catch {
                        _ = gate.tryResume(cont, .failure(error))
                    }
                }
                Task.detached(priority: .high) {
                    try? await Task.sleep(nanoseconds: UInt64(seconds * 1_000_000_000))
                    guard gate.tryResume(cont, .failure(NetTimeout(seconds: seconds, op: op))) else { return }
                    onTimeout?()
                }
            }
        } onCancel: {
            latch.fire()
        }
    }
}

// MARK: - 请求健康度（连续失败 → 触发自愈选路）

/// 只统计「链路层」失败：连续失败达到阈值即回调一次，由 AppSettings 重新在内外网间选路。
/// 触发后计数归零并进入冷却，避免网络抖动时来回翻面。
final class NetHealth: @unchecked Sendable {
    static let shared = NetHealth()

    /// 连续失败阈值（一次抖动不切，两次才认为这一侧真不通）
    static let threshold = 2
    /// 两次自愈之间的最小间隔
    static let cooldown: TimeInterval = 20

    private let lock = NSLock()
    private var consecutive = 0
    private var lastKick = Date.distantPast

    /// 主线程回调，参数为最后一次失败原因
    var onRepeatedFailure: ((String) -> Void)?

    private init() {}

    func noteSuccess() {
        lock.lock()
        consecutive = 0
        lock.unlock()
    }

    /// 记录一次链路失败；返回 true 表示本次触发了自愈
    @discardableResult
    func noteFailure(_ reason: String) -> Bool {
        lock.lock()
        consecutive += 1
        let n = consecutive
        let cooling = Date().timeIntervalSince(lastKick) < Self.cooldown
        let fire = (n >= Self.threshold) && !cooling
        if fire {
            consecutive = 0
            lastKick = Date()
        }
        lock.unlock()

        guard fire, let cb = onRepeatedFailure else { return false }
        DispatchQueue.main.async { cb(reason) }
        return true
    }

    /// 手动改地址 / 重置配置后清零计数
    func reset() {
        lock.lock()
        consecutive = 0
        lock.unlock()
    }
}

// MARK: - URLSession 会话（统一超时策略）

enum NetTransport {
    private static let apiLock = NSLock()
    private static var apiSession = makeAPI()

    /// 常规 API 会话：查询本身 <5s，20s 请求 / 60s 总时长足够让失败尽早显形。
    /// 会话可整体重建（见 resetAPI）——共享会话一旦被吊死的连接占满，新请求会卡在等连接
    /// 且不触发超时，这正是「用一段时间后突然连不上」的机制。调用方应每次现取，不要缓存。
    static var api: URLSession {
        apiLock.lock()
        defer { apiLock.unlock() }
        return apiSession
    }

    private static func makeAPI() -> URLSession {
        let cfg = URLSessionConfiguration.default
        cfg.timeoutIntervalForRequest = 20
        cfg.timeoutIntervalForResource = 60
        // 不允许「等待网络可用」：宁可快速失败也不无限期挂着
        cfg.waitsForConnectivity = false
        // 缓存由 App 自己管（图片缓存 / 每次重拉数据），避免拿到过期或错误响应
        cfg.requestCachePolicy = .reloadIgnoringLocalCacheData
        cfg.urlCache = nil
        return URLSession(configuration: cfg)
    }

    /// 重建 API 会话并丢弃旧连接（硬超时 / 连续失败后调用）。
    /// 不重建的话，吊死的连接会一直占着连接池，后续请求全部排队等待。
    static func resetAPI(reason: String) {
        apiLock.lock()
        let old = apiSession
        apiSession = makeAPI()
        apiLock.unlock()
        old.invalidateAndCancel()
        NetLog.shared.record(category: .diag, level: .warn, title: "重建网络会话", message: reason)
    }

    private static let imageLock = NSLock()
    private static var imageSession = makeImage()

    /// 图片会话：resource 是「总时长」上限（request 超时只是空闲计时，慢速滴流会一直续命），
    /// 30s 封底保证任何情况下转圈都会结束。
    /// 关闭 URLCache：图片缓存由 ImageCache 负责，若走系统缓存会把错误页以 0ms 重放。
    /// 与 api 一样可重建，避免连接池被吊死的连接占满（网格里几十张图并发时更容易发生）。
    static var image: URLSession {
        imageLock.lock()
        defer { imageLock.unlock() }
        return imageSession
    }

    private static func makeImage() -> URLSession {
        let cfg = URLSessionConfiguration.ephemeral
        cfg.timeoutIntervalForRequest = 15
        cfg.timeoutIntervalForResource = 30
        cfg.waitsForConnectivity = false
        cfg.httpMaximumConnectionsPerHost = 6
        cfg.requestCachePolicy = .reloadIgnoringLocalCacheData
        cfg.urlCache = nil
        return URLSession(configuration: cfg)
    }

    /// 重建图片会话并丢弃旧连接（图片下载硬超时后调用）
    static func resetImage(reason: String) {
        imageLock.lock()
        let old = imageSession
        imageSession = makeImage()
        imageLock.unlock()
        old.invalidateAndCancel()
        NetLog.shared.record(category: .diag, level: .warn, title: "重建图片会话", message: reason)
    }

    /// 绕过系统代理的直连会话（诊断对比用）：可区分「系统代理吊死」与「本地网络权限挂起」
    static let direct: URLSession = {
        let cfg = URLSessionConfiguration.ephemeral
        cfg.connectionProxyDictionary = [:]
        cfg.timeoutIntervalForRequest = 6
        cfg.timeoutIntervalForResource = 10
        cfg.waitsForConnectivity = false
        cfg.requestCachePolicy = .reloadIgnoringLocalCacheData
        cfg.urlCache = nil
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
