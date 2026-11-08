import Foundation

// MARK: - Auth
struct User: Codable, Equatable {
    let id: String
    let username: String
    /// "user" | "admin". Older server responses omit it — default "user".
    var role: String

    var isAdmin: Bool { role == "admin" }

    init(id: String, username: String, role: String = "user") {
        self.id = id; self.username = username; self.role = role
    }

    enum CodingKeys: String, CodingKey { case id, username, role }
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(String.self, forKey: .id)
        username = try c.decode(String.self, forKey: .username)
        role = (try? c.decodeIfPresent(String.self, forKey: .role)) ?? "user"
    }
}

// MARK: - Shared
struct DayTime: Codable, Equatable, Hashable {
    var startTime: String
    var endTime: String
}

// MARK: - Classes
struct SchoolClass: Codable, Identifiable, Equatable {
    var id: String
    var name: String
    var teacher: String
    var room: String
    var color: String
    var period: Int
    var startTime: String
    var endTime: String
    var days: [Int]
    var dayTimes: [String: DayTime]?
    var semester: String
    var source: String?
    var sourceId: String?
    var grade: String?
    var gradePercent: Double?
    var categoryWeights: [String: Double]?
    var weightSource: String?
    /// AP class — +1.0 on the 4.0 scale in the weighted GPA (web `isAp`).
    var isAp: Bool?
    /// User's drag-to-reorder position on the Classes page (web `sortOrder`).
    var sortOrder: Int?
    /// Which school this class belongs to for multi-school users (web `schoolName`).
    var schoolName: String?

    var isPowerSchool: Bool { source == "powerschool" }
    /// Teacher with PowerSchool's leading "Email " prefix stripped; nil when
    /// empty or the "TBD" placeholder (mirrors web display rules).
    var displayTeacher: String? {
        let t = teacher.replacingOccurrences(of: "^Email\\s+", with: "", options: .regularExpression)
            .trimmingCharacters(in: .whitespaces)
        if t.isEmpty || t == "TBD" { return nil }
        return t
    }
}

// MARK: - Homework
struct Homework: Codable, Identifiable, Equatable {
    var id: String
    var classId: String
    var title: String
    var description: String
    var dueDate: String
    var completed: Bool
    var priority: String
    var source: String
    var sourceId: String?
    var score: String?
    var scorePercent: Double?
    var category: String?
    var flags: String?
    var stages: [TaskStage]?
    var stageId: String?
    /// "in_class" | "after_class" | nil (unset).
    var dueTiming: String?
    /// Teacher's comment on this graded assignment (split from score at scrape time).
    var teacherNote: String?
}

// MARK: - Exams
struct Exam: Codable, Identifiable, Equatable {
    var id: String
    var classId: String
    var title: String
    var date: String
    var startTime: String
    var endTime: String
    var location: String
    var notes: String
    var weightPercent: Double?
}

// MARK: - Grade History
struct GradeHistoryEntry: Codable, Identifiable, Equatable {
    var id: String
    var classId: String
    var gradePercent: Double?
    var letter: String?
    var semester: String
    var capturedAt: String
}

// MARK: - Sync Log
struct SyncLogEntry: Codable, Identifiable, Equatable {
    var id: String
    var syncId: String
    var occurredAt: String
    var entityType: String   // 'class' | 'homework' | 'sync'
    var entityId: String
    var classId: String?
    var label: String
    var changeType: String   // added | removed | score_changed | grade_changed | flag_changed | none | error
    var detail: String
}

// MARK: - Tasks
struct SchoolTask: Codable, Identifiable, Equatable {
    var id: String
    var title: String
    var description: String
    var dueDate: String
    var completed: Bool
    var priority: String
    var category: String
    var classId: String?
    var stages: [TaskStage]?
    var stageId: String?
    /// "in_class" | "after_class" | nil (unset).
    var dueTiming: String?
}

// MARK: - Completion stages
struct TaskStage: Codable, Equatable, Identifiable, Hashable {
    var id: String
    var label: String
}

// MARK: - Due timing (web `DueTiming`)
enum DueTiming: String, CaseIterable {
    case inClass = "in_class"
    case afterClass = "after_class"

    var label: String { self == .inClass ? "In class" : "After class" }
    var detailLabel: String { self == .inClass ? "Due in class" : "Due after class / online" }
    var systemImage: String { self == .inClass ? "door.left.hand.open" : "laptopcomputer" }
}

// MARK: - Disruptions
struct PeriodOverride: Codable, Equatable, Identifiable {
    var period: Int
    var startTime: String
    var endTime: String
    var cancelled: Bool
    var id: Int { period }
}

struct ScheduleDisruption: Codable, Identifiable, Equatable {
    var id: String
    var date: String
    /// Optional multi-day end date (inclusive); nil/empty means single-day.
    var endDate: String?
    /// early_out | late_start | no_school | assembly | 1_6 | day_swap | custom
    var type: String
    /// May be "" — falls back to the type's label wherever shown.
    var label: String
    var periodOverrides: [PeriodOverride]
    /// Only for type == "day_swap": the weekday (0=Sun..6=Sat) whose normal
    /// class list/times run on this date instead.
    var sourceDayOfWeek: Int?

