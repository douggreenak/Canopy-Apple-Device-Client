import Foundation

// MARK: - Category Average

/// Equal-weight average of all graded (non-missing) assignments in a category.
func categoryAverage(assignments: [Homework], category: String) -> Double? {
    let graded = assignments.filter {
        $0.category == category &&
        $0.scorePercent != nil &&
        !($0.flags?.lowercased().contains("missing") ?? false)
    }
    guard !graded.isEmpty else { return nil }
    let sum = graded.compactMap(\.scorePercent).reduce(0, +)
    return sum / Double(graded.count)
}

// MARK: - Overall Grade

/// Weighted average across active categories only (renormalizes over categories with graded items).
func overallGrade(assignments: [Homework], weights: [String: Double]) -> Double? {
    let cats = weights.keys.filter { (weights[$0] ?? 0) > 0 }
    var active: [(avg: Double, weight: Double)] = []
    for cat in cats {
        if let avg = categoryAverage(assignments: assignments, category: cat) {
            active.append((avg: avg, weight: weights[cat] ?? 0))
        }
    }
    guard !active.isEmpty else { return nil }
    let totalWeight = active.reduce(0) { $0 + $1.weight }
    return active.reduce(0) { $0 + $1.avg * ($1.weight / totalWeight) }
}

// MARK: - What-if Simulation

/// Simulate scoring `percent` on a new assignment in `category` and return the projected overall grade.
/// Appends a synthetic assignment so existing scores in the category are preserved — matches TS behavior.
func simulateWhatIf(
    assignments: [Homework],
    weights: [String: Double],
    category: String,
    percent: Double
) -> Double? {
    let fake = Homework(
        id: "__whatif__",
        classId: assignments.first?.classId ?? "",
        title: "Hypothetical",
        description: "",
        dueDate: "",
        completed: false,
        priority: "medium",
        source: "",
        sourceId: nil,
        score: nil,
        scorePercent: percent,
        category: category,
        flags: nil
    )
    return overallGrade(assignments: assignments + [fake], weights: weights)
}

// MARK: - Most Impactful Assignment

/// Compare after vs before state and find the assignment whose score change moved the grade most.
func mostImpactfulAssignment(
    after: [Homework],
    before: [Homework],
    weights: [String: Double]
) -> (homework: Homework, delta: Double)? {
    guard let afterGrade = overallGrade(assignments: after, weights: weights) else { return nil }

    var best: (homework: Homework, delta: Double)?
    for hw in after {
        let hwKey = hw.sourceId ?? hw.id
        guard let prior = before.first(where: { ($0.sourceId ?? $0.id) == hwKey }) else { continue }
        guard prior.scorePercent != hw.scorePercent else { continue }

        let hypothetical = after.map { a -> Homework in
            guard (a.sourceId ?? a.id) == hwKey else { return a }
            var m = a; m.scorePercent = prior.scorePercent; return m
        }
        guard let hypoGrade = overallGrade(assignments: hypothetical, weights: weights) else { continue }
        let delta = afterGrade - hypoGrade
        if best == nil || abs(delta) > abs(best!.delta) {
            best = (homework: hw, delta: delta)
        }
    }
    return best
}

// MARK: - Missing Work Impact

/// Rank Missing-flagged assignments by how much each one hurts the grade (worst first).
func missingWorkImpact(
    assignments: [Homework],
    weights: [String: Double]
) -> [(homework: Homework, gradeImpactPercent: Double)] {
    guard let currentGrade = overallGrade(assignments: assignments, weights: weights) else { return [] }

    let missing = assignments.filter {
        ($0.flags?.lowercased().contains("missing") ?? false) && $0.category != nil
    }
    var impacts: [(homework: Homework, gradeImpactPercent: Double)] = []
    for hw in missing {
        let hypothetical = assignments.map { a -> Homework in
            guard a.id == hw.id else { return a }
            var m = a; m.scorePercent = 0; m.flags = nil; return m
        }
        guard let hypoGrade = overallGrade(assignments: hypothetical, weights: weights) else { continue }
        let impact = currentGrade - hypoGrade
        if impact > 0 { impacts.append((homework: hw, gradeImpactPercent: impact)) }
    }
    return impacts.sorted { $0.gradeImpactPercent > $1.gradeImpactPercent }
}
