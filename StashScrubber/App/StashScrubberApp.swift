import SwiftUI

// MARK: - 应用入口（苹果原生外观，自动跟随系统浅色/深色）

@main
struct StashScrubberApp: App {
    // 注意：模块内自定义的 Scene 模型结构体会遮蔽 SwiftUI.Scene 协议，此处须全限定
    @Environment(\.scenePhase) private var scenePhase

    var body: some SwiftUI.Scene {
        WindowGroup {
            RootGate()
                .environmentObject(AppSettings.shared)
                .environmentObject(WiFiAutoSwitch.shared)
                .onChange(of: scenePhase) { phase in
                    if phase == .active {
                        // 回到前台时按 WiFi 规则自动切换内外网档案
                        Task { await WiFiAutoSwitch.shared.checkAndSwitch(settings: .shared) }
                    }
                }
        }
    }
}

// 登录门禁：未完成服务器初始化（API Key 登入）时展示登录页
struct RootGate: View {
    @AppStorage("stash.serverSetupDone") private var serverSetupDone = false

    var body: some View {
        if serverSetupDone {
            RootView()
        } else {
            LoginView()
        }
    }
}

// MARK: - 服务器档案（内网 / 外网多套配置，可一键切换）

struct ServerProfile: Codable, Identifiable, Equatable {
    var id: UUID = UUID()
    var name: String          // 如 "内网 NAS" / "外网域名"
    var url: String           // 如 http://192.168.2.210:9999 或 https://stash.example.com/stash
    var apiKey: String        // Stash 设置 → 安全 → API Key，可留空
}

// MARK: - 根视图：iPhone 用 TabView，iPad 用双栏 SplitView（均为原生组件）

enum AppSection: Hashable {
    case scenes, performers, settings
}

struct RootView: View {
    @Environment(\.horizontalSizeClass) private var hSize

    var body: some View {
        if hSize == .compact {
            TabRootView()
        } else {
            SplitRootView()
        }
    }
}

struct TabRootView: View {
    @State private var selection: AppSection = .scenes

    var body: some View {
        TabView(selection: $selection) {
            ScenesView()
                .tabItem { Label("短片", systemImage: "film") }
                .tag(AppSection.scenes)
            PerformersView()
                .tabItem { Label("演员", systemImage: "person.2") }
                .tag(AppSection.performers)
            SettingsView()
                .tabItem { Label("设置", systemImage: "gearshape") }
                .tag(AppSection.settings)
        }
    }
}

struct SplitRootView: View {
    @State private var selection: AppSection? = .scenes

    var body: some View {
        NavigationSplitView {
            List(selection: $selection) {
                NavigationLink(value: AppSection.scenes) {
                    Label("短片", systemImage: "film")
                }
                NavigationLink(value: AppSection.performers) {
                    Label("演员", systemImage: "person.2")
                }
                NavigationLink(value: AppSection.settings) {
                    Label("设置", systemImage: "gearshape")
                }
            }
            .navigationTitle("Stash 削刮")
            .navigationSplitViewColumnWidth(min: 170, ideal: 200, max: 260)
        } detail: {
            switch selection {
            case .scenes: ScenesView()
            case .performers: PerformersView()
            case .settings: SettingsView()
            case nil:
                EmptyStateView(title: "未选择板块", hint: "从侧边栏选择 短片 / 演员 / 设置")
            }
        }
    }
}

// MARK: - 服务器配置（UserDefaults 持久化，支持多档案切换内外网）

@MainActor
final class AppSettings: ObservableObject {
    static let shared = AppSettings()

    private static let profilesKey = "stash.profiles"
    private static let activeKey = "stash.activeProfileID"

    @Published var profiles: [ServerProfile] {
        didSet { persist() }
    }
    @Published var activeProfileID: UUID? {
        didSet { persist() }
    }

    private init() {
        let d = UserDefaults.standard
        if let data = d.data(forKey: Self.profilesKey),
           let saved = try? JSONDecoder().decode([ServerProfile].self, from: data), !saved.isEmpty {
            profiles = saved
        } else {
            // 首次启动的默认档案：内网直连 + 外网示例
            profiles = [
                ServerProfile(name: "内网 NAS", url: "http://192.168.2.210:9999", apiKey: ""),
                ServerProfile(name: "外网", url: "https://stash.example.com", apiKey: "")
            ]
        }
        activeProfileID = d.object(forKey: Self.activeKey) as? UUID ?? profiles.first?.id
    }

