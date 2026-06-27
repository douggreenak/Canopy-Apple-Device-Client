import Foundation

// Port of web src/lib/schedule.ts — early-out / late-start period override
// generation and the Lathrop bell-schedule template.

enum ScheduleEngine {
    /// Lathrop High early-out bell schedule (period → times).
    static let lathropEarlyOut: [Int: DayTime] = [
        1: DayTime(startTime: "07:30", endTime: "08:10"),
        2: DayTime(startTime: "08:15", endTime: "08:55"),
        3: DayTime(startTime: "09:00", endTime: "09:40"),
        4: DayTime(startTime: "09:50", endTime: "10:30"),
        5: DayTime(startTime: "10:35", endTime: "11:15"),
        6: DayTime(startTime: "11:20", endTime: "12:00"),
    ]

    static func buildLathropEarlyOutTemplate(classes: [SchoolClass]? = nil) -> [Int: DayTime] {
        var tpl = lathropEarlyOut
        if let classes,
           let ext = classes.first(where: { $0.name.range(of: #"\b(ext|extension|seminar|advisory|homeroom)\b"#, options: [.regularExpression, .caseInsensitive]) != nil }) {
            tpl[ext.period] = DayTime(startTime: "07:30", endTime: "08:10")
        }
        return tpl
    }

    static func timeToMinutes(_ t: String) -> Int {
        let parts = t.split(separator: ":").compactMap { Int($0) }
        guard parts.count == 2 else { return 0 }
        return parts[0] * 60 + parts[1]
    }

    static func minutesToTime(_ m: Int) -> String {
        String(format: "%02d:%02d", m / 60, m % 60)
    }

    /// Find the next future date a class meets (skips today). ISO yyyy-MM-dd.
    static func nextMeetingDate(days: [Int], from: Date = .now) -> String {
        guard !days.isEmpty else { return "" }
        let cal = Calendar.current
        for i in 1...14 {
            guard let candidate = cal.date(byAdding: .day, value: i, to: from) else { continue }
            let dow = cal.component(.weekday, from: candidate) - 1 // 0=Sun
            if days.contains(dow) { return DateFormatter.iso.string(from: candidate) }
        }
        return ""
    }

    /// Generate early-out period overrides. Uses the template when supplied,
    /// otherwise proportionally compresses the day to end at `earlyEndTime`.
    static func generateEarlyOutOverrides(
        classes: [SchoolClass],
        earlyEndTime: String,
        dayOfWeek: Int? = nil,
        template: [Int: DayTime]? = nil
    ) -> [PeriodOverride] {
        if let template, !template.isEmpty {
            return classes
                .filter { template[$0.period] != nil }
                .sorted { timeToMinutes(template[$0.period]!.startTime) < timeToMinutes(template[$1.period]!.startTime) }
                .map { PeriodOverride(period: $0.period, startTime: template[$0.period]!.startTime, endTime: template[$0.period]!.endTime, cancelled: false) }
        }

        func eStart(_ c: SchoolClass) -> String {
            if let dow = dayOfWeek, let dt = c.dayTimes?[String(dow)]?.startTime { return dt }
            return c.startTime
        }
        func eEnd(_ c: SchoolClass) -> String {
            if let dow = dayOfWeek, let dt = c.dayTimes?[String(dow)]?.endTime { return dt }
            return c.endTime
        }

        let sorted = classes.sorted { timeToMinutes(eStart($0)) < timeToMinutes(eStart($1)) }
        guard !sorted.isEmpty else { return [] }
        let firstStart = timeToMinutes(eStart(sorted[0]))
        let lastEnd = timeToMinutes(eEnd(sorted[sorted.count - 1]))
        let earlyEnd = timeToMinutes(earlyEndTime)
        guard earlyEnd > firstStart, earlyEnd < lastEnd else { return [] }
        let ratio = Double(earlyEnd - firstStart) / Double(lastEnd - firstStart)

        var overrides = sorted.map { c -> PeriodOverride in
            let origStart = timeToMinutes(eStart(c))
            let origEnd = timeToMinutes(eEnd(c))
            let newStart = Int((Double(firstStart) + Double(origStart - firstStart) * ratio).rounded())
            let newEnd = Int((Double(firstStart) + Double(origEnd - firstStart) * ratio).rounded())
            return PeriodOverride(period: c.period, startTime: minutesToTime(newStart), endTime: minutesToTime(max(newStart + 1, newEnd)), cancelled: false)
        }
        overrides[overrides.count - 1].endTime = minutesToTime(earlyEnd)
        return overrides
    }

    /// Generate late-start overrides by delaying every period equally.
    static func generateLateStartOverrides(
        classes: [SchoolClass],
        lateStartTime: String,
        dayOfWeek: Int? = nil
    ) -> [PeriodOverride] {
        func eStart(_ c: SchoolClass) -> String {
            if let dow = dayOfWeek, let dt = c.dayTimes?[String(dow)]?.startTime { return dt }
            return c.startTime
        }
        func eEnd(_ c: SchoolClass) -> String {
            if let dow = dayOfWeek, let dt = c.dayTimes?[String(dow)]?.endTime { return dt }
            return c.endTime
        }
        let sorted = classes.sorted { timeToMinutes(eStart($0)) < timeToMinutes(eStart($1)) }
        guard !sorted.isEmpty else { return [] }
        let delay = timeToMinutes(lateStartTime) - timeToMinutes(eStart(sorted[0]))
        return sorted.map { c in
            PeriodOverride(period: c.period,
                           startTime: minutesToTime(timeToMinutes(eStart(c)) + delay),
                           endTime: minutesToTime(timeToMinutes(eEnd(c)) + delay),
                           cancelled: false)
        }
    }
}
