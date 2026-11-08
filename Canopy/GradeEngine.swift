import Foundation

// Port of web src/lib/gradeEngine.ts — pure grade math. All percents 0–100.

// MARK: - GPA points (whole-letter scale; A- = 4.0, deliberately)

func unweightedGpaPoints(_ percent: Double) -> Double {
    if percent >= 90 { return 4.0 }
    if percent >= 80 { return 3.0 }
    if percent >= 70 { return 2.0 }
    if percent >= 60 { return 1.0 }
    return 0.0
}

/// Standard AP weighting: +1.0 on top of the unweighted points.
func weightedGpaPoints(_ percent: Double, isAp: Bool?) -> Double {
    unweightedGpaPoints(percent) + ((isAp ?? false) ? 1.0 : 0)
}

// MARK: - Category matching

/// Case/punctuation-insensitive normalisation ("Quizzes/Labs" → "quizzeslabs").
func normCat(_ s: String) -> String {
    s.lowercased().replacingOccurrences(of: "[^a-z0-9]+", with: "", options: .regularExpression)
}

/// "Quizzes - Short Writes" matches "Quiz"; "Tests" matches "Test": equal, or
/// one (≥3 chars) is a prefix of the other.
func categoriesMatch(_ a: String, _ b: String) -> Bool {
    let x = normCat(a), y = normCat(b)
    if x.isEmpty || y.isEmpty { return false }
    if x == y { return true }
    let (short, long) = x.count <= y.count ? (x, y) : (y, x)
    return short.count >= 3 && long.hasPrefix(short)
}

// MARK: - Category Average

/// Equal-weight mean of scorePercent for graded assignments in one category.
func categoryAverage(assignments: [Homework], category: String) -> Double? {
    let graded = assignments.filter { categoriesMatch($0.category ?? "", category) && $0.scorePercent != nil }
    guard !graded.isEmpty else { return nil }
    let sum = graded.compactMap(\.scorePercent).reduce(0, +)
    return sum / Double(graded.count)
}

// MARK: - Overall Grade

/// Weighted overall grade, renormalised over categories that have graded items.
func overallGrade(assignments: [Homework], weights: [String: Double]) -> Double? {
    var active: [(avg: Double, weight: Double)] = []
    for (cat, weight) in weights {
        if let avg = categoryAverage(assignments: assignments, category: cat) {
            active.append((avg: avg, weight: weight))
        }
    }
    guard !active.isEmpty else { return nil }
    let totalWeight = active.reduce(0) { $0 + $1.weight }
    guard totalWeight != 0 else { return nil }
    return active.reduce(0) { $0 + ($1.weight / totalWeight) * $1.avg }
}

// MARK: - What-if Simulation

/// Inject a hypothetical assignment into `category` and return the projected grade.
func simulateWhatIf(assignments: [Homework], weights: [String: Double], category: String, percent: Double) -> Double? {
    let fake = Homework(id: "__whatif__", classId: "", title: "Hypothetical", description: "", dueDate: "",
                        completed: false, priority: "medium", source: "manual", sourceId: nil, score: nil,
                        scorePercent: percent, category: category, flags: nil)
    return overallGrade(assignments: assignments + [fake], weights: weights)
}

/// Swap one existing assignment's score for a hypothetical one.
func simulateScoreChange(assignments: [Homework], weights: [String: Double], assignmentId: String, percent: Double) -> Double? {
    let updated = assignments.map { h -> Homework in
        guard h.id == assignmentId else { return h }
        var m = h; m.scorePercent = percent; return m
    }
    return overallGrade(assignments: updated, weights: weights)
}

// MARK: - calcGrade (weighted, else points-based / mean)

enum GradeMethod: String { case weighted, average }

struct CalcGradeResult { var grade: Double?; var method: GradeMethod }

func calcGrade(assignments: [Homework], weights: [String: Double]) -> CalcGradeResult {
    if let w = overallGrade(assignments: assignments, weights: weights) {
        return CalcGradeResult(grade: w, method: .weighted)
    }
    let scored = assignments.filter { $0.scorePercent != nil }
    if scored.isEmpty { return CalcGradeResult(grade: nil, method: .average) }
    // Points possible from the score text ("15/15", "--/100").
    let possible: [Double] = scored.map { h in
        let s = h.score ?? ""
        if let r = s.range(of: #"/\s*(\d+(?:\.\d+)?)"#, options: .regularExpression) {
            let frag = s[r].dropFirst().trimmingCharacters(in: .whitespaces)
            return Double(frag) ?? 0
        }
        return 0
    }
    if possible.allSatisfy({ $0 > 0 }) {
        let total = possible.reduce(0, +)
        var earned = 0.0
        for (i, h) in scored.enumerated() { earned += ((h.scorePercent ?? 0) / 100) * possible[i] }
        return CalcGradeResult(grade: earned / total * 100, method: .average)
    }
    let mean = scored.compactMap(\.scorePercent).reduce(0, +) / Double(scored.count)
    return CalcGradeResult(grade: mean, method: .average)
}

// MARK: - predictGradeChange

struct GradePrediction {
    var oldGrade: Double?
    var newGrade: Double?
    var method: GradeMethod
}

