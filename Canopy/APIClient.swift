import Foundation

// MARK: - Errors
enum APIError: LocalizedError {
    case invalidURL
    case unauthorized
    case serverError(String)

    var errorDescription: String? {
        switch self {
        case .invalidURL:         return "Invalid URL."
        case .unauthorized:       return "Session expired. Please sign in again."
        case .serverError(let m): return m
        }
    }
}

// MARK: - Response envelopes (private)
private struct SuccessResponse: Decodable { let success: Bool }
private struct ErrorResponse: Decodable { let error: String?; let message: String? }
private struct AuthRequestBody: Encodable { let action, username, password: String }
private struct ActionBody: Encodable { let action: String }

// MARK: - Public response types
struct AuthResponse: Decodable {
    let success: Bool; let user: User
}
struct SessionResponse: Decodable { let user: User? }

/// GET /api/setup — integration status.
struct SetupStatus: Decodable {
    let configured: Bool
    let hasDatabase: Bool
    let hasClassroomOAuth: Bool
    let hasPowerschool: Bool
    let powerschoolUrl: String
    let powerschoolUsername: String
}

/// POST /api/powerschool — sync result summary.
struct SyncResult: Decodable {
    let success: Bool
    let classAdded: Int?
    let classUpdated: Int?
    let classRemoved: Int?
    let assignmentAdded: Int?
    let assignmentUpdated: Int?
    let assignmentRemoved: Int?
    let log: [String]?
    let error: String?
}

/// POST /api/setup generate-setup-code
struct SetupCodeResult: Decodable { let success: Bool; let setupCode: String?; let error: String? }
/// POST /api/setup use-setup-code
struct UseSetupCodeResult: Decodable {
    let success: Bool; let hasClassroomOAuth: Bool?; let hasPowerschool: Bool?; let error: String?
}

// MARK: - APIClient
@MainActor
final class APIClient {
    static let shared = APIClient()

    private let baseURL = "https://canopy.apexengineeringak.com"
    private let session: URLSession
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()

    private init() {
        // Configure URLSession to handle cookies automatically
        let config = URLSessionConfiguration.default
        config.httpShouldSetCookies = true
        config.httpCookieAcceptPolicy = .always
        self.session = URLSession(configuration: config)
    }

    // MARK: - Core
    private func buildRequest(
        path: String,
        method: String = "GET",
        body: Data? = nil,
        queryItems: [URLQueryItem]? = nil
    ) throws -> URLRequest {
        var comps = URLComponents(string: baseURL + path)!
        if let items = queryItems, !items.isEmpty { comps.queryItems = items }
        guard let url = comps.url else { throw APIError.invalidURL }
        var req = URLRequest(url: url)
        req.httpMethod = method
        // Cookies are automatically handled by URLSession configuration
        if let body {
            req.setValue("application/json", forHTTPHeaderField: "Content-Type")
            req.httpBody = body
        }
        return req
    }

    private func run(_ req: URLRequest) async throws -> Data {
        let (data, response) = try await session.data(for: req)
        guard let http = response as? HTTPURLResponse else {
            throw APIError.serverError("No HTTP response")
        }
        if http.statusCode == 401 { throw APIError.unauthorized }
        guard (200..<300).contains(http.statusCode) else {
            let msg = (try? decoder.decode(ErrorResponse.self, from: data))
                .flatMap { $0.error ?? $0.message }
                ?? HTTPURLResponse.localizedString(forStatusCode: http.statusCode)
            throw APIError.serverError(msg)
        }
        return data
    }

    private func get<T: Decodable>(_ path: String, queryItems: [URLQueryItem]? = nil) async throws -> T {
        let req = try buildRequest(path: path, queryItems: queryItems)
        return try decoder.decode(T.self, from: try await run(req))
    }

    private func mutate<B: Encodable>(_ method: String, path: String, body: B) async throws {
        let data = try encoder.encode(body)
        let req = try buildRequest(path: path, method: method, body: data)
        _ = try await run(req)
    }

    private func deleteItem(_ path: String, id: String) async throws {
        let req = try buildRequest(path: path, method: "DELETE",
                                   queryItems: [URLQueryItem(name: "id", value: id)])
        _ = try await run(req)
    }

    // MARK: - Auth
    func login(username: String, password: String) async throws -> AuthResponse {
        let data = try encoder.encode(AuthRequestBody(action: "login", username: username, password: password))
        let req = try buildRequest(path: "/api/auth", method: "POST", body: data)
        return try decoder.decode(AuthResponse.self, from: try await run(req))
    }

    func register(username: String, password: String) async throws -> AuthResponse {
        let data = try encoder.encode(AuthRequestBody(action: "register", username: username, password: password))
        let req = try buildRequest(path: "/api/auth", method: "POST", body: data)
        return try decoder.decode(AuthResponse.self, from: try await run(req))
    }

    func checkSession() async throws -> SessionResponse { try await get("/api/auth") }

    func logout() async throws {
        let data = try encoder.encode(ActionBody(action: "logout"))
        let req = try buildRequest(path: "/api/auth", method: "POST", body: data)
        _ = try? await run(req)
    }

    func deleteAccount(password: String) async throws {
        struct Body: Encodable { let action = "deleteAccount"; let password: String }
        let data = try encoder.encode(Body(password: password))
        let req = try buildRequest(path: "/api/auth", method: "POST", body: data)
        _ = try await run(req)
    }

    func changePassword(current: String, new: String) async throws {
        struct Body: Encodable { let action = "changePassword"; let currentPassword: String; let newPassword: String }
        let data = try encoder.encode(Body(currentPassword: current, newPassword: new))
        let req = try buildRequest(path: "/api/auth", method: "POST", body: data)
        _ = try await run(req)
    }

