import Foundation
import Observation

@MainActor
@Observable
final class AuthStore {
    private(set) var user: User?
    private(set) var token: String?
    var isLoading = false
    var errorMessage: String?

    var isLoggedIn: Bool { user != nil }

    private static let tokenKey = "authToken"

    init() {
        let saved = KeychainHelper.load(for: Self.tokenKey)
        token = saved
        APIClient.shared.token = saved
    }

    // Called at app launch to restore a prior session.
    func checkSession() async {
        guard token != nil else { return }
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
            // Network unavailable — keep token, user will see an error on next data fetch
        }
    }

    @discardableResult
    func login(username: String, password: String) async throws -> User {
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }
        let resp = try await APIClient.shared.login(username: username, password: password)
        applySession(token: resp.token, user: resp.user)
        return resp.user
    }

    @discardableResult
    func register(username: String, password: String) async throws -> User {
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }
        let resp = try await APIClient.shared.register(username: username, password: password)
        applySession(token: resp.token, user: resp.user)
        return resp.user
    }

    func logout() async {
        isLoading = true
        defer { isLoading = false }
        try? await APIClient.shared.logout()
        clearSession()
    }

    func deleteAccount() async throws {
        isLoading = true
        defer { isLoading = false }
        try await APIClient.shared.deleteAccount()
        clearSession()
    }

    // MARK: - Private
    private func applySession(token: String, user: User) {
        self.token = token
        self.user = user
        APIClient.shared.token = token
        KeychainHelper.save(token, for: Self.tokenKey)
    }

    private func clearSession() {
        token = nil
        user = nil
        APIClient.shared.token = nil
        KeychainHelper.delete(for: Self.tokenKey)
    }
}
