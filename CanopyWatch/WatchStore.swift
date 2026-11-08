import Foundation
import Observation

@MainActor
@Observable
final class WatchStore {
    var user: WUser?
    var classes: [WClass] = []
    var homework: [WHomework] = []
    var exams: [WExam] = []
    var isLoading = false
    var errorMessage: String?
    /// Status line for the pairing screen ("Synced from iPhone just now", errors).
    var linkMessage: String?
    var phoneReachable = false
    var lastPhoneSync: Date?

    private static let tokenKey = "authToken"
    private static let userKey = "watchUser"
    private static let snapshotKey = "watchSnapshot"
    private static let baseURLKey = "watchBaseURL"
    private static let syncedAtKey = "watchSyncedAt"

    var isLoggedIn: Bool { user != nil }

    init() {
        WatchAPI.shared.token = WKeychain.load(key: Self.tokenKey)
        if let s = UserDefaults.standard.string(forKey: Self.baseURLKey), !s.isEmpty { WatchAPI.shared.baseURL = s }
    }

    /// Launch: show what the phone sent last (works offline), then refresh.
    func restore() async {
        let d = UserDefaults.standard
        if let data = d.data(forKey: Self.userKey), let u = try? JSONDecoder().decode(WUser.self, from: data) {
            user = u
        }
        if let data = d.data(forKey: Self.snapshotKey) { applySnapshot(data) }
        let t = d.double(forKey: Self.syncedAtKey)
        if t > 0 { lastPhoneSync = Date(timeIntervalSince1970: t) }
        guard WatchAPI.shared.token != nil, user != nil else { return }
        await loadAll()
    }

    // MARK: - Phone hand-off (see WatchPhoneLink / phone-side WatchBridge)

    private struct Snapshot: Decodable {
        var classes: [WClass]
        var homework: [WHomework]
        var exams: [WExam]
    }

    func applyPhonePayload(_ payload: [String: Any]) {
        let d = UserDefaults.standard
        if let auth = payload["auth"] as? [String: Any],
           let token = auth["token"] as? String, !token.isEmpty,
           let id = auth["userId"] as? String,
           let username = auth["username"] as? String {
            if let base = auth["baseURL"] as? String, !base.isEmpty {
                WatchAPI.shared.baseURL = base
                d.set(base, forKey: Self.baseURLKey)
            }
            WatchAPI.shared.token = token
            WKeychain.save(token, key: Self.tokenKey)
            let u = WUser(id: id, username: username)
            user = u
            if let data = try? JSONEncoder().encode(u) { d.set(data, forKey: Self.userKey) }
            if let data = payload["snapshot"] as? Data {
                applySnapshot(data)
                d.set(data, forKey: Self.snapshotKey)
            }
            lastPhoneSync = .now
            d.set(lastPhoneSync!.timeIntervalSince1970, forKey: Self.syncedAtKey)
            linkMessage = nil
            errorMessage = nil
            Task { await loadAll() }
        } else if payload["sentAt"] != nil {
            // The phone signed out (or has no session): follow it.
            clearLocal()
            linkMessage = "Signed out on iPhone."
        }
    }

    private func applySnapshot(_ data: Data) {
        guard let s = try? JSONDecoder().decode(Snapshot.self, from: data) else { return }
        classes = s.classes
        homework = s.homework
        exams = s.exams
    }

    /// Forget everything on the watch. The phone is the only way back in.
    func clearLocal() {
        WatchAPI.shared.token = nil
        WKeychain.delete(key: Self.tokenKey)
        let d = UserDefaults.standard
        d.removeObject(forKey: Self.userKey)
        d.removeObject(forKey: Self.snapshotKey)
        d.removeObject(forKey: Self.syncedAtKey)
        user = nil; classes = []; homework = []; exams = []
        lastPhoneSync = nil
    }

    /// Live refresh straight from the server with the forwarded token.
    /// Keeps the phone's snapshot if the network or session is unavailable.
    func loadAll() async {
        guard WatchAPI.shared.token != nil else { return }
        isLoading = true; defer { isLoading = false }
        do {
            let c = try await WatchAPI.shared.getClasses()
            let h = try await WatchAPI.shared.getHomework()
            let e = try await WatchAPI.shared.getExams()
            classes = c; homework = h; exams = e
            errorMessage = nil
        } catch WAPIError.unauthorized {
            // Token expired: ask the phone for a fresh one rather than dropping the UI.
            errorMessage = "Session expired — syncing from iPhone…"
            WatchPhoneLink.shared.requestSync()
        } catch {
            errorMessage = nil   // offline: the snapshot stays on screen
        }
    }

    // Derived
    func todaysClasses(for date: Date = .now) -> [WClass] {
        let weekday = Calendar.current.component(.weekday, from: date) - 1
        return classes.filter { $0.days.contains(weekday) }.sorted { $0.period < $1.period }
            .map { c in
                var out = c
                if let dt = c.dayTimes?[String(weekday)] { out.startTime = dt.startTime; out.endTime = dt.endTime }
                return out
            }
    }

    func upcomingHomework(limit: Int = 20) -> [WHomework] {
        let today = isoToday
        return homework
            .filter { !$0.completed && $0.dueDate >= today && $0.source != "powerschool" }
            .sorted { $0.dueDate < $1.dueDate }
            .prefix(limit).map { $0 }
    }

    func upcomingExams(limit: Int = 10) -> [WExam] {
        let today = isoToday
        return exams.filter { $0.date >= today }.sorted { $0.date < $1.date }.prefix(limit).map { $0 }
    }

    var gradedClasses: [WClass] {
        classes.filter { $0.grade != nil || $0.gradePercent != nil }
            .sorted { ($0.gradePercent ?? 0) > ($1.gradePercent ?? 0) }
    }

    func className(_ id: String) -> String { classes.first { $0.id == id }?.name ?? "" }
    func classColor(_ id: String) -> String { classes.first { $0.id == id }?.color ?? "#888888" }

    func toggle(_ hw: WHomework) async {
        var m = hw; m.completed.toggle()
        if (try? await WatchAPI.shared.updateHomework(m)) != nil,
           let i = homework.firstIndex(where: { $0.id == hw.id }) {
            homework[i].completed = m.completed
        } else {
            errorMessage = "Couldn't update — check your connection."
        }
    }

    private var isoToday: String {
        let f = DateFormatter(); f.dateFormat = "yyyy-MM-dd"; f.locale = Locale(identifier: "en_US_POSIX")
        return f.string(from: .now)
    }
}
