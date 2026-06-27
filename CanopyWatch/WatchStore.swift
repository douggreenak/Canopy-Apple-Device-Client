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

    private static let tokenKey = "authToken"

    var isLoggedIn: Bool { user != nil }

    init() {
        let saved = WKeychain.load(key: Self.tokenKey)
        WatchAPI.shared.token = saved
    }

    func restore() async {
        guard WatchAPI.shared.token != nil else { return }
        do {
            if let u = try await WatchAPI.shared.checkSession() { user = u; await loadAll() }
            else { logout() }
        } catch WAPIError.unauthorized { logout() } catch { }
    }

    func login(username: String, password: String) async {
        isLoading = true; errorMessage = nil
        defer { isLoading = false }
        do {
            let (token, u) = try await WatchAPI.shared.login(username: username, password: password)
            WatchAPI.shared.token = token
            WKeychain.save(token, key: Self.tokenKey)
            user = u
            await loadAll()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func logout() {
        WatchAPI.shared.token = nil
        WKeychain.delete(key: Self.tokenKey)
        user = nil; classes = []; homework = []; exams = []
    }

    func loadAll() async {
        isLoading = true; defer { isLoading = false }
        if let c = try? await WatchAPI.shared.getClasses() { classes = c }
        if let h = try? await WatchAPI.shared.getHomework() { homework = h }
        if let e = try? await WatchAPI.shared.getExams() { exams = e }
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
        }
    }

    private var isoToday: String {
        let f = DateFormatter(); f.dateFormat = "yyyy-MM-dd"; f.locale = Locale(identifier: "en_US_POSIX")
        return f.string(from: .now)
    }
}