    // MARK: - Classes
    func getClasses() async throws -> [SchoolClass]     { try await get("/api/classes") }
    func createClass(_ c: SchoolClass) async throws     { try await mutate("POST", path: "/api/classes", body: c) }
    func updateClass(_ c: SchoolClass) async throws     { try await mutate("PUT",  path: "/api/classes", body: c) }
    func deleteClass(id: String) async throws           { try await deleteItem("/api/classes", id: id) }

    // MARK: - Homework
    func getHomework() async throws -> [Homework]       { try await get("/api/homework") }
    func createHomework(_ h: Homework) async throws     { try await mutate("POST", path: "/api/homework", body: h) }
    func updateHomework(_ h: Homework) async throws     { try await mutate("PUT",  path: "/api/homework", body: h) }
    func deleteHomework(id: String) async throws        { try await deleteItem("/api/homework", id: id) }

    // MARK: - Exams
    func getExams() async throws -> [Exam]              { try await get("/api/exams") }
    func createExam(_ e: Exam) async throws             { try await mutate("POST", path: "/api/exams", body: e) }
    func updateExam(_ e: Exam) async throws             { try await mutate("PUT",  path: "/api/exams", body: e) }
    func deleteExam(id: String) async throws            { try await deleteItem("/api/exams", id: id) }

    // MARK: - Tasks
    func getTasks() async throws -> [SchoolTask]              { try await get("/api/tasks") }
    func createTask(_ t: SchoolTask) async throws             { try await mutate("POST", path: "/api/tasks", body: t) }
    func updateTask(_ t: SchoolTask) async throws             { try await mutate("PUT",  path: "/api/tasks", body: t) }
    func deleteTask(id: String) async throws            { try await deleteItem("/api/tasks", id: id) }

    // MARK: - Disruptions
    func getDisruptions() async throws -> [ScheduleDisruption] { try await get("/api/disruptions") }
    func createDisruption(_ d: ScheduleDisruption) async throws { try await mutate("POST", path: "/api/disruptions", body: d) }
    func updateDisruption(_ d: ScheduleDisruption) async throws { try await mutate("PUT",  path: "/api/disruptions", body: d) }
    func deleteDisruption(id: String) async throws      { try await deleteItem("/api/disruptions", id: id) }

    // MARK: - Grade History
    func getGradeHistory(classId: String? = nil) async throws -> [GradeHistoryEntry] {
        var items: [URLQueryItem] = []
        if let classId { items.append(URLQueryItem(name: "classId", value: classId)) }
        return try await get("/api/grade-history", queryItems: items.isEmpty ? nil : items)
    }

    // MARK: - Sync Log
    func getSyncLog(classId: String? = nil, limit: Int = 200) async throws -> [SyncLogEntry] {
        var items: [URLQueryItem] = [URLQueryItem(name: "limit", value: "\(limit)")]
        if let classId { items.append(URLQueryItem(name: "classId", value: classId)) }
        return try await get("/api/sync-log", queryItems: items)
    }

    // MARK: - Settings
    func getSettings() async throws -> AppSettings { try await get("/api/settings") }

    func saveSetting<T: Encodable>(key: String, value: T) async throws {
        try await mutate("POST", path: "/api/settings", body: SettingBody(key: key, value: value))
    }

    func saveSettingsBatch(_ batch: [String: String]) async throws {
        struct BatchBody: Encodable { let batch: [String: String] }
        try await mutate("POST", path: "/api/settings", body: BatchBody(batch: batch))
    }

    // MARK: - PowerSchool / Setup
    private func postDecode<B: Encodable, R: Decodable>(_ path: String, _ body: B) async throws -> R {
        let data = try encoder.encode(body)
        let req = try buildRequest(path: path, method: "POST", body: data)
        return try decoder.decode(R.self, from: try await run(req))
    }

    func getSetupStatus() async throws -> SetupStatus { try await get("/api/setup") }

    /// Run a PowerSchool sync. Pass credentials for a one-off, or nil to use saved login.
    func syncPowerSchool(url: String? = nil, username: String? = nil, password: String? = nil) async throws -> SyncResult {
        struct Body: Encodable { let url: String?; let username: String?; let password: String? }
        return try await postDecode("/api/powerschool", Body(url: url, username: username, password: password))
    }

    func savePowerSchool(url: String, username: String, password: String) async throws {
        struct Body: Encodable { let action = "save-powerschool"; let url: String; let username: String; let password: String }
        _ = try await run(try buildRequest(path: "/api/setup", method: "POST", body: try encoder.encode(Body(url: url, username: username, password: password))))
    }

    func clearPowerSchool() async throws {
        _ = try await run(try buildRequest(path: "/api/setup", method: "POST", body: try encoder.encode(ActionBody(action: "clear-powerschool"))))
    }

    func saveClassroomOAuth(clientId: String, clientSecret: String) async throws {
        struct Body: Encodable { let action = "save-classroom-oauth"; let clientId: String; let clientSecret: String }
        _ = try await run(try buildRequest(path: "/api/setup", method: "POST", body: try encoder.encode(Body(clientId: clientId, clientSecret: clientSecret))))
    }

    func generateSetupCode(passphrase: String) async throws -> SetupCodeResult {
        struct Body: Encodable { let action = "generate-setup-code"; let passphrase: String }
        return try await postDecode("/api/setup", Body(passphrase: passphrase))
    }

    func useSetupCode(_ setupCode: String, passphrase: String) async throws -> UseSetupCodeResult {
        struct Body: Encodable { let action = "use-setup-code"; let setupCode: String; let passphrase: String }
        return try await postDecode("/api/setup", Body(setupCode: setupCode, passphrase: passphrase))
    }
}

private struct SettingBody<V: Encodable>: Encodable { let key: String; let value: V }
