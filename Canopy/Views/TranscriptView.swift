import SwiftUI

// MARK: - GPA helpers

private func percentToGpa(_ p: Double) -> Double {
    switch p {
    case 93...: return 4.0
    case 90...: return 3.7
    case 87...: return 3.3
    case 83...: return 3.0
    case 80...: return 2.7
    case 77...: return 2.3
    case 73...: return 2.0
    case 70...: return 1.7
    case 67...: return 1.3
    case 63...: return 1.0
    case 60...: return 0.7
    default:    return 0.0
    }
}

// MARK: - Data model

private struct SemesterRow: Identifiable {
    let id: String
    let semester: String
    let classes: [ClassGpaRow]
    let semesterGpa: Double
    let capturedAt: String
}

private struct ClassGpaRow: Identifiable {
    let id: String
    let name: String
    let gradePercent: Double
    let letter: String
    let gpa: Double
}

// MARK: - Build transcript

private func buildTranscript(history: [GradeHistoryEntry], classNames: [String: String]) -> [SemesterRow] {
    var latestBySemesterClass: [String: GradeHistoryEntry] = [:]
    for e in history {
        guard e.gradePercent != nil else { continue }
        let key = "\(e.semester)||\(e.classId)"
        if let existing = latestBySemesterClass[key] {
            if e.capturedAt > existing.capturedAt { latestBySemesterClass[key] = e }
        } else {
            latestBySemesterClass[key] = e
        }
    }

    var bySemester: [String: [GradeHistoryEntry]] = [:]
    for e in latestBySemesterClass.values {
        bySemester[e.semester, default: []].append(e)
    }

    var rows: [SemesterRow] = []
    for (semester, entries) in bySemester {
        let cls = entries.compactMap { e -> ClassGpaRow? in
            guard let pct = e.gradePercent else { return nil }
            return ClassGpaRow(
                id: e.classId,
                name: classNames[e.classId] ?? "Unknown Class",
                gradePercent: pct,
                letter: e.letter ?? letterGrade(from: pct),
                gpa: percentToGpa(pct)
            )
        }.sorted { $0.name < $1.name }

        guard !cls.isEmpty else { continue }
        let semGpa = cls.reduce(0) { $0 + $1.gpa } / Double(cls.count)
        let latest = entries.sorted { $0.capturedAt > $1.capturedAt }.first?.capturedAt ?? ""
        rows.append(SemesterRow(id: semester, semester: semester, classes: cls, semesterGpa: semGpa, capturedAt: latest))
    }

    return rows.sorted { $0.capturedAt > $1.capturedAt }
}

// MARK: - Transcript View

struct TranscriptView: View {
    @Environment(CanopyStore.self) private var store

    private var classNames: [String: String] {
        Dictionary(uniqueKeysWithValues: store.classes.map { ($0.id, $0.name) })
    }

    private var transcript: [SemesterRow] {
        buildTranscript(history: store.gradeHistory, classNames: classNames)
    }

    private var cumulativeGpa: Double? {
        guard !transcript.isEmpty else { return nil }
        let weighted = transcript.reduce(0.0) { $0 + $1.semesterGpa * Double($1.classes.count) }
        let count = transcript.reduce(0) { $0 + $1.classes.count }
        return count > 0 ? weighted / Double(count) : nil
    }

    var body: some View {
        ZStack { CanopyBackground()
            if store.gradeHistory.isEmpty {
                emptyState
            } else {
                ScrollView {
                    VStack(spacing: 16) {
                        if let cum = cumulativeGpa {
                            cumulativeCard(cum)
                        }
                        ForEach(transcript) { row in
                            semesterCard(row)
                        }
                    }
                    .padding(16)
                    .padding(.bottom, 32)
                }
            }
        }
        .navigationTitle("Transcript")
        .navigationBarTitleInline()
        .refreshable { await store.loadAll() }
    }

