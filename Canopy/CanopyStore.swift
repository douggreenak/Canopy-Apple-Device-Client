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

    var isLoading = false
    var loadError: String?

    // MARK: - Load
    func loadAll() async {
        isLoading = true
        defer { isLoading = false }
        loadError = nil
        if let c = try? await APIClient.shared.getClasses()     { classes = c }
        if let h = try? await APIClient.shared.getHomework()    { homework = h }
        if let e = try? await APIClient.shared.getExams()       { exams = e }
        if let t = try? await APIClient.shared.getTasks()       { tasks = t }
        if let d = try? await APIClient.shared.getDisruptions() { disruptions = d }
        if let s = try? await APIClient.shared.getSettings()    { settings = s }
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
        let weekday = Calendar.current.component(.weekday, from: date) - 1
        let dayKey = String(weekday)

        var disruption: ScheduleDisruption? {
            let ds = DateFormatter.iso.string(from: date)
            return disruptions.first { $0.date == ds }
        }

        return classes.filter { $0.days.contains(weekday) }.map { cls in
            // dayTimes override takes precedence
            var out = cls
            if let dt = cls.dayTimes?[dayKey] {
                out.startTime = dt.startTime
                out.endTime   = dt.endTime
            }
            return out
        }.sorted { $0.period < $1.period }
    }

    func lunchTime(for date: Date) -> DayTime? {
        let weekday = Calendar.current.component(.weekday, from: date) - 1
        let key = String(weekday)
        return (settings.lunchTimes ?? AppSettings.defaultLunchTimes)[key]
    }

    // MARK: - Lookup
    func className(for id: String) -> String {
        classes.first { $0.id == id }?.name ?? "Unknown"
    }

    func schoolClass(_ id: String) -> SchoolClass? {
        classes.first { $0.id == id }
    }

    // MARK: - Homework CRUD
    func toggleHomework(_ hw: Homework) async {
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
