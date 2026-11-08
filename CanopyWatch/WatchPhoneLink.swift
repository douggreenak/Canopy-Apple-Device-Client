import Foundation
import WatchConnectivity

// Receives the session + data the iPhone app pushes (see Canopy/WatchBridge.swift)
// and can ask the phone for a fresh push when it's reachable.
@MainActor
final class WatchPhoneLink: NSObject, WCSessionDelegate {
    static let shared = WatchPhoneLink()
    private weak var store: WatchStore?

    private override init() { super.init() }

    func attach(store: WatchStore) {
        self.store = store
        guard WCSession.isSupported() else { return }
        let session = WCSession.default
        session.delegate = self
        session.activate()
    }

    var isPhoneReachable: Bool {
        WCSession.isSupported() && WCSession.default.isReachable
    }

    /// Ask the phone to push its current session and data. Falls back to
    /// whatever context was delivered last if the phone isn't reachable.
    func requestSync() {
        guard WCSession.isSupported() else { return }
        let session = WCSession.default
        guard session.activationState == .activated else { return }
        if session.isReachable {
            session.sendMessage(["request": "sync"], replyHandler: { reply in
                Task { @MainActor in self.apply(reply) }
            }, errorHandler: { error in
                Task { @MainActor in
                    self.store?.linkMessage = "Couldn't reach iPhone: \(error.localizedDescription)"
                }
            })
        } else {
            apply(session.receivedApplicationContext)
            store?.linkMessage = "iPhone not reachable. Open Canopy on your iPhone, then try again."
        }
    }

    private func apply(_ context: [String: Any]) {
        guard !context.isEmpty else { return }
        store?.applyPhonePayload(context)
    }

    // MARK: - WCSessionDelegate

    nonisolated func session(_ session: WCSession, activationDidCompleteWith activationState: WCSessionActivationState, error: Error?) {
        let context = session.receivedApplicationContext
        Task { @MainActor in self.apply(context) }
    }

    nonisolated func session(_ session: WCSession, didReceiveApplicationContext applicationContext: [String: Any]) {
        Task { @MainActor in self.apply(applicationContext) }
    }

    nonisolated func sessionReachabilityDidChange(_ session: WCSession) {
        Task { @MainActor in
            self.store?.phoneReachable = session.isReachable
            // The phone just came within reach: pick up anything new.
            if session.isReachable, self.store?.isLoggedIn == false { self.requestSync() }
        }
    }
}
