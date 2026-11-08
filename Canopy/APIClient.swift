import Foundation
import Observation

// MARK: - Errors
enum APIError: LocalizedError {
    case invalidURL
    case unauthorized
    case forbidden
    case serverError(String)

    var errorDescription: String? {
        switch self {
        case .invalidURL:         return "Invalid URL."
        case .unauthorized:       return "Session expired. Please sign in again."
        case .forbidden:          return "You don't have permission to do that."
        case .serverError(let m): return m
        }
    }
}

// MARK: - Response envelopes (private)
private struct ErrorResponse: Decodable { let error: String?; let message: String? }
private struct AuthRequestBody: Encodable { let action, username, password: String }
private struct ActionBody: Encodable { let action: String }
private struct EmptyBody: Encodable {}

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

/// GET /api/setup/health
struct HealthStatus: Decodable { let ok: Bool; let cached: Bool?; let error: String? }

/// POST /api/powerschool — kickoff response. The real result arrives via
/// GET /api/powerschool/status (see PowerSchoolSyncStore).
struct SyncKickoff: Decodable {
    let success: Bool
    let syncId: String?
    let status: String?
    let alreadyRunning: Bool?
    let error: String?
    let log: [String]?
}

/// POST /api/powerschool/verify
struct VerifyResult: Decodable { let ok: Bool; let error: String?; let log: [String]? }

/// POST /api/powerschool/migrate — response summary.
struct MigrateResult: Decodable { let success: Bool; let migrated: Int?; let error: String? }

/// Global mutation activity, for the save-status indicator (web
/// SaveStatusIndicator / networkActivity.ts).
@MainActor
@Observable
final class NetworkActivity {
    static let shared = NetworkActivity()
    var inFlightMutations = 0
    var lastMutationFailed = false
    var lastSavedAt: Date?
    var isOffline = false

    fileprivate func begin() { inFlightMutations += 1 }
    fileprivate func end(success: Bool) {
        inFlightMutations = max(0, inFlightMutations - 1)
        if success { lastMutationFailed = false; lastSavedAt = .now } else { lastMutationFailed = true }
    }
}

// MARK: - APIClient
@MainActor
final class APIClient {
    static let shared = APIClient()

    /// Production backend. Override for local testing with the launch argument
    /// `-canopyBaseURL http://localhost:3000` (or UserDefaults key `canopyBaseURL`).
    let baseURL: String = {
        if let o = UserDefaults.standard.string(forKey: "canopyBaseURL"), !o.isEmpty { return o }
        return "https://canopy.apexengineeringak.com"
    }()
    private let session: URLSession
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()

    private init() {
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
        if let body {
            req.setValue("application/json", forHTTPHeaderField: "Content-Type")
            req.httpBody = body
        }
        return req
    }

