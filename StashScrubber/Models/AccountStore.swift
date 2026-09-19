import Foundation
import CommonCrypto

// MARK: - App 内账号系统（注册 / 登录验证 / 加密存储 / 会话保持与登出）
//
// 密码不落明文：PBKDF2-HMAC-SHA256（12 万轮，16 字节随机盐）后仅存哈希与盐。

struct StoredAccount: Codable {
    let salt: String      // hex
    let hash: String      // hex
    let createdAt: Date
}

struct StoredSession: Codable {
    let username: String
    let token: String     // 会话标识
    let expiresAt: Date
}

enum AccountError: LocalizedError {
    case emptyUsername
    case weakPassword
    case usernameTaken
    case userNotFound
    case wrongPassword

    var errorDescription: String? {
        switch self {
        case .emptyUsername:  return "用户名不能为空"
        case .weakPassword:   return "密码至少需要 6 位"
        case .usernameTaken:  return "该用户名已被注册，请换一个"
        case .userNotFound:   return "用户名不存在，请先注册"
        case .wrongPassword:  return "密码错误，请重试"
        }
    }
}

@MainActor
final class AccountStore: ObservableObject {
    static let shared = AccountStore()

    private static let accountsKey = "stash.accounts"
    private static let sessionKey = "stash.session"
    /// 会话保持：30 天
    private static let sessionLifetime: TimeInterval = 30 * 24 * 3600
    private static let pbkdf2Rounds: UInt32 = 120_000

    @Published private(set) var currentUser: String?

    private init() {
        // 会话保持：启动时恢复未过期会话
        if let s = Self.loadSession(), s.expiresAt > Date() {
            currentUser = s.username
        }
    }

    // MARK: 注册 / 登录 / 登出

    func register(username: String, password: String) throws {
        let name = username.trimmingCharacters(in: .whitespaces)
        guard !name.isEmpty else { throw AccountError.emptyUsername }
        guard password.count >= 6 else { throw AccountError.weakPassword }
        var all = Self.loadAccounts()
        guard all[name] == nil else { throw AccountError.usernameTaken }
        let salt = Self.randomSalt()
        let hash = Self.pbkdf2(password, salt: salt)
        all[name] = StoredAccount(salt: Self.hex(salt), hash: Self.hex(hash), createdAt: Date())
        if let data = try? JSONEncoder().encode(all) {
            UserDefaults.standard.set(data, forKey: Self.accountsKey)
        }
    }

    func login(username: String, password: String) throws {
        let name = username.trimmingCharacters(in: .whitespaces)
        guard !name.isEmpty else { throw AccountError.emptyUsername }
        guard let acc = Self.loadAccounts()[name] else { throw AccountError.userNotFound }
        guard let salt = Self.fromHex(acc.salt), let expect = Self.fromHex(acc.hash),
              Self.pbkdf2(password, salt: salt) == expect else {
            throw AccountError.wrongPassword
        }
        let s = StoredSession(
            username: name,
            token: UUID().uuidString,
            expiresAt: Date().addingTimeInterval(Self.sessionLifetime)
        )
        if let data = try? JSONEncoder().encode(s) {
            UserDefaults.standard.set(data, forKey: Self.sessionKey)
        }
        currentUser = name
    }

    /// 登录：账号已存在则校验密码；不存在则自动创建（App 无独立注册功能，首次登录即设置账号）
    func loginOrRegister(username: String, password: String) throws {
        let name = username.trimmingCharacters(in: .whitespaces)
        if Self.loadAccounts()[name] != nil {
            try login(username: name, password: password)
        } else {
            try register(username: name, password: password)
            try login(username: name, password: password)
        }
    }

    func logout() {
        UserDefaults.standard.removeObject(forKey: Self.sessionKey)
        currentUser = nil
    }

    // MARK: 存取与加密

    private static func loadAccounts() -> [String: StoredAccount] {
        guard let data = UserDefaults.standard.data(forKey: accountsKey),
              let all = try? JSONDecoder().decode([String: StoredAccount].self, from: data) else { return [:] }
        return all
    }

    private static func loadSession() -> StoredSession? {
        guard let data = UserDefaults.standard.data(forKey: sessionKey) else { return nil }
        return try? JSONDecoder().decode(StoredSession.self, from: data)
    }

    private static func randomSalt() -> Data {
        var bytes = [UInt8](repeating: 0, count: 16)
        _ = SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes)
        return Data(bytes)
    }

    /// PBKDF2-HMAC-SHA256，输出 32 字节
    private static func pbkdf2(_ password: String, salt: Data) -> Data {
        let pw = password.cString(using: .utf8)!   // 含结尾 \0
        let pwLen = pw.count - 1
        var derived = [UInt8](repeating: 0, count: 32)
        let status = salt.withUnsafeBytes { (sp: UnsafeRawBufferPointer) -> Int32 in
            CCKeyDerivationPBKDF(
                CCPBKDFAlgorithm(kCCPBKDF2),
                pw, pwLen,
                sp.bindMemory(to: UInt8.self).baseAddress, salt.count,
                CCPseudoRandomAlgorithm(kCCPRFHmacAlgSHA256),
                pbkdf2Rounds,
                &derived, derived.count
            )
        }
        precondition(status == kCCSuccess, "PBKDF2 failed: \(status)")
        return Data(derived)
    }

    private static func hex(_ d: Data) -> String {
        d.map { String(format: "%02x", $0) }.joined()
    }

    private static func fromHex(_ s: String) -> Data? {
        var d = Data()
        var i = s.startIndex
        while i < s.endIndex, s.index(after: i) < s.endIndex {
            let j = s.index(after: i)
            if let b = UInt8(s[i...j].prefix(2), radix: 16) { d.append(b) }
            i = s.index(after: j)
        }
        return d.isEmpty ? nil : d
    }
}
