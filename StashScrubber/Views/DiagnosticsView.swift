import SwiftUI

// MARK: - 网络诊断：一键定位「转圈 / 连不上」问题的真实链路状态
// 检测项：
//  1. 所有档案的 GraphQL 可达性（并发探测，报告延迟 / HTTP 状态 / Stash 版本或错误）
//  2. 当前档案的图片链路（取一张短片截图，报告 HTTP 状态 / 字节数 / Content-Type）
//  3. 系统代理对比：同请求绕过系统代理直连，区分「代理吊死」与「本地网络权限」
//  4. WiFi 自动切换的最近状态（SSID / 动作）
// 探测实现统一来自 NetProbe（NetworkCore.swift），每个探测外挂硬超时：
// 到点强制取消任务，诊断页绝不整体吊死。所有结果同时写入网络日志。

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
                Text("逐项检测所有档案的 GraphQL 可达性、图片链路与系统代理干扰；检测结果同时记录到网络日志，可一键复制反馈。")
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

                NavigationLink {
                    NetLogView()
                } label: {
                    Label("查看网络日志（可复制）", systemImage: "doc.text.magnifyingglass")
                }
            }
        }
        .navigationTitle("网络诊断")
        .navigationBarTitleDisplayMode(.inline)
        .task { await runAll() }
    }

    // MARK: 检测流程（全部并发；每个探测由 NetProbe 外挂硬超时兜底）

    private func runAll() async {
        guard !running else { return }
        running = true
        rows = []
        defer { running = false }

        let results = await withTaskGroup(of: [Row].self, returning: [Row].self) { group in
            for p in settings.profiles {
                group.addTask {
                    let isLAN = StashEndpoint.isLAN(p.url)
                    let r = await Self.probeGraphQL(p)
                    var row = Self.row(for: r, title: "GraphQL · \(p.name)", isLAN: isLAN)
                    // 系统代理对比：仅对失败档案做绕过代理的直连复测
                    if r.error != nil {
                        let d = await Self.probeGraphQL(p, direct: true)
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

    // MARK: 探测（统一走 NetProbe）

    private static func probeGraphQL(_ p: ServerProfile, direct: Bool = false) async -> NetProbe.Result {
        let title = "GraphQL 探测 · \(p.name)" + (direct ? "（直连对比）" : "")
        let session = direct ? NetTransport.direct : NetTransport.api
        return await NetProbe.hardTimeout(8, category: .diag, title: title,
                                          url: StashEndpoint.graphqlURL(p.url)?.absoluteString) {
            await NetProbe.graphql(base: p.url, apiKey: p.apiKey,
                                   query: "{ version { version } }", timeout: 6,
                                   session: session, category: .diag, title: title)
        }
    }

    private static func imageProbe(profile p: ServerProfile) async -> [Row] {
        let q = #"query { findScenes(filter: {per_page: 1}) { scenes { paths { screenshot } } } }"#
        let title = "图片链路 · \(p.name)"
        let r = await NetProbe.hardTimeout(8, category: .diag, title: title,
                                           url: StashEndpoint.graphqlURL(p.url)?.absoluteString) {
            await NetProbe.graphql(base: p.url, apiKey: p.apiKey, query: q, timeout: 6,
                                   category: .diag, title: title)
        }
        if let err = r.error {
            return [Row(title: title, detail: "查询短片失败：\(err)", state: .fail)]
        }
        guard let shot = NetProbe.firstScreenshot(r.raw) else {
            return [Row(title: title, detail: "库里没有短片可测，或响应不含截图地址", state: .info)]
        }
        var out: [Row] = [Row(title: title, detail: "原始地址：\(shot)", state: .info)]
        guard let finalURL = finalImageURL(shot, base: p.url) else {
            out.append(Row(title: "图片下载 · \(p.name)", detail: "图片地址无效：\(shot)", state: .fail))
            return out
        }
        let img = await NetProbe.hardTimeout(12, category: .diag, title: "图片下载 · \(p.name)", url: finalURL) {
            await NetProbe.image(urlString: finalURL, apiKey: p.apiKey, timeout: 10,
                                 category: .diag, title: "图片下载 · \(p.name)")
        }
        let t = "图片下载 · \(p.name)"
        if let err = img.error {
            let d = await NetProbe.hardTimeout(12, category: .diag, title: t + "（直连对比）", url: finalURL) {
                await NetProbe.image(urlString: finalURL, apiKey: p.apiKey, timeout: 10,
                                     session: NetTransport.direct, category: .diag,
                                     title: t + "（直连对比）")
            }
            if let derr = d.error {
                out.append(Row(title: t, detail: "失败：\(err)（\(String(format: "%.1f", img.latency))s）\n直连也失败：\(derr)\n地址：\(finalURL)", state: .fail))
            } else {
                out.append(Row(title: t, detail: "常规会话失败：\(err)\n⚠️ 直连成功：\(d.describeImage(url: finalURL))\n→ 系统代理干扰，检查 Wi-Fi 的 HTTP 代理设置\n地址：\(finalURL)", state: .warn))
            }
        } else {
            out.append(Row(title: t, detail: img.describeImage(url: finalURL), state: .ok))
        }
        return out
    }

    private static func finalImageURL(_ raw: String, base: String) -> String? {
        StashEndpoint.rewriteImage(raw, base: base)?.absoluteString
    }

    // MARK: 结果映射

    private static func row(for r: NetProbe.Result, title: String, isLAN: Bool) -> Row {
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
    private static func withDirectCompare(primary: Row, direct: NetProbe.Result, isLAN: Bool) -> Row {
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
}
