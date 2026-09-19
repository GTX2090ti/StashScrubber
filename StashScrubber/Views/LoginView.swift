import SwiftUI

// MARK: - 登录（API Key 即登录凭据，无账号密码）
//
// 首次使用必须填写：内网地址、外网地址、API Key（Stash 设置 → 安全 → API Key）。
// 点「登录」会对两个地址各做一次真实连接测试（带 ApiKey 头），
// 全部通过才保存档案并进入主界面，密钥缺失/错误（401）会在登录时被直接拦截。

struct LoginView: View {
    @EnvironmentObject private var settings: AppSettings
    @AppStorage("stash.serverSetupDone") private var serverSetupDone = false
    @State private var lanURL = ""
    @State private var wanURL = ""
    @State private var apiKey = ""
    @State private var errorText: String?
    @State private var busy = false
    @State private var lanResult: String?
    @State private var wanResult: String?

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("内网地址（如 http://192.168.2.210:9999）", text: $lanURL)
                        .keyboardType(.URL)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                    TextField("外网地址（如 https://stash.example.com）", text: $wanURL)
                        .keyboardType(.URL)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                    SecureField("API Key（必填）", text: $apiKey)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                } header: {
                    Text("服务器配置（首次使用必填）")
                } footer: {
                    Text("登录时会分别实测内网与外网连接，均通过后才进入。API Key 在 Stash 的 设置 → 安全 中获取；此后可按 WiFi 规则在内外网档案间自动切换。")
                }

                if let e = errorText {
                    Section {
                        Label(e, systemImage: "exclamationmark.triangle.fill")
                            .font(.subheadline)
                            .foregroundStyle(.red)
                    }
                }

                Section {
                    Button {
                        Task { await submit() }
                    } label: {
                        HStack {
                            Spacer()
                            if busy {
                                ProgressView()
                            } else {
                                Text("登录")
                                    .fontWeight(.semibold)
                            }
                            Spacer()
                        }
                    }
                    .disabled(busy || Self.invalidAddress(lanURL) || Self.invalidAddress(wanURL) || apiKey.isEmpty)

                    if let r = lanResult {
                        Label(r, systemImage: r.contains("成功") ? "checkmark.circle" : "xmark.circle")
                            .font(.subheadline)
                            .foregroundStyle(r.contains("成功") ? Color.green : Color.red)
                    }
                    if let r = wanResult {
                        Label(r, systemImage: r.contains("成功") ? "checkmark.circle" : "xmark.circle")
                            .font(.subheadline)
                            .foregroundStyle(r.contains("成功") ? Color.green : Color.red)
                    }
                } header: {
                    Text("连接")
                }
            }
            .navigationTitle("Stash 登入")
        }
    }

    private static func invalidAddress(_ s: String) -> Bool {
        let t = s.trimmingCharacters(in: .whitespaces)
        return !(t.hasPrefix("http://") || t.hasPrefix("https://"))
    }

    private func submit() async {
        errorText = nil
        lanResult = nil
        wanResult = nil
        busy = true
        defer { busy = false }
        let lan = lanURL.trimmingCharacters(in: .whitespaces)
        let wan = wanURL.trimmingCharacters(in: .whitespaces)
        let key = apiKey.trimmingCharacters(in: .whitespaces)
        do {
            let lanClient = try GraphQLClient(baseURL: lan, apiKey: key)
            let lanV = try await StashAPI.version(lanClient)
            lanResult = "内网连接成功 · Stash \(lanV)"

            let wanClient = try GraphQLClient(baseURL: wan, apiKey: key)
            let wanV = try await StashAPI.version(wanClient)
            wanResult = "外网连接成功 · Stash \(wanV)"

            settings.applyFirstSetup(lanURL: lan, wanURL: wan, apiKey: key)
            serverSetupDone = true
        } catch {
            errorText = error.localizedDescription
        }
    }
}
