import SwiftUI

// MARK: - 服务器连接 UI（按「飞牛音乐」连接配置模板的结构组织）
//
// 列表行   ：连接名 + 地址类型 + 内外网地址摘要 + 「当前」标记 + 延迟
// 详情页   ：连接信息（类型 / 地址类型 / 内网地址 / 外网地址 / API Key / 最后同步）
//            + 网络设置（地址类型、连接配置、测试当前连接）+ 删除此连接
// 配置页   ：外网地址（主机 + 端口 + HTTPS）、内网地址（主机 + 端口 + HTTPS）、
//            「优先使用内网地址」（内网不可用时自动切换到外网）

// MARK: - 列表行

struct ConnectionRow: View {
    let connection: ServerConnection
    let isActive: Bool
    let activeSlot: AddressSlot
    let latency: LatencyMonitor

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "server.rack")
                .font(.title3)
                .foregroundStyle(Color.accentColor)
                .frame(width: 26)

            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    Text(connection.name)
                        .font(.body)
                        .foregroundStyle(.primary)
                    Text(connection.kind.label)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Capsule().fill(Color.secondary.opacity(0.15)))
                }
                Text(connection.summaryAddress)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                if isActive, case .failed(let msg) = latency.state(for: currentURL) {
                    Text(msg)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }
            }

            Spacer(minLength: 6)

            VStack(alignment: .trailing, spacing: 4) {
                if isActive {
                    Text("当前 · \(activeSlot.label)")
                        .font(.caption2)
                        .foregroundStyle(.green)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Capsule().fill(Color.green.opacity(0.15)))
                }
                LatencyBadge(state: latency.state(for: currentURL))
            }
        }
        .padding(.vertical, 2)
    }

    /// 当前（或优先）地址：生效连接看生效地址，其它连接看优先地址
    private var currentURL: String {
        if isActive { return connection.url(for: activeSlot) ?? "" }
        guard let slot = connection.preferredSlot else { return "" }
        return connection.url(for: slot) ?? ""
    }
}

// MARK: - 连接详情

struct ConnectionDetailView: View {
    let connectionID: UUID

    @EnvironmentObject private var settings: AppSettings
    @Environment(\.dismiss) private var dismiss
    @ObservedObject private var latency = LatencyMonitor.shared
    @State private var confirmDelete = false
    @State private var testing = false
    @State private var testSummary: String?

    private var connection: ServerConnection? { settings.connection(connectionID) }

    var body: some View {
        Form {
            if let c = connection {
                Section {
                    LabeledContent("类型", value: "Stash")
                    LabeledContent("连接名称", value: c.name)
                    LabeledContent("地址类型", value: c.kind.label)
                    LabeledContent("内网地址") {
                        HStack(spacing: 8) {
                            Text(c.displayURL(for: .lan) ?? "未配置")
                                .foregroundStyle(c.hasLAN ? Color.primary : Color.secondary)
                            if c.hasLAN { LatencyBadge(state: latency.state(for: c.lanURL ?? "")) }
                        }
                    }
                    LabeledContent("外网地址") {
                        HStack(spacing: 8) {
                            Text(c.displayURL(for: .wan) ?? "未配置")
                                .foregroundStyle(c.hasWAN ? Color.primary : Color.secondary)
                            if c.hasWAN { LatencyBadge(state: latency.state(for: c.wanURL ?? "")) }
                        }
                    }
                    LabeledContent("访问码", value: c.hasAPIKey ? "已设置" : "未设置")
                    LabeledContent("最后同步", value: c.lastSyncText)
                } header: {
                    Text("连接信息")
                }

                Section {
                    LabeledContent("当前生效") {
                        HStack(spacing: 8) {
                            Text(settings.activeConnection?.id == c.id
                                 ? "\(settings.activeSlot.label) · \(settings.activeAddress)"
                                 : "非当前连接")
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                            if settings.activeConnection?.id == c.id {
                                LatencyBadge(state: latency.state(for: settings.activeAddress))
                            }
                        }
                    }
                    if settings.isSlotPinned, settings.activeConnection?.id == c.id {
                        Button {
                            settings.clearPin()
                        } label: {
                            Label("已锁定\(settings.activeSlot.label)地址 · 点此恢复自动选择",
                                  systemImage: "arrow.triangle.2.circlepath")
                        }
                    }
                    if let r = settings.lastSwitchReason,
                       settings.activeConnection?.id == c.id {
                        Text(r)
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                } header: {
                    Text("生效地址")
                } footer: {
                    Text("「优先使用内网地址」开启时，App 在启动 / 回到前台时实测内网地址，不可达会自动切到外网；无需手动切换。")
                }

                Section {
                    Picker("地址类型", selection: kindBinding(c)) {
                        ForEach(AddressKind.allCases) { k in
                            Text(k.label).tag(k)
                        }
                    }
                    NavigationLink(value: SettingsRoute.connectionConfig(c.id)) {
                        Label("连接配置", systemImage: "slider.horizontal.3")
                    }
                    TextField("连接名称", text: nameBinding(c))

                    LabeledContent("使用哪些地址") {
                        Text(c.summaryAddress)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.trailing)
                    }
                } header: {
                    Text("网络设置")
                } footer: {
                    Text("在「连接配置」中填写内外网地址与端口。地址类型只会影响可选范围，不会删除已填地址。")
                }

                Section {
                    Button {
                        Task { await runTest(c) }
                    } label: {
                        HStack {
                            if testing { ProgressView().padding(.trailing, 6) }
                            Label("测试当前连接", systemImage: "bolt.horizontal.circle")
                        }
                    }
                    .disabled(testing || c.availableSlots.isEmpty)
                    if let testSummary {
                        Text(testSummary)
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                            .textSelection(.enabled)
                    }
                } header: {
                    Text("连接")
                } footer: {
                    Text("对已配置的每个地址各发一次最小 GraphQL 查询，测完按「优先使用内网地址」重新选路。")
                }

                Section {
                    Button(role: .destructive) {
                        confirmDelete = true
                    } label: {
                        Label("删除此连接", systemImage: "trash")
                    }
                }
            } else {
                Section {
                    Text("该连接已被删除")
                        .foregroundStyle(.secondary)
                }
            }
        }
        .navigationTitle(connection?.name ?? "连接")
        .navigationBarTitleDisplayMode(.inline)
        .task {
            latency.probeConnections(settings.connections)
        }
        .confirmationDialog("删除此连接？", isPresented: $confirmDelete, titleVisibility: .visible) {
            Button("删除", role: .destructive) {
                if let c = connection {
                    settings.deleteConnection(c)
                    dismiss()
                }
            }
            Button("取消", role: .cancel) {}
        } message: {
            Text("仅删除本机保存的连接配置，不影响 NAS 上的 Stash 服务。")
        }
    }

