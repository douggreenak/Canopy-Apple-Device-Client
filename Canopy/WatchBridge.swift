#if os(iOS) && canImport(WatchConnectivity)
import Foundation
import Observation
import WatchConnectivity

// The watch app never signs in on its own: the iPhone is the source of
// truth. Whenever the phone's session or data changes, this bridge pushes
// the session token (the server accepts it as a bearer token), the user,
// the base URL, and a compact snapshot of classes / homework / exams to
// the paired watch via WatchConnectivity's application context, which is
// delivered even if the watch app isn't running. The watch also asks for
// a push on demand with a "sync" message.
@MainActor
final class WatchBridge: NSObject, WCSessionDelegate {
    static let shared = WatchBridge()

    private weak var store: CanopyStore?
    private weak var auth: AuthStore?
    private var pending: Task<Void, Never>?

    /// Session cookie name on the server (web `SESSION_COOKIE`).
    private static let sessionCookie = "sp-session"

    private override init() { super.init() }

    /// Called once at launch. Activates the session and starts observing
    /// the stores so every login / logout / data change is forwarded.
    func attach(store: CanopyStore, auth: AuthStore) {
        self.store = store
        self.auth = auth
        guard WCSession.isSupported() else { return }
        let session = WCSession.default
        session.delegate = self
        session.activate()
        observe()
    }

    // MARK: - Observation

    /// Re-arms itself after every change (withObservationTracking fires once).
    private func observe() {
        withObservationTracking {
            guard let store, let auth else { return }
            _ = auth.user
            _ = store.classes
            _ = store.homework
            _ = store.exams
        } onChange: {
            Task { @MainActor in
                self.scheduleSync()
                self.observe()
            }
        }
    }

    /// Debounced push so a burst of edits becomes one transfer.
    func scheduleSync() {
        pending?.cancel()
        pending = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(400))
            guard !Task.isCancelled else { return }
            self?.pushNow()
        }
    }

    func pushNow() {
        guard WCSession.isSupported() else { return }
        let session = WCSession.default
        guard session.activationState == .activated, session.isPaired, session.isWatchAppInstalled else { return }
        do {
            try session.updateApplicationContext(payload())
        } catch {
            NSLog("Canopy watch bridge: context update failed: %@", error.localizedDescription)
        }
    }

    // MARK: - Payload

    private func payload() -> [String: Any] {
        var p: [String: Any] = ["sentAt": Date().timeIntervalSince1970]
        guard let user = auth?.user, let token = sessionToken() else { return p }
        p["auth"] = [
            "token": token,
            "userId": user.id,
            "username": user.username,
            "role": user.role,
            "baseURL": APIClient.shared.baseURL,
        ]
        if let store, let data = try? JSONEncoder().encode(WatchSnapshot(store: store)) {
            p["snapshot"] = data
        }
        return p
    }

    private func sessionToken() -> String? {
        guard let url = URL(string: APIClient.shared.baseURL) else { return nil }
        return HTTPCookieStorage.shared.cookies(for: url)?
            .first { $0.name == Self.sessionCookie }?.value
    }

    // MARK: - WCSessionDelegate

    nonisolated func session(_ session: WCSession, activationDidCompleteWith activationState: WCSessionActivationState, error: Error?) {
        Task { @MainActor in self.pushNow() }
    }

    nonisolated func sessionDidBecomeInactive(_ session: WCSession) {}

    nonisolated func sessionDidDeactivate(_ session: WCSession) {
        // Required for watch switching: reactivate for the new watch.
        session.activate()
    }

    nonisolated func sessionWatchStateDidChange(_ session: WCSession) {
        Task { @MainActor in self.pushNow() }
    }

    nonisolated func sessionReachabilityDidChange(_ session: WCSession) {
        Task { @MainActor in self.pushNow() }
    }

    nonisolated func session(_ session: WCSession, didReceiveMessage message: [String: Any], replyHandler: @escaping ([String: Any]) -> Void) {
        Task { @MainActor in
            if message["request"] as? String == "sync" {
                replyHandler(self.payload())
            } else {
                replyHandler([:])
            }
        }
    }

    nonisolated func session(_ session: WCSession, didReceiveMessage message: [String: Any]) {
        Task { @MainActor in
            if message["request"] as? String == "sync" { self.pushNow() }
        }
    }
}

/// What the watch shows offline: the class list (with grades), personal
/// homework and tasks still to do, PowerSchool assignments coming up that
/// have no score yet, and upcoming exams. Kept small so it fits an
/// application-context transfer.
struct WatchSnapshot: Encodable {
    let classes: [SchoolClass]
    let homework: [Homework]
    let tasks: [SchoolTask]
    let exams: [Exam]
    let generatedAt: Double

    @MainActor
    init(store: CanopyStore) {
        let today = DateFormatter.iso.string(from: .now)
        classes = store.orderedClasses
        let manual = store.homework
            .filter { !$0.completed && $0.source != "powerschool" && ($0.dueDate.isEmpty || $0.dueDate >= today) }
            .sorted { $0.dueDate < $1.dueDate }
            .prefix(40)
        let assignments = store.homework
            .filter { $0.source == "powerschool" && !$0.isGraded && $0.dueDate >= today }
            .sorted { $0.dueDate < $1.dueDate }
            .prefix(40)
        homework = Array(manual) + Array(assignments)
        tasks = Array(store.tasks
            .filter { !$0.completed && ($0.dueDate.isEmpty || $0.dueDate >= today) }
            .sorted { $0.dueDate < $1.dueDate }
            .prefix(40))
        exams = Array(store.exams
            .filter { $0.date >= today }
            .sorted { $0.date < $1.date }
            .prefix(30))
        generatedAt = Date().timeIntervalSince1970
    }
}
#endif
