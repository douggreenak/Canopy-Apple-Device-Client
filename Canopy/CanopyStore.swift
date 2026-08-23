import Foundation
import Observation

@MainActor
@Observable
final class CanopyStore {
    var classes: [SchoolClass] = []
    var homework: [Homework] = []
    var exams: [Exam] = []
    var tasks: [SchoolTask] = []
    var disruptions: [ScheduleDisruption] = []
    var settings = AppSettings()
    var gradeHistory: [GradeHistoryEntry] = []
    var syncLog: [SyncLogEntry] = []

    var isLoading = false
    var loadError: String?

    // MARK: - Load
    func loadAll() async {
        isLoading = true
        defer { isLoading = false }
        loadError = nil
        var failed: [String] = []
        if let c = try? await APIClient.shared.getClasses()        { classes = c } else { failed.append("classes") }
        if let h = try? await APIClient.shared.getHomework()       { homework = h } else { failed.append("homework") }
        if let e = try? await APIClient.shared.getExams()          { exams = e } else { failed.append("exams") }
        if let t = try? await APIClient.shared.getTasks()          { tasks = t } else { failed.append("tasks") }
        if let d = try? await APIClient.shared.getDisruptions()    { disruptions = d } else { failed.append("disruptions") }
        if let s = try? await APIClient.shared.getSettings()       { settings = s } else { failed.append("settings") }
        if let gh = try? await APIClient.shared.getGradeHistory()  { gradeHistory = gh } else { failed.append("grade history") }
        if let sl = try? await APIClient.shared.getSyncLog(limit: 200) { syncLog = sl } else { failed.append("sync log") }
        if !failed.isEmpty {
            loadError = "Couldn't load \(failed.joined(separator: ", ")). Pull to refresh to retry."
        }
    }

    // MARK: - Dashboard helpers
    func todaysClasses(for date: Date = .now) -> [SchoolClass] {
        let weekday = Calendar.current.component(.weekday, from: date) - 1
        return classes.filter { $0.days.contains(weekday) }.sorted { $0.period < $1.period }
    }

    func upcomingHomework(limit: Int = 5) -> [Homework] {
        let today = DateFormatter.iso.string(from: .now)
        return homework
            .filter { !$0.completed && $0.dueDate >= today && $0.source != "powerschool" }
            .sorted { $0.dueDate < $1.dueDate }
            .prefix(limit).map { $0 }
    }

    func upcomingExams(limit: Int = 3) -> [Exam] {
        let today = DateFormatter.iso.string(from: .now)
        return exams
            .filter { $0.date >= today }
            .sorted { $0.date < $1.date }
            .prefix(limit).map { $0 }
    }

    func pendingTasks(limit: Int = 5) -> [SchoolTask] {
        return tasks
            .filter { !$0.completed }
            .sorted { $0.priority.priorityOrder < $1.priority.priorityOrder }
            .prefix(limit).map { $0 }
    }

    var askTasks: [SchoolTask] { tasks.filter { !$0.completed && $0.category == "Ask" } }

    // MARK: - Schedule helpers
    func classes(for date: Date) -> [SchoolClass] {
        // Outside the configured semester, nothing meets (mirrors web
        // buildDaySchedule) — any disruption still shows via disruption(on:).
        let ds = DateFormatter.iso.string(from: date)
        if let start = settings.semesterStart, !start.isEmpty, ds < start { return [] }
        if let end = settings.semesterEnd, !end.isEmpty, ds > end { return [] }

        let weekday = Calendar.current.component(.weekday, from: date) - 1
        let dayKey = String(weekday)

        let dis = disruption(on: date)
        // A "1-6 Schedule" disruption runs every period in its overrides even if
        // the class doesn't normally meet this weekday (mirrors web buildDaySchedule).
        let oneToSixPeriods: Set<Int>? = dis?.type == "1_6"
            ? Set(dis!.periodOverrides.map(\.period)) : nil

        return classes.filter { $0.days.contains(weekday) || (oneToSixPeriods?.contains($0.period) ?? false) }.map { cls in
            // dayTimes override takes precedence
            var out = cls
            if let dt = cls.dayTimes?[dayKey] {
                out.startTime = dt.startTime
                out.endTime   = dt.endTime
            }
            return out
        }.sorted { $0.period < $1.period }
    }

