import SwiftUI

// Port of web src/app/transcript/page.tsx — GPA estimate (unweighted and
// AP-weighted, whole-letter scale) built from PowerSchool sync snapshots.

// MARK: - Data model

private struct SemesterRow: Identifiable {
    let semester: String
    let classes: [ClassGpaRow]
    let semesterGpa: Double
    let semesterGpaWeighted: Double
    let capturedAt: String
    var id: String { semester }
}

private struct ClassGpaRow: Identifiable {
    let classId: String
    let name: String
    let gradePercent: Double
    let letter: String
    let gpa: Double
    let gpaWeighted: Double
    let isAp: Bool
    var id: String { classId }
}

// MARK: - Build transcript

private func buildTranscript(history: [GradeHistoryEntry], classes: [SchoolClass]) -> [SemesterRow] {
    let byId = Dictionary(classes.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })

    // For each (semester, class) pair take the most recent snapshot.
    var latest: [String: GradeHistoryEntry] = [:]
    for e in history where e.gradePercent != nil {
        let key = "\(e.semester)||\(e.classId)"
        if let existing = latest[key] {
            if e.capturedAt > existing.capturedAt { latest[key] = e }
        } else {
            latest[key] = e
        }
    }

    var bySemester: [String: [GradeHistoryEntry]] = [:]
    for e in latest.values { bySemester[e.semester, default: []].append(e) }

    var rows: [SemesterRow] = []
    for (semester, entries) in bySemester {
        let cls = entries.compactMap { e -> ClassGpaRow? in
            guard let pct = e.gradePercent else { return nil }
            let isAp = byId[e.classId]?.isAp == true
            return ClassGpaRow(
                classId: e.classId,
                name: byId[e.classId]?.name ?? "Unknown Class",
                gradePercent: pct,
                letter: e.letter?.nonEmpty ?? GradesUtil.letterFromPercent(pct),
                gpa: unweightedGpaPoints(pct),
                gpaWeighted: weightedGpaPoints(pct, isAp: isAp),
                isAp: isAp
            )
        }.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }

        guard !cls.isEmpty else { continue }
        let gpa = cls.reduce(0) { $0 + $1.gpa } / Double(cls.count)
        let weighted = cls.reduce(0) { $0 + $1.gpaWeighted } / Double(cls.count)
        let capturedAt = entries.map(\.capturedAt).max() ?? ""
        rows.append(SemesterRow(semester: semester, classes: cls, semesterGpa: gpa,
                                semesterGpaWeighted: weighted, capturedAt: capturedAt))
    }
    return rows.sorted { $0.capturedAt > $1.capturedAt }
}

// MARK: - Transcript View

struct TranscriptView: View {
    @Environment(CanopyStore.self) private var store

    private var transcript: [SemesterRow] {
        buildTranscript(history: store.gradeHistory, classes: store.classes)
    }

    private var classCount: Int { transcript.reduce(0) { $0 + $1.classes.count } }

    private var cumulativeGpa: Double? {
        guard classCount > 0 else { return nil }
        return transcript.reduce(0.0) { $0 + $1.semesterGpa * Double($1.classes.count) } / Double(classCount)
    }

    private var cumulativeGpaWeighted: Double? {
        guard classCount > 0 else { return nil }
        return transcript.reduce(0.0) { $0 + $1.semesterGpaWeighted * Double($1.classes.count) } / Double(classCount)
    }

