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
    let success: Bool; let token: String; let user: User
}
struct SessionResponse: Decodable { let user: User? }

// MARK: - APIClient
@MainActor
final class APIClient {
    static let shared = APIClient()

    private let baseURL = "https://vercel.apexengineeringak.com"
    private let session = URLSession.shared
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()

    var token: String?

    private init() {}

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
        if let t = token { req.setValue("Bearer \(t)", forHTTPHeaderField: "Authorization") }
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

    func deleteAccount() async throws {
        let data = try encoder.encode(ActionBody(action: "deleteAccount"))
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

    // MARK: - Settings
    func getSettings() async throws -> AppSettings { try await get("/api/settings") }

    func saveSetting<T: Encodable>(key: String, value: T) async throws {
        try await mutate("POST", path: "/api/settings", body: SettingBody(key: key, value: value))
    }
}

private struct SettingBody<V: Encodable>: Encodable { let key: String; let value: V }
