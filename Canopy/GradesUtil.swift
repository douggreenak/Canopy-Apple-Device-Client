import Foundation

// Port of web src/lib/grades.ts status predicates, counts, and time buckets.

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

enum GradesUtil {
    static func parseScorePercent(_ raw: String?) -> Double? {
        guard let raw else { return nil }
        let txt = raw.replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression).trimmingCharacters(in: .whitespaces)
        if txt.isEmpty { return nil }
        // fraction a/b
        if let m = txt.range(of: #"(\d+(?:\.\d+)?)\s*/\s*(\d+(?:\.\d+)?)"#, options: .regularExpression) {
            let frac = txt[m].split(separator: "/")
            if frac.count == 2,
               let num = Double(frac[0].trimmingCharacters(in: .whitespaces)),
               let den = Double(frac[1].trimmingCharacters(in: .whitespaces)), den > 0 {
                return num / den * 100
            }
        }
        // percent
        if let m = txt.range(of: #"(\d+(?:\.\d+)?)\s*%"#, options: .regularExpression) {
            let n = txt[m].replacingOccurrences(of: "%", with: "").trimmingCharacters(in: .whitespaces)
            return Double(n)
        }
        // bare number 0..150
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
}