    /// 对已配置的每个地址各测一次，并把结论汇总成可复制的多行文本
    private func runTest(_ c: ServerConnection) async {
        testing = true
        testSummary = nil
        defer { testing = false }

        var lines: [String] = []
        var any = false
        for slot in c.availableSlots {
            guard let url = c.url(for: slot) else { continue }
            let st = await LatencyMonitor.shared.measure(url: url, apiKey: c.apiKey,
                                                         name: "\(c.name) · \(slot.label)",
                                                         force: true)
            if st.isReachable {
                any = true
                lines.append("\(slot.label) · \(c.displayURL(for: slot) ?? "-") · \(st.text)"
                             + (st.detail.map { " · " + $0 } ?? ""))
            } else {
                lines.append("\(slot.label) · \(c.displayURL(for: slot) ?? "-") · 失败："
                             + (st.detail ?? "未知错误"))
            }
        }
        if any {
            settings.markSynced()
            await settings.autoSelectSlot(force: false)
        }
        let isActive = settings.activeConnection?.id == c.id
        lines.append(isActive
                     ? "当前使用：\(settings.activeSlot.label)地址"
                     : "（该连接当前未生效）")
        testSummary = lines.joined(separator: "\n")
    }

    private func kindBinding(_ c: ServerConnection) -> Binding<AddressKind> {
        Binding(get: { settings.connection(connectionID)?.kind ?? c.kind },
                set: { v in
                    settings.mutate(connectionID) { $0.kind = v }
                    Task { await settings.autoSelectSlot(force: true) }
                })
    }

    private func nameBinding(_ c: ServerConnection) -> Binding<String> {
        Binding(get: { settings.connection(connectionID)?.name ?? c.name },
                set: { v in settings.mutate(connectionID) { $0.name = v } })
    }
}

// MARK: - 连接配置（内外网地址 + 优先内网）

struct ConnectionConfigView: View {
    let connectionID: UUID

    @EnvironmentObject private var settings: AppSettings
    @ObservedObject private var latency = LatencyMonitor.shared
    @State private var testing = false
    @State private var results: [String: LatencyState] = [:]

    private var connection: ServerConnection? { settings.connection(connectionID) }

