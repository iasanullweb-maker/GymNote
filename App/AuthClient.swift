import CryptoKit
import Foundation
import Security

enum AccountError: LocalizedError {
    case notConfigured, invalidInput, unauthorized, rateLimited, server, storage, conflict, stale
    case cancelled, providerUnavailable, browserUnavailable, wrongAccount, featureUnavailable
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
        case .cancelled: return "로그인을 취소했어요. 기기의 기록은 그대로예요."
        case .providerUnavailable: return "이 로그인 방식은 아직 준비되지 않았어요. 다른 방법으로 로그인해 주세요."
        case .browserUnavailable: return "로그인 창을 열지 못했어요. 잠시 후 다시 시도해 주세요."
        case .wrongAccount: return "현재 계정과 다른 계정으로 인증했어요. 이 계정에 연결된 로그인 방법으로 다시 확인해 주세요."
        case .featureUnavailable: return "친구 기능 서버가 아직 준비되지 않았어요. 기기의 기록은 그대로예요."
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

/// `providers` mirrors Supabase `app_metadata.providers` (e.g. ["email", "google"]).
/// It only decides which re-authentication methods to offer; the server still verifies every login.
struct AccountUser: Codable {
    var id: UUID
    var email: String?
    var providers: [String] = []

    init(id: UUID, email: String?, providers: [String] = []) {
        self.id = id
        self.email = email
        self.providers = providers
    }

    private enum CodingKeys: String, CodingKey { case id, email, app_metadata }
    private enum MetadataKeys: String, CodingKey { case providers }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(UUID.self, forKey: .id)
        email = try c.decodeIfPresent(String.self, forKey: .email)
        if let metadata = try? c.nestedContainer(keyedBy: MetadataKeys.self, forKey: .app_metadata) {
            providers = (try? metadata.decodeIfPresent([String].self, forKey: .providers)) ?? []
        }
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(id, forKey: .id)
        try c.encodeIfPresent(email, forKey: .email)
        var metadata = c.nestedContainer(keyedBy: MetadataKeys.self, forKey: .app_metadata)
        try metadata.encode(providers, forKey: .providers)
    }
}

/// Social providers the app can start through Supabase's hosted OAuth + PKCE flow.
enum SocialProvider: String, CaseIterable, Identifiable {
    case apple, google
    var id: String { rawValue }
    var title: String { self == .apple ? "Apple" : "Google" }
}

/// RFC 7636 PKCE (S256). The verifier stays in memory for one flow and is never written to disk.
enum PKCE {
    static func verifier() throws -> String {
        var bytes = [UInt8](repeating: 0, count: 32)
        guard SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes) == errSecSuccess else { throw AccountError.storage }
        return base64URL(Data(bytes))
    }
    static func challenge(for verifier: String) -> String {
        base64URL(Data(SHA256.hash(data: Data(verifier.utf8))))
    }
    private static func base64URL(_ data: Data) -> String {
        data.base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }
}