    // MARK: - Cumulative GPA card
    private func cumulativeCard(_ gpa: Double) -> some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                Text("Cumulative GPA estimate").font(.caption).foregroundStyle(.secondary)
                Text("GPA estimate (unweighted)").font(.caption2).foregroundStyle(.tertiary)
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 2) {
                Text(String(format: "%.2f", gpa))
                    .font(.system(size: 44, weight: .bold, design: .rounded))
                    .foregroundStyle(gpaColor(gpa))
                Text("\(transcript.reduce(0) { $0 + $1.classes.count }) classes total")
                    .font(.caption2).foregroundStyle(.secondary)
            }
        }
        .padding(16)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
    }

    // MARK: - Semester card
    private func semesterCard(_ row: SemesterRow) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            // Header
            HStack {
                VStack(alignment: .leading, spacing: 3) {
                    Text(row.semester).font(.headline)
                    Text("\(row.classes.count) class\(row.classes.count == 1 ? "" : "es") · as of \(formatDate(row.capturedAt))")
                        .font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
                VStack(alignment: .trailing, spacing: 2) {
                    Text("Semester GPA").font(.caption2).foregroundStyle(.secondary)
                    Text(String(format: "%.2f", row.semesterGpa))
                        .font(.title2.bold().monospacedDigit())
                        .foregroundStyle(gpaColor(row.semesterGpa))
                }
            }
            .padding(14)

            // GPA bar
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 3)
                        .fill(gpaColor(row.semesterGpa).opacity(0.15))
                    RoundedRectangle(cornerRadius: 3)
                        .fill(gpaColor(row.semesterGpa))
                        .frame(width: geo.size.width * min(row.semesterGpa / 4.0, 1.0))
                }
            }
            .frame(height: 6)
            .padding(.horizontal, 14)
            .padding(.bottom, 10)

            Divider()

            // Per-class rows
            ForEach(Array(row.classes.enumerated()), id: \.element.id) { idx, cls in
                HStack(spacing: 12) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(cls.name).font(.subheadline).lineLimit(1)
                    }
                    Spacer()
                    Text(String(format: "%.1f%%", cls.gradePercent))
                        .font(.subheadline.monospacedDigit())
                        .foregroundStyle(classGradeColor(cls.gradePercent))
                    Text(cls.letter)
                        .font(.caption.bold())
                        .padding(.horizontal, 7).padding(.vertical, 2)
                        .background(classGradeColor(cls.gradePercent).opacity(0.12), in: Capsule())
                        .foregroundStyle(classGradeColor(cls.gradePercent))
                    Text(String(format: "%.1f", cls.gpa))
                        .font(.subheadline.bold().monospacedDigit())
                        .foregroundStyle(gpaColor(cls.gpa))
                        .frame(width: 28, alignment: .trailing)
                }
                .padding(.horizontal, 14).padding(.vertical, 10)
                if idx < row.classes.count - 1 { Divider().padding(.leading, 14) }
            }
        }
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
    }

    // MARK: - Empty state
    private var emptyState: some View {
        ContentUnavailableView(
            "No Grade History",
            systemImage: "graduationcap",
            description: Text("Sync from PowerSchool on the web app. Each sync snapshots your grades and builds up the history shown here.")
        )
    }

    // MARK: - Helpers
    private func gpaColor(_ gpa: Double) -> Color {
        gpa >= 3.5 ? .green : gpa >= 2.5 ? .accentColor : gpa >= 1.5 ? .orange : .red
    }

    private func classGradeColor(_ pct: Double) -> Color {
        gradeColor(letterGrade(from: pct))
    }

    private func formatDate(_ iso: String) -> String {
        guard let date = CanopyStore.isoFull.date(from: iso) else {
            // Try treating as YYYY-MM-DD
            guard let d = iso.asDate else { return iso }
            let f = DateFormatter(); f.dateFormat = "MMM d, yyyy"
            return f.string(from: d)
        }
        let f = DateFormatter(); f.dateFormat = "MMM d, yyyy"
        return f.string(from: date)
    }
}