    var body: some View {
        Form {
            if let c = connection {
                Section {
                    hostRow(.wan)
                    Toggle("HTTPS", isOn: httpsBinding(.wan))
                } header: {
                    Text("外网地址（远程访问）")
                } footer: {
                    Text(composedText(c.wanURL, fallback: "在外网（蜂窝 / 异地 WiFi）访问用地址。建议配 HTTPS 反向代理；留空表示不使用外网地址。"))
                }

                Section {
                    hostRow(.lan)
                    Toggle("HTTPS", isOn: httpsBinding(.lan))
                } header: {
                    Text("内网地址（局域网直连）")
                } footer: {
                    Text(composedText(c.lanURL, fallback: "在家里的 Wi-Fi 下直连 NAS 用地址，如 192.168.2.210:9999；内网通常不需要 HTTPS。留空表示不使用内网地址。"))
                }

                Section {
                    Toggle("优先使用内网地址", isOn: preferBinding(c))
                        .disabled(c.kind != .both)
                } header: {
                    Text("选路")
                } footer: {
                    Text(c.kind == .both
                         ? "内网不可用时自动切换到外网。关闭则固定走外网地址（在家也走外网，通常更慢）。"
                         : "当前地址类型为「\(c.kind.label)」，仅一侧可用；改为「内外网都有」后此开关才会生效。")
                }

                Section {
                    SecureField("API Key", text: apiKeyBinding(c))
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                } header: {
                    Text("认证")
                } footer: {
                    Text("即「访问码」，来自 Stash 的 设置 → 安全 → API Key；服务端未启用时可留空。内外网地址共用同一把密钥。")
                }

                Section {
                    Button {
                        Task { await runTest() }
                    } label: {
                        HStack {
                            if testing { ProgressView().padding(.trailing, 6) }
                            Text("测试当前连接")
                        }
                    }
                    .disabled(testing || c.availableSlots.isEmpty)

                    ForEach(c.availableSlots, id: \.self) { slot in
                        if let st = results[slot.rawValue] {
                            HStack(alignment: .top, spacing: 10) {
                                Image(systemName: st.isReachable ? "checkmark.circle.fill" : "xmark.circle.fill")
                                    .foregroundStyle(st.isReachable ? Color.green : Color.red)
                                    .frame(width: 20)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text("\(slot.label) · \(c.displayURL(for: slot) ?? "-")")
                                        .font(.subheadline)
                                    Text(st.isReachable
                                         ? st.text + (st.detail.map { " · " + $0 } ?? "")
                                         : "失败：" + (st.detail ?? "未知错误"))
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                            }
                        }
                    }

                    if let r = settings.lastSwitchReason {
                        Text("当前使用：\(settings.activeSlot.label)地址 · \(r)")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                } header: {
                    Text("连接")
                } footer: {
                    Text("测试会对已填写的地址各发一次最小 GraphQL 查询（Version），顺带刷新延迟；内网不可达时按「优先使用内网地址」自动改走外网。")
                }
            } else {
                Section { Text("该连接已被删除").foregroundStyle(.secondary) }
            }
        }
        .navigationTitle("连接配置")
        .navigationBarTitleDisplayMode(.inline)
        .task { latency.probeConnections(settings.connections) }
    }

    // MARK: 字段行

    private func hostRow(_ slot: AddressSlot) -> some View {
        HStack(spacing: 10) {
            TextField(slot == .lan ? "192.168.2.210" : "nas.example.com", text: hostBinding(slot))
                .keyboardType(.URL)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
            Divider().frame(height: 22)
            TextField("端口", text: portBinding(slot))
                .keyboardType(.numberPad)
                .multilineTextAlignment(.trailing)
                .frame(width: 62)
        }
    }

    private func composedText(_ url: String?, fallback: String) -> String {
        guard let url else { return fallback }
        return "当前：\(url)"
    }

    // MARK: 绑定

    private func hostBinding(_ slot: AddressSlot) -> Binding<String> {
        let kp: WritableKeyPath<ServerConnection, String> = slot == .lan ? \.lanHost : \.wanHost
        return Binding(get: { settings.connection(connectionID)?[keyPath: kp] ?? "" },
                       set: { v in settings.mutate(connectionID) { $0[keyPath: kp] = v } })
    }

    private func portBinding(_ slot: AddressSlot) -> Binding<String> {
        let kp: WritableKeyPath<ServerConnection, String> = slot == .lan ? \.lanPort : \.wanPort
        return Binding(get: { settings.connection(connectionID)?[keyPath: kp] ?? "" },
                       set: { v in
                           let digits = v.filter { $0.isNumber }
                           settings.mutate(connectionID) { $0[keyPath: kp] = digits }
                       })
    }

    private func httpsBinding(_ slot: AddressSlot) -> Binding<Bool> {
        let kp: WritableKeyPath<ServerConnection, Bool> = slot == .lan ? \.lanHTTPS : \.wanHTTPS
        return Binding(get: { settings.connection(connectionID)?[keyPath: kp] ?? false },
                       set: { v in settings.mutate(connectionID) { $0[keyPath: kp] = v } })
    }

    private func apiKeyBinding(_ c: ServerConnection) -> Binding<String> {
        Binding(get: { settings.connection(connectionID)?.apiKey ?? c.apiKey },
                set: { v in settings.mutate(connectionID) { $0.apiKey = v } })
    }

    private func preferBinding(_ c: ServerConnection) -> Binding<Bool> {
        Binding(get: { settings.connection(connectionID)?.preferLAN ?? c.preferLAN },
                set: { v in
                    settings.mutate(connectionID) { $0.preferLAN = v }
                    Task { await settings.autoSelectSlot(force: true) }
                })
    }

    // MARK: 测试

    private func runTest() async {
        guard let c = connection else { return }
        testing = true
        defer { testing = false }
        var any = false
        for slot in c.availableSlots {
            guard let url = c.url(for: slot) else { continue }
            let st = await LatencyMonitor.shared.measure(url: url, apiKey: c.apiKey,
                                                         name: "\(c.name) · \(slot.label)",
                                                         force: true)
            results[slot.rawValue] = st
            if st.isReachable { any = true }
        }
        if any { settings.markSynced() }
        // 测完按「优先内网」重新选路（内网刚失败 → 立即改走外网）
        await settings.autoSelectSlot(force: false)
    }
}

// MARK: - 添加连接

struct AddConnectionSheet: View {
    var defaultAPIKey: String = ""
    var onAdd: (ServerConnection) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var draft = ServerConnection(name: "Stash 服务器", kind: .both,
                                                lanHTTPS: false, wanHTTPS: true,
                                                preferLAN: true)

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("连接名称", text: $draft.name)
                    Picker("地址类型", selection: $draft.kind) {
                        ForEach(AddressKind.allCases) { k in
                            Text(k.label).tag(k)
                        }
                    }
                } header: {
                    Text("连接")
                } footer: {
                    Text("「内外网都有」时可开启优先内网并自动兜底，推荐用于 NAS 这类既能内网直连、又能外网反代的场景。")
                }

