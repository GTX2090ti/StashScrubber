import SwiftUI

// MARK: - 登录（App 内账号门禁，无注册功能）
//
// 首次登录：除账号密码外，必须填写内网 / 外网两个服务地址，
// 提交后自动生成「内网 / 外网」两个服务器档案（内网默认激活）。
// 首次登录即创建本机账号（账号不存在时自动建立，密码 PBKDF2 加盐哈希存储）。

struct LoginView: View {
    @EnvironmentObject private var account: AccountStore
    @EnvironmentObject private var settings: AppSettings
    @AppStorage("stash.serverSetupDone") private var serverSetupDone = false
    @State private var username = ""
    @State private var password = ""
    @State private var lanURL = ""
    @State private var wanURL = ""
    @State private var apiKey = ""
    @State private var errorText: String?
    @State private var busy = false

    private var serverFieldsInvalid: Bool {
        !serverSetupDone && (Self.invalidAddress(lanURL) || Self.invalidAddress(wanURL))
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("账号") {
                    TextField("用户名", text: $username)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                    SecureField("密码", text: $password)
                }

                if !serverSetupDone {
                    Section {
                        TextField("内网地址（如 http://192.168.2.210:9999）", text: $lanURL)
                            .keyboardType(.URL)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                        TextField("外网地址（如 https://stash.example.com）", text: $wanURL)
                            .keyboardType(.URL)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                        SecureField("API Key（内外网通用，可留空）", text: $apiKey)
                    } header: {
                        Text("服务器配置（首次登录必填）")
                    } footer: {
                        Text("需填写内网与外网两个服务地址（http:// 或 https:// 开头，可含路径前缀），登录后自动生成内外网档案，可在设置中修改或经 WiFi 规则自动切换。")
                    }
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
                    .disabled(busy || username.isEmpty || password.isEmpty || serverFieldsInvalid)
                } footer: {
                    Text("首次登录将以此创建本机账号；密码使用 PBKDF2 加盐哈希存储，不保存明文。")
                }
            }
            .navigationTitle("Stash 削刮")
        }
    }

    private static func invalidAddress(_ s: String) -> Bool {
        let t = s.trimmingCharacters(in: .whitespaces)
        return !(t.hasPrefix("http://") || t.hasPrefix("https://"))
    }

    private func submit() async {
        errorText = nil
        guard !serverFieldsInvalid else {
            errorText = "请填写有效的内网与外网地址（以 http:// 或 https:// 开头）"
            return
        }
        busy = true
        defer { busy = false }
        do {
            try account.loginOrRegister(username: username, password: password)
            if !serverSetupDone {
                settings.applyFirstSetup(
                    lanURL: lanURL.trimmingCharacters(in: .whitespaces),
                    wanURL: wanURL.trimmingCharacters(in: .whitespaces),
                    apiKey: apiKey
                )
                serverSetupDone = true
            }
        } catch {
            errorText = error.localizedDescription
        }
    }
}