    private func persist() {
        let d = UserDefaults.standard
        if let data = try? JSONEncoder().encode(profiles) {
            d.set(data, forKey: Self.profilesKey)
        }
        d.set(activeProfileID?.uuidString, forKey: Self.activeKey)
    }

    var activeProfile: ServerProfile? {
        profiles.first { $0.id == activeProfileID } ?? profiles.first
    }

    var serverURL: String { activeProfile?.url ?? "" }
    var apiKey: String { activeProfile?.apiKey ?? "" }

    func makeClient() throws -> GraphQLClient {
        guard let p = activeProfile, !p.url.isEmpty else {
            throw StashAPIError.badURL("请先在设置中配置 Stash 服务器地址")
        }
        return try GraphQLClient(baseURL: p.url, apiKey: p.apiKey)
    }

    func updateActive(name: String? = nil, url: String? = nil, apiKey: String? = nil) {
        guard let idx = profiles.firstIndex(where: { $0.id == activeProfileID }) ?? profiles.indices.first else { return }
        if let name { profiles[idx].name = name }
        if let url { profiles[idx].url = url }
        if let apiKey { profiles[idx].apiKey = apiKey }
    }

    /// 首次登录初始化：用登录页填写的内外网地址重建档案（内网默认激活，API Key 两档案通用）
    func applyFirstSetup(lanURL: String, wanURL: String, apiKey: String) {
        let lan = ServerProfile(name: "内网", url: lanURL, apiKey: apiKey)
        let wan = ServerProfile(name: "外网", url: wanURL, apiKey: apiKey)
        profiles = [lan, wan]
        activeProfileID = lan.id
    }

    func addProfile(_ p: ServerProfile) {
        profiles.append(p)
        activeProfileID = p.id
    }

    func deleteProfile(_ p: ServerProfile) {
        profiles.removeAll { $0.id == p.id }
        if activeProfileID == p.id { activeProfileID = profiles.first?.id }
    }

    func switchTo(_ p: ServerProfile) {
        activeProfileID = p.id
    }
}

// MARK: - 服务器快速切换菜单（各列表页工具栏共用）

struct ServerSwitcherMenu: View {
    @EnvironmentObject private var settings: AppSettings

    var body: some View {
        Menu {
            ForEach(settings.profiles) { p in
                Button {
                    settings.switchTo(p)
                } label: {
                    if p.id == settings.activeProfile?.id {
                        Label(p.name, systemImage: "checkmark")
                    } else {
                        Text(p.name)
                    }
                }
            }
        } label: {
            Label(
                settings.activeProfile?.name ?? "未配置",
                systemImage: "server.rack"
            )
        }
    }
}

// MARK: - 设置页