    func disruption(on date: Date) -> ScheduleDisruption? {
        let ds = DateFormatter.iso.string(from: date)
        return disruptions.first { ds >= $0.date && ds <= ($0.endDate ?? $0.date) }
    }

    /// A class meeting on a date with disruption overrides/cancellations applied
    /// (mirrors web buildDaySchedule).
    struct DayEntry: Identifiable {
        let cls: SchoolClass
        let startTime: String
        let endTime: String
        let cancelled: Bool
        var id: String { cls.id }
    }

    func dayEntries(for date: Date) -> [DayEntry] {
        let base = classes(for: date)
        var entries: [DayEntry]
        if let dis = disruption(on: date) {
            entries = base.map { c in
                if let o = dis.periodOverrides.first(where: { $0.period == c.period }) {
                    return DayEntry(cls: c,
                                    startTime: o.cancelled ? c.startTime : o.startTime,
                                    endTime: o.cancelled ? c.endTime : o.endTime,
                                    cancelled: o.cancelled)
                }
                if dis.type == "no_school" {
                    return DayEntry(cls: c, startTime: c.startTime, endTime: c.endTime, cancelled: true)
                }
                return DayEntry(cls: c, startTime: c.startTime, endTime: c.endTime, cancelled: false)
            }
        } else {
            entries = base.map { DayEntry(cls: $0, startTime: $0.startTime, endTime: $0.endTime, cancelled: false) }
        }
        entries.sort { ScheduleEngine.timeToMinutes($0.startTime) < ScheduleEngine.timeToMinutes($1.startTime) }

        // A cancelled entry (e.g. an Extension period not meeting on a 1-6 day)
        // is shown crossed-out at its normal fallback time purely as information.
        // But when a disruption's override shifts a different, still-running
        // class into that same slot, the two blocks visually collide — drop the
        // cancelled one in that case (mirrors web buildDaySchedule).
        for i in stride(from: entries.count - 1, through: 0, by: -1) {
            let e = entries[i]
            guard e.cancelled else { continue }
            let es = ScheduleEngine.timeToMinutes(e.startTime)
            let ee = ScheduleEngine.timeToMinutes(e.endTime)
            let collidesWithActive = entries.enumerated().contains { j, other in
                j != i && !other.cancelled &&
                es < ScheduleEngine.timeToMinutes(other.endTime) &&
                ScheduleEngine.timeToMinutes(other.startTime) < ee
            }
            if collidesWithActive { entries.remove(at: i) }
        }
        return entries
    }

    func lunchTime(for date: Date) -> DayTime? {
        let weekday = Calendar.current.component(.weekday, from: date) - 1
        let key = String(weekday)
        return (settings.lunchTimes ?? AppSettings.defaultLunchTimes)[key]
    }

    /// The lunch block for a date, or nil if it shouldn't be shown: on a
    /// no_school day, or whenever it would visually overlap an active
    /// (non-cancelled) class that day (mirrors web buildDaySchedule's general
    /// lunch-overlap suppression).
    func visibleLunchTime(for date: Date) -> DayTime? {
        guard let lunch = lunchTime(for: date) else { return nil }
        if disruption(on: date)?.type == "no_school" { return nil }
        let ls = ScheduleEngine.timeToMinutes(lunch.startTime)
        let le = ScheduleEngine.timeToMinutes(lunch.endTime)
        let overlapsActive = dayEntries(for: date).contains { entry in
            !entry.cancelled &&
            ls < ScheduleEngine.timeToMinutes(entry.endTime) &&
            ScheduleEngine.timeToMinutes(entry.startTime) < le
        }
        return overlapsActive ? nil : lunch
    }

