import SwiftUI

// MARK: - 登录（API Key 即登录凭据，无账号密码）
//
// 首次使用需填写：内网地址、外网地址（两者至少填一个）、API Key
// （Stash 设置 → 安全 → API Key）。
// 点「登录」会对已填写的地址各做一次真实连接测试（带 ApiKey 头），
// 至少一侧通过才保存并进入主界面，密钥错误（401）会在登录时被直接拦截。
//
// 登录成功后按「内外网都有 + 优先使用内网地址」建立一条连接，
// 后续在 设置 → 服务器连接 里可随时增删地址、切换优先策略。

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

    private var hasLAN: Bool { !lanURL.trimmingCharacters(in: .whitespaces).isEmpty }
    private var hasWAN: Bool { !wanURL.trimmingCharacters(in: .whitespaces).isEmpty }
    private var anyAddressValid: Bool {
        (hasLAN && !Self.invalidAddress(lanURL)) || (hasWAN && !Self.invalidAddress(wanURL))
    }

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
                    Text("服务器配置（首次使用，内外网至少填一个）")
                } footer: {
                    Text("两个地址都填 → 建立一条双地址连接并「优先使用内网地址」，内网不可达时自动切外网；只填一个则固定走该地址。登录会实测已填地址，API Key 在 Stash 的 设置 → 安全 中获取。")
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
                    .disabled(busy || !anyAddressValid || apiKey.trimmingCharacters(in: .whitespaces).isEmpty)

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
            .onAppear { prefillFromExisting() }
        }
    }

    private static func invalidAddress(_ s: String) -> Bool {
        let t = s.trimmingCharacters(in: .whitespaces)
        return !(t.hasPrefix("http://") || t.hasPrefix("https://"))
    }

    /// 重置服务器配置后回到登录页时，用现有连接回填，避免重新手打
    private func prefillFromExisting() {
        guard lanURL.isEmpty, wanURL.isEmpty, apiKey.isEmpty,
              let c = settings.activeConnection else { return }
        lanURL = c.lanURL ?? ""
        wanURL = c.wanURL ?? ""
        apiKey = c.apiKey
    }

    private func submit() async {
        errorText = nil
        lanResult = nil
        wanResult = nil
        busy = true
        defer { busy = false }

        let lan = hasLAN ? lanURL.trimmingCharacters(in: .whitespaces) : ""
        let wan = hasWAN ? wanURL.trimmingCharacters(in: .whitespaces) : ""
        let key = apiKey.trimmingCharacters(in: .whitespaces)
        var passed = 0

        if !lan.isEmpty {
            do {
                let client = try GraphQLClient(baseURL: lan, apiKey: key, profileName: "内网（登录测试）")
                let v = try await StashAPI.version(client)
                lanResult = "内网连接成功 · Stash \(v)"
                passed += 1
            } catch {
                let msg = NetError.friendly(error)
                lanResult = "内网连接失败：\(msg)"
                NetLog.shared.record(category: .auth, level: .error, title: "登录连接测试 · 内网",
                                     url: lan, message: msg)
            }
        }

        if !wan.isEmpty {
            do {
                let client = try GraphQLClient(baseURL: wan, apiKey: key, profileName: "外网（登录测试）")
                let v = try await StashAPI.version(client)
                wanResult = "外网连接成功 · Stash \(v)"
                passed += 1
            } catch {
                let msg = NetError.friendly(error)
                wanResult = "外网连接失败：\(msg)"
                NetLog.shared.record(category: .auth, level: .error, title: "登录连接测试 · 外网",
                                     url: wan, message: msg)
            }
        }

        guard passed > 0 else {
            errorText = "没有任何地址连接成功，请检查地址、端口与 API Key（外网访问通常需要反向代理与端口映射）"
            return
        }
        settings.applyFirstSetup(lanURL: lan, wanURL: wan, apiKey: key)
        settings.markSynced()
        serverSetupDone = true
    }
}
