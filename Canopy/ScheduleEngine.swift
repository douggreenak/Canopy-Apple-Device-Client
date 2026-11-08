import Foundation

// Port of web src/lib/schedule.ts — early-out / late-start period override
// generation and the Lathrop bell-schedule template.

enum ScheduleEngine {
    // MARK: - Disruption types
    // Port of web src/lib/disruptionTypes.ts::DISRUPTION_TYPES. `type` is a raw
    // string persisted server-side and shared with the web app — these six
    // values/colors must stay byte-for-byte identical on both platforms.
    struct DisruptionTypeInfo: Equatable {
        let value: String
        let label: String
        let color: String  // hex
    }

    static let disruptionTypes: [DisruptionTypeInfo] = [
        DisruptionTypeInfo(value: "early_out",  label: "Early Out",     color: "#f9ab00"),
        DisruptionTypeInfo(value: "late_start", label: "Late Start",    color: "#1a73e8"),
        DisruptionTypeInfo(value: "no_school",  label: "No School",     color: "#d93025"),
        DisruptionTypeInfo(value: "assembly",   label: "Assembly",      color: "#7BAAF7"),
        DisruptionTypeInfo(value: "1_6",        label: "1-6 Schedule",  color: "#34a853"),
        DisruptionTypeInfo(value: "day_swap",   label: "Different Day’s Schedule", color: "#8e24aa"),
        DisruptionTypeInfo(value: "custom",     label: "Custom",        color: "#9aa0a6"),
    ]

    /// Reserved `PeriodOverride.period` for the synthesized Assembly block.
    static let assemblyPeriod = -1
    /// Synthetic ids mirroring web's `__lunch__` / `__assembly__` classes.
    static let lunchClassId = "__lunch__"
    static let assemblyClassId = "__assembly__"

    static let weekdayNames = ["Sunday", "Monday", "Tuesday", "Wednesday", "Thursday", "Friday", "Saturday"]

    /// Web `disruptionTypeLabel` — alias of `disruptionLabel(for:)`.
    static func disruptionTypeLabel(_ type: String) -> String { disruptionLabel(for: type) }

    /// Display label for a PeriodOverride row: "Lunch", "Assembly", or "P{n}".
    static func periodLabel(_ period: Int) -> String {
        if period == 0 { return "Lunch" }
        if period == assemblyPeriod { return "Assembly" }
        return "P\(period)"
    }

    static func disruptionLabel(for type: String) -> String {
        disruptionTypes.first { $0.value == type }?.label
            ?? type.replacingOccurrences(of: "_", with: " ").capitalized
    }

    static func disruptionColorHex(for type: String) -> String {
        disruptionTypes.first { $0.value == type }?.color ?? "#9aa0a6"
    }

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

