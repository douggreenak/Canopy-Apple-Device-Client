import Foundation
import SwiftUI

// Minimal model set shared in shape with the phone app / backend JSON.

struct WUser: Codable, Equatable { let id: String; let username: String }

struct WDayTime: Codable, Equatable { var startTime: String; var endTime: String }

struct WClass: Codable, Identifiable, Equatable {
    var id: String
    var name: String
    var teacher: String
    var room: String
    var color: String
    var period: Int
    var startTime: String
    var endTime: String
    var days: [Int]
    var dayTimes: [String: WDayTime]?
    var semester: String
    var grade: String?
    var gradePercent: Double?
}

struct WHomework: Codable, Identifiable, Equatable {
    var id: String
    var classId: String
    var title: String
    var description: String
    var dueDate: String
    var completed: Bool
    var priority: String
    var source: String
    var category: String?
    var flags: String?
}

struct WExam: Codable, Identifiable, Equatable {
    var id: String
    var classId: String
    var title: String
    var date: String
    var startTime: String
    var endTime: String
    var location: String
    var notes: String
}

extension String {
    var wAsDate: Date? {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd"
        f.locale = Locale(identifier: "en_US_POSIX")
        return f.date(from: self)
    }
    var wDueLabel: String {
        guard let d = wAsDate else { return self }
        if Calendar.current.isDateInToday(d) { return "Today" }
        if Calendar.current.isDateInTomorrow(d) { return "Tomorrow" }
        let f = DateFormatter(); f.dateFormat = "MMM d"
        return f.string(from: d)
    }
}

extension Color {
    init(wHex: String) {
        let hex = wHex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        var int: UInt64 = 0
        Scanner(string: hex).scanHexInt64(&int)
        let r, g, b: UInt64
        switch hex.count {
        case 3:  (r, g, b) = ((int >> 8) * 17, (int >> 4 & 0xF) * 17, (int & 0xF) * 17)
        case 6:  (r, g, b) = (int >> 16, int >> 8 & 0xFF, int & 0xFF)
        default: (r, g, b) = (0, 0, 0)
        }
        self.init(.sRGB, red: Double(r)/255, green: Double(g)/255, blue: Double(b)/255, opacity: 1)
    }
}

func wLetterGrade(from pct: Double) -> String {
    switch pct {
    case 97...: return "A+"; case 93...: return "A"; case 90...: return "A-"
    case 87...: return "B+"; case 83...: return "B"; case 80...: return "B-"
    case 77...: return "C+"; case 73...: return "C"; case 70...: return "C-"
    case 67...: return "D+"; case 63...: return "D"; case 60...: return "D-"
    default: return "F"
    }
}

func wGradeColor(_ grade: String) -> Color {
    switch grade.prefix(1) {
    case "A": return .green
    case "B": return .blue
    case "C": return .orange
    case "D": return .red
    default:  return .secondary
    }
}
