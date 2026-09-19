import Foundation

// MARK: - GraphQL 错误定义

struct GraphQLErrorItem: Codable {
    let message: String
}

enum StashAPIError: LocalizedError {
    case badURL(String)
    case http(Int, String)
    case server([String])
    case noData
    case decoding(String)

    var errorDescription: String? {
        switch self {
        case .badURL(let u):
            return "无效的服务地址：\(u)"
        case .http(let code, let body):
            return "HTTP \(code)：\(body.prefix(200))"
        case .server(let msgs):
            return "Stash 返回错误：\n" + msgs.joined(separator: "\n")
        case .noData:
            return "响应为空，请检查服务地址是否指向 Stash"
        case .decoding(let detail):
            return "数据解析失败：\(detail)"
        }
    }
}

// MARK: - 轻量 GraphQL 客户端（无第三方依赖）

final class GraphQLClient {
    let url: URL
    let apiKey: String?
    private let session: URLSession

    /// - Parameters:
    ///   - baseURL: 形如 http://192.168.2.210:9999 或 https://stash.example.com/stash（支持路径前缀，适配外网反代）
    ///   - apiKey: Stash 设置 → 安全 → API Key，可空
    init(baseURL: String, apiKey: String?) throws {
        var s = baseURL.trimmingCharacters(in: .whitespacesAndNewlines)
        if s.isEmpty {
            throw StashAPIError.badURL("(空)")
        }
        if !s.hasSuffix("/graphql") {
            s = s.hasSuffix("/") ? s + "graphql" : s + "/graphql"
        }
        guard let u = URL(string: s) else {
            throw StashAPIError.badURL(baseURL)
        }
        self.url = u
        self.apiKey = (apiKey?.isEmpty == false) ? apiKey : nil

        let cfg = URLSessionConfiguration.default
        cfg.timeoutIntervalForRequest = 45   // 外网链路放宽超时
        cfg.timeoutIntervalForResource = 120
        cfg.requestCachePolicy = .reloadIgnoringLocalCacheData
        self.session = URLSession(configuration: cfg)
    }

    /// 发送 GraphQL 请求并解码 data 节点
    func send<T: Decodable>(_ query: String, variables: [String: Any] = [:], as type: T.Type) async throws -> T {
        var body: [String: Any] = ["query": query]
        if !variables.isEmpty { body["variables"] = variables }

        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        if let apiKey { req.setValue(apiKey, forHTTPHeaderField: "ApiKey") }
        req.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, resp) = try await session.data(for: req)
        if let http = resp as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
            let text = String(data: data, encoding: .utf8) ?? ""
            throw StashAPIError.http(http.statusCode, text)
        }

        struct Envelope: Decodable {
            let data: T?
            let errors: [GraphQLErrorItem]?
        }

        let env: Envelope
        do {
            env = try JSONDecoder().decode(Envelope.self, from: data)
        } catch {
            throw StashAPIError.decoding(error.localizedDescription)
        }
        if let errs = env.errors, !errs.isEmpty {
            throw StashAPIError.server(errs.map(\.message))
        }
        guard let d = env.data else {
            throw StashAPIError.noData
        }
        return d
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