    /// Parse "07:30" or "7:30 AM" into minutes since midnight (web parseMinutes).
    static func timeToMinutes(_ t: String) -> Int {
        let trimmed = t.trimmingCharacters(in: .whitespaces)
        guard let r = trimmed.range(of: #"^(\d{1,2}):(\d{2})\s*([AaPp][Mm])?$"#, options: .regularExpression) else { return 0 }
        let str = String(trimmed[r])
        let core = str.split(whereSeparator: { $0 == ":" || $0 == " " })
        guard core.count >= 2, var h = Int(core[0]), let m = Int(core[1].prefix(2)) else { return 0 }
        let ap = str.suffix(2).lowercased()
        if ap == "pm", h < 12 { h += 12 } else if ap == "am", h == 12 { h = 0 }
        return h * 60 + m
    }

    /// "9:30 AM" style display for an "HH:mm" string.
    static func formatTime12(_ t: String) -> String {
        let m = timeToMinutes(t)
        let h = m / 60, mm = m % 60
        let h12 = h % 12 == 0 ? 12 : h % 12
        return String(format: "%d:%02d %@", h12, mm, h < 12 ? "AM" : "PM")
    }

    /// Monday anchoring the displayed week; a Sunday shows the UPCOMING week (web weekViewStart).
    static func weekViewStart(for date: Date) -> Date {
        var cal = Calendar(identifier: .iso8601)
        cal.firstWeekday = 2
        let dow = Calendar.current.component(.weekday, from: date) // 1=Sun
        let anchor = dow == 1 ? cal.date(byAdding: .day, value: 1, to: date)! : date
        let comps = cal.dateComponents([.yearForWeekOfYear, .weekOfYear], from: anchor)
        return cal.startOfDay(for: cal.date(from: comps)!)
    }

    // MARK: - Calendar grid bounds (web calendarMetrics.computeDayBounds)
    struct DayBounds: Equatable { var startMin: Int; var endMin: Int }
    static let defaultDayBounds = DayBounds(startMin: 7 * 60, endMin: 19 * 60)

    /// Visible hour range from every class's times (incl. dayTimes), unioned with 7 AM–7 PM.
    static func computeDayBounds(classes: [SchoolClass], lunch: [String: DayTime]? = nil) -> DayBounds {
        var minStart = Int.max, maxEnd = Int.min
        func consider(_ s: String, _ e: String) {
            guard !s.isEmpty, !e.isEmpty else { return }
            let sm = timeToMinutes(s), em = timeToMinutes(e)
            guard em > sm else { return }
            minStart = min(minStart, sm); maxEnd = max(maxEnd, em)
        }
        for c in classes {
            consider(c.startTime, c.endTime)
            for dt in c.dayTimes?.values ?? [:].values { consider(dt.startTime, dt.endTime) }
        }
        for dt in lunch?.values ?? [:].values { consider(dt.startTime, dt.endTime) }
        guard minStart != Int.max, maxEnd != Int.min else { return defaultDayBounds }
        let paddedStart = Int(floor(Double(minStart - 30) / 60.0)) * 60
        let paddedEnd = Int(ceil(Double(maxEnd + 30) / 60.0)) * 60
        return DayBounds(startMin: max(0, min(defaultDayBounds.startMin, paddedStart)),
                         endMin: min(24 * 60, max(defaultDayBounds.endMin, paddedEnd)))
    }

    static func hours(in b: DayBounds) -> [Int] {
        let sh = b.startMin / 60
        let eh = Int(ceil(Double(b.endMin) / 60.0))
        return Array(sh...eh)
    }

    static func hourLabel(_ hour: Int) -> String {
        let h12 = hour % 12 == 0 ? 12 : hour % 12
        return "\(h12) \(hour < 12 || hour == 24 ? "AM" : "PM")"
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

    // MARK: - "1-6 Schedule" generation
    // The six periods a straight "1-6" day actually runs. Anything else on a
    // student's normal schedule — a period-9 Extension/Advisory block, a zero
    // period, etc. — does not meet at all on a 1-6 day.
    static let oneToSixCorePeriods: Set<Int> = [1, 2, 3, 4, 5, 6]

    /// Generate "1-6 Schedule" overrides (port of web generateOneToSixOverrides).
    /// Core periods 1-6 run at their own normal times; every other period the
    /// student has is explicitly cancelled (shown crossed out, not just dropped).
    /// A Lunch override (period 0) is inserted into the largest ≥20-minute gap
    /// between core periods, if the day has a lunch period at all.
    ///
    /// Web's version detects "does this day have lunch" from a `__lunch__`
    /// sentinel class mixed into its `classes` array; Apple tracks lunch
    /// separately (`CanopyStore.lunchTime(for:)`), so callers pass that as
    /// `hasLunch` instead.
    static func generateOneToSixOverrides(classes: [SchoolClass], hasLunch: Bool) -> [PeriodOverride] {
        var byPeriod: [Int: SchoolClass] = [:]
        for c in classes where byPeriod[c.period] == nil { byPeriod[c.period] = c }
        let allPeriods = byPeriod.keys.sorted().compactMap { byPeriod[$0] }
        let corePeriods = allPeriods.filter { oneToSixCorePeriods.contains($0.period) }
        let otherPeriods = allPeriods.filter { !oneToSixCorePeriods.contains($0.period) }

        var overrides = corePeriods.map {
            PeriodOverride(period: $0.period, startTime: $0.startTime, endTime: $0.endTime, cancelled: false)
        }
        overrides += otherPeriods.map {
            PeriodOverride(period: $0.period, startTime: $0.startTime, endTime: $0.endTime, cancelled: true)
        }

        if hasLunch, corePeriods.count >= 2 {
            var gapIdx = -1
            var gapSize = 0
            for i in 0..<(corePeriods.count - 1) {
                let gap = timeToMinutes(corePeriods[i + 1].startTime) - timeToMinutes(corePeriods[i].endTime)
                if gap > gapSize { gapSize = gap; gapIdx = i }
            }
            // Only treat it as a lunch break if the gap is meaningfully longer
            // than a passing period — otherwise leave Lunch out rather than guess.
            if gapIdx != -1, gapSize >= 20 {
                overrides.append(PeriodOverride(
                    period: 0,
                    startTime: corePeriods[gapIdx].endTime,
                    endTime: corePeriods[gapIdx + 1].startTime,
                    cancelled: false))
            }
        }
        return overrides
    }

    // MARK: - Assembly-day generation (web generateAssemblyOverrides)
    static let assemblyClassMinutes = 70
    static let assemblyPassingMinutes = 8
    static let assemblyLunchMinutes = 32
    static let assemblyBlockMinutes = 45

    static func isLathropExtensionClass(_ name: String) -> Bool {
        name.range(of: #"\b(ext|extension|seminar|advisory|homeroom)\b"#, options: [.regularExpression, .caseInsensitive]) != nil
    }

    /// Compressed assembly schedule: Extension dropped, core periods back-to-back
    /// (70 min + 8 passing), Lunch (32) at its natural gap, 45-minute Assembly at the end.
    static func generateAssemblyOverrides(classes: [SchoolClass], dayOfWeek: Int, hasLunch: Bool) -> [PeriodOverride] {
        var byPeriod: [Int: SchoolClass] = [:]
        var order: [Int] = []
        for c in classes where c.days.contains(dayOfWeek) && c.id != lunchClassId {
            if byPeriod[c.period] == nil { byPeriod[c.period] = c; order.append(c.period) }
        }
        let allPeriods = order.compactMap { byPeriod[$0] }
        if allPeriods.isEmpty { return [] }
        func dayStart(_ c: SchoolClass) -> String { let v = c.dayTimes?[String(dayOfWeek)]?.startTime ?? ""; return v.isEmpty ? c.startTime : v }
        func dayEnd(_ c: SchoolClass) -> String { let v = c.dayTimes?[String(dayOfWeek)]?.endTime ?? ""; return v.isEmpty ? c.endTime : v }

        let ext = allPeriods.filter { isLathropExtensionClass($0.name) }
        let core = allPeriods.filter { !isLathropExtensionClass($0.name) }
            .sorted { timeToMinutes(dayStart($0)) < timeToMinutes(dayStart($1)) }
        if core.isEmpty { return [] }
        let anchorStart = allPeriods.map { timeToMinutes(dayStart($0)) }.min() ?? 0

        var lunchAfterIdx = -1
        if hasLunch, core.count >= 2 {
            var gapSize = 0
            for i in 0..<(core.count - 1) {
                let gap = timeToMinutes(dayStart(core[i + 1])) - timeToMinutes(dayEnd(core[i]))
                if gap > gapSize { gapSize = gap; lunchAfterIdx = i }
            }
        }

        var overrides: [PeriodOverride] = []
        var cursor = anchorStart
        for (i, c) in core.enumerated() {
            let start = cursor, end = start + assemblyClassMinutes
            overrides.append(PeriodOverride(period: c.period, startTime: minutesToTime(start), endTime: minutesToTime(end), cancelled: false))
            cursor = end + assemblyPassingMinutes
            if i == lunchAfterIdx {
                let ls = cursor, le = ls + assemblyLunchMinutes
                overrides.append(PeriodOverride(period: 0, startTime: minutesToTime(ls), endTime: minutesToTime(le), cancelled: false))
                cursor = le + assemblyPassingMinutes
            }
        }
        for e in ext {
            overrides.append(PeriodOverride(period: e.period, startTime: dayStart(e), endTime: dayEnd(e), cancelled: true))
        }
        overrides.append(PeriodOverride(period: assemblyPeriod, startTime: minutesToTime(cursor), endTime: minutesToTime(cursor + assemblyBlockMinutes), cancelled: false))
        return overrides
    }

    // MARK: - Full weekly Lathrop bell schedule ("Apply Default Bell Schedule")
    // Port of web src/app/settings/page.tsx::applyLathropSchedule. Unlike the
    // early-out template above (used only when creating an early-out
    // disruption), this replaces a class's everyday startTime/endTime/days so
    // the whole week's A/B rotation applies automatically.
    enum LathropSlot: Hashable { case ext, period(Int) }

    /// Keys are weekday numbers 1=Mon...5=Fri — the same convention
    /// `SchoolClass.dayTimes` already uses, so no conversion is needed.
    static let lathropWeekTemplate: [Int: [LathropSlot: DayTime]] = [
        1: [.period(1): DayTime(startTime: "07:30", endTime: "08:24"), .period(2): DayTime(startTime: "08:31", endTime: "09:25"),
            .period(3): DayTime(startTime: "09:32", endTime: "10:26"), .period(4): DayTime(startTime: "11:04", endTime: "11:58"),
            .period(5): DayTime(startTime: "12:05", endTime: "12:59"), .period(6): DayTime(startTime: "13:06", endTime: "14:00")],
        2: [.ext: DayTime(startTime: "07:30", endTime: "08:05"), .period(1): DayTime(startTime: "08:13", endTime: "09:26"),
            .period(2): DayTime(startTime: "09:34", endTime: "10:47"), .period(4): DayTime(startTime: "11:26", endTime: "12:39"),
            .period(5): DayTime(startTime: "12:47", endTime: "14:00")],
        3: [.ext: DayTime(startTime: "07:30", endTime: "08:05"), .period(2): DayTime(startTime: "08:13", endTime: "09:26"),
            .period(3): DayTime(startTime: "09:34", endTime: "10:47"), .period(5): DayTime(startTime: "11:26", endTime: "12:39"),
            .period(6): DayTime(startTime: "12:47", endTime: "14:00")],
        4: [.ext: DayTime(startTime: "07:30", endTime: "08:05"), .period(1): DayTime(startTime: "08:13", endTime: "09:26"),
            .period(3): DayTime(startTime: "09:34", endTime: "10:47"), .period(4): DayTime(startTime: "11:26", endTime: "12:39"),
            .period(6): DayTime(startTime: "12:47", endTime: "14:00")],
        5: [.period(1): DayTime(startTime: "07:30", endTime: "08:24"), .period(2): DayTime(startTime: "08:31", endTime: "09:25"),
            .period(3): DayTime(startTime: "09:32", endTime: "10:26"), .period(4): DayTime(startTime: "11:04", endTime: "11:58"),
            .period(5): DayTime(startTime: "12:05", endTime: "12:59"), .period(6): DayTime(startTime: "13:06", endTime: "14:00")],
    ]

    struct LathropApplyResult {
        var updatedClasses: [SchoolClass]
        var appliedCount: Int
        var skippedCount: Int
    }

    /// Build updated copies of `classes` per the full weekly Lathrop template.
    /// Matches a class to the "ext" slot by name (same regex as
    /// `buildLathropEarlyOutTemplate`), else by period number 1-6. Classes
    /// matching neither slot are left out of `updatedClasses` and counted as
    /// skipped — callers should leave those classes untouched.
    static func applyLathropWeekSchedule(classes: [SchoolClass]) -> LathropApplyResult {
        let extRegex = #"\b(ext|extension|seminar|advisory|homeroom)\b"#
        var updated: [SchoolClass] = []
        var applied = 0, skipped = 0
        for c in classes {
            let slot: LathropSlot?
            if c.name.range(of: extRegex, options: [.regularExpression, .caseInsensitive]) != nil {
                slot = .ext
            } else if (1...6).contains(c.period) {
                slot = .period(c.period)
            } else {
                slot = nil
            }
            guard let slot else { skipped += 1; continue }

            var days: [Int] = []
            var dayTimes: [String: DayTime] = [:]
            for d in 1...5 {
                if let t = lathropWeekTemplate[d]?[slot] {
                    days.append(d)
                    dayTimes[String(d)] = t
                }
            }
            guard let firstDay = days.first, let representative = dayTimes[String(firstDay)] else {
                skipped += 1; continue
            }
            var out = c
            out.startTime = representative.startTime
            out.endTime = representative.endTime
            out.days = days.sorted()
            out.dayTimes = dayTimes
            updated.append(out)
            applied += 1
        }
        return LathropApplyResult(updatedClasses: updated, appliedCount: applied, skippedCount: skipped)
    }
}
