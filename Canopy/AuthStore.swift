import Foundation
import Observation

@MainActor
@Observable
final class AuthStore {
    private(set) var user: User?
    var isLoading = false
    var errorMessage: String?

    var isLoggedIn: Bool { user != nil }

    init() {
        // No persistent token to load - we rely on session cookies
    }

    // Called at app launch to restore a prior session.
    func checkSession() async {
        do {
            let resp = try await APIClient.shared.checkSession()
            if let u = resp.user {
                user = u
            } else {
                clearSession()
            }
        } catch APIError.unauthorized {
            clearSession()
        } catch {
            // Network unavailable — keep user, they'll see an error on next data fetch
        }
    }

    @discardableResult
    func login(username: String, password: String) async throws -> User {
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }
        let resp = try await APIClient.shared.login(username: username, password: password)
        user = resp.user
        return resp.user
    }

    @discardableResult
    func register(username: String, password: String) async throws -> User {
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }
        let resp = try await APIClient.shared.register(username: username, password: password)
        user = resp.user
        return resp.user
    }

    func logout() async {
        isLoading = true
        defer { isLoading = false }
        try? await APIClient.shared.logout()
        clearSession()
    }

    func deleteAccount(password: String) async throws {
        isLoading = true
        defer { isLoading = false }
        try await APIClient.shared.deleteAccount(password: password)
        clearSession()
    }

    func changePassword(current: String, new: String) async throws {
        try await APIClient.shared.changePassword(current: current, new: new)
    }

    // MARK: - Private
    private func clearSession() {
        user = nil
        // Session cookies are automatically cleared by URLSession when we logout
    }
}
