import Foundation

// MARK: - GraphQL 错误定义

struct GraphQLErrorItem: Codable {
    let message: String
}

enum StashAPIError: LocalizedError {
    case badURL(String)
    case http(Int, String)
    case server([String])
    case notFound(String)
    case noData(status: Int?, body: String)
    case decoding(String)

    var errorDescription: String? {
        switch self {
        case .badURL(let u):
            return "无效的服务地址：\(u)"
        case .http(let code, let body):
            if code == 401 {
                return "HTTP 401：API Key 缺失或错误。请到 Stash 设置 → 安全 复制 API Key，在登录页或设置中填写"
            }
            return "HTTP \(code)：\(body.prefix(200))"
        case .server(let msgs):
            return "Stash 返回错误：\n" + msgs.joined(separator: "\n")
        case .notFound(let what):
            return "未找到：\(what)"
        case .noData(let status, let body):
            let snippet = body.isEmpty ? "(空响应体)" : String(body.prefix(300))
            return "响应无 data 节点（HTTP \(status.map(String.init) ?? "?")）：服务可能不是 Stash。响应体：\(snippet)"
        case .decoding(let detail):
            return "数据解析失败：\(detail)"
        }
    }
}

// MARK: - GraphQL 响应信封（泛型类型须定义在函数外，不能嵌套在泛型方法里）

private struct Envelope<T: Decodable>: Decodable {
    let data: T?
    let errors: [GraphQLErrorItem]?
}

// MARK: - 轻量 GraphQL 客户端（无第三方依赖）
//
// 端点解析、会话与超时策略、错误翻译、请求日志分别收口在 StashEndpoint / NetTransport /
// NetError / NetLog（见 NetworkCore.swift），本类只负责协议细节。

final class GraphQLClient {
    let url: URL
    let apiKey: String?
    /// 档案名（用于日志区分内网 / 外网）
    let profileName: String
    private let logTitle: String

    /// 常规请求硬超时（秒）：服务器侧查询本身 <5s，25s 是「链路已死」的判据
    static let hardTimeout: Double = 25
    /// 长耗时请求硬超时（秒）：刮削 / 识别要由服务端去外部站点取数，给足时间
    static let longTimeout: Double = 120

    /// - Parameters:
    ///   - baseURL: 形如 http://192.168.2.210:9999 或 https://stash.example.com/stash（支持路径前缀，适配外网反代）
    ///   - apiKey: Stash 设置 → 安全 → API Key，可空
    ///   - profileName: 当前档案名，仅用于日志
    init(baseURL: String, apiKey: String?, profileName: String = "") throws {
        guard let u = StashEndpoint.graphqlURL(baseURL) else {
            throw StashAPIError.badURL(baseURL.isEmpty ? "(空)" : baseURL)
        }
        self.url = u
        self.apiKey = (apiKey?.isEmpty == false) ? apiKey : nil
        self.profileName = profileName
        self.logTitle = "GraphQL · " + (profileName.isEmpty ? "未命名档案" : profileName)
    }

