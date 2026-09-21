import SwiftUI

// MARK: - WiFi 自动切换规则管理（SSID → 连接 / 内网·外网地址）
//
// 默认「内外网切换」由 App 自动完成（优先内网、不可达自动切外网）；
// 本页用于按 WiFi 名称主动覆盖该策略，例如在家锁内网、连公司 WiFi 锁外网。

struct WiFiRulesView: View {
    @EnvironmentObject private var settings: AppSettings
    @EnvironmentObject private var wifi: WiFiAutoSwitch
    @State private var showAdd = false
    @State private var editingRule: SSIDRule?

    var body: some View {
        Form {
            Section {
                Toggle("启用规则", isOn: $wifi.enabled)
                HStack {
                    Text("当前 WiFi")
                    Spacer()
                    Text(wifi.lastSSID ?? "获取失败 / 不在 WiFi 下")
                        .foregroundStyle(.secondary)
                }
                LabeledContent("当前地址") {
                    Text("\(settings.activeSlot.label) · \(settings.activeConnection?.name ?? "-")\(settings.isSlotPinned ? "（规则锁定）" : "")")
                        .foregroundStyle(.secondary)
                }
                Button {
                    Task { await wifi.checkAndSwitch(settings: settings) }
                } label: {
                    Label("立即检测并应用规则", systemImage: "dot.radiowaves.left.and.right")
                }
                if let a = wifi.lastAction {
                    Text(a)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            } header: {
                Text("自动切换")
            } footer: {
                Text("回到前台或点击「立即检测」时，按当前 WiFi 名称匹配规则。未配置规则的 WiFi 保持「优先内网、不可达自动切外网」。SSID 获取依赖定位权限（设置 → 隐私与安全性 → 定位服务 → 本 App → 使用 App 期间）。")
            }

            Section {
                if wifi.rules.isEmpty {
                    Text("暂无规则，点右上角添加")
                        .foregroundStyle(.secondary)
                }
                ForEach(wifi.rules) { rule in
                    Button { editingRule = rule } label: {
                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(rule.ssid).foregroundStyle(.primary)
                                Text(targetText(rule))
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            Spacer()
                            Image(systemName: "chevron.right")
                                .font(.caption)
                                .foregroundStyle(.tertiary)
                        }
                    }
                    .swipeActions {
                        Button(role: .destructive) {
                            wifi.rules.removeAll { $0.id == rule.id }
                        } label: {
                            Label("删除", systemImage: "trash")
                        }
                    }
                }
            } header: {
                Text("SSID 规则")
            } footer: {
                Text("「锁定内网 / 外网」会在匹配到该 WiFi 时固定使用对应地址；选「自动」则仅切换连接，地址仍由「优先内网」策略决定。锁定前会先探测可达性，避免蜂窝网络下误判 WiFi 名称。")
            }
        }
        .navigationTitle("WiFi 自动切换")
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button { showAdd = true } label: {
                    Label("添加规则", systemImage: "plus")
                }
            }
        }
        .sheet(isPresented: $showAdd) {
            RuleEditor(existing: nil) { wifi.rules.append($0) }
        }
        .sheet(item: $editingRule) { rule in
            RuleEditor(existing: rule) { updated in
                if let idx = wifi.rules.firstIndex(where: { $0.id == updated.id }) {
                    wifi.rules[idx] = updated
                }
            }
        }
    }

    private func targetText(_ rule: SSIDRule) -> String {
        let name = settings.connections.first { $0.id == rule.profileID }?.name ?? "已删除的连接"
        if let slot = rule.slot { return "→ \(name) · 锁定\(slot.label)地址" }
        return "→ \(name) · 自动选路"
    }
}

// MARK: - 规则编辑器（新增 / 编辑共用）

struct RuleEditor: View {
    let existing: SSIDRule?
    var onSave: (SSIDRule) -> Void

    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var settings: AppSettings
    @State private var ssid = ""
    @State private var connectionID = ""
    /// "" = 自动；"lan" / "wan" = 锁定该侧
    @State private var slotChoice = ""

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("WiFi 名称（SSID），如 Home-5G", text: $ssid)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                    Button {
                        Task { @MainActor in
                            if let s = await WiFiAutoSwitch.fetchCurrentSSID() { ssid = s }
                        }
                    } label: {
                        Label("填入当前 WiFi", systemImage: "wifi")
                    }
                } header: {
                    Text("匹配 WiFi 名称（SSID）")
                }

                Section {
                    Picker("连接", selection: $connectionID) {
                        Text("请选择").tag("")
                        ForEach(settings.connections) { c in
                            Text(c.name).tag(c.id.uuidString)
                        }
                    }
                    Picker("地址", selection: $slotChoice) {
                        Text("自动（优先内网）").tag("")
                        Text("锁定内网地址").tag(AddressSlot.lan.rawValue)
                        Text("锁定外网地址").tag(AddressSlot.wan.rawValue)
                    }
                } header: {
                    Text("匹配后")
                } footer: {
                    Text("选择「自动」时该规则只切连接；锁定某侧地址会在探测可达后固定使用该地址，直到匹配到其它规则或手动恢复自动选择。")
                }
            }
            .navigationTitle(existing == nil ? "添加规则" : "编辑规则")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(existing == nil ? "添加" : "保存") {
                        onSave(SSIDRule(
                            id: existing?.id ?? UUID(),
                            ssid: ssid.trimmingCharacters(in: .whitespaces),
                            profileID: UUID(uuidString: connectionID) ?? UUID(),
                            slot: AddressSlot(rawValue: slotChoice)
                        ))
                        dismiss()
                    }
                    .disabled(ssid.isEmpty || UUID(uuidString: connectionID) == nil)
                }
            }
            .task {
                if let existing {
                    ssid = existing.ssid
                    connectionID = existing.profileID.uuidString
                    slotChoice = existing.slot?.rawValue ?? ""
                } else if connectionID.isEmpty {
                    connectionID = settings.activeConnection?.id.uuidString
                        ?? settings.connections.first?.id.uuidString ?? ""
                }
            }
        }
        .presentationDetents([.medium])
    }
}
