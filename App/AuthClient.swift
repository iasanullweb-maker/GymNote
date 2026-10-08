import Foundation
import Security

enum AccountError: LocalizedError {
    case notConfigured, invalidInput, unauthorized, rateLimited, server, storage, conflict, stale
    var errorDescription: String? {
        switch self {
        case .notConfigured: return "계정 연결을 준비 중입니다. 지금은 기기에 운동 기록을 저장할 수 있어요."
        case .invalidInput: return "이메일과 인증번호를 확인해 주세요."
        case .unauthorized: return "인증이 만료되었거나 인증번호가 올바르지 않아요. 다시 로그인해 주세요."
        case .rateLimited: return "요청이 많아요. 잠시 후 다시 시도해 주세요."
        case .server: return "서버에 연결하지 못했어요. 기기의 기록은 그대로 보관됩니다."
        case .storage: return "안전하게 저장하지 못했어요. 기기를 잠금 해제하고 다시 시도해 주세요."
        case .conflict: return "다른 기기에서 기록이 바뀌었어요. 사용할 기록을 선택해 주세요."
        case .stale: return "작업 중 계정이나 기록이 바뀌었어요. 다시 시도해 주세요."
        }
    }
}

struct AuthConfiguration {
    let url: URL
    let publicKey: String
    static var current: AuthConfiguration? {
        guard let value = Bundle.main.object(forInfoDictionaryKey: "GYMNOTE_SUPABASE_URL") as? String,
              let url = URL(string: value), url.scheme == "https", let host = url.host,
              host.hasSuffix(".supabase.co"), url.user == nil, url.password == nil,
              url.port == nil, url.query == nil, url.fragment == nil, url.path.isEmpty || url.path == "/",
              let key = Bundle.main.object(forInfoDictionaryKey: "GYMNOTE_SUPABASE_PUBLISHABLE_KEY") as? String,
              key.hasPrefix("sb_publishable_"), key.count > 20
        else { return nil }
        return AuthConfiguration(url: url, publicKey: key)
    }
}

struct AccountUser: Codable {
    var id: UUID
    var email: String?
}

struct AccountSession: Codable {
    var accessToken: String
    var refreshToken: String
    var expiresAt: TimeInterval
    var user: AccountUser
}

private struct TokenResponse: Decodable {
    let access_token: String
    let refresh_token: String
    let expires_in: TimeInterval
    let expires_at: TimeInterval?
    let user: AccountUser
    var session: AccountSession {
        AccountSession(accessToken: access_token, refreshToken: refresh_token,
                       expiresAt: expires_at ?? Date().timeIntervalSince1970 + expires_in, user: user)
    }
}