    /// Runs a request. `preserveAuthMessage` keeps the server's own 401 text
    /// (login/register: "Invalid username or password.") instead of mapping
    /// it to the generic "Session expired".
    private func run(_ req: URLRequest, preserveAuthMessage: Bool = false) async throws -> Data {
        let isMutation = req.httpMethod != "GET"
        if isMutation { NetworkActivity.shared.begin() }
        var ok = false
        defer { if isMutation { NetworkActivity.shared.end(success: ok) } }

        let data: Data, response: URLResponse
        do {
            (data, response) = try await session.data(for: req)
            NetworkActivity.shared.isOffline = false
        } catch {
            if (error as? URLError)?.code == .notConnectedToInternet { NetworkActivity.shared.isOffline = true }
            throw error
        }
        guard let http = response as? HTTPURLResponse else {
            throw APIError.serverError("No HTTP response")
        }
        let serverMsg = (try? decoder.decode(ErrorResponse.self, from: data)).flatMap { $0.error ?? $0.message }
        if http.statusCode == 401 {
            if preserveAuthMessage, let m = serverMsg { throw APIError.serverError(m) }
            throw APIError.unauthorized
        }
        if http.statusCode == 403 { throw serverMsg.map { APIError.serverError($0) } ?? APIError.forbidden }
        guard (200..<300).contains(http.statusCode) else {
            throw APIError.serverError(serverMsg ?? HTTPURLResponse.localizedString(forStatusCode: http.statusCode))
        }
        ok = true
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

    private func postDecode<B: Encodable, R: Decodable>(_ path: String, _ body: B, method: String = "POST", preserveAuthMessage: Bool = false) async throws -> R {
        let data = try encoder.encode(body)
        let req = try buildRequest(path: path, method: method, body: data)
        return try decoder.decode(R.self, from: try await run(req, preserveAuthMessage: preserveAuthMessage))
    }

    private func deleteItem(_ path: String, id: String) async throws {
        let req = try buildRequest(path: path, method: "DELETE",
                                   queryItems: [URLQueryItem(name: "id", value: id)])
        _ = try await run(req)
    }

    private func deleteBatch(_ path: String, ids: [String]) async throws {
        guard !ids.isEmpty else { return }
        let req = try buildRequest(path: path, method: "DELETE",
                                   queryItems: [URLQueryItem(name: "ids", value: ids.joined(separator: ","))])
        _ = try await run(req)
    }

    // MARK: - Auth
    func login(username: String, password: String) async throws -> AuthResponse {
        try await postDecode("/api/auth", AuthRequestBody(action: "login", username: username.trimmingCharacters(in: .whitespaces), password: password), preserveAuthMessage: true)
    }

    func register(username: String, password: String) async throws -> AuthResponse {
        try await postDecode("/api/auth", AuthRequestBody(action: "register", username: username.trimmingCharacters(in: .whitespaces), password: password), preserveAuthMessage: true)
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
        _ = try await run(req, preserveAuthMessage: true)
    }

    func changePassword(current: String, new: String) async throws {
        struct Body: Encodable { let action = "changePassword"; let currentPassword: String; let newPassword: String }
        let data = try encoder.encode(Body(currentPassword: current, newPassword: new))
        let req = try buildRequest(path: "/api/auth", method: "POST", body: data)
        _ = try await run(req, preserveAuthMessage: true)
    }

    // MARK: - Health
    func getHealth(force: Bool = false) async throws -> HealthStatus {
        try await get("/api/setup/health", queryItems: force ? [URLQueryItem(name: "force", value: "1")] : nil)
    }

    // MARK: - Classes
    func getClasses() async throws -> [SchoolClass]     { try await get("/api/classes") }
    func createClass(_ c: SchoolClass) async throws     { try await mutate("POST", path: "/api/classes", body: c) }
    func updateClass(_ c: SchoolClass) async throws     { try await mutate("PUT",  path: "/api/classes", body: c) }
    func deleteClass(id: String) async throws           { try await deleteItem("/api/classes", id: id) }
    /// Drag-to-reorder: the FULL class id list in display order.
    func reorderClasses(_ order: [String]) async throws {
        struct Body: Encodable { let order: [String] }
        try await mutate("PATCH", path: "/api/classes", body: Body(order: order))
    }

    // MARK: - Homework
    func getHomework() async throws -> [Homework]       { try await get("/api/homework") }
    func createHomework(_ h: Homework) async throws     { try await mutate("POST", path: "/api/homework", body: h) }
    func updateHomework(_ h: Homework) async throws     { try await mutate("PUT",  path: "/api/homework", body: h) }
    func deleteHomework(id: String) async throws        { try await deleteItem("/api/homework", id: id) }
    func deleteHomeworkBatch(ids: [String]) async throws { try await deleteBatch("/api/homework", ids: ids) }

    // MARK: - Exams
    func getExams() async throws -> [Exam]              { try await get("/api/exams") }
    func createExam(_ e: Exam) async throws             { try await mutate("POST", path: "/api/exams", body: e) }
    func updateExam(_ e: Exam) async throws             { try await mutate("PUT",  path: "/api/exams", body: e) }
    func deleteExam(id: String) async throws            { try await deleteItem("/api/exams", id: id) }

    // MARK: - Tasks
    func getTasks() async throws -> [SchoolTask]        { try await get("/api/tasks") }
    func createTask(_ t: SchoolTask) async throws       { try await mutate("POST", path: "/api/tasks", body: t) }
    func updateTask(_ t: SchoolTask) async throws       { try await mutate("PUT",  path: "/api/tasks", body: t) }
    func deleteTask(id: String) async throws            { try await deleteItem("/api/tasks", id: id) }
    func deleteTasksBatch(ids: [String]) async throws   { try await deleteBatch("/api/tasks", ids: ids) }

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
    func getSetupStatus() async throws -> SetupStatus { try await get("/api/setup") }

    /// Kick off a background sync. Pass credentials for a one-off, or nil to
    /// use the saved login. Poll `getPowerSchoolStatus()` for the result.
    func startPowerSchoolSync(url: String? = nil, username: String? = nil, password: String? = nil) async throws -> SyncKickoff {
        struct Body: Encodable { let url: String?; let username: String?; let password: String? }
        let data = try encoder.encode(Body(url: url, username: username, password: password))
        let req = try buildRequest(path: "/api/powerschool", method: "POST", body: data)
        // 400 "Missing PowerSchool credentials" is a soft failure — decode it instead of throwing.
        let (respData, response) = try await session.data(for: req)
        if let http = response as? HTTPURLResponse, http.statusCode == 401 { throw APIError.unauthorized }
        if let kick = try? decoder.decode(SyncKickoff.self, from: respData) { return kick }
        throw APIError.serverError("Sync failed to start.")
    }

    func getPowerSchoolStatus() async throws -> PowerSchoolStatus { try await get("/api/powerschool/status") }

    /// Fast login-only credential check used by the setup wizard.
    func verifyPowerSchool(url: String, username: String, password: String) async throws -> VerifyResult {
        struct Body: Encodable { let url: String; let username: String; let password: String }
        let data = try encoder.encode(Body(url: url, username: username, password: password))
        let req = try buildRequest(path: "/api/powerschool/verify", method: "POST", body: data)
        let (respData, response) = try await session.data(for: req)
        if let http = response as? HTTPURLResponse, http.statusCode == 401 { throw APIError.unauthorized }
        if let v = try? decoder.decode(VerifyResult.self, from: respData) { return v }
        throw APIError.serverError("Verification failed.")
    }

    /// Re-links manually-created classes to newly-synced PowerSchool classes.
    func migratePowerSchool() async throws -> MigrateResult {
        try await postDecode("/api/powerschool/migrate", EmptyBody())
    }

    func savePowerSchool(url: String, username: String, password: String) async throws {
        struct Body: Encodable { let action = "save-powerschool"; let url: String; let username: String; let password: String }
        struct Resp: Decodable { let success: Bool; let error: String? }
        let r: Resp = try await postDecode("/api/setup", Body(url: url, username: username, password: password))
        if !r.success { throw APIError.serverError(r.error ?? "Could not save PowerSchool login.") }
    }

    func clearPowerSchool() async throws {
        _ = try await run(try buildRequest(path: "/api/setup", method: "POST", body: try encoder.encode(ActionBody(action: "clear-powerschool"))))
    }

    // MARK: - Other schools
    func getSchoolAccounts() async throws -> [SchoolAccountSummary] { try await get("/api/powerschool/schools") }

    func addSchoolAccount(schoolName: String, url: String, username: String, password: String) async throws {
        struct Body: Encodable { let schoolName, url, username, password: String }
        try await mutate("POST", path: "/api/powerschool/schools", body: Body(schoolName: schoolName, url: url, username: username, password: password))
    }

    func syncSchoolAccount(id: String) async throws {
        struct Body: Encodable { let action = "sync"; let id: String }
        try await mutate("POST", path: "/api/powerschool/schools", body: Body(id: id))
    }

    func deleteSchoolAccount(id: String) async throws { try await deleteItem("/api/powerschool/schools", id: id) }

    // MARK: - Admin
    func getAdminStats() async throws -> SystemStats { try await get("/api/admin/stats") }

    func adminDeleteUser(username: String) async throws {
        struct Body: Encodable { let username: String }
        try await mutate("DELETE", path: "/api/admin/users", body: Body(username: username))
    }
}

private struct SettingBody<V: Encodable>: Encodable { let key: String; let value: V }
