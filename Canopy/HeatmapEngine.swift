import Foundation

// Port of web src/lib/heatmap.ts and src/lib/dueCounts.ts.

// MARK: - Heatmap Day

struct HeatmapDay: Identifiable {
    var id: String { date }
    let date: String  // YYYY-MM-DD
    let hwCount: Int
    let taskCount: Int
    let total: Int
    let intensity: Int  // 0 = none, 1 = light, 2 = moderate, 3 = heavy
    /// Present when a schedule disruption covers this date.
    let disruption: (type: String, label: String)?
}

// MARK: - Rebalance Suggestion

struct RebalanceSuggestion: Identifiable {
    var id: String { homework.id }
    let homework: Homework
    let currentDue: String
    let clusterSize: Int
    let startBy: String
    let reason: String
}

/// Absolute item-count bands (not relative to the busiest day).
private func intensityFor(_ total: Int) -> Int {
    if total == 0 { return 0 }
    if total <= 2 { return 1 }
    if total <= 4 { return 2 }
    return 3
}

// MARK: - Build 14-day heatmap

/// Only user-created items count: tasks always, homework only when `source == "manual"`.
func buildHeatmap(homework: [Homework], tasks: [SchoolTask], disruptions: [ScheduleDisruption] = [], days: Int = 14) -> [HeatmapDay] {
    let cal = Calendar.current
    let today = cal.startOfDay(for: .now)
    let iso = DateFormatter.iso

    var counts: [(date: String, hw: Int, task: Int)] = (0..<days).map { i in
        let d = cal.date(byAdding: .day, value: i, to: today)!
        return (date: iso.string(from: d), hw: 0, task: 0)
    }

    for hw in homework {
        guard hw.source == "manual", !hw.dueDate.isEmpty, !hw.completed else { continue }
        if let idx = counts.firstIndex(where: { $0.date == hw.dueDate }) { counts[idx].hw += 1 }
    }
    for task in tasks {
        guard !task.completed, !task.dueDate.isEmpty else { continue }
        if let idx = counts.firstIndex(where: { $0.date == task.dueDate }) { counts[idx].task += 1 }
    }

    return counts.map { c in
        let total = c.hw + c.task
        let dis = disruptions.first { $0.covers(c.date) }
        return HeatmapDay(date: c.date, hwCount: c.hw, taskCount: c.task, total: total,
                          intensity: intensityFor(total),
                          disruption: dis.map { ($0.type, $0.displayLabel) })
    }
}

// MARK: - Rebalancing suggestions

private let rebalanceMonthDay: DateFormatter = {
    let f = DateFormatter(); f.dateFormat = "MMM d"; return f
}()

/// Homework items (manual only) whose due dates cluster (3+ within ±1 day).
func suggestRebalancing(homework: [Homework]) -> [RebalanceSuggestion] {
    let iso = DateFormatter.iso
    let cal = Calendar.current
    let today = cal.startOfDay(for: .now)
    let todayStr = iso.string(from: today)

    let upcoming = homework.filter { $0.source == "manual" && !$0.completed && !$0.dueDate.isEmpty && $0.dueDate >= todayStr }

    var dueCounts: [String: Int] = [:]
    for hw in upcoming { dueCounts[hw.dueDate, default: 0] += 1 }

    var suggestions: [RebalanceSuggestion] = []
    for hw in upcoming {
        guard let hwDate = hw.dueDate.asDate else { continue }
        var cluster = 0
        for (d, count) in dueCounts {
            guard let date = d.asDate else { continue }
            let diff = abs(cal.dateComponents([.day], from: hwDate, to: date).day ?? 999)
            if diff <= 1 { cluster += count }
        }
        guard cluster >= 3 else { continue }
        let daysUntil = cal.dateComponents([.day], from: today, to: hwDate).day ?? 0
        guard daysUntil >= 2 else { continue }
        let startByDate = cal.date(byAdding: .day, value: -min(2, daysUntil - 1), to: hwDate)!
        let startByStr = iso.string(from: startByDate)
        guard startByStr > todayStr else { continue }
        let others = cluster - 1
        suggestions.append(RebalanceSuggestion(
            homework: hw, currentDue: hw.dueDate, clusterSize: cluster, startBy: startByStr,
            reason: "Clusters with \(others) other item\(others == 1 ? "" : "s") around \(rebalanceMonthDay.string(from: hwDate))"
        ))
    }
    return Array(suggestions.prefix(10))
}

// MARK: - Due-count badges (web src/lib/dueCounts.ts)

/// `classId::date` → count. Tasks always count; homework only when manual.
/// Items with dueTiming == "after_class" are excluded. Completed items still count.
func buildDueCountMap(homework: [Homework], tasks: [SchoolTask]) -> [String: Int] {
    var map: [String: Int] = [:]
    for h in homework {
        guard h.source == "manual", !h.classId.isEmpty, !h.dueDate.isEmpty, h.dueTiming != "after_class" else { continue }
        map["\(h.classId)::\(h.dueDate)", default: 0] += 1
    }
    for t in tasks {
        guard let cid = t.classId, !cid.isEmpty, !t.dueDate.isEmpty, t.dueTiming != "after_class" else { continue }
        map["\(cid)::\(t.dueDate)", default: 0] += 1
    }
    return map
}

func dueCountFor(_ map: [String: Int], classId: String, date: String) -> Int {
    map["\(classId)::\(date)"] ?? 0
}
