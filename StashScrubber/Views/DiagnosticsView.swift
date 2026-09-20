import SwiftUI

// MARK: - 网络诊断：一键定位「转圈 / 连不上」问题的真实链路状态
// 检测项：
//  1. 所有档案的 GraphQL 可达性（短超时探测，报告延迟 / HTTP 状态 / Stash 版本或错误）
//  2. 当前档案的图片链路（取一张短片截图，报告 HTTP 状态 / 字节数 / Content-Type）
//  3. WiFi 自动切换的最近状态（SSID / 动作）

struct DiagnosticsView: View {
    @EnvironmentObject private var settings: AppSettings

    struct Row: Identifiable {
        let id = UUID()
        let title: String
        let detail: String
        let state: State
        enum State { case ok, fail, info }
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
                Text("逐项检测所有档案的 GraphQL 可达性与当前档案的图片链路；任何一项失败请截图反馈。")
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

    // MARK: 检测流程（主体在 MainActor，探测函数 nonisolated 短超时）

    private func runAll() async {
        guard !running else { return }
        running = true
        rows = []
        defer { running = false }

        // 1. 所有档案 GraphQL 可达性
        for p in settings.profiles {
            let r = await Self.gql(p.url, apiKey: p.apiKey, query: "{ version { version } }", timeout: 6)
            append(r.error == nil
                   ? Row(title: "GraphQL · \(p.name)",
                         detail: r.describe(),
                         state: .ok)
                   : Row(title: "GraphQL · \(p.name)",
                         detail: "失败：\(r.error ?? "未知")（\(String(format: "%.1f", r.latency))s）",
                         state: .fail))
        }

        // 2. 当前档案图片链路：取一张短片截图，按 resolvedURL 同款重写规则访问
        if let p = settings.activeProfile {
            let q = #"query { findScenes(filter: {per_page: 1}) { scenes { paths { screenshot } } } }"#
            let r = await Self.gql(p.url, apiKey: p.apiKey, query: q, timeout: 6)
            if let err = r.error {
                append(Row(title: "图片链路 · \(p.name)", detail: "查询短片失败：\(err)", state: .fail))
            } else if let shot = Self.firstScreenshot(r.raw) {
                append(Row(title: "图片链路 · \(p.name)",
                           detail: "原始地址：\(shot)",
                           state: .info))
                let finalURL = Self.rewrite(shot, to: p.url) ?? shot
                let img = await Self.getImage(finalURL, apiKey: p.apiKey, timeout: 10)
                append(img.error == nil
                       ? Row(title: "图片下载 · \(p.name)", detail: img.describeImage(url: finalURL), state: .ok)
                       : Row(title: "图片下载 · \(p.name)",
                             detail: "失败：\(img.error ?? "未知")（\(String(format: "%.1f", img.latency))s）\n地址：\(finalURL)",
                             state: .fail))
            } else {
                append(Row(title: "图片链路 · \(p.name)", detail: "库里没有短片可测，或响应不含截图地址", state: .info))
            }
        }
    }

    private func append(_ r: Row) {
        rows.append(r)
    }

    // MARK: 探测工具

    private struct ProbeOut {
        var status: Int?
        var snippet: String?
        var raw: Data?
        var latency: Double = 0
        var error: String?

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
        var byteCount: Int?
        var contentType: String?
    }

    /// 拼接 GraphQL 端点（与 GraphQLClient 同规则：去尾斜杠、补 /graphql）
    private static nonisolated func endpoint(_ base: String) -> String {
        var s = base.trimmingCharacters(in: .whitespacesAndNewlines)
        if s.hasSuffix("/") { s.removeLast() }
        if !s.hasSuffix("/graphql") { s += "/graphql" }
        return s
    }

    /// 短超时 GraphQL 探测：任何 HTTP 应答（含 401/400）都算可达，body 供解析
    private static nonisolated func gql(_ base: String, apiKey: String, query: String, timeout: Double) async -> ProbeOut {
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
            let (data, resp) = try await URLSession.shared.data(for: req)
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
        } catch {
            return ProbeOut(latency: Date().timeIntervalSince(t0), error: error.localizedDescription)
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
    private static nonisolated func getImage(_ urlString: String, apiKey: String, timeout: Double) async -> ProbeOut {
        guard let url = URL(string: urlString) else {
            return ProbeOut(error: "地址无效")
        }
        var req = URLRequest(url: url)
        req.timeoutInterval = timeout
        if !apiKey.isEmpty { req.setValue(apiKey, forHTTPHeaderField: "ApiKey") }
        let t0 = Date()
        do {
            let (data, resp) = try await URLSession.shared.data(for: req)
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
        } catch {
            return ProbeOut(latency: Date().timeIntervalSince(t0), error: error.localizedDescription)
        }
    }
}
