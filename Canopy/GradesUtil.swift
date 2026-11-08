import Foundation
import SwiftUI

// Port of web src/lib/grades.ts status predicates, counts, colours and time buckets.

extension Homework {
    /// Prefer scraper-captured scorePercent; fall back to parsing the score text.
    var percentValue: Double? {
        if let p = scorePercent { return p }
        return GradesUtil.parseScorePercent(score)
    }

    var isMissing: Bool { (flags?.range(of: "miss", options: .caseInsensitive)) != nil }
    var isLate: Bool { (flags?.range(of: "late|incomplete", options: [.regularExpression, .caseInsensitive])) != nil }
    var isGraded: Bool { percentValue != nil }

    /// Past-due with no score and not missing.
    var isUngraded: Bool {
        if isGraded || isMissing { return false }
        guard let d = dueDate.asDate else { return false }
        return Calendar.current.startOfDay(for: d) <= Calendar.current.startOfDay(for: .now)
    }

    var isUpcoming: Bool {
        if isGraded { return false }
        guard let d = dueDate.asDate else { return false }
        return Calendar.current.startOfDay(for: d) > Calendar.current.startOfDay(for: .now)
    }
}

struct StatusCounts {
    var total = 0, graded = 0, missing = 0, late = 0, ungraded = 0, upcoming = 0, upcomingThisWeek = 0
}

enum TimeBucket: String, CaseIterable {
    case upcoming = "Upcoming"
    case thisWeek = "This Week"
    case lastWeek = "Last Week"
    case thisMonth = "This Month"
    case earlier = "Earlier"
}

/// Web `flagSeverity` — chip colour for a PowerSchool flag string.
enum FlagSeverity { case error, warning, success, normal
    var color: Color {
        switch self {
        case .error: return .red
        case .warning: return .orange
        case .success: return .green
        case .normal: return .secondary
        }
    }
}

enum GradesUtil {
    // MARK: Colours (web gradeColor: ≥90 green, ≥80 blue, ≥70 orange, else red; nil grey)
    static func gradeColor(_ percent: Double?) -> Color {
        guard let p = percent else { return Color.secondary.opacity(0.6) }
        if p >= 90 { return .green }
        if p >= 80 { return .blue }
        if p >= 70 { return .orange }
        return .red
    }

    /// Letter → approximate percent, used only when a class has a letter but no percent.
    static func approxPercent(forLetter letter: String?) -> Double? {
        guard let l = letter?.trimmingCharacters(in: .whitespaces).uppercased(), let first = l.first else { return nil }
        switch first {
        case "A": return 95
        case "B": return 85
        case "C": return 75
        case "D": return 65
        case "F": return 50
        default: return nil
        }
    }

    static func flagSeverity(_ flag: String) -> FlagSeverity {
        let f = flag.lowercased()
        if f.contains("miss") { return .error }
        if f.contains("late") || f.contains("incomplete") { return .warning }
        if f.contains("collect") || f.contains("exempt") { return .success }
        return .normal
    }

    // MARK: Letter grades (no A+)
    static func letterFromPercent(_ p: Double) -> String {
        if p >= 93 { return "A" }
        if p >= 90 { return "A-" }
        if p >= 87 { return "B+" }
        if p >= 83 { return "B" }
        if p >= 80 { return "B-" }
        if p >= 77 { return "C+" }
        if p >= 73 { return "C" }
        if p >= 70 { return "C-" }
        if p >= 67 { return "D+" }
        if p >= 63 { return "D" }
        if p >= 60 { return "D-" }
        return "F"
    }

    /// GPA colour: ≥3.5 green, ≥2.5 blue, ≥1.5 orange, else red (web Transcript).
    static func gpaColor(_ gpa: Double) -> Color {
        if gpa >= 3.5 { return .green }
        if gpa >= 2.5 { return .blue }
        if gpa >= 1.5 { return .orange }
        return .red
    }