    /// Label with the type-label fallback the web applies everywhere.
    var displayLabel: String {
        label.isEmpty ? ScheduleEngine.disruptionTypeLabel(type) : label
    }

    func covers(_ dateString: String) -> Bool {
        let end = (endDate?.isEmpty == false) ? endDate! : date
        return dateString >= date && dateString <= end
    }
}

// MARK: - PowerSchool schedule-matrix suggestion
struct MatrixSuggestion: Codable, Equatable {
    var days: [Int]
    var startTime: String?
    var endTime: String?
}

// MARK: - PowerSchool sync status (GET /api/powerschool/status)
struct PowerSchoolStatus: Codable, Equatable {
    var syncId: String
    var status: String      // idle | running | success | error
    var startedAt: String?
    var finishedAt: String?
    var log: [String]
    var result: SyncResultSummary?
    var error: String?

    static let idle = PowerSchoolStatus(syncId: "", status: "idle", startedAt: nil, finishedAt: nil, log: [], result: nil, error: nil)

    var isRunning: Bool { status == "running" }
    var isTerminal: Bool { status == "success" || status == "error" }

    /// Whether the last failure was a rejected PowerSchool login (web
    /// `PowerSchoolLoginWarning` rule).
    var isLoginFailure: Bool {
        guard status == "error", let e = error else { return false }
        return e.range(of: "login failed|invalid (username|password)|incorrect (username|password)",
                       options: [.regularExpression, .caseInsensitive]) != nil
    }

    init(syncId: String, status: String, startedAt: String?, finishedAt: String?, log: [String], result: SyncResultSummary?, error: String?) {
        self.syncId = syncId; self.status = status; self.startedAt = startedAt; self.finishedAt = finishedAt
        self.log = log; self.result = result; self.error = error
    }

    enum CodingKeys: String, CodingKey { case syncId, status, startedAt, finishedAt, log, result, error }
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        syncId = (try? c.decodeIfPresent(String.self, forKey: .syncId)) ?? ""
        status = (try? c.decodeIfPresent(String.self, forKey: .status)) ?? "idle"
        startedAt = try? c.decodeIfPresent(String.self, forKey: .startedAt)
        finishedAt = try? c.decodeIfPresent(String.self, forKey: .finishedAt)
        log = (try? c.decodeIfPresent([String].self, forKey: .log)) ?? []
        result = try? c.decodeIfPresent(SyncResultSummary.self, forKey: .result)
        error = try? c.decodeIfPresent(String.self, forKey: .error)
    }
}

/// `result` payload of a successful sync.
struct SyncResultSummary: Codable, Equatable {
    var classCount: Int?
    var classAdded: Int?
    var classUpdated: Int?
    var classRemoved: Int?
    var assignmentCount: Int?
    var assignmentAdded: Int?
    var assignmentUpdated: Int?
    var assignmentRemoved: Int?
    var matrixByClassId: [String: MatrixSuggestion]?

    /// Web Grades-page summary sentence.
    var gradesSummary: String {
        var parts: [String] = []
        if let n = classAdded, n > 0 { parts.append("\(n) class\(n == 1 ? "" : "es") added") }
        if let n = classUpdated, n > 0 { parts.append("\(n) updated") }
        if let n = classRemoved, n > 0 { parts.append("\(n) removed") }
        if let n = assignmentAdded, n > 0 { parts.append("\(n) assignment\(n == 1 ? "" : "s") added") }
        if let n = assignmentUpdated, n > 0 { parts.append("\(n) assignments updated") }
        if parts.isEmpty {
            return "Synced — already up to date (\(classCount ?? 0) classes, \(assignmentCount ?? 0) assignments)."
        }
        return "Synced — " + parts.joined(separator: ", ") + "."
    }

    /// Web Settings-page summary sentence.
    var settingsSummary: String {
        var parts: [String] = []
        if let n = classAdded, n > 0 { parts.append("\(n) added") }
        if let n = classUpdated, n > 0 { parts.append("\(n) updated") }
        if let n = classRemoved, n > 0 { parts.append("\(n) removed") }
        let classSummary = parts.isEmpty ? "no changes" : parts.joined(separator: ", ")
        return "PowerSchool sync complete — \(classSummary). \(assignmentCount ?? 0) assignments synced."
    }
}

// MARK: - Other schools (GET /api/powerschool/schools)
struct SchoolAccountSummary: Codable, Identifiable, Equatable {
    var id: String
    var schoolName: String
    var url: String
    var username: String
}