/// Tokens stay in the app's private Keychain, never the widget App Group or a JSON file.
struct SessionVault {
    let project: String
    private var query: [String: Any] {
        [kSecClass as String: kSecClassGenericPassword,
         kSecAttrService as String: "com.gymnote.auth.\(project)",
         kSecAttrAccount as String: "session",
         kSecAttrSynchronizable as String: false]
    }
    func read() throws -> AccountSession? {
        var lookup = query
        lookup[kSecReturnData as String] = true
        lookup[kSecMatchLimit as String] = kSecMatchLimitOne
        var value: CFTypeRef?
        let status = SecItemCopyMatching(lookup as CFDictionary, &value)
        if status == errSecItemNotFound { return nil }
        guard status == errSecSuccess, let data = value as? Data else { throw AccountError.storage }
        return try JSONDecoder().decode(AccountSession.self, from: data)
    }
    func write(_ session: AccountSession) throws {
        let values: [String: Any] = [
            kSecValueData as String: try JSONEncoder().encode(session),
            kSecAttrAccessible as String: kSecAttrAccessibleWhenUnlockedThisDeviceOnly,
        ]
        var status = SecItemUpdate(query as CFDictionary, values as CFDictionary)
        if status == errSecItemNotFound {
            status = SecItemAdd(query.merging(values) { _, new in new } as CFDictionary, nil)
        }
        guard status == errSecSuccess else { throw AccountError.storage }
    }
    func clear() throws {
        let status = SecItemDelete(query as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else { throw AccountError.storage }
    }
}

private final class NoRedirects: NSObject, URLSessionTaskDelegate {
    func urlSession(_ session: URLSession, task: URLSessionTask,
                    willPerformHTTPRedirection response: HTTPURLResponse, newRequest request: URLRequest,
                    completionHandler: @escaping (URLRequest?) -> Void) { completionHandler(nil) }
}

struct CloudWorkout: Codable {
    var version: Int64
    var payload: AppData
}

/// Authentication and JWT validation are performed by Supabase, using its documented GoTrue API.
/// An ephemeral session prevents tokens and workout responses entering URLCache or cookies.
final class AuthClient {
    let config: AuthConfiguration
    private let transport: URLSession
    init(config: AuthConfiguration, configuration: URLSessionConfiguration = .ephemeral) {
        self.config = config
        let settings = configuration
        settings.urlCache = nil
        settings.httpCookieStorage = nil
        settings.requestCachePolicy = .reloadIgnoringLocalCacheData
        settings.timeoutIntervalForRequest = 25
        settings.timeoutIntervalForResource = 40
        transport = URLSession(configuration: settings, delegate: NoRedirects(), delegateQueue: nil)
    }
    deinit { transport.invalidateAndCancel() }
    func request(path: String, token: String? = nil, body: Data? = nil, method: String = "POST") async throws -> Data {
        guard let url = URL(string: path, relativeTo: config.url)?.absoluteURL,
              url.host == config.url.host, url.scheme == "https" else { throw AccountError.notConfigured }
        var request = URLRequest(url: url)
        request.httpMethod = method
        request.httpBody = body
        request.setValue(config.publicKey, forHTTPHeaderField: "apikey")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        if let token { request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization") }
        let (data, response) = try await transport.data(for: request)
        guard let response = response as? HTTPURLResponse, data.count <= 5_000_000 else { throw AccountError.server }
        switch response.statusCode {
        case 200..<300: return data
        case 401, 403: throw AccountError.unauthorized
        case 429: throw AccountError.rateLimited
        case 400, 422:
            if path.hasPrefix("/auth/v1/verify") || path.hasPrefix("/auth/v1/token") { throw AccountError.unauthorized }
            throw AccountError.invalidInput
        default: throw AccountError.server // Never expose raw provider errors, tokens, or account existence.
        }
    }
    func sendCode(email: String, createUser: Bool) async throws {
        let body = try JSONSerialization.data(withJSONObject: ["email": email, "create_user": createUser])
        _ = try await request(path: "/auth/v1/otp", body: body)
    }
    func verify(email: String, code: String) async throws -> AccountSession {
        let body = try JSONSerialization.data(withJSONObject: ["email": email, "token": code, "type": "email"])
        let data = try await request(path: "/auth/v1/verify", body: body)
        return try JSONDecoder().decode(TokenResponse.self, from: data).session
    }
    func refresh(_ session: AccountSession) async throws -> AccountSession {
        let body = try JSONSerialization.data(withJSONObject: ["refresh_token": session.refreshToken])
        let data = try await request(path: "/auth/v1/token?grant_type=refresh_token", body: body)
        return try JSONDecoder().decode(TokenResponse.self, from: data).session
    }
    func user(token: String) async throws -> AccountUser {
        try JSONDecoder().decode(AccountUser.self, from: await request(path: "/auth/v1/user", token: token, method: "GET"))
    }
    func signOut(token: String) async throws {
        _ = try await request(path: "/auth/v1/logout?scope=local", token: token)
    }
    func download(token: String) async throws -> CloudWorkout? {
        let data = try await request(path: "/rest/v1/rpc/load_workout", token: token, body: Data("{}".utf8))
        return try JSONDecoder().decode([CloudWorkout].self, from: data).first
    }
    func upload(_ snapshot: StoredWorkout, token: String) async throws -> Int64 {
        struct Body: Encodable { var p_payload: AppData; var p_expected_version: Int64 }
        let body = try JSONEncoder().encode(Body(p_payload: snapshot.data, p_expected_version: snapshot.serverVersion))
        let data = try await request(path: "/rest/v1/rpc/save_workout", token: token, body: body)
        guard let saved = try JSONDecoder().decode([CloudWorkout].self, from: data).first else { throw AccountError.conflict }
        return saved.version
    }
    func deleteAccount(token: String) async throws {
        _ = try await request(path: "/functions/v1/delete-account", token: token, body: Data("{}".utf8))
    }
}
