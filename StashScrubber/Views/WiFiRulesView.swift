import SwiftUI

// MARK: - WiFi 自动切换规则管理（SSID → 服务器档案）

struct WiFiRulesView: View {
    @EnvironmentObject private var settings: AppSettings
    @EnvironmentObject private var wifi: WiFiAutoSwitch
    @State private var showAdd = false
    @State private var editingRule: SSIDRule?

    var body: some View {
        Form {
            Section {
                Toggle("启用自动切换", isOn: $wifi.enabled)
                HStack {
                    Text("当前 WiFi")
                    Spacer()
                    Text(wifi.lastSSID ?? "获取失败 / 不在 WiFi 下")
                        .foregroundStyle(.secondary)
                }
                Button {
                    wifi.checkAndSwitch(settings: settings)
                } label: {
                    Label("立即检测并切换", systemImage: "dot.radiowaves.left.and.right")
                }
                if let a = wifi.lastAction {
                    Text(a)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            } header: {
                Text("自动切换")
            } footer: {
                Text("回到前台或点击「立即检测」时，按当前 WiFi 名称匹配规则切换服务器档案。SSID 获取依赖定位权限（设置 → 隐私与安全性 → 定位服务 → 本 App → 使用 App 期间）。")
            }

            Section("SSID 规则（WiFi → 服务器档案）") {
                if wifi.rules.isEmpty {
                    Text("暂无规则，点击右上角添加")
                        .foregroundStyle(.secondary)
                }
                ForEach(wifi.rules) { rule in
                    Button { editingRule = rule } label: {
                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(rule.ssid).foregroundStyle(.primary)
                                Text("→ \(settings.profiles.first { $0.id == rule.profileID }?.name ?? "已删除的档案")")
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
}

// MARK: - 规则编辑器（新增 / 编辑共用）

struct RuleEditor: View {
    let existing: SSIDRule?
    var onSave: (SSIDRule) -> Void

    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var settings: AppSettings
    @State private var ssid = ""
    @State private var profileID = ""

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("WiFi 名称（SSID），如 Home-5G", text: $ssid)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                    Button {
                        if let s = WiFiAutoSwitch.currentSSID() { ssid = s }
                    } label: {
                        Label("填入当前 WiFi", systemImage: "wifi")
                    }
                } header: {
                    Text("匹配 WiFi 名称（SSID）")
                }

                Section("切换到档案") {
                    Picker("档案", selection: $profileID) {
                        Text("请选择").tag("")
                        ForEach(settings.profiles) { p in
                            Text(p.name).tag(p.id.uuidString)
                        }
                    }
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
                            profileID: UUID(uuidString: profileID) ?? UUID()
                        ))
                        dismiss()
                    }
                    .disabled(ssid.isEmpty || UUID(uuidString: profileID) == nil)
                }
            }
            .task {
                if let existing {
                    ssid = existing.ssid
                    profileID = existing.profileID.uuidString
                } else if profileID.isEmpty {
                    profileID = settings.activeProfile?.id.uuidString
                        ?? settings.profiles.first?.id.uuidString ?? ""
                }
            }
        }
        .presentationDetents([.medium])
    }
}