    static func parseScorePercent(_ raw: String?) -> Double? {
        guard let raw else { return nil }
        let txt = raw.replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression).trimmingCharacters(in: .whitespaces)
        if txt.isEmpty { return nil }
        if let m = txt.range(of: #"(\d+(?:\.\d+)?)\s*/\s*(\d+(?:\.\d+)?)"#, options: .regularExpression) {
            let frac = txt[m].split(separator: "/")
            if frac.count == 2,
               let num = Double(frac[0].trimmingCharacters(in: .whitespaces)),
               let den = Double(frac[1].trimmingCharacters(in: .whitespaces)), den > 0 {
                return num / den * 100
            }
        }
        if let m = txt.range(of: #"(\d+(?:\.\d+)?)\s*%"#, options: .regularExpression) {
            let n = txt[m].replacingOccurrences(of: "%", with: "").trimmingCharacters(in: .whitespaces)
            return Double(n)
        }
        if let n = Double(txt), n >= 0, n <= 150 { return n }
        return nil
    }

    static func counts(_ list: [Homework]) -> StatusCounts {
        var c = StatusCounts()
        c.total = list.count
        let weekAhead = Calendar.current.date(byAdding: .day, value: 7, to: Calendar.current.startOfDay(for: .now))!
        for h in list {
            if h.isMissing { c.missing += 1 }
            if h.isLate { c.late += 1 }
            if h.isGraded { c.graded += 1 }
            else if h.isUngraded { c.ungraded += 1 }
            if h.isUpcoming {
                c.upcoming += 1
                if let d = h.dueDate.asDate, d <= weekAhead { c.upcomingThisWeek += 1 }
            }
        }
        return c
    }

    static func timeBucket(_ iso: String?) -> TimeBucket {
        guard let iso, let d = iso.asDate else { return .earlier }
        let today = Calendar.current.startOfDay(for: .now)
        let diff = Calendar.current.dateComponents([.day], from: today, to: Calendar.current.startOfDay(for: d)).day ?? 0
        if diff > 0 { return .upcoming }
        if diff >= -6 { return .thisWeek }
        if diff >= -13 { return .lastWeek }
        if diff >= -30 { return .thisMonth }
        return .earlier
    }

    static func relativeDueLabel(_ iso: String?) -> String {
        guard let iso, let d = iso.asDate else { return "—" }
        let today = Calendar.current.startOfDay(for: .now)
        let diff = Calendar.current.dateComponents([.day], from: today, to: Calendar.current.startOfDay(for: d)).day ?? 0
        switch diff {
        case 0: return "Today"
        case 1: return "Tomorrow"
        case -1: return "Yesterday"
        case 2...6: return "In \(diff) days"
        case -6...(-2): return "\(abs(diff)) days ago"
        default:
            let f = DateFormatter(); f.dateFormat = abs(diff) < 365 ? "MMM d" : "MMM d, yyyy"
            return f.string(from: d)
        }
    }

    /// "MMM d, yyyy"
    static func fullDueLabel(_ iso: String?) -> String {
        guard let iso, let d = iso.asDate else { return "—" }
        let f = DateFormatter(); f.dateFormat = "MMM d, yyyy"
        return f.string(from: d)
    }

    /// Web `fromNow()`-style relative time for an ISO timestamp.
    static func timeAgo(_ iso: String) -> String {
        guard let d = CanopyStore.parseISO(iso) else { return "" }
        let f = RelativeDateTimeFormatter(); f.unitsStyle = .full
        return f.localizedString(for: d, relativeTo: .now)
    }
}

// MARK: - Last-used stage template (web src/lib/stages.ts, localStorage → UserDefaults)
enum StageTemplate {
    private static let key = "canopy:lastTaskStages"

    static func load() -> [TaskStage] {
        guard let data = UserDefaults.standard.data(forKey: key),
              let arr = try? JSONDecoder().decode([TaskStage].self, from: data) else { return [] }
        return arr.filter { !$0.label.trimmingCharacters(in: .whitespaces).isEmpty }
            .map { TaskStage(id: $0.id, label: $0.label.trimmingCharacters(in: .whitespaces)) }
    }

    static func save(_ stages: [TaskStage]) {
        if stages.isEmpty { UserDefaults.standard.removeObject(forKey: key); return }
        if let data = try? JSONEncoder().encode(stages) { UserDefaults.standard.set(data, forKey: key) }
    }
}
