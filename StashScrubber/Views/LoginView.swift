import SwiftUI

// MARK: - 登录 / 注册（App 内账号门禁）

struct LoginView: View {
    @EnvironmentObject private var account: AccountStore
    @State private var mode = 0   // 0=登录 1=注册
    @State private var username = ""
    @State private var password = ""
    @State private var confirm = ""
    @State private var errorText: String?
    @State private var busy = false

    var body: some View {
        NavigationStack {
            Form {
                Picker("", selection: $mode) {
                    Text("登录").tag(0)
                    Text("注册").tag(1)
                }
                .pickerStyle(.segmented)
                .listRowBackground(Color.clear)

                Section("账号") {
                    TextField("用户名", text: $username)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                    SecureField("密码", text: $password)
                    if mode == 1 {
                        SecureField("确认密码", text: $confirm)
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
                                Text(mode == 0 ? "登录" : "注册并登录")
                                    .fontWeight(.semibold)
                            }
                            Spacer()
                        }
                    }
                    .disabled(busy || username.isEmpty || password.isEmpty
                              || (mode == 1 && confirm.isEmpty))
                } footer: {
                    Text(mode == 0
                         ? "没有账号？切换到「注册」创建一个。"
                         : "密码使用 PBKDF2 加盐哈希存储，不保存明文。")
                }
            }
            .navigationTitle("Stash 削刮")
        }
        .onChange(of: mode) { _ in errorText = nil }
    }

    private func submit() async {
        errorText = nil
        if mode == 1 && password != confirm {
            errorText = "两次输入的密码不一致"
            return
        }
        busy = true
        defer { busy = false }
        do {
            if mode == 1 {
                try account.register(username: username, password: password)
            }
            try account.login(username: username, password: password)
        } catch {
            errorText = error.localizedDescription
        }
    }
}