    // MARK: - Lookup
    func className(for id: String) -> String {
        classes.first { $0.id == id }?.name ?? "Unknown"
    }

    func schoolClass(_ id: String) -> SchoolClass? {
        classes.first { $0.id == id }
    }

    // MARK: - Grade velocity (delta vs 5+ days ago)
    func gradeVelocity(for classId: String) -> Double? {
        let classHist = gradeHistory
            .filter { $0.classId == classId && $0.gradePercent != nil }
            .sorted { $0.capturedAt > $1.capturedAt }
        guard let latest = classHist.first,
              let latestPct = latest.gradePercent,
              let latestDate = CanopyStore.parseISO(latest.capturedAt) else { return nil }
        let cutoff = latestDate.addingTimeInterval(-5 * 86400)
        guard let older = classHist.first(where: {
            guard let d = CanopyStore.parseISO($0.capturedAt) else { return false }
            return d <= cutoff
        }), let olderPct = older.gradePercent else { return nil }
        let delta = latestPct - olderPct
        return abs(delta) < 0.3 ? nil : delta   // matches web's VELOCITY_THRESHOLD (src/lib/grades.ts)
    }

    // MARK: - Completion stages (mirrors web src/lib/stages.ts)
    /// Whether `stageId` is the final stage in `stages` — the `completed` flag
    /// must always be derived this way wherever stage state changes, never set
    /// independently.
    func completedForStage(_ stages: [TaskStage], _ stageId: String?) -> Bool {
        guard let stageId, let last = stages.last else { return false }
        return last.id == stageId
    }

    func setHomeworkStage(_ hw: Homework, stageId: String?) async {
        var m = hw
        m.stageId = stageId
        m.completed = completedForStage(hw.stages ?? [], stageId)
        if (try? await APIClient.shared.updateHomework(m)) != nil,
           let i = homework.firstIndex(where: { $0.id == hw.id }) {
            homework[i] = m
        }
    }

    func setTaskStage(_ task: SchoolTask, stageId: String?) async {
        var m = task
        m.stageId = stageId
        m.completed = completedForStage(task.stages ?? [], stageId)
        if (try? await APIClient.shared.updateTask(m)) != nil,
           let i = tasks.firstIndex(where: { $0.id == task.id }) {
            tasks[i] = m
        }
    }

    // MARK: - Homework CRUD
    func toggleHomework(_ hw: Homework) async {
        // For a staged item, the checkbox/swipe toggle is a shortcut that jumps
        // straight to the last stage (done) or back to not-started — it never
        // flips `completed` independently of `stageId`.
        if let stages = hw.stages, !stages.isEmpty {
            await setHomeworkStage(hw, stageId: hw.completed ? nil : stages.last?.id)
            return
        }
        var m = hw; m.completed.toggle()
        if (try? await APIClient.shared.updateHomework(m)) != nil,
           let i = homework.firstIndex(where: { $0.id == hw.id }) {
            homework[i].completed = m.completed
        }
    }

    func saveHomework(_ hw: Homework, isNew: Bool) async throws {
        if isNew {
            try await APIClient.shared.createHomework(hw); homework.append(hw)
        } else {
            try await APIClient.shared.updateHomework(hw)
            if let i = homework.firstIndex(where: { $0.id == hw.id }) { homework[i] = hw }
        }
    }

    func deleteHomework(_ hw: Homework) async {
        if (try? await APIClient.shared.deleteHomework(id: hw.id)) != nil {
            homework.removeAll { $0.id == hw.id }
        }
    }

    // MARK: - Task CRUD
    func toggleTask(_ task: SchoolTask) async {
        if let stages = task.stages, !stages.isEmpty {
            await setTaskStage(task, stageId: task.completed ? nil : stages.last?.id)
            return
        }
        var m = task; m.completed.toggle()
        if (try? await APIClient.shared.updateTask(m)) != nil,
           let i = tasks.firstIndex(where: { $0.id == task.id }) {
            tasks[i].completed = m.completed
        }
    }

