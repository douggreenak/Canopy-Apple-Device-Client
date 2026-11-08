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
    var setupStatus: SetupStatus?
    var schoolAccounts: [SchoolAccountSummary] = []

    var isLoading = false
    var loadError: String?
    /// Last mutation error, for views that want to surface it (web snackbar).
    var lastMutationError: String?

    private var pollTask: Task<Void, Never>?

    // MARK: - Load
    func loadAll() async {
        isLoading = true
        defer { isLoading = false }
        loadError = nil
        var failed: [String] = []
        async let c = APIClient.shared.getClasses()
        async let h = APIClient.shared.getHomework()
        async let e = APIClient.shared.getExams()
        async let t = APIClient.shared.getTasks()
        async let d = APIClient.shared.getDisruptions()
        async let s = APIClient.shared.getSettings()
        async let gh = APIClient.shared.getGradeHistory()
        async let sl = APIClient.shared.getSyncLog(limit: 500)
        async let st = APIClient.shared.getSetupStatus()
        if let v = try? await c  { classes = v } else { failed.append("classes") }
        if let v = try? await h  { homework = v } else { failed.append("homework") }
        if let v = try? await e  { exams = v } else { failed.append("exams") }
        if let v = try? await t  { tasks = v } else { failed.append("tasks") }
        if let v = try? await d  { disruptions = v } else { failed.append("disruptions") }
        if let v = try? await s  { settings = v } else { failed.append("settings") }
        if let v = try? await gh { gradeHistory = v } else { failed.append("grade history") }
        if let v = try? await sl { syncLog = v } else { failed.append("sync log") }
        if let v = try? await st { setupStatus = v }
        if !failed.isEmpty {
            loadError = "Couldn't load \(failed.joined(separator: ", ")). Pull to refresh to retry."
        }
        startBackgroundRefresh()
    }

    /// Web polls every 60 s while visible; same here while the store is alive.
    func startBackgroundRefresh() {
        guard pollTask == nil else { return }
        pollTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 60_000_000_000)
                guard let self, !self.isLoading else { continue }
                await self.refreshSilently()
            }
        }
    }

    func stopBackgroundRefresh() { pollTask?.cancel(); pollTask = nil }

    /// Refetch everything without flipping `isLoading` (never discards what's on screen).
    func refreshSilently() async {
        if let v = try? await APIClient.shared.getClasses() { classes = v }
        if let v = try? await APIClient.shared.getHomework() { homework = v }
        if let v = try? await APIClient.shared.getExams() { exams = v }
        if let v = try? await APIClient.shared.getTasks() { tasks = v }
        if let v = try? await APIClient.shared.getDisruptions() { disruptions = v }
        if let v = try? await APIClient.shared.getSettings() { settings = v }
    }

    /// Clear everything on logout so the next user never sees stale data.
    func clearAll() {
        stopBackgroundRefresh()
        classes = []; homework = []; exams = []; tasks = []; disruptions = []
        settings = AppSettings(); gradeHistory = []; syncLog = []; setupStatus = nil; schoolAccounts = []
        loadError = nil; lastMutationError = nil
    }

    func refreshSetupStatus() async {
        if let v = try? await APIClient.shared.getSetupStatus() { setupStatus = v }
    }

    func refreshSettings() async {
        if let v = try? await APIClient.shared.getSettings() { settings = v }
    }

    // MARK: - Dashboard helpers

    /// Classes actually meeting (not cancelled) on a date — web "Classes Today".
    func activeClassCount(for date: Date) -> Int {
        dayEntries(for: date).filter { !$0.cancelled && !$0.isSynthetic }.count
    }

    /// Manual homework due today or later, soonest first (web `upcomingHomework`).
    func upcomingHomework(limit: Int = 5) -> [Homework] {
        let today = DateFormatter.iso.string(from: .now)
        return homework
            .filter { !$0.completed && $0.source == "manual" && $0.dueDate >= today }
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

    /// Pending tasks by due date, undated last (web Dashboard).
    func pendingTasks(limit: Int = 5) -> [SchoolTask] {
        tasks.filter { !$0.completed }
            .sorted { a, b in
                if a.dueDate.isEmpty && b.dueDate.isEmpty { return false }
                if a.dueDate.isEmpty { return false }
                if b.dueDate.isEmpty { return true }
                return a.dueDate < b.dueDate
            }
            .prefix(limit).map { $0 }
    }

    var askTasks: [SchoolTask] { tasks.filter { !$0.completed && $0.category == "Ask" } }

    /// Web "Due Today": manual homework + tasks due today → (done, total).
    func dueToday(_ date: Date = .now) -> (done: Int, total: Int) {
        let ds = DateFormatter.iso.string(from: date)
        let hw = homework.filter { $0.source == "manual" && $0.dueDate == ds }
        let tk = tasks.filter { $0.dueDate == ds }
        return (hw.filter(\.completed).count + tk.filter(\.completed).count, hw.count + tk.count)
    }

    // MARK: - Schedule helpers

    /// Classes in display order: server sort (sortOrder, then period, then name).
    var orderedClasses: [SchoolClass] {
        classes.sorted { a, b in
            switch (a.sortOrder, b.sortOrder) {
            case let (x?, y?) where x != y: return x < y
            case (.some, .none): return true
            case (.none, .some): return false
            default:
                if a.period != b.period { return a.period < b.period }
                return a.name.localizedCaseInsensitiveCompare(b.name) == .orderedAscending
            }
        }
    }

    /// The synthetic Lunch class (web `__lunch__`), days Mon–Fri with
    /// settings-driven dayTimes.
    var lunchClass: SchoolClass {
        var times = AppSettings.defaultLunchTimes
        for (k, v) in settings.lunchTimes ?? [:] { times[k] = v }
        return SchoolClass(id: ScheduleEngine.lunchClassId, name: "Lunch", teacher: "", room: "", color: "#9E9E9E",
                           period: 0, startTime: times["1"]?.startTime ?? "10:26", endTime: times["1"]?.endTime ?? "10:57",
                           days: [1, 2, 3, 4, 5], dayTimes: times, semester: "")
    }

    func disruption(on date: Date) -> ScheduleDisruption? {
        disruption(onISO: DateFormatter.iso.string(from: date))
    }

    func disruption(onISO ds: String) -> ScheduleDisruption? {
        disruptions.first { $0.covers(ds) }
    }

    /// A class meeting on a date with disruption overrides/cancellations
    /// applied (port of web buildDaySchedule, including the synthetic Lunch
    /// and Assembly entries).
    struct DayEntry: Identifiable, Equatable {
        let cls: SchoolClass
        let startTime: String
        let endTime: String
        let cancelled: Bool
        var id: String { cls.id }
        var isLunch: Bool { cls.id == ScheduleEngine.lunchClassId }
        var isAssembly: Bool { cls.id == ScheduleEngine.assemblyClassId }
        var isSynthetic: Bool { isLunch || isAssembly }
        /// Entry time differs from the class's normal time for this weekday.
        func isShifted(weekday: Int) -> Bool {
            if cancelled { return false }
            let ns = cls.dayTimes?[String(weekday)]?.startTime ?? cls.startTime
            let ne = cls.dayTimes?[String(weekday)]?.endTime ?? cls.endTime
            return startTime != ns || endTime != ne
        }
    }

    func dayEntries(for date: Date) -> [DayEntry] {
        dayEntries(forISO: DateFormatter.iso.string(from: date))
    }

    func dayEntries(forISO ds: String) -> [DayEntry] {
        guard let date = ds.asDate else { return [] }
        let dayOfWeek = Calendar.current.component(.weekday, from: date) - 1
        let dis = disruption(onISO: ds)

        let oneToSix: Set<Int>? = dis?.type == "1_6" ? Set(dis!.periodOverrides.map(\.period)) : nil
        let scheduleDow: Int = (dis?.type == "day_swap" && dis?.sourceDayOfWeek != nil) ? dis!.sourceDayOfWeek! : dayOfWeek
        let dowKey = String(scheduleDow)

        let all = classes + [lunchClass]
        let dayClasses = all.filter { $0.days.contains(scheduleDow) || (oneToSix?.contains($0.period) ?? false) }

        var entries: [DayEntry] = dayClasses.map { c in
            let normalStart = c.dayTimes?[dowKey]?.startTime.nonEmpty ?? c.startTime
            let normalEnd = c.dayTimes?[dowKey]?.endTime.nonEmpty ?? c.endTime
            if let dis {
                if let o = dis.periodOverrides.first(where: { $0.period == c.period }) {
                    return DayEntry(cls: c, startTime: o.cancelled ? normalStart : o.startTime,
                                    endTime: o.cancelled ? normalEnd : o.endTime, cancelled: o.cancelled)
                }
                if dis.type == "no_school" {
                    return DayEntry(cls: c, startTime: normalStart, endTime: normalEnd, cancelled: true)
                }
            }
            return DayEntry(cls: c, startTime: normalStart, endTime: normalEnd, cancelled: false)
        }

        if let dis, dis.type == "assembly",
           let o = dis.periodOverrides.first(where: { $0.period == ScheduleEngine.assemblyPeriod }), !o.cancelled {
            let asm = SchoolClass(id: ScheduleEngine.assemblyClassId, name: dis.label.isEmpty ? "Assembly" : dis.label,
                                  teacher: "", room: "", color: "#7BAAF7", period: ScheduleEngine.assemblyPeriod,
                                  startTime: o.startTime, endTime: o.endTime, days: [dayOfWeek], semester: "")
            entries.append(DayEntry(cls: asm, startTime: o.startTime, endTime: o.endTime, cancelled: false))
        }

        let tm = ScheduleEngine.timeToMinutes
        entries.sort { tm($0.startTime) < tm($1.startTime) }

        // Drop Lunch when it overlaps a real, active class.
        if let li = entries.firstIndex(where: { $0.isLunch }) {
            let l = entries[li]
            let ls = tm(l.startTime), le = tm(l.endTime)
            let overlaps = entries.enumerated().contains { i, e in
                i != li && !e.isLunch && !e.cancelled && ls < tm(e.endTime) && tm(e.startTime) < le
            }
            if overlaps { entries.remove(at: li) }
        }

        // Drop a cancelled entry that collides with an active one.
        for i in stride(from: entries.count - 1, through: 0, by: -1) {
            let e = entries[i]
            guard e.cancelled else { continue }
            let es = tm(e.startTime), ee = tm(e.endTime)
            let collides = entries.enumerated().contains { j, o in
                j != i && !o.cancelled && es < tm(o.endTime) && tm(o.startTime) < ee
            }
            if collides { entries.remove(at: i) }
        }
        return entries
    }

    /// Real (non-synthetic) classes meeting on a date, with times resolved.
    func classes(for date: Date) -> [SchoolClass] {
        dayEntries(for: date).filter { !$0.isSynthetic }.map { e in
            var c = e.cls; c.startTime = e.startTime; c.endTime = e.endTime; return c
        }
    }

    /// `classId::date` set of cancelled class instances (web Tasks page "Class cancelled" chip).
    func cancelledKeys(forDates dates: Set<String>) -> Set<String> {
        var out = Set<String>()
        for ds in dates {
            for e in dayEntries(forISO: ds) where e.cancelled && !e.isSynthetic {
                out.insert("\(e.cls.id)::\(ds)")
            }
        }
        return out
    }

    func lunchTime(for date: Date) -> DayTime? {
        let weekday = Calendar.current.component(.weekday, from: date) - 1
        return (settings.lunchTimes ?? AppSettings.defaultLunchTimes)[String(weekday)]
    }

    // MARK: - Lookup
    func className(for id: String) -> String {
        classes.first { $0.id == id }?.name ?? "Unknown"
    }

    func schoolClass(_ id: String) -> SchoolClass? {
        classes.first { $0.id == id }
    }

    // MARK: - Grade velocity (web: recent vs first snapshot ≥5 days before NOW)
    func gradeVelocity(for classId: String) -> Double? {
        let hist = gradeHistory.filter { $0.classId == classId }.sorted { $0.capturedAt > $1.capturedAt }
        guard let recent = hist.first, let recentPct = recent.gradePercent else { return nil }
        let cutoff = Date.now.addingTimeInterval(-5 * 86400)
        guard let older = hist.first(where: { e in
            guard e.id != recent.id, let d = CanopyStore.parseISO(e.capturedAt) else { return false }
            return d <= cutoff
        }), let olderPct = older.gradePercent else { return nil }
        let delta = recentPct - olderPct
        return abs(delta) < 0.3 ? nil : delta
    }

    // MARK: - Completion stages
    func completedForStage(_ stages: [TaskStage], _ stageId: String?) -> Bool {
        guard let stageId, let last = stages.last else { return false }
        return last.id == stageId
    }

    func setHomeworkStage(_ hw: Homework, stageId: String?) async {
        var m = hw
        m.stageId = stageId
        m.completed = completedForStage(hw.stages ?? [], stageId)
        if let i = homework.firstIndex(where: { $0.id == hw.id }) { homework[i] = m }
        do { try await APIClient.shared.updateHomework(m) }
        catch { if let i = homework.firstIndex(where: { $0.id == hw.id }) { homework[i] = hw }; lastMutationError = error.localizedDescription }
    }

    func setTaskStage(_ task: SchoolTask, stageId: String?) async {
        var m = task
        m.stageId = stageId
        m.completed = completedForStage(task.stages ?? [], stageId)
        if let i = tasks.firstIndex(where: { $0.id == task.id }) { tasks[i] = m }
        do { try await APIClient.shared.updateTask(m) }
        catch { if let i = tasks.firstIndex(where: { $0.id == task.id }) { tasks[i] = task }; lastMutationError = error.localizedDescription }
    }

    // MARK: - Homework CRUD (optimistic, with rollback)
    func toggleHomework(_ hw: Homework) async {
        if let stages = hw.stages, !stages.isEmpty {
            await setHomeworkStage(hw, stageId: hw.completed ? nil : stages.last?.id)
            return
        }
        var m = hw; m.completed.toggle()
        if let i = homework.firstIndex(where: { $0.id == hw.id }) { homework[i] = m }
        do { try await APIClient.shared.updateHomework(m) }
        catch { if let i = homework.firstIndex(where: { $0.id == hw.id }) { homework[i] = hw }; lastMutationError = error.localizedDescription }
    }

    func saveHomework(_ hw: Homework, isNew: Bool) async throws {
        if isNew {
            homework.insert(hw, at: 0)
            do { try await APIClient.shared.createHomework(hw) }
            catch { homework.removeAll { $0.id == hw.id }; throw error }
        } else {
            let prev = homework.first { $0.id == hw.id }
            if let i = homework.firstIndex(where: { $0.id == hw.id }) { homework[i] = hw }
            do { try await APIClient.shared.updateHomework(hw) }
            catch { if let prev, let i = homework.firstIndex(where: { $0.id == hw.id }) { homework[i] = prev }; throw error }
        }
        if let s = hw.stages, !s.isEmpty { StageTemplate.save(s) }
    }

    func deleteHomework(_ hw: Homework) async {
        homework.removeAll { $0.id == hw.id }
        do { try await APIClient.shared.deleteHomework(id: hw.id) }
        catch { homework.append(hw); lastMutationError = error.localizedDescription }
    }

    // MARK: - Task CRUD
    func toggleTask(_ task: SchoolTask) async {
        if let stages = task.stages, !stages.isEmpty {
            await setTaskStage(task, stageId: task.completed ? nil : stages.last?.id)
            return
        }
        var m = task; m.completed.toggle()
        if let i = tasks.firstIndex(where: { $0.id == task.id }) { tasks[i] = m }
        do { try await APIClient.shared.updateTask(m) }
        catch { if let i = tasks.firstIndex(where: { $0.id == task.id }) { tasks[i] = task }; lastMutationError = error.localizedDescription }
    }

    func saveTask(_ task: SchoolTask, isNew: Bool) async throws {
        if isNew {
            tasks.insert(task, at: 0)
            do { try await APIClient.shared.createTask(task) }
            catch { tasks.removeAll { $0.id == task.id }; throw error }
        } else {
            let prev = tasks.first { $0.id == task.id }
            if let i = tasks.firstIndex(where: { $0.id == task.id }) { tasks[i] = task }
            do { try await APIClient.shared.updateTask(task) }
            catch { if let prev, let i = tasks.firstIndex(where: { $0.id == task.id }) { tasks[i] = prev }; throw error }
        }
        if let s = task.stages, !s.isEmpty { StageTemplate.save(s) }
    }

    func deleteTask(_ task: SchoolTask) async {
        tasks.removeAll { $0.id == task.id }
        do { try await APIClient.shared.deleteTask(id: task.id) }
        catch { tasks.append(task); lastMutationError = error.localizedDescription }
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

    func deleteClass(_ cls: SchoolClass) async throws {
        classes.removeAll { $0.id == cls.id }
        do { try await APIClient.shared.deleteClass(id: cls.id) }
        catch { classes.append(cls); throw error }
    }

    /// Persist a new display order (full id list). Rolls back on failure.
    func reorderClasses(_ ordered: [SchoolClass]) async throws {
        let prev = classes
        for (i, c) in ordered.enumerated() {
            if let idx = classes.firstIndex(where: { $0.id == c.id }) { classes[idx].sortOrder = i }
        }
        do { try await APIClient.shared.reorderClasses(ordered.map(\.id)) }
        catch { classes = prev; throw error }
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
        exams.removeAll { $0.id == exam.id }
        do { try await APIClient.shared.deleteExam(id: exam.id) }
        catch { exams.append(exam); lastMutationError = error.localizedDescription }
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
        disruptions.removeAll { $0.id == d.id }
        do { try await APIClient.shared.deleteDisruption(id: d.id) }
        catch { disruptions.append(d); lastMutationError = error.localizedDescription }
    }

    // MARK: - Settings
    func saveSchoolInfo(schoolName: String?, timezone: String?) async throws {
        var batch: [String: String] = [:]
        if let schoolName { batch["schoolName"] = schoolName }
        if let timezone { batch["timezone"] = timezone }
        guard !batch.isEmpty else { return }
        try await APIClient.shared.saveSettingsBatch(batch)
        if let schoolName { settings.schoolName = schoolName }
        if let timezone { settings.timezone = timezone }
    }

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

    /// Web `saveLathropMode`: save the flag; when turning ON, fill an empty
    /// early-out template and apply the weekly bell schedule to all classes.
    /// Returns the web snackbar message (nil when nothing was applied).
    @discardableResult
    func saveLathropMode(_ on: Bool) async -> String? {
        try? await APIClient.shared.saveSetting(key: "lathropMode", value: on ? "true" : "false")
        settings.lathropMode = on ? "true" : "false"
        guard on else { return nil }
        if settings.earlyOutTemplate == nil {
            let tpl = ScheduleEngine.buildLathropEarlyOutTemplate(classes: classes)
            try? await saveEarlyOut(Dictionary(uniqueKeysWithValues: tpl.map { (String($0.key), $0.value) }))
        }
        if !classes.isEmpty { return await applyLathropSchedule() }
        return nil
    }

    /// Apply the full weekly Lathrop template to every matching class.
    func applyLathropSchedule() async -> String {
        let result = ScheduleEngine.applyLathropWeekSchedule(classes: classes)
        for updated in result.updatedClasses {
            try? await saveClass(updated, isNew: false)
        }
        if result.skippedCount > 0 {
            return "Lathrop bell schedule applied to \(result.appliedCount) class\(result.appliedCount == 1 ? "" : "es"). \(result.skippedCount) skipped (no period 1-6 or Extension)."
        }
        return "Lathrop bell schedule applied."
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

    /// Scheduled daily sync toggle (web `powerschoolAutoSync`).
    func saveAutoSync(_ enabled: Bool) async throws {
        struct V: Encodable { let enabled: Bool }
        try await APIClient.shared.saveSetting(key: "powerschoolAutoSync", value: V(enabled: enabled))
        settings.powerschoolAutoSync = "{\"enabled\":\(enabled)}"
    }

    /// Return the calendar feed token, generating + persisting one if absent.
    func ensureCalendarToken() async -> String {
        if let t = settings.calendarToken, !t.isEmpty { return t }
        return await regenerateCalendarToken()
    }

    @discardableResult
    func regenerateCalendarToken() async -> String {
        let t = UUID().uuidString.lowercased()
        try? await APIClient.shared.saveSetting(key: "calendarToken", value: t)
        settings.calendarToken = t
        return t
    }

    // MARK: - PowerSchool sync
    var isSyncing: Bool { PowerSchoolSyncStore.shared.isRunning || PowerSchoolSyncStore.shared.isWaiting }
    var lastSyncLog: [String] = []
    /// Scraper-derived schedule guesses from the most recent sync, keyed by class id.
    var psMatrixSuggestions: [String: MatrixSuggestion] = [:]

    /// Start a sync and wait for its terminal status, then refetch synced
    /// data and run the post-sync steps the web does (migrate, Lathrop).
    /// Pass credentials for a one-off, or nil to use the saved login.
    func syncPowerSchool(url: String? = nil, username: String? = nil, password: String? = nil) async throws -> PowerSchoolStatus {
        let status = try await PowerSchoolSyncStore.shared.syncAndWait(url: url, username: username, password: password)
        await handleSyncOutcome(status)
        return status
    }

    /// Resume watching a sync already in flight (started elsewhere or by cron).
    func resumeSyncIfRunning() async -> PowerSchoolStatus? {
        let s = await PowerSchoolSyncStore.shared.fetchNow()
        guard s.isRunning else { return nil }
        let final = await PowerSchoolSyncStore.shared.waitForSync()
        await handleSyncOutcome(final)
        return final
    }

    /// Web `handleSyncOutcome`: refetch, migrate linked classes, apply Lathrop.
    func handleSyncOutcome(_ status: PowerSchoolStatus) async {
        lastSyncLog = status.log
        guard status.status == "success" else { return }
        psMatrixSuggestions = status.result?.matrixByClassId ?? [:]
        if let c = try? await APIClient.shared.getClasses()        { classes = c }
        if let h = try? await APIClient.shared.getHomework()       { homework = h }
        if let gh = try? await APIClient.shared.getGradeHistory()  { gradeHistory = gh }
        if let sl = try? await APIClient.shared.getSyncLog(limit: 500) { syncLog = sl }
        await refreshSettings()
        await refreshSetupStatus()

        if let matrix = status.result?.matrixByClassId, !matrix.isEmpty {
            if let migrated = try? await APIClient.shared.migratePowerSchool() {
                let count = migrated.migrated ?? 0
                lastSyncLog.append(count > 0
                    ? "Migration complete: \(count) class\(count == 1 ? "" : "es") linked."
                    : "Migration complete: no manual classes needed linking.")
                if let c = try? await APIClient.shared.getClasses() { classes = c }
            }
        }
        if settings.lathropEnabled, !classes.isEmpty {
            let msg = await applyLathropSchedule()
            lastSyncLog.append(msg)
        }
    }

    // MARK: - Other schools
    func loadSchoolAccounts() async {
        if let v = try? await APIClient.shared.getSchoolAccounts() { schoolAccounts = v }
    }

    // MARK: - Bulk delete (web batch DELETE ?ids=)
    func clearDone() async throws -> Int {
        let hw = homework.filter { $0.completed && $0.source != "powerschool" }
        let tk = tasks.filter { $0.completed }
        let prevHw = homework, prevTk = tasks
        homework.removeAll { h in hw.contains { $0.id == h.id } }
        tasks.removeAll { t in tk.contains { $0.id == t.id } }
        do {
            async let a: Void = APIClient.shared.deleteHomeworkBatch(ids: hw.map(\.id))
            async let b: Void = APIClient.shared.deleteTasksBatch(ids: tk.map(\.id))
            _ = try await (a, b)
        } catch {
            homework = prevHw; tasks = prevTk
            throw error
        }
        return hw.count + tk.count
    }
}

// MARK: - Shared ISO8601 formatters for timestamps
extension CanopyStore {
    static let isoFull: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f
    }()

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

    static let monthDay: DateFormatter = {
        let f = DateFormatter(); f.dateFormat = "MMM d"; return f
    }()

    static let monthDayYear: DateFormatter = {
        let f = DateFormatter(); f.dateFormat = "MMM d, yyyy"; return f
    }()

    static let weekdayMonthDay: DateFormatter = {
        let f = DateFormatter(); f.dateFormat = "EEEE, MMM d"; return f
    }()

    static let fullDate: DateFormatter = {
        let f = DateFormatter(); f.dateFormat = "EEEE, MMMM d, yyyy"; return f
    }()
}

extension String {
    var nonEmpty: String? { isEmpty ? nil : self }
}
