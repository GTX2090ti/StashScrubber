import SwiftUI

// MARK: - 网络诊断：一键定位「转圈 / 连不上」问题的真实链路状态
// 检测项：
//  1. 所有连接的可用地址（内网 / 外网）GraphQL 可达性（并发探测，报告延迟 / HTTP 状态 / Stash 版本或错误）
//  2. 当前生效地址的图片链路（取一张短片截图，报告 HTTP 状态 / 字节数 / Content-Type）
//  3. 系统代理对比：同请求绕过系统代理直连，区分「代理吊死」与「本地网络权限」
//  4. 地址选路状态（当前生效地址 / 是否被 WiFi 规则锁定 / 最近一次选路结论）
// 探测实现统一来自 NetProbe（NetworkCore.swift），每个探测外挂硬超时：
// 到点强制取消任务，诊断页绝不整体吊死。所有结果同时写入网络日志。

// 探测目标：放文件作用域（非 @MainActor 隔离），供 TaskGroup 并发使用
private struct Target: Sendable {
    let title: String
    let url: String
    let apiKey: String
    let isLAN: Bool
}

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
                if let c = settings.activeConnection {
                    LabeledContent("连接", value: c.name)
                    LabeledContent("地址类型", value: c.kind.label)
                    LabeledContent("当前生效") {
                        Text("\(settings.activeSlot.label) · \(settings.activeAddress)")
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                    LabeledContent("内网地址", value: c.displayURL(for: .lan) ?? "未配置")
                    LabeledContent("外网地址", value: c.displayURL(for: .wan) ?? "未配置")
                    LabeledContent("API Key", value: c.hasAPIKey ? "已设置" : "未设置")
                } else {
                    Text("未配置连接").foregroundStyle(.secondary)
                }
            } header: {
                Text("当前连接")
            } footer: {
                Text("逐项检测每条连接的可用地址（内网 / 外网）与当前生效地址的图片链路；检测结果同时记录到网络日志，可一键复制反馈。")
            }

            Section {
                LabeledContent("选路方式", value: settings.isSlotPinned
                               ? "已锁定「\(settings.activeSlot.label)地址」"
                               : "自动（优先内网，不可达切外网）")
                if let r = settings.lastSwitchReason {
                    Text(r)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
                if settings.isSlotPinned {
                    Button("恢复自动选择") { settings.clearPin() }
                }
                Button("立即重新选路（测速）") {
                    Task { await settings.autoSelectSlot(force: true) }
                }
            } header: {
                Text("地址选路")
            } footer: {
                Text("「优先使用内网地址」在启动 / 回到前台时实测内网地址，不可达则自动切到外网；被 WiFi 规则锁定后不再自动兜底。")
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
                LabeledContent("规则开关", value: WiFiAutoSwitch.shared.enabled ? "开启" : "关闭")
                LabeledContent("规则数", value: "\(WiFiAutoSwitch.shared.rules.count)")
                LabeledContent("最近检测 SSID", value: WiFiAutoSwitch.shared.lastSSID ?? "无")
                LabeledContent("最近动作", value: WiFiAutoSwitch.shared.lastAction ?? "无")
            } header: {
                Text("WiFi 规则状态")
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

                NavigationLink(value: SettingsRoute.netLog) {
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

        // 快照所有连接的可用地址
        var targets: [Target] = []
        for c in settings.connections {
            for slot in c.availableSlots {
                guard let u = c.url(for: slot) else { continue }
                targets.append(Target(title: "\(c.name) · \(slot.label)", url: u,
                                      apiKey: c.apiKey, isLAN: slot == .lan))
            }
        }
        let activeProfile = settings.activeProfile

        let results = await withTaskGroup(of: [Row].self, returning: [Row].self) { group in
            for t in targets {
                group.addTask {
                    let r = await Self.probeGraphQL(t)
                    var row = await Self.row(for: r, title: "GraphQL · \(t.title)", isLAN: t.isLAN)
                    // 系统代理对比：仅对失败地址做绕过代理的直连复测
                    if r.error != nil {
                        let d = await Self.probeGraphQL(t, direct: true)
                        row = await Self.withDirectCompare(primary: row, direct: d, isLAN: t.isLAN)
                    }
                    return [row]
                }
            }

            // 当前生效地址的图片链路 + 直连对比
            if let p = activeProfile {
                group.addTask { await Self.imageProbe(profile: p) }
            }

            var out: [Row] = []
            for await rs in group { out.append(contentsOf: rs) }
            return out
        }
        rows = results
    }

    // MARK: 探测（统一走 NetProbe）

    private static func probeGraphQL(_ t: Target, direct: Bool = false) async -> NetProbe.Result {
        let title = "GraphQL 探测 · \(t.title)" + (direct ? "（直连对比）" : "")
        let session = direct ? NetTransport.direct : NetTransport.probe
        return await NetProbe.hardTimeout(8, category: .diag, title: title,
                                          url: StashEndpoint.graphqlURL(t.url)?.absoluteString,
                                          onTimeout: direct ? nil : {
                                              NetTransport.resetProbe(reason: "诊断探测硬超时（\(t.title)），重建探测会话")
                                          }) {
            await NetProbe.graphql(base: t.url, apiKey: t.apiKey,
                                   query: "{ version { version } }", timeout: 6,
                                   session: session, category: .diag, title: title)
        }
    }

    private static func imageProbe(profile p: ServerProfile) async -> [Row] {
        let q = #"query { findScenes(filter: {per_page: 1}) { scenes { paths { screenshot } } } }"#
        let title = "图片链路 · \(p.name)"
        let r = await NetProbe.hardTimeout(8, category: .diag, title: title,
                                           url: StashEndpoint.graphqlURL(p.url)?.absoluteString,
                                           onTimeout: {
                                               NetTransport.resetProbe(reason: "诊断图片链路探测硬超时（\(p.name)），重建探测会话")
                                           }) {
            await NetProbe.graphql(base: p.url, apiKey: p.apiKey, query: q, timeout: 6,
                                   session: NetTransport.probe,
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
        let img = await NetProbe.hardTimeout(12, category: .diag, title: "图片下载 · \(p.name)", url: finalURL,
                                             onTimeout: {
                                                 NetTransport.resetImage(reason: "诊断图片下载硬超时（\(p.name)），重建图片会话")
                                             }) {
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
                detail += "\n提示：内网地址——若长时间无响应，检查 设置→隐私与安全性→本地网络 是否允许本 App；或该 Wi-Fi 下内网不可达（App 会自动改走外网）"
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
