import Foundation
import Security

// MARK: - Keychain (watch-local session token)

enum WKeychain {
    private static let service = "canopy.watch"
    static func save(_ value: String, key: String) {
        let data = Data(value.utf8)
        let query: [String: Any] = [kSecClass as String: kSecClassGenericPassword,
                                     kSecAttrService as String: service,
                                     kSecAttrAccount as String: key]
        SecItemDelete(query as CFDictionary)
        var add = query; add[kSecValueData as String] = data
        SecItemAdd(add as CFDictionary, nil)
    }
    static func load(key: String) -> String? {
        let query: [String: Any] = [kSecClass as String: kSecClassGenericPassword,
                                     kSecAttrService as String: service,
                                     kSecAttrAccount as String: key,
                                     kSecReturnData as String: true,
                                     kSecMatchLimit as String: kSecMatchLimitOne]
        var item: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &item) == errSecSuccess,
              let data = item as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }
    static func delete(key: String) {
        let query: [String: Any] = [kSecClass as String: kSecClassGenericPassword,
                                     kSecAttrService as String: service,
                                     kSecAttrAccount as String: key]
        SecItemDelete(query as CFDictionary)
    }
}

// MARK: - API client

enum WAPIError: LocalizedError {
    case unauthorized, server(String)
    var errorDescription: String? {
        switch self { case .unauthorized: return "Session expired."; case .server(let m): return m }
    }
}

@MainActor
final class WatchAPI {
    static let shared = WatchAPI()
    private let baseURL = "https://canopy.apexengineeringak.com"
    private let decoder = JSONDecoder()
    private let encoder = JSONEncoder()
    var token: String?
    private init() {}

    private struct AuthResp: Decodable { let success: Bool; let token: String; let user: WUser }
    private struct SessionResp: Decodable { let user: WUser? }
    private struct ErrResp: Decodable { let error: String?; let message: String? }

    private func req(_ path: String, method: String = "GET", body: Data? = nil) -> URLRequest {
        var r = URLRequest(url: URL(string: baseURL + path)!)
        r.httpMethod = method
        if let token { r.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization") }
        if let body { r.setValue("application/json", forHTTPHeaderField: "Content-Type"); r.httpBody = body }
        return r
    }

    private func run(_ r: URLRequest) async throws -> Data {
        let (data, resp) = try await URLSession.shared.data(for: r)
        guard let http = resp as? HTTPURLResponse else { throw WAPIError.server("No response") }
        if http.statusCode == 401 { throw WAPIError.unauthorized }
        guard (200..<300).contains(http.statusCode) else {
            let msg = (try? decoder.decode(ErrResp.self, from: data)).flatMap { $0.error ?? $0.message }
            throw WAPIError.server(msg ?? "Error \(http.statusCode)")
        }
        return data
    }

    func login(username: String, password: String) async throws -> (String, WUser) {
        struct Body: Encodable { let action = "login"; let username: String; let password: String }
        let data = try await run(req("/api/auth", method: "POST", body: try encoder.encode(Body(username: username, password: password))))
        let resp = try decoder.decode(AuthResp.self, from: data)
        return (resp.token, resp.user)
    }

    func checkSession() async throws -> WUser? {
        let data = try await run(req("/api/auth"))
        return try decoder.decode(SessionResp.self, from: data).user
    }

    func getClasses() async throws -> [WClass] { try decoder.decode([WClass].self, from: try await run(req("/api/classes"))) }
    func getHomework() async throws -> [WHomework] { try decoder.decode([WHomework].self, from: try await run(req("/api/homework"))) }
    func getExams() async throws -> [WExam] { try decoder.decode([WExam].self, from: try await run(req("/api/exams"))) }

    func updateHomework(_ h: WHomework) async throws {
        _ = try await run(req("/api/homework", method: "PUT", body: try encoder.encode(h)))
    }
}
