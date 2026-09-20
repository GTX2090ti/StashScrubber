import SwiftUI

// MARK: - 网络诊断：一键定位「转圈 / 连不上」问题的真实链路状态
// 检测项：
//  1. 所有档案的 GraphQL 可达性（并发探测，报告延迟 / HTTP 状态 / Stash 版本或错误）
//  2. 当前档案的图片链路（取一张短片截图，报告 HTTP 状态 / 字节数 / Content-Type）
//  3. 系统代理对比：同请求绕过系统代理直连，区分「代理吊死」与「本地网络权限」
//  4. WiFi 自动切换的最近状态（SSID / 动作）
// 所有探测外挂硬超时：到点强制取消任务，诊断页绝不整体吊死。

struct DiagnosticsView: View {
    @EnvironmentObject private var settings: AppSettings

    struct Row: Identifiable {
        let id = UUID()
        let title: String
        let detail: String
        let state: State
        enum State { case ok, fail, info, warn }
    }

    @State private var rows: [Row] = []
    @State private var running = false

    var body: some View {
        List {
            Section {
                LabeledContent("当前档案", value: settings.activeProfile?.name ?? "无")
                LabeledContent("地址", value: settings.activeProfile?.url ?? "-")
                LabeledContent("API Key", value: (settings.activeProfile?.apiKey.isEmpty ?? true) ? "未设置" : "已设置")
            } header: {
                Text("当前档案")
            } footer: {
                Text("逐项检测所有档案的 GraphQL 可达性、图片链路与系统代理干扰；任何一项失败请截图反馈。")
            }

            Section("检测结果") {
                if rows.isEmpty {
                    HStack {
                        Spacer()
                        if running { ProgressView() } else { Text("尚未检测").foregroundStyle(.secondary) }
                        Spacer()
                    }
                    .padding(.vertical, 8)
                }
                ForEach(rows) { r in
                    HStack(alignment: .top, spacing: 10) {
                        switch r.state {
                        case .ok:
                            Image(systemName: "checkmark.circle.fill").foregroundStyle(.green).frame(width: 20)
                        case .fail:
                            Image(systemName: "xmark.circle.fill").foregroundStyle(.red).frame(width: 20)
                        case .info:
                            Image(systemName: "info.circle").foregroundStyle(.secondary).frame(width: 20)
                        case .warn:
                            Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.orange).frame(width: 20)
                        }
                        VStack(alignment: .leading, spacing: 2) {
                            Text(r.title).font(.subheadline)
                            Text(r.detail).font(.caption).foregroundStyle(.secondary)
                                .textSelection(.enabled)
                        }
                    }
                }
            }

            Section {
                LabeledContent("自动切换", value: WiFiAutoSwitch.shared.enabled ? "开启" : "关闭")
                LabeledContent("规则数", value: "\(WiFiAutoSwitch.shared.rules.count)")
                LabeledContent("最近检测 SSID", value: WiFiAutoSwitch.shared.lastSSID ?? "无")
                LabeledContent("最近动作", value: WiFiAutoSwitch.shared.lastAction ?? "无")
            } header: {
                Text("WiFi 自动切换状态")
            }

            Section {
                Button {
                    Task { await runAll() }
                } label: {
                    HStack {
                        if running { ProgressView().padding(.trailing, 6) }
                        Text("重新检测")
                    }
                }
                .disabled(running)
            }
        }
        .navigationTitle("网络诊断")
        .navigationBarTitleDisplayMode(.inline)
        .task { await runAll() }
    }

    // MARK: 检测流程（主体在 MainActor，探测函数 nonisolated 短超时 + 硬超时兜底）

    private func runAll() async {
        guard !running else { return }
        running = true
        rows = []
        defer { running = false }

        // 全部探测并发执行；每个探测有 URLSession 自身超时 + 外挂硬超时双重保险
        let results = await withTaskGroup(of: [Row].self, returning: [Row].self) { group in
            for p in settings.profiles {
                group.addTask {
                    let r = await Self.timed(8) {
                        await Self.gql(p.url, apiKey: p.apiKey, query: "{ version { version } }", timeout: 6)
                    }
                    let isLAN = Self.isLANHost(p.url)
                    var row = Self.row(for: r, title: "GraphQL · \(p.name)", isLAN: isLAN)
                    // 系统代理对比：仅对探测失败的档案做直连复测
                    if r.error != nil {
                        let d = await Self.timed(8) {
                            await Self.gql(p.url, apiKey: p.apiKey, query: "{ version { version } }", timeout: 6,
                                           session: Self.directSession)
                        }
                        row = Self.withDirectCompare(primary: row, direct: d, isLAN: isLAN)
                    }
                    return [row]
                }
            }

            // 当前档案图片链路 + 直连对比
            if let p = settings.activeProfile {
                group.addTask { await Self.imageProbe(profile: p) }
            }

            var out: [Row] = []
            for await rs in group { out.append(contentsOf: rs) }
            return out
        }
        rows = results
    }

    private static func isLANHost(_ url: String) -> Bool {
        guard let h = URL(string: url)?.host ?? URL(string: "http://" + url.trimmingCharacters(in: .whitespaces))?.host else { return false }
        return h.hasPrefix("192.168.") || h.hasPrefix("10.") || h.hasPrefix("172.")
    }

    private static func row(for r: ProbeOut, title: String, isLAN: Bool) -> Row {
        if let err = r.error {
            var detail = "失败：\(err)（\(String(format: "%.1f", r.latency))s）"
            if isLAN {
                detail += "\n提示：内网地址——若长时间无响应，检查 设置→隐私与安全性→本地网络 是否允许本 App；或该 Wi-Fi 下内网不可达"
            }
            return Row(title: title, detail: detail, state: .fail)
        }
        return Row(title: title, detail: r.describe(), state: .ok)
    }

    /// 对失败的探测补一条「绕过系统代理直连」的对比结论
    private static func withDirectCompare(primary: Row, direct: ProbeOut, isLAN: Bool) -> Row {
        var detail = primary.detail
        if let derr = direct.error {
            detail += "\n直连（绕过系统代理）也失败：\(derr)"
            if isLAN {
                detail += "\n→ 疑似本地网络权限被拒（设置→隐私与安全性→本地网络→StashScrubber 设为允许），或手机不在此内网"
            }
            return Row(title: primary.title, detail: detail, state: .fail)
        }
        detail += "\n⚠️ 直连（绕过系统代理）成功：\(direct.describe())\n→ 系统代理把请求吊住了！检查 设置→无线局域网→当前网络→HTTP 代理（指向已失效代理会无限转圈），关闭后重试"
        return Row(title: primary.title, detail: detail, state: .warn)
    }

    private static func imageProbe(profile p: ServerProfile) async -> [Row] {
        let q = #"query { findScenes(filter: {per_page: 1}) { scenes { paths { screenshot } } } }"#
        let r = await Self.timed(8) { await Self.gql(p.url, apiKey: p.apiKey, query: q, timeout: 6) }
        if let err = r.error {
            return [Row(title: "图片链路 · \(p.name)", detail: "查询短片失败：\(err)", state: .fail)]
        }
        guard let shot = Self.firstScreenshot(r.raw) else {
            return [Row(title: "图片链路 · \(p.name)", detail: "库里没有短片可测，或响应不含截图地址", state: .info)]
        }
        var out: [Row] = [Row(title: "图片链路 · \(p.name)", detail: "原始地址：\(shot)", state: .info)]
        let finalURL = Self.rewrite(shot, to: p.url) ?? shot
        // 常规会话（走系统代理）
        let img = await Self.timed(12) { await Self.getImage(finalURL, apiKey: p.apiKey, timeout: 10) }
        let title = "图片下载 · \(p.name)"
        if let err = img.error {
            // 直连复测
            let d = await Self.timed(12) { await Self.getImage(finalURL, apiKey: p.apiKey, timeout: 10, session: Self.directSession) }
            if let derr = d.error {
                out.append(Row(title: title, detail: "失败：\(err)（\(String(format: "%.1f", img.latency))s）\n直连也失败：\(derr)\n地址：\(finalURL)", state: .fail))
            } else {
                out.append(Row(title: title, detail: "常规会话失败：\(err)\n⚠️ 直连成功：\(d.describeImage(url: finalURL))\n→ 系统代理干扰，检查 Wi-Fi 的 HTTP 代理设置\n地址：\(finalURL)", state: .warn))
            }
        } else {
            out.append(Row(title: title, detail: img.describeImage(url: finalURL), state: .ok))
        }
        return out
    }

    // MARK: 探测工具

    private struct ProbeOut {
        var status: Int?
        var snippet: String?
        var raw: Data?
        var latency: Double = 0
        var error: String?
        var byteCount: Int?
        var contentType: String?

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
            if let b = byteCount { parts.append("\(b)B") }
            if let ct = contentType { parts.append(ct) }
            parts.append(String(format: "%.2f", latency) + "s")
            return parts.joined(separator: " · ") + "\n地址：\(url)"
        }
    }

    /// 硬超时包装：探测函数自身超时失灵（如本地网络权限挂起）时，到点强制取消
    private static nonisolated func timed(_ seconds: Double, _ op: @escaping @Sendable () async -> ProbeOut) async -> ProbeOut {
        await withTaskGroup(of: ProbeOut.self) { g in
            g.addTask { await op() }
            g.addTask {
                try? await Task.sleep(nanoseconds: UInt64(seconds * 1_000_000_000))
                return ProbeOut(latency: seconds, error: "硬超时 \(Int(seconds))s（探测任务无响应，已强制终止）")
            }
            let first = await g.next() ?? ProbeOut(error: "无结果")
            g.cancelAll()
            return first
        }
    }

    /// 绕过系统代理的会话（对比用）
    private static let directSession: URLSession = {
        let cfg = URLSessionConfiguration.ephemeral
        cfg.connectionProxyDictionary = [:]
        cfg.timeoutIntervalForRequest = 6
        cfg.timeoutIntervalForResource = 10
        return URLSession(configuration: cfg)
    }()

    /// 拼接 GraphQL 端点（与 GraphQLClient 同规则：去尾斜杠、补 /graphql）
    private static nonisolated func endpoint(_ base: String) -> String {
        var s = base.trimmingCharacters(in: .whitespacesAndNewlines)
        if s.hasSuffix("/") { s.removeLast() }
        if !s.hasSuffix("/graphql") { s += "/graphql" }
        return s
    }

    /// 短超时 GraphQL 探测：任何 HTTP 应答（含 401/400）都算可达，body 供解析
    private static nonisolated func gql(_ base: String, apiKey: String, query: String, timeout: Double,
                                        session: URLSession = .shared) async -> ProbeOut {
        guard let url = URL(string: endpoint(base)) else {
            return ProbeOut(error: "地址无效")
        }
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.timeoutInterval = timeout
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        if !apiKey.isEmpty { req.setValue(apiKey, forHTTPHeaderField: "ApiKey") }
        let payload: [String: Any] = ["query": query, "variables": [:]]
        req.httpBody = try? JSONSerialization.data(withJSONObject: payload)
        let t0 = Date()
        do {
            let (data, resp) = try await session.data(for: req)
            var out = ProbeOut(status: (resp as? HTTPURLResponse)?.statusCode,
                               raw: data,
                               latency: Date().timeIntervalSince(t0))
            // 摘要：Stash 版本或 GraphQL 错误信息
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
            return out
        } catch is CancellationError {
            return ProbeOut(latency: Date().timeIntervalSince(t0), error: "已取消")
        } catch {
            return ProbeOut(latency: Date().timeIntervalSince(t0), error: Self.friendly(error))
        }
    }

    /// 从查询结果中取第一张短片截图地址
    private static nonisolated func firstScreenshot(_ data: Data?) -> String? {
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

    /// 与 RemoteImageView.resolvedURL 同款重写：把指向其他主机的图片地址改写到当前档案基址
    private static nonisolated func rewrite(_ urlString: String, to base: String) -> String? {
        guard var comps = URLComponents(string: urlString), comps.host != nil,
              let bc = URLComponents(string: base.trimmingCharacters(in: .whitespacesAndNewlines)),
              bc.host != nil else { return urlString }
        if comps.host == bc.host && comps.port == bc.port { return urlString }
        var merged = bc
        var bp = bc.path
        if bp.hasSuffix("/") { bp.removeLast() }
        merged.path = bp + comps.path
        merged.queryItems = comps.queryItems
        return merged.url?.absoluteString
    }

    /// 图片 GET 探测
    private static nonisolated func getImage(_ urlString: String, apiKey: String, timeout: Double,
                                             session: URLSession = .shared) async -> ProbeOut {
        guard let url = URL(string: urlString) else {
            return ProbeOut(error: "地址无效")
        }
        var req = URLRequest(url: url)
        req.timeoutInterval = timeout
        if !apiKey.isEmpty { req.setValue(apiKey, forHTTPHeaderField: "ApiKey") }
        let t0 = Date()
        do {
            let (data, resp) = try await session.data(for: req)
            let http = resp as? HTTPURLResponse
            let ct = http?.value(forHTTPHeaderField: "Content-Type") ?? "-"
            var out = ProbeOut(status: http?.statusCode,
                               latency: Date().timeIntervalSince(t0),
                               byteCount: data.count,
                               contentType: ct)
            if let http, !(200...299).contains(http.statusCode) {
                out.error = "HTTP \(http.statusCode)"
            } else if !ct.lowercased().contains("image") {
                out.error = "返回的不是图片（Content-Type: \(ct)）"
            }
            return out
        } catch is CancellationError {
            return ProbeOut(latency: Date().timeIntervalSince(t0), error: "已取消")
        } catch {
            return ProbeOut(latency: Date().timeIntervalSince(t0), error: Self.friendly(error))
        }
    }

    /// 常见 URLError 的人话翻译
    private static nonisolated func friendly(_ error: Error) -> String {
        guard let ue = error as? URLError else { return error.localizedDescription }
        switch ue.code {
        case .timedOut: return "超时（连接或响应无进展）"
        case .cannotFindHost: return "DNS 解析失败（域名不存在或 DNS 挂了）"
        case .cannotConnectToHost: return "连接被拒（端口不通/服务未起）"
        case .networkConnectionLost: return "连接中断"
        case .notConnectedToInternet: return "无网络连接"
        case .dnsLookupFailed: return "DNS 查询失败"
        case .cancelled: return "已取消"
        default: return ue.localizedDescription
        }
    }
}