// MARK: - Admin stats (GET /api/admin/stats)
struct SystemStats: Codable, Equatable {
    struct MonthCount: Codable, Equatable, Identifiable {
        var month: String
        var count: Int
        var id: String { month }
    }
    struct UserRow: Codable, Equatable, Identifiable {
        var username: String
        var registeredAt: String
        var lastActiveAt: String?
        var id: String { username }
    }
    var totalUsers: Int
    var activeUsersLast7Days: Int
    var activeUsersLast30Days: Int
    var totalClasses: Int
    var totalAssignments: Int
    var totalExams: Int
    var totalTasks: Int
    var registrationsByMonth: [MonthCount]
    var userList: [UserRow]
}

// MARK: - Settings
struct AppSettings: Codable {
    var schoolName: String?
    var calendarToken: String?
    var lunchTimes: [String: DayTime]?

    // Appearance
    var themeMode: String?          // "light" | "dark" | "system"
    var accentColor: String?        // preset NAME (web convention); legacy hex falls back to default

    // School / scheduling
    var timezone: String?
    var lathropMode: String?        // "true" | "false" | nil (nil = ON, web default)
    var earlyOutSchedule: String?   // raw JSON string of [period: DayTime]
    var lastSyncAt: String?         // ISO timestamp of last PowerSchool sync
    /// Scheduled daily sync. Server stores a raw JSON string `{"enabled":true}`.
    var powerschoolAutoSync: String?

    enum CodingKeys: String, CodingKey {
        case schoolName, calendarToken, lunchTimes
        case themeMode, accentColor, timezone, lathropMode, lastSyncAt, powerschoolAutoSync
        case earlyOutSchedule = "early_out_schedule"
    }

    init() {}

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        schoolName = try? c.decodeIfPresent(String.self, forKey: .schoolName)
        calendarToken = try? c.decodeIfPresent(String.self, forKey: .calendarToken)
        // lunchTimes is parsed server-side into an object, but tolerate a raw string too.
        if let obj = try? c.decodeIfPresent([String: DayTime].self, forKey: .lunchTimes) {
            lunchTimes = obj
        } else if let raw = try? c.decodeIfPresent(String.self, forKey: .lunchTimes),
                  let data = raw.data(using: .utf8) {
            lunchTimes = try? JSONDecoder().decode([String: DayTime].self, from: data)
        }
        themeMode = try? c.decodeIfPresent(String.self, forKey: .themeMode)
        accentColor = try? c.decodeIfPresent(String.self, forKey: .accentColor)
        timezone = try? c.decodeIfPresent(String.self, forKey: .timezone)
        // lathropMode may arrive as a string or (legacy) bool.
        if let s = try? c.decodeIfPresent(String.self, forKey: .lathropMode) {
            lathropMode = s
        } else if let b = try? c.decodeIfPresent(Bool.self, forKey: .lathropMode) {
            lathropMode = b ? "true" : "false"
        }
        earlyOutSchedule = try? c.decodeIfPresent(String.self, forKey: .earlyOutSchedule)
        lastSyncAt = try? c.decodeIfPresent(String.self, forKey: .lastSyncAt)
        if let s = try? c.decodeIfPresent(String.self, forKey: .powerschoolAutoSync) {
            powerschoolAutoSync = s
        } else if let obj = try? c.decodeIfPresent([String: Bool].self, forKey: .powerschoolAutoSync) {
            powerschoolAutoSync = "{\"enabled\":\(obj["enabled"] == true)}"
        }
    }

    /// Web: undefined → ON. Registration also stores 'true' explicitly.
    var lathropEnabled: Bool { lathropMode == nil || lathropMode == "true" }

    /// Scheduled sync. Web default: true when unset or malformed.
    var autoSyncEnabled: Bool {
        guard let raw = powerschoolAutoSync, let data = raw.data(using: .utf8) else { return true }
        struct Wrap: Decodable { let enabled: Bool? }
        if let w = try? JSONDecoder().decode(Wrap.self, from: data) { return w.enabled ?? true }
        return true
    }

    /// Parse the early-out schedule JSON string into a usable map.
    var earlyOutTemplate: [String: DayTime]? {
        guard let raw = earlyOutSchedule, let data = raw.data(using: .utf8) else { return nil }
        let map = try? JSONDecoder().decode([String: DayTime].self, from: data)
        return (map?.isEmpty ?? true) ? nil : map
    }

    // Default lunch schedule (Lathrop HS bell schedule)
    static let defaultLunchTimes: [String: DayTime] = [
        "1": DayTime(startTime: "10:26", endTime: "10:57"),  // Mon
        "5": DayTime(startTime: "10:26", endTime: "10:57"),  // Fri
        "2": DayTime(startTime: "10:50", endTime: "11:20"),  // Tue
        "3": DayTime(startTime: "10:50", endTime: "11:20"),  // Wed
        "4": DayTime(startTime: "10:50", endTime: "11:20"),  // Thu
    ]
}

// MARK: - Date parsing helpers
extension String {
    var asDate: Date? {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd"
        f.locale = Locale(identifier: "en_US_POSIX")
        return f.date(from: self)
    }
}
