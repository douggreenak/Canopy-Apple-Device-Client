import Foundation
import Observation

// Port of web src/lib/powerschoolStatusStore.ts + powerschoolClient.ts.
//
// The server runs PowerSchool syncs in the background: POST /api/powerschool
// returns at once with `status: "running"`, and GET /api/powerschool/status
// carries progress and the final result. This store is the single app-wide
// poller for that endpoint, so any screen (Settings, Grades, the wizard's
// Done step, the save-status indicator) can show "syncing" correctly even
// when a sync was started elsewhere or by the daily cron.
@MainActor
@Observable
final class PowerSchoolSyncStore {
    static let shared = PowerSchoolSyncStore()

    private(set) var status: PowerSchoolStatus = .idle
    /// True while a client-side wait loop is active (any screen).
    private(set) var isWaiting = false
    /// Per-`finishedAt` dismissal of the login-failure banner (web sessionStorage).
    var dismissedLoginWarningFor: String?

    private var pollTask: Task<Void, Never>?
    private var subscribers = 0
    private var inFlight: Task<PowerSchoolStatus, Never>?

    private static let runningPollNs: UInt64 = 2_500_000_000
    private static let idlePollNs: UInt64   = 15_000_000_000
    private static let waitPollNs: UInt64   = 2_000_000_000
    private static let maxWaitPolls = 150

    var isRunning: Bool { status.isRunning }

    /// Shows the "PowerSchool rejected your password" banner?
    var showsLoginWarning: Bool {
        guard status.isLoginFailure else { return false }
        if let d = dismissedLoginWarningFor, d == (status.finishedAt ?? "") { return false }
        return true
    }

    func dismissLoginWarning() { dismissedLoginWarningFor = status.finishedAt ?? "" }

    // MARK: - Subscription-driven background polling
    func subscribe() {
        subscribers += 1
        if subscribers == 1 { startPolling() }
    }

    func unsubscribe() {
        subscribers = max(0, subscribers - 1)
        if subscribers == 0 { pollTask?.cancel(); pollTask = nil }
    }

    private func startPolling() {
        pollTask?.cancel()
        pollTask = Task { [weak self] in
            while !Task.isCancelled {
                guard let self else { return }
                _ = await self.fetchNow()
                let delay = self.status.isRunning ? Self.runningPollNs : Self.idlePollNs
                try? await Task.sleep(nanoseconds: delay)
            }
        }
    }

    /// Immediate poll, bypassing the cadence (web `pokePowerSchoolStatus`).
    func poke() {
        if subscribers > 0 { startPolling() } else { Task { _ = await fetchNow() } }
    }

    /// One-off fetch; concurrent callers share the same request.
    @discardableResult
    func fetchNow() async -> PowerSchoolStatus {
        if let inFlight { return await inFlight.value }
        let t = Task<PowerSchoolStatus, Never> { [weak self] in
            if let s = try? await APIClient.shared.getPowerSchoolStatus() {
                self?.status = s
            }
            return self?.status ?? .idle
        }
        inFlight = t
        let v = await t.value
        inFlight = nil
        return v
    }

    // MARK: - Wait loops (web waitForPowerSchoolSync / syncPowerSchoolAndWait)

    /// Polls until success/error or the budget runs out (then returns the
    /// still-running status; the server keeps going).
    func waitForSync(onTick: ((PowerSchoolStatus) -> Void)? = nil) async -> PowerSchoolStatus {
        isWaiting = true
        defer { isWaiting = false }
        for _ in 0..<Self.maxWaitPolls {
            let s = await fetchNow()
            onTick?(s)
            if s.isTerminal { return s }
            try? await Task.sleep(nanoseconds: Self.waitPollNs)
            if Task.isCancelled { break }
        }
        return PowerSchoolStatus(syncId: "", status: "running", startedAt: nil, finishedAt: nil, log: [], result: nil, error: nil)
    }

    /// Starts a sync (optionally with fresh credentials) and waits for it.
    /// Soft failures (missing credentials) come back as an `error` status.
    func syncAndWait(url: String? = nil, username: String? = nil, password: String? = nil,
                     onTick: ((PowerSchoolStatus) -> Void)? = nil) async throws -> PowerSchoolStatus {
        let kick = try await APIClient.shared.startPowerSchoolSync(url: url, username: username, password: password)
        if !kick.success {
            return PowerSchoolStatus(syncId: "", status: "error", startedAt: nil, finishedAt: nil,
                                     log: kick.log ?? [], result: nil, error: kick.error ?? "Sync failed to start.")
        }
        status = PowerSchoolStatus(syncId: kick.syncId ?? "", status: "running", startedAt: CanopyStore.isoFull.string(from: .now),
                                   finishedAt: nil, log: [], result: nil, error: nil)
        return await waitForSync(onTick: onTick)
    }

    /// Web copy for a terminal status in the Grades context.
    static func gradesMessage(for s: PowerSchoolStatus) -> String {
        switch s.status {
        case "success": return s.result?.gradesSummary ?? "Synced."
        case "error":
            if (s.error ?? "").contains("Missing PowerSchool credentials") {
                return "Save your PowerSchool login in Settings first, then sync from here."
            }
            return s.error ?? "Sync failed."
        default: return "Still syncing in the background — check back in a bit, or reload to see the latest status."
        }
    }
}