/// One in-flight browser sign-in. A new verifier is created for every attempt.
struct OAuthAttempt {
    let provider: SocialProvider
    let verifier: String
    let url: URL
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
        // 서버에 친구 기능 함수가 아직 없을 때(마이그레이션 적용 전)
        case 404 where path.hasPrefix("/rest/v1/rpc/social_"): throw AccountError.featureUnavailable
        case 400, 422:
            if path.hasPrefix("/auth/v1/verify") || path.hasPrefix("/auth/v1/token") { throw AccountError.unauthorized }
            throw AccountError.invalidInput
        default: throw AccountError.server // Never expose raw provider errors, tokens, or account existence.
        }
    }
    // MARK: Social login (Supabase hosted OAuth, PKCE, system authentication browser)

    /// Not registered in Info.plist: only the ASWebAuthenticationSession that started the flow receives it.
    /// The exact URL must also be in Supabase Auth → URL Configuration → Redirect URLs.
    static let callbackScheme = "com.gymnote.app"
    static let redirectURL = URL(string: "com.gymnote.app://auth-callback")!

    /// Public settings; reports which providers the Supabase project has actually enabled.
    func enabledProviders() async throws -> Set<SocialProvider> {
        struct Settings: Decodable { let external: [String: Bool] }
        let data = try await request(path: "/auth/v1/settings", method: "GET")
        let settings = try JSONDecoder().decode(Settings.self, from: data)
        return Set(SocialProvider.allCases.filter { settings.external[$0.rawValue] == true })
    }

    func beginOAuth(_ provider: SocialProvider) throws -> OAuthAttempt {
        let verifier = try PKCE.verifier()
        guard var parts = URLComponents(url: config.url.appendingPathComponent("auth/v1/authorize"), resolvingAgainstBaseURL: false)
        else { throw AccountError.notConfigured }
        parts.queryItems = [
            URLQueryItem(name: "provider", value: provider.rawValue),
            URLQueryItem(name: "redirect_to", value: Self.redirectURL.absoluteString),
            URLQueryItem(name: "code_challenge", value: PKCE.challenge(for: verifier)),
            URLQueryItem(name: "code_challenge_method", value: "s256"),
        ]
        guard let url = parts.url, url.scheme == "https", url.host == config.url.host else { throw AccountError.notConfigured }
        return OAuthAttempt(provider: provider, verifier: verifier, url: url)
    }

    /// Accepts only our exact return address. Provider errors are reported without echoing their text.
    static func authorizationCode(from callback: URL) throws -> String {
        guard callback.scheme?.lowercased() == callbackScheme, callback.host?.lowercased() == "auth-callback",
              callback.path.isEmpty || callback.path == "/",
              let parts = URLComponents(url: callback, resolvingAgainstBaseURL: false)
        else { throw AccountError.unauthorized }
        var values: [String: String] = [:]
        for item in parts.queryItems ?? [] { values[item.name] = item.value }
        if let fragment = callback.fragment {
            // Errors may arrive in the fragment. Malformed text is rejected rather than parsed loosely.
            guard let extra = URLComponents(string: "x:?" + fragment) else { throw AccountError.unauthorized }
            for item in extra.queryItems ?? [] where values[item.name] == nil { values[item.name] = item.value }
        }
        if let error = values["error"] {
            throw error == "access_denied" ? AccountError.cancelled : AccountError.unauthorized
        }
        guard let code = values["code"], (1...512).contains(code.count),
              code.allSatisfy({ $0.isASCII && ($0.isLetter || $0.isNumber || "-._~".contains($0)) })
        else { throw AccountError.unauthorized }
        return code
    }

    func exchange(code: String, verifier: String) async throws -> AccountSession {
        let body = try JSONSerialization.data(withJSONObject: ["auth_code": code, "code_verifier": verifier])
        let data = try await request(path: "/auth/v1/token?grant_type=pkce", body: body)
        return try JSONDecoder().decode(TokenResponse.self, from: data).session
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

    func recordCatalog() async throws -> [CatalogRecordType] {
        let data = try await request(path: "/rest/v1/rpc/list_record_catalog", body: Data("{}".utf8))
        return try JSONDecoder().decode([CatalogRecordType].self, from: data)
    }

    func isCatalogAdmin(token: String) async throws -> Bool {
        let data = try await request(path: "/rest/v1/rpc/is_record_catalog_admin", token: token, body: Data("{}".utf8))
        return try JSONDecoder().decode(Bool.self, from: data)
    }

    func saveCatalogType(_ type: CatalogRecordType, token: String) async throws -> CatalogRecordType {
        struct Body: Encodable { let p_type: CatalogRecordType; let p_expected_revision: Int64 }
        let body = try JSONEncoder().encode(Body(p_type: type, p_expected_revision: type.revision))
        let raw = try await request(path: "/rest/v1/rpc/save_record_catalog_type", token: token, body: body)
        guard let saved = try JSONDecoder().decode([CatalogRecordType].self, from: raw).first else {
            throw AccountError.conflict
        }
        return saved
    }

    // MARK: 친구·그룹 경쟁 (Supabase RPC, 모두 서버가 세션과 소유자를 확인)

    private func socialCall(_ name: String, token: String, body: Data = Data("{}".utf8)) async throws -> Data {
        try await request(path: "/rest/v1/rpc/\(name)", token: token, body: body)
    }
    private func json(_ object: [String: Any]) throws -> Data { try JSONSerialization.data(withJSONObject: object) }

    func socialOverview(token: String) async throws -> SocialOverview {
        try JSONDecoder().decode(SocialOverview.self, from: await socialCall("social_overview", token: token))
    }
    func withdrawSocial(token: String) async throws -> Bool {
        try JSONDecoder().decode(Bool.self, from: await socialCall("social_withdraw", token: token))
    }
    func saveSocialProfile(nickname: String, share: Bool, token: String) async throws -> SocialOverview.Profile {
        let data = try await socialCall("social_save_profile", token: token,
                                        body: json(["p_nickname": nickname, "p_share": share]))
        guard let profile = try JSONDecoder().decode([SocialOverview.Profile].self, from: data).first else { throw AccountError.server }
        return profile
    }
    func sendFriendRequest(code: String, token: String) async throws -> String {
        try JSONDecoder().decode(String.self, from: await socialCall("social_send_friend_request", token: token,
                                                                       body: json(["p_code": code])))
    }
    func respondFriendRequest(from user: UUID, accept: Bool, token: String) async throws -> Bool {
        try JSONDecoder().decode(Bool.self, from: await socialCall("social_respond_friend_request", token: token,
            body: json(["p_requester": user.uuidString, "p_accept": accept])))
    }
    func removeFriend(_ user: UUID, token: String) async throws -> Bool {
        try JSONDecoder().decode(Bool.self, from: await socialCall("social_remove_friend", token: token,
                                                                     body: json(["p_user": user.uuidString])))
    }
    func createGroup(name: String, token: String) async throws -> UUID {
        try JSONDecoder().decode(UUID.self, from: await socialCall("social_create_group", token: token,
                                                                     body: json(["p_name": name])))
    }
    func inviteToGroup(_ group: UUID, user: UUID, token: String) async throws -> Bool {
        try JSONDecoder().decode(Bool.self, from: await socialCall("social_invite_to_group", token: token,
            body: json(["p_group": group.uuidString, "p_user": user.uuidString])))
    }
    func respondGroupInvite(_ group: UUID, accept: Bool, token: String) async throws -> Bool {
        try JSONDecoder().decode(Bool.self, from: await socialCall("social_respond_group_invite", token: token,
            body: json(["p_group": group.uuidString, "p_accept": accept])))
    }
    func leaveGroup(_ group: UUID, token: String) async throws -> Bool {
        try JSONDecoder().decode(Bool.self, from: await socialCall("social_leave_group", token: token,
                                                                     body: json(["p_group": group.uuidString])))
    }
    func publishRecords(_ records: [PublishedRecord], token: String) async throws -> Int {
        struct Body: Encodable { let p_records: [PublishedRecord] }
        return try JSONDecoder().decode(Int.self, from: await socialCall("social_publish_records", token: token,
                                                                           body: JSONEncoder().encode(Body(p_records: records))))
    }
    func leaderboard(group: UUID?, token: String) async throws -> [SocialEntry] {
        let body = try json(group.map { ["p_group": $0.uuidString] } ?? [:])
        return try JSONDecoder().decode([SocialEntry].self, from: await socialCall("social_leaderboard", token: token, body: body))
    }
}