    func saveTask(_ task: SchoolTask, isNew: Bool) async throws {
        if isNew {
            try await APIClient.shared.createTask(task); tasks.append(task)
        } else {
            try await APIClient.shared.updateTask(task)
            if let i = tasks.firstIndex(where: { $0.id == task.id }) { tasks[i] = task }
        }
    }

    func deleteTask(_ task: SchoolTask) async {
        if (try? await APIClient.shared.deleteTask(id: task.id)) != nil {
            tasks.removeAll { $0.id == task.id }
        }
    }

    // MARK: - Class CRUD
    func saveClass(_ cls: SchoolClass, isNew: Bool) async throws {
        if isNew {
            try await APIClient.shared.createClass(cls); classes.append(cls)
        } else {
            try await APIClient.shared.updateClass(cls)
            if let i = classes.firstIndex(where: { $0.id == cls.id }) { classes[i] = cls }
        }
    }

    func deleteClass(_ cls: SchoolClass) async {
        if (try? await APIClient.shared.deleteClass(id: cls.id)) != nil {
            classes.removeAll { $0.id == cls.id }
        }
    }

    // MARK: - Exam CRUD
    func saveExam(_ exam: Exam, isNew: Bool) async throws {
        if isNew {
            try await APIClient.shared.createExam(exam); exams.append(exam)
        } else {
            try await APIClient.shared.updateExam(exam)
            if let i = exams.firstIndex(where: { $0.id == exam.id }) { exams[i] = exam }
        }
    }

    func deleteExam(_ exam: Exam) async {
        if (try? await APIClient.shared.deleteExam(id: exam.id)) != nil {
            exams.removeAll { $0.id == exam.id }
        }
    }

    // MARK: - Disruption CRUD
    func saveDisruption(_ d: ScheduleDisruption, isNew: Bool) async throws {
        if isNew {
            try await APIClient.shared.createDisruption(d); disruptions.append(d)
        } else {
            try await APIClient.shared.updateDisruption(d)
            if let i = disruptions.firstIndex(where: { $0.id == d.id }) { disruptions[i] = d }
        }
    }

    func deleteDisruption(_ d: ScheduleDisruption) async {
        if (try? await APIClient.shared.deleteDisruption(id: d.id)) != nil {
            disruptions.removeAll { $0.id == d.id }
        }
    }

    // MARK: - Settings Update
    func saveSettings(schoolName: String?, start: String?, end: String?) async throws {
        if let schoolName {
            try await APIClient.shared.saveSetting(key: "schoolName", value: schoolName)
            settings.schoolName = schoolName
        }
        if let start {
            try await APIClient.shared.saveSetting(key: "semesterStart", value: start)
            settings.semesterStart = start
        }
        if let end {
            try await APIClient.shared.saveSetting(key: "semesterEnd", value: end)
            settings.semesterEnd = end
        }
    }

    // MARK: - Extended settings
    func saveAppearance(theme: String?, accent: String?) async {
        if let theme {
            try? await APIClient.shared.saveSetting(key: "themeMode", value: theme)
            settings.themeMode = theme
        }
        if let accent {
            try? await APIClient.shared.saveSetting(key: "accentColor", value: accent)
            settings.accentColor = accent
        }
    }

    func saveTimezone(_ tz: String) async {
        try? await APIClient.shared.saveSetting(key: "timezone", value: tz)
        settings.timezone = tz
    }

    func saveLathropMode(_ on: Bool) async {
        try? await APIClient.shared.saveSetting(key: "lathropMode", value: on ? "true" : "false")
        settings.lathropMode = on ? "true" : "false"
    }

    func saveLunchTimes(_ times: [String: DayTime]) async throws {
        let json = String(data: try JSONEncoder().encode(times), encoding: .utf8) ?? "{}"
        try await APIClient.shared.saveSetting(key: "lunchTimes", value: json)
        settings.lunchTimes = times
    }

    func saveEarlyOut(_ map: [String: DayTime]) async throws {
        let json = String(data: try JSONEncoder().encode(map), encoding: .utf8) ?? "{}"
        try await APIClient.shared.saveSetting(key: "early_out_schedule", value: json)
        settings.earlyOutSchedule = json
    }