                Section {
                    HStack(spacing: 10) {
                        TextField("nas.example.com", text: $draft.wanHost)
                            .keyboardType(.URL)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                        Divider().frame(height: 22)
                        TextField("端口", text: $draft.wanPort)
                            .keyboardType(.numberPad)
                            .multilineTextAlignment(.trailing)
                            .frame(width: 62)
                    }
                    Toggle("HTTPS", isOn: $draft.wanHTTPS)
                } header: {
                    Text("外网地址（远程访问）")
                }

                Section {
                    HStack(spacing: 10) {
                        TextField("192.168.2.210", text: $draft.lanHost)
                            .keyboardType(.URL)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                        Divider().frame(height: 22)
                        TextField("端口", text: $draft.lanPort)
                            .keyboardType(.numberPad)
                            .multilineTextAlignment(.trailing)
                            .frame(width: 62)
                    }
                    Toggle("HTTPS", isOn: $draft.lanHTTPS)
                } header: {
                    Text("内网地址（局域网直连）")
                }

                Section {
                    Toggle("优先使用内网地址", isOn: $draft.preferLAN)
                        .disabled(draft.kind != .both)
                } header: {
                    Text("选路")
                } footer: {
                    Text("内网不可用时自动切换到外网。")
                }

                Section {
                    SecureField("API Key（可留空）", text: $draft.apiKey)
                } header: {
                    Text("认证")
                }
            }
            .navigationTitle("添加连接")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("添加") {
                        var c = draft
                        c.name = c.name.trimmingCharacters(in: .whitespaces)
                        if c.name.isEmpty { c.name = "Stash 服务器" }
                        c.apiKey = c.apiKey.trimmingCharacters(in: .whitespaces)
                        c.lanHost = c.lanHost.trimmingCharacters(in: .whitespaces)
                        c.wanHost = c.wanHost.trimmingCharacters(in: .whitespaces)
                        // 选了「内外网都有」却只填了一侧时自动收敛，避免出现空的一侧
                        if c.kind == .both {
                            if !c.hasLAN { c.kind = .wan }
                            else if !c.hasWAN { c.kind = .lan }
                        }
                        onAdd(c)
                        dismiss()
                    }
                    .disabled(!canAdd)
                }
            }
            .onAppear {
                if draft.apiKey.isEmpty { draft.apiKey = defaultAPIKey }
            }
        }
    }

    private func trimmed(_ s: String) -> String {
        s.trimmingCharacters(in: .whitespaces)
    }

    private var canAdd: Bool {
        guard !trimmed(draft.name).isEmpty else { return false }
        switch draft.kind {
        case .both:
            return !trimmed(draft.lanHost).isEmpty || !trimmed(draft.wanHost).isEmpty
        case .lan:
            return !trimmed(draft.lanHost).isEmpty
        case .wan:
            return !trimmed(draft.wanHost).isEmpty
        }
    }
}
