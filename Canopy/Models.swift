import Foundation

// MARK: - Auth
struct User: Codable, Equatable {
    let id: String
    let username: String
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
    var entityType: String
    var entityId: String
    var classId: String?
    var label: String
    var changeType: String
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
}

// MARK: - Completion stages
// One step in a per-item completion pipeline (e.g. "Draft" -> "Turned In").
// `id` is stable across renames/reorders so a lingering `stageId` never dangles.
// Port of web src/types/index.ts::TaskStage.
struct TaskStage: Codable, Equatable, Identifiable {
    var id: String
    var label: String
}

// MARK: - Disruptions
struct PeriodOverride: Codable, Equatable {
    var period: Int
    var startTime: String
    var endTime: String
    var cancelled: Bool
}

struct ScheduleDisruption: Codable, Identifiable, Equatable {
    var id: String
    var date: String
    /// Optional multi-day end date (inclusive); nil/empty means single-day.
    /// A date `d` falls under this disruption iff `date <= d <= (endDate ?? date)`.
    var endDate: String?
    var type: String
    var label: String
    var periodOverrides: [PeriodOverride]
}

// MARK: - PowerSchool schedule-matrix suggestion
// A scraper-derived guess at a class's real meeting days/times, offered as an
// Apply/Dismiss suggestion while editing that class after a sync.
struct MatrixSuggestion: Codable, Equatable {
    var days: [Int]
    var startTime: String?
    var endTime: String?
}

// MARK: - Settings
struct AppSettings: Codable {
    var schoolName: String?
    var semesterStart: String?
    var semesterEnd: String?
    var calendarToken: String?
    var lunchTimes: [String: DayTime]?

    // Appearance
    var themeMode: String?          // "light" | "dark" | "system"
    var accentColor: String?        // hex string

    // School / scheduling
    var timezone: String?
    var lathropMode: String?        // "true" | "false"
    var earlyOutSchedule: String?   // raw JSON string of [period: DayTime]
    var lastSyncAt: String?         // ISO timestamp of last PowerSchool sync

    enum CodingKeys: String, CodingKey {
        case schoolName, semesterStart, semesterEnd, calendarToken, lunchTimes
        case themeMode, accentColor, timezone, lathropMode, lastSyncAt
        case earlyOutSchedule = "early_out_schedule"
    }

    var lathropEnabled: Bool { lathropMode == "true" }

    /// Parse the early-out schedule JSON string into a usable map.
    var earlyOutTemplate: [String: DayTime]? {
        guard let raw = earlyOutSchedule, let data = raw.data(using: .utf8) else { return nil }
        return try? JSONDecoder().decode([String: DayTime].self, from: data)
    }

    // Default lunch schedule when settings haven't loaded yet
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
