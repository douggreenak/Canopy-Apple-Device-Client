import Foundation

// MARK: - Heatmap Day

struct HeatmapDay: Identifiable {
    var id: String { date }
    let date: String  // YYYY-MM-DD
    let hwCount: Int
    let taskCount: Int
    let total: Int
    let intensity: Int  // 0 = none, 1 = light, 2 = moderate, 3 = heavy
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

// MARK: - Build 14-day heatmap

func buildHeatmap(homework: [Homework], tasks: [SchoolTask], days: Int = 14) -> [HeatmapDay] {
    let cal = Calendar.current
    let today = cal.startOfDay(for: .now)
    let iso = DateFormatter.iso

    var counts: [(date: String, hw: Int, task: Int)] = (0..<days).map { i in
        let d = cal.date(byAdding: .day, value: i, to: today)!
        return (date: iso.string(from: d), hw: 0, task: 0)
    }

    for hw in homework {
        guard !hw.completed, !hw.dueDate.isEmpty else { continue }
        if let idx = counts.firstIndex(where: { $0.date == hw.dueDate }) {
            counts[idx].hw += 1
        }
    }
    for task in tasks {
        guard !task.completed, !task.dueDate.isEmpty else { continue }
        if let idx = counts.firstIndex(where: { $0.date == task.dueDate }) {
            counts[idx].task += 1
        }
    }

    let peak = counts.map { $0.hw + $0.task }.max() ?? 0
    return counts.map { c in
        let total = c.hw + c.task
        let intensity: Int
        if total == 0 || peak == 0 { intensity = 0 }
        else {
            let r = Double(total) / Double(peak)
            intensity = r <= 0.33 ? 1 : r <= 0.66 ? 2 : 3
        }
        return HeatmapDay(date: c.date, hwCount: c.hw, taskCount: c.task, total: total, intensity: intensity)
    }
}

// MARK: - Rebalancing suggestions

private let rebalanceFmt: DateFormatter = {
    let f = DateFormatter()
    f.dateFormat = "EEE MMM d"
    return f
}()

/// Find homework items whose due dates cluster (3+ within ±1 day) and suggest starting earlier.
func suggestRebalancing(homework: [Homework]) -> [RebalanceSuggestion] {
    let iso = DateFormatter.iso
    let today = Calendar.current.startOfDay(for: .now)
    let todayStr = iso.string(from: today)

    let upcoming = homework.filter { !$0.completed && !$0.dueDate.isEmpty && $0.dueDate >= todayStr }

    var dueCounts: [String: Int] = [:]
    for hw in upcoming { dueCounts[hw.dueDate, default: 0] += 1 }

    var suggestions: [RebalanceSuggestion] = []
    for hw in upcoming {
        guard let hwDate = hw.dueDate.asDate else { continue }

        var cluster = 0
        for (d, count) in dueCounts {
            guard let date = d.asDate else { continue }
            let diff = abs(Calendar.current.dateComponents([.day], from: hwDate, to: date).day ?? 999)
            if diff <= 1 { cluster += count }
        }
        guard cluster >= 3 else { continue }

        let daysUntil = Calendar.current.dateComponents([.day], from: today, to: hwDate).day ?? 0
        // Require ≥2 days so we never suggest "start by tomorrow on something due tomorrow."
        guard daysUntil >= 2 else { continue }

        let startByDate = Calendar.current.date(byAdding: .day, value: -min(2, daysUntil - 1), to: hwDate)!
        let startByStr = iso.string(from: startByDate)
        guard startByStr > todayStr else { continue }

        suggestions.append(RebalanceSuggestion(
            homework: hw,
            currentDue: hw.dueDate,
            clusterSize: cluster,
            startBy: startByStr,
            reason: "Start by \(rebalanceFmt.string(from: startByDate)) — clusters with \(cluster - 1) other item\(cluster - 1 == 1 ? "" : "s")"
        ))
    }
    return Array(suggestions.prefix(10))
}