struct SettingsView: View {
    @EnvironmentObject private var settings: AppSettings
    @AppStorage("stash.serverSetupDone") private var serverSetupDone = false
    @State private var testing = false
    @State private var testResult: String?
    @State private var error: String?
    @State private var showAdd = false

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    ForEach(settings.profiles) { p in
                        Button {
                            settings.switchTo(p)
                        } label: {
                            HStack {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(p.name).font(.body).foregroundStyle(.primary)
                                    Text(p.url)
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                        .lineLimit(1)
                                }
                                Spacer()
                                if p.id == settings.activeProfile?.id {
                                    Image(systemName: "checkmark.circle.fill")
                                        .foregroundStyle(Color.accentColor)
                                }
                            }
                        }
                        .swipeActions {
                            Button(role: .destructive) {
                                settings.deleteProfile(p)
                            } label: {
                                Label("删除", systemImage: "trash")
                            }
                        }
                    }
                    Button {
                        showAdd = true
                    } label: {
                        Label("添加服务器档案", systemImage: "plus")
                    }
                } header: {
                    Text("服务器档案（内网 / 外网）")
                } footer: {
                    Text("切换后所有列表与削刮操作立即指向所选档案。外网访问建议使用 HTTPS 反向代理（如 Nginx/Caddy），或经 WireGuard/Tailscale 回家后使用内网地址。")
                }

                Section {
                    TextField("档案名称", text: Binding(
                        get: { settings.activeProfile?.name ?? "" },
                        set: { settings.updateActive(name: $0) }))
                    TextField("服务地址（http:// 或 https://，可含路径前缀）", text: Binding(
                        get: { settings.activeProfile?.url ?? "" },
                        set: { settings.updateActive(url: $0) }))
                        .keyboardType(.URL)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                    SecureField("API Key（可留空）", text: Binding(
                        get: { settings.activeProfile?.apiKey ?? "" },
                        set: { settings.updateActive(apiKey: $0) }))
                } header: {
                    Text("当前档案：\(settings.activeProfile?.name ?? "无")")
                } footer: {
                    Text("GraphQL 端点会自动追加 /graphql。削刮功能要求 Stash 服务端已配置对应刮削器；若服务端启用了 API Key，请务必填写。")
                }

                Section {
                    Button {
                        Task { await testConnection() }
                    } label: {
                        HStack {
                            if testing { ProgressView().padding(.trailing, 6) }
                            Text("测试连接")
                        }
                    }
                    .disabled(testing || (settings.activeProfile?.url.isEmpty ?? true))
                    if let testResult {
                        Label(testResult, systemImage: testResult.contains("成功") ? "checkmark.circle" : "xmark.circle")
                            .font(.subheadline)
                            .foregroundStyle(testResult.contains("成功") ? Color.green : Color.red)
                    }
                } header: {
                    Text("连接")
                }

                Section {
                    NavigationLink {
                        WiFiRulesView()
                    } label: {
                        Label("WiFi 自动切换", systemImage: "wifi")
                    }
                    NavigationLink {
                        DiagnosticsView()
                    } label: {
                        Label("网络诊断", systemImage: "stethoscope")
                    }
                } header: {
                    Text("网络")
                } footer: {
                    Text("按 WiFi 名称（SSID）自动在内网/外网档案间切换，规则支持增删改；回到前台时自动检测。")
                }

                Section {
                    Button(role: .destructive) {
                        serverSetupDone = false
                    } label: {
                        Label("重置服务器配置（返回登录页）", systemImage: "arrow.counterclockwise")
                    }
                } header: {
                    Text("账号")
                } footer: {
                    Text("返回登录页后需重新填写内外网地址与 API Key；登录会实测连接，密钥错误会被直接拦截。")
                }

                Section("说明") {
                    LabeledContent("版本", value: "1.5.13")
                    LabeledContent("适配", value: "iPhone / iPad · iOS 16+")
                }
            }
            .navigationTitle("设置")
            .errorAlert($error)
            .sheet(isPresented: $showAdd) {
                AddProfileSheet { settings.addProfile($0) }
            }
        }
    }

    private func testConnection() async {
        testing = true
        testResult = nil
        defer { testing = false }
        do {
            let client = try settings.makeClient()
            let v = try await StashAPI.version(client)
            testResult = "连接成功 · Stash \(v)"
        } catch {
            self.error = error.localizedDescription
            testResult = "连接失败：\(error.localizedDescription)"
        }
    }
}

struct AddProfileSheet: View {
    var onAdd: (ServerProfile) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var name = ""
    @State private var url = "https://"
    @State private var apiKey = ""

    var body: some View {
        NavigationStack {
            Form {
                TextField("档案名称（如 外网域名 / WireGuard）", text: $name)
                TextField("服务地址", text: $url)
                    .keyboardType(.URL)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                SecureField("API Key（可留空）", text: $apiKey)
            }
            .navigationTitle("添加服务器")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("添加") {
                        onAdd(ServerProfile(
                            name: name.isEmpty ? "服务器 \(settings_profileCountHint())" : name,
                            url: url,
                            apiKey: apiKey
                        ))
                        dismiss()
                    }
                    .disabled(url.isEmpty)
                }
            }
        }
        .presentationDetents([.medium])
    }

    private func settings_profileCountHint() -> Int {
        (UserDefaults.standard.data(forKey: "stash.profiles")
            .flatMap { try? JSONDecoder().decode([ServerProfile].self, from: $0) }?.count ?? 0) + 1
    }
}