    /// 发送 GraphQL 请求并解码 data 节点
    /// - Parameter timeout: 硬超时秒数（默认 `hardTimeout`；刮削 / 识别类请传 `longTimeout`）
    func send<T: Decodable>(_ query: String, variables: [String: Any] = [:],
                            as type: T.Type,
                            timeout: Double = GraphQLClient.hardTimeout) async throws -> T {
        var body: [String: Any] = ["query": query]
        if !variables.isEmpty { body["variables"] = variables }

        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        if let apiKey { req.setValue(apiKey, forHTTPHeaderField: "ApiKey") }
        req.httpBody = try JSONSerialization.data(withJSONObject: body)
        // 交给 @Sendable 闭包前复制成不可变值，避免「捕获可变 var」（Swift 6 下为错误）
        let request = req

        let op = Self.operationName(query)
        let t0 = Date()
        let title = logTitle
        func elapsedMs() -> Double { Date().timeIntervalSince(t0) * 1000 }

        // 是否为写操作：mutation 不自动重试（可能重复写入），query 可安全重试
        let isMutationCall = query.trimmingCharacters(in: .whitespacesAndNewlines).hasPrefix("mutation")

        // 单次请求 + 解码（不含外层重试逻辑）
        func once() async throws -> T {
            // 硬超时兜底：URLSession 自身超时在连接池被吊死 / 网络切换等场景会失灵，
            // 到点强制返回并重建会话（丢掉吊死连接），保证视图 loading 状态一定复位。
            let r = try await NetCall.deadline(timeout, op: op, onTimeout: {
                NetTransport.resetAPI(reason: "\(title) 请求硬超时（\(op)），重建会话丢弃吊死连接")
            }) {
                // 每次现取会话：resetAPI 之后仍能拿到新会话
                let (d, resp) = try await NetTransport.api.data(for: request)
                return NetHTTPResult(data: d, status: (resp as? HTTPURLResponse)?.statusCode)
            }
            let data = r.data
            let httpStatus = r.status

            guard let code = httpStatus, (200..<300).contains(code) else {
                let text = String(data: data, encoding: .utf8) ?? ""
                NetLog.shared.record(category: .graphql, level: .error,
                                     title: "\(logTitle) · \(op)", method: "POST",
                                     url: url.absoluteString, status: httpStatus, ms: elapsedMs(),
                                     bytes: data.count,
                                     message: "HTTP \(httpStatus ?? 0)：\(text.prefix(150))")
                throw StashAPIError.http(httpStatus ?? -1, text)
            }

            let env: Envelope<T>
            do {
                env = try JSONDecoder().decode(Envelope<T>.self, from: data)
            } catch {
                NetLog.shared.record(category: .graphql, level: .error,
                                     title: "\(logTitle) · \(op)", method: "POST",
                                     url: url.absoluteString, status: httpStatus, ms: elapsedMs(),
                                     bytes: data.count,
                                     message: "解析失败：\(error.localizedDescription)")
                throw StashAPIError.decoding(error.localizedDescription)
            }

            if let errs = env.errors, !errs.isEmpty {
                let msgs = errs.map(\.message)
                NetLog.shared.record(category: .graphql, level: .error,
                                     title: "\(logTitle) · \(op)", method: "POST",
                                     url: url.absoluteString, status: httpStatus, ms: elapsedMs(),
                                     bytes: data.count,
                                     message: "Stash 返回：" + msgs.joined(separator: "; "))
                throw StashAPIError.server(msgs)
            }

            guard let d = env.data else {
                let text = String(data: data, encoding: .utf8) ?? ""
                NetLog.shared.record(category: .graphql, level: .warn,
                                     title: "\(logTitle) · \(op)", method: "POST",
                                     url: url.absoluteString, status: httpStatus, ms: elapsedMs(),
                                     bytes: data.count,
                                     message: "响应无 data 节点（对端可能不是 Stash）：\(text.prefix(150))")
                throw StashAPIError.noData(status: httpStatus, body: text)
            }

            NetLog.shared.record(category: .graphql, level: .info,
                                 title: "\(logTitle) · \(op)", method: "POST",
                                 url: url.absoluteString, status: httpStatus, ms: elapsedMs(),
                                 bytes: data.count)
            NetHealth.shared.noteSuccess()
            return d
        }

        do {
            return try await once()
        } catch {
            // 取消（页面切换 / 视图复用）属噪音，不入日志，直接抛
            if NetError.isCancellation(error) { throw error }

            // 上面各分支已记录过业务错误，这里只补记网络层异常
            if !(error is StashAPIError) {
                NetLog.shared.record(category: .graphql, level: .error,
                                     title: "\(logTitle) · \(op)", method: "POST",
                                     url: url.absoluteString, ms: elapsedMs(),
                                     message: NetError.friendly(error))
            }

            // 关键自愈：查询请求遇到链路层失败（keep-alive 死连接 / 网络抖动 / 半开连接）
            // 先重建会话丢弃吊死连接池，再自动重试一次——多数情况用户无感，不用杀 App 重启。
            // mutation 不自动重试，避免重复写入。
            if NetError.isConnectivity(error), !isMutationCall {
                let reason = NetError.friendly(error)
                NetTransport.resetAPI(reason: "查询「\(op)」链路失败（\(reason)），重建会话后自动重试一次")
                do {
                    let v = try await once()
                    NetLog.shared.record(category: .diag, level: .warn,
                                         title: "自动重试成功",
                                         message: "「\(op)」首次失败（\(reason)），重建会话后重试成功")
                    return v
                } catch {
                    if NetError.isCancellation(error) { throw error }
                    if !(error is StashAPIError) {
                        NetLog.shared.record(category: .graphql, level: .error,
                                             title: "\(logTitle) · \(op)", method: "POST",
                                             url: url.absoluteString, ms: elapsedMs(),
                                             message: "重试仍失败：" + NetError.friendly(error))
                    }
                    fallthroughToHealth(error)
                    throw error
                }
            }
            fallthroughToHealth(error)
            throw error
        }

        // 链路层失败累加：连续两次即触发一次自动重新选路（内外网翻面自愈）。
        // 触发自愈时同时重建会话——否则切了地址还共用死连接池，新请求照样卡死。
        func fallthroughToHealth(_ error: Error) {
            if NetError.isConnectivity(error) {
                if NetHealth.shared.noteFailure(NetError.friendly(error)) {
                    NetTransport.resetAPI(reason: "连续链路失败触发自愈：\(NetError.friendly(error))，重建会话")
                }
            }
        }
    }

    /// 从查询文本提取操作名（用于日志）：query Foo / mutation Bar → Foo，匿名查询取首个字段名
    static func operationName(_ query: String) -> String {
        let q = query.trimmingCharacters(in: .whitespacesAndNewlines)
        for kw in ["query ", "mutation "] where q.hasPrefix(kw) {
            let rest = q.dropFirst(kw.count)
            let name = rest.prefix { $0.isLetter || $0.isNumber || $0 == "_" }
            if !name.isEmpty { return String(name) }
        }
        if let brace = q.firstIndex(of: "{") {
            let rest = q[q.index(after: brace)...].drop { $0 == " " || $0 == "\n" || $0 == "\r" }
            let name = rest.prefix { $0.isLetter || $0.isNumber || $0 == "_" }
            if !name.isEmpty { return String(name) }
        }
        return "query"
    }
}

// MARK: - Encodable → GraphQL variables 字典

func jsonDict<T: Encodable>(_ value: T, snakeCase: Bool = true) throws -> [String: Any] {
    let enc = JSONEncoder()
    if snakeCase { enc.keyEncodingStrategy = .convertToSnakeCase }
    let data = try enc.encode(value)
    guard let obj = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
        throw StashAPIError.decoding("输入结构不是对象")
    }
    return obj
}