    var body: some View {
        ZStack { CanopyBackground()
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    headerCard
                    if transcript.isEmpty {
                        emptyState
                    } else {
                        ForEach(transcript) { row in
                            semesterCard(row)
                        }
                    }
                }
                .padding(16)
                .padding(.bottom, 32)
            }
        }
        .navigationTitle("Transcript")
        .navigationBarTitleInline()
        .refreshable { await store.loadAll() }
    }

    // MARK: Header (title, subtitle, cumulative GPAs)

    private var headerCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    Image(systemName: "chart.xyaxis.line").foregroundStyle(Color.accentColor)
                    Text("Transcript")
                }
                .font(.title3.bold())
                .fontDesign(.rounded)
                Text("GPA estimate — unweighted and AP-weighted — based on PowerSchool sync snapshots.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            if let gpa = cumulativeGpa, let weighted = cumulativeGpaWeighted {
                HStack(alignment: .bottom, spacing: 24) {
                    gpaColumn(label: "Unweighted GPA", value: gpa, big: true)
                    gpaColumn(label: "Weighted GPA", value: weighted, big: true)
                    Spacer()
                    Text("\(classCount) class\(classCount == 1 ? "" : "es")")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
    }

    private func gpaColumn(label: String, value: Double, big: Bool) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label).font(.caption2).foregroundStyle(.secondary)
            Text(String(format: "%.2f", value))
                .font(big ? .system(size: 32, weight: .semibold, design: .rounded) : .title2.weight(.semibold))
                .monospacedDigit()
                .foregroundStyle(GradesUtil.gpaColor(value))
        }
    }

    // MARK: Semester card

    private func semesterCard(_ row: SemesterRow) -> some View {
        let weightedColor = GradesUtil.gpaColor(row.semesterGpaWeighted)
        return VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 3) {
                    Text(row.semester).font(.headline)
                    Text("\(row.classes.count) class\(row.classes.count == 1 ? "" : "es") · as of \(GradesDisplay.shortDate(row.capturedAt))")
                        .font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
                HStack(spacing: 16) {
                    VStack(alignment: .trailing, spacing: 2) {
                        Text("Unweighted").font(.caption2).foregroundStyle(.secondary)
                        Text(String(format: "%.2f", row.semesterGpa))
                            .font(.title2.weight(.semibold)).monospacedDigit()
                            .foregroundStyle(GradesUtil.gpaColor(row.semesterGpa))
                    }
                    VStack(alignment: .trailing, spacing: 2) {
                        Text("Weighted").font(.caption2).foregroundStyle(.secondary)
                        Text(String(format: "%.2f", row.semesterGpaWeighted))
                            .font(.title2.weight(.semibold)).monospacedDigit()
                            .foregroundStyle(weightedColor)
                    }
                }
            }
            .padding(14)

            // Weighted scale (0–5) so AP bars can exceed the unweighted 4.0 reference.
            GradeProgressBar(value: row.semesterGpaWeighted / 5, color: weightedColor)
                .padding(.horizontal, 14)
                .padding(.bottom, 12)

            Divider()

            ForEach(Array(row.classes.enumerated()), id: \.element.id) { idx, cls in
                classRow(cls)
                if idx < row.classes.count - 1 { Divider().padding(.leading, 14) }
            }
        }
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
    }

    private func classRow(_ cls: ClassGpaRow) -> some View {
        let c = GradesUtil.gradeColor(cls.gradePercent)
        return VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                Text(cls.name).font(.subheadline).lineLimit(1)
                if cls.isAp {
                    Text("AP")
                        .font(.system(size: 9, weight: .bold))
                        .padding(.horizontal, 5).padding(.vertical, 1)
                        .background(Color.accentColor, in: Capsule())
                        .foregroundStyle(.white)
                }
                Spacer()
                Text(GradesDisplay.pct1(cls.gradePercent))
                    .font(.subheadline.weight(.semibold)).monospacedDigit()
                    .foregroundStyle(c)
                Text(cls.letter)
                    .font(.caption2.bold())
                    .padding(.horizontal, 6).padding(.vertical, 2)
                    .background(c.opacity(0.12), in: Capsule())
                    .foregroundStyle(c)
            }
            HStack(spacing: 12) {
                GradeProgressBar(value: cls.gpaWeighted / 5, color: c, height: 6)
                HStack(spacing: 3) {
                    Text("GPA pts").font(.caption2).foregroundStyle(.secondary)
                    Text(String(format: "%.1f", cls.gpa))
                        .font(.caption.weight(.medium)).monospacedDigit().foregroundStyle(c)
                }
                HStack(spacing: 3) {
                    Text("Weighted").font(.caption2).foregroundStyle(.secondary)
                    Text(String(format: "%.1f", cls.gpaWeighted))
                        .font(.caption.weight(.medium)).monospacedDigit()
                        .foregroundStyle(cls.isAp ? Color.accentColor : c)
                }
            }
        }
        .padding(.horizontal, 14).padding(.vertical, 10)
    }

    // MARK: Empty state

    private var emptyState: some View {
        VStack(spacing: 12) {
            Image(systemName: "graduationcap")
                .font(.system(size: 56))
                .foregroundStyle(.tertiary)
            Text("No grade history yet").font(.title3.weight(.semibold))
            Text("Sync from PowerSchool on the Grades page. Each sync snapshots your grades and builds up the history shown here.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .padding(.vertical, 40)
        .padding(.horizontal, 24)
        .frame(maxWidth: .infinity)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
    }
}