    /// Return the calendar feed token, generating + persisting one if absent.
    func ensureCalendarToken() async -> String {
        if let t = settings.calendarToken, !t.isEmpty { return t }
        return await regenerateCalendarToken()
    }

    /// Mint and persist a brand-new calendar feed token, invalidating the old
    /// link (anyone with the previous URL loses access).
    @discardableResult
    func regenerateCalendarToken() async -> String {
        let t = UUID().uuidString
        try? await APIClient.shared.saveSetting(key: "calendarToken", value: t)
        settings.calendarToken = t
        return t
    }

    // MARK: - PowerSchool sync
    var isSyncing = false
    var lastSyncLog: [String] = []
    /// Scraper-derived schedule guesses from the most recent sync, keyed by
    /// class id — consumed by ClassEditorSheet's Apply/Dismiss suggestion banner.
    var psMatrixSuggestions: [String: MatrixSuggestion] = [:]

    /// Run a sync; pass credentials for a one-off or nil to use the saved login.
    /// Refreshes synced data on success. Throws on transport/server (5xx) errors;
    /// soft failures arrive as a SyncResult with success == false and an error message.
    func syncPowerSchool(url: String? = nil, username: String? = nil, password: String? = nil) async throws -> SyncResult {
        isSyncing = true
        defer { isSyncing = false }
        let result = try await APIClient.shared.syncPowerSchool(url: url, username: username, password: password)
        lastSyncLog = result.log ?? []
        psMatrixSuggestions = result.matrixByClassId ?? [:]
        if result.success {
            if let c = try? await APIClient.shared.getClasses()        { classes = c }
            if let h = try? await APIClient.shared.getHomework()       { homework = h }
            if let gh = try? await APIClient.shared.getGradeHistory()  { gradeHistory = gh }
            if let sl = try? await APIClient.shared.getSyncLog(limit: 200) { syncLog = sl }
            let now = CanopyStore.isoFull.string(from: .now)
            try? await APIClient.shared.saveSetting(key: "lastSyncAt", value: now)
            settings.lastSyncAt = now

            // Re-link manually-created classes to newly-synced PowerSchool
            // classes when the sync surfaced schedule-matrix guesses.
            if let matrix = result.matrixByClassId, !matrix.isEmpty {
                if let migrated = try? await APIClient.shared.migratePowerSchool() {
                    let count = migrated.migrated ?? 0
                    lastSyncLog.append(count > 0
                        ? "Migration complete: \(count) class\(count == 1 ? "" : "es") linked."
                        : "Migration complete: no manual classes needed linking.")
                    if let c = try? await APIClient.shared.getClasses() { classes = c }
                }
            }
        }
        return result
    }

    // MARK: - Bulk delete
    func clearDoneHomework() async {
        let done = homework.filter { $0.completed && $0.source != "powerschool" }
        for hw in done {
            if (try? await APIClient.shared.deleteHomework(id: hw.id)) != nil {
                homework.removeAll { $0.id == hw.id }
            }
        }
    }

    func clearDoneTasks() async {
        let done = tasks.filter { $0.completed }
        for task in done {
            if (try? await APIClient.shared.deleteTask(id: task.id)) != nil {
                tasks.removeAll { $0.id == task.id }
            }
        }
    }
}

// MARK: - Shared ISO8601 formatters for timestamps
extension CanopyStore {
    static let isoFull: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f
    }()

    // Fallback for timestamps Postgres writes without fractional seconds.
    private static let isoNoFraction: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime]
        return f
    }()

    static func parseISO(_ s: String) -> Date? {
        isoFull.date(from: s) ?? isoNoFraction.date(from: s)
    }
}

// MARK: - Date formatter shared instance
extension DateFormatter {
    static let iso: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd"
        f.locale = Locale(identifier: "en_US_POSIX")
        return f
    }()

    static let displayDate: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "MMMM d"
        return f
    }()
}