/// Predict the class grade if ONE assignment scored `percent`, anchored to the
/// official PowerSchool grade when known.
func predictGradeChange(assignments: [Homework], weights: [String: Double], assignmentId: String,
                        percent: Double, officialGrade: Double?) -> GradePrediction {
    let before = calcGrade(assignments: assignments, weights: weights)
    let updated = assignments.map { h -> Homework in
        guard h.id == assignmentId else { return h }
        var m = h; m.scorePercent = percent; return m
    }
    let after = calcGrade(assignments: updated, weights: weights)
    let method = after.method
    if let official = officialGrade, let b = before.grade, let a = after.grade, before.method == after.method {
        return GradePrediction(oldGrade: official, newGrade: max(0, official + (a - b)), method: method)
    }
    return GradePrediction(oldGrade: officialGrade ?? before.grade, newGrade: after.grade, method: method)
}

// MARK: - Most Impactful Assignment

/// Which assignment most moved the grade between two snapshots (by sourceId/id).
func mostImpactfulAssignment(after: [Homework], before: [Homework], weights: [String: Double]) -> (homework: Homework, delta: Double)? {
    var beforeById: [String: Homework] = [:]
    for h in before { beforeById[h.sourceId ?? h.id] = h }
    let current = calcGrade(assignments: after, weights: weights)
    guard let currentGrade = current.grade else { return nil }

    var candidates: [(homework: Homework, delta: Double)] = []
    for hw in after {
        guard let old = beforeById[hw.sourceId ?? hw.id] else { continue }
        if hw.scorePercent == old.scorePercent { continue }
        if let a = hw.scorePercent, let b = old.scorePercent, abs(a - b) < 0.01 { continue }
        let reverted = after.map { h -> Homework in
            guard h.id == hw.id else { return h }
            var m = h; m.scorePercent = old.scorePercent; return m
        }
        let without = calcGrade(assignments: reverted, weights: weights)
        guard let wg = without.grade, without.method == current.method else { continue }
        let delta = currentGrade - wg
        if abs(delta) < 0.001 { continue }
        candidates.append((homework: hw, delta: delta))
    }
    return candidates.max { abs($0.delta) < abs($1.delta) }
}

// MARK: - Missing Work Impact

/// Rank Missing-flagged, unscored assignments by the grade hit of scoring 0. Largest first.
func missingWorkImpact(assignments: [Homework], weights: [String: Double]) -> [(homework: Homework, gradeImpactPercent: Double)] {
    let missing = assignments.filter {
        ($0.flags?.range(of: "missing", options: .caseInsensitive) != nil) && $0.scorePercent == nil
    }
    if missing.isEmpty { return [] }
    let baseGrade = overallGrade(assignments: assignments, weights: weights) ?? 100
    let results = missing.map { hw -> (homework: Homework, gradeImpactPercent: Double) in
        var withZero = hw; withZero.scorePercent = 0
        let projected = overallGrade(assignments: assignments.filter { $0.id != hw.id } + [withZero], weights: weights) ?? baseGrade
        return (homework: hw, gradeImpactPercent: max(0, baseGrade - projected))
    }
    return results.sorted { $0.gradeImpactPercent > $1.gradeImpactPercent }
}

// MARK: - AP detection (web src/lib/apDetection.ts)

enum APDetection {
    static func detectApFromName(_ name: String) -> Bool {
        name.range(of: #"\bAP\b"#, options: [.regularExpression, .caseInsensitive]) != nil
            || name.range(of: #"\bAPUSH\b"#, options: [.regularExpression, .caseInsensitive]) != nil
    }
}

// MARK: - Exam stakes (web src/app/exams/page.tsx::examStakesText)

enum ExamStakes {
    private static let cutoffs: [(cutoff: Double, letter: String)] = [
        (97, "A+"), (93, "A"), (90, "A-"), (87, "B+"), (83, "B"), (80, "B-"),
        (77, "C+"), (73, "C"), (70, "C-"), (67, "D+"), (63, "D"), (60, "D-"), (0, "F"),
    ]

    /// Web copy: "Worth 20% of your grade — score below 75% and your B becomes a B-."
    /// nil when weight is out of range or the threshold is not in (0, 100].
    static func text(currentGrade g: Double, weight w: Double) -> String? {
        guard w > 0, w <= 100 else { return nil }
        guard let idx = cutoffs.firstIndex(where: { g >= $0.cutoff }) else { return nil }
        guard idx + 1 < cutoffs.count else { return nil }
        let drop = cutoffs[idx + 1]
        let frac = w / 100
        let threshold = (cutoffs[idx].cutoff - g * (1 - frac)) / frac
        guard threshold > 0, threshold <= 100 else { return nil }
        let wStr = w == w.rounded() ? String(Int(w)) : String(w)
        return "Worth \(wStr)% of your grade — score below \(Int(threshold.rounded(.up)))% and your \(GradesUtil.letterFromPercent(g)) becomes a \(drop.letter)."
    }

    static func fallbackText(weight w: Double) -> String {
        let wStr = w == w.rounded() ? String(Int(w)) : String(w)
        return "Worth \(wStr)% of your grade."
    }
}
