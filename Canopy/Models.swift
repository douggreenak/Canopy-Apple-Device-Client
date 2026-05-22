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
    var grade: String?
    var gradePercent: Double?
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
    var score: String?
    var scorePercent: Double?
    var category: String?
    var flags: String?
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
    var type: String
    var label: String
    var periodOverrides: [PeriodOverride]
}

// MARK: - Settings
struct AppSettings: Codable {
    var schoolName: String?
    var semesterStart: String?
    var semesterEnd: String?
    var calendarToken: String?
    var lunchTimes: [String: DayTime]?

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
