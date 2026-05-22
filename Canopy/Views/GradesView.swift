import SwiftUI

struct GradesView: View {
    @Environment(CanopyStore.self) private var store
    @State private var expandedClassId: String?

    private var gradedClasses: [SchoolClass] {
        store.classes
            .filter { $0.grade != nil || $0.gradePercent != nil }
            .sorted { ($0.gradePercent ?? 0) > ($1.gradePercent ?? 0) }
    }

    private var ungradedClasses: [SchoolClass] {
        store.classes.filter { $0.grade == nil && $0.gradePercent == nil }
    }

    var body: some View {
        NavigationStack {
            ZStack { CanopyBackground()
                if store.classes.isEmpty {
                    ContentUnavailableView("No Classes", systemImage: "books.vertical",
                        description: Text("Add classes in the web app to see grades here."))
                } else {
                    List {
                        if !gradedClasses.isEmpty {
                            Section("Graded") {
                                ForEach(gradedClasses) { cls in
                                    GradeRow(cls: cls,
                                             assignments: psAssignments(for: cls),
                                             isExpanded: expandedClassId == cls.id)
                                    .onTapGesture {
                                        withAnimation(.spring(duration: 0.3)) {
                                            expandedClassId = expandedClassId == cls.id ? nil : cls.id
                                        }
                                    }
                                }
                            }
                        }
                        if !ungradedClasses.isEmpty {
                            Section("Classes") {
                                ForEach(ungradedClasses) { cls in
                                    HStack(spacing: 12) {
                                        ClassColorDot(hex: cls.color)
                                        Text(cls.name).font(.body)
                                        Spacer()
                                        Text("No grade").font(.caption).foregroundStyle(.secondary)
                                    }
                                    .padding(.vertical, 2)
                                }
                            }
                        }
                    }
                    .listStyle(.insetGrouped)
                    .scrollContentBackground(.hidden)
                }
            }
            .navigationTitle("Grades")
            .refreshable { await store.loadAll() }
        }
    }

    private func psAssignments(for cls: SchoolClass) -> [Homework] {
        store.homework.filter { $0.classId == cls.id && $0.source == "powerschool" }
            .sorted { ($0.dueDate) > ($1.dueDate) }
    }
}

// MARK: - Grade Row
struct GradeRow: View {
    let cls: SchoolClass
    let assignments: [Homework]
    let isExpanded: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 12) {
                ClassColorDot(hex: cls.color, size: 12)
                Text(cls.name).font(.body.bold())
                Spacer()
                VStack(alignment: .trailing, spacing: 2) {
                    if let g = cls.grade {
                        Text(g)
                            .font(.title2.bold())
                            .foregroundStyle(gradeColor(g))
                    }
                    if let pct = cls.gradePercent {
                        Text(String(format: "%.1f%%", pct))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                if !assignments.isEmpty {
                    Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .padding(.vertical, 4)

            if isExpanded && !assignments.isEmpty {
                Divider().padding(.top, 8)
                ForEach(assignments) { hw in
                    AssignmentRow(hw: hw)
                }
            }
        }
    }
}

struct AssignmentRow: View {
    let hw: Homework
    var body: some View {
        HStack(spacing: 10) {
            Circle()
                .fill(hw.completed ? Color.canopyGreen : Color(uiColor: .systemFill))
                .frame(width: 8, height: 8)
            VStack(alignment: .leading, spacing: 2) {
                Text(hw.title).font(.subheadline).lineLimit(1)
                if let cat = hw.category { Text(cat).font(.caption2).foregroundStyle(.secondary) }
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 2) {
                if let score = hw.score { Text(score).font(.subheadline.bold()) }
                if let pct = hw.scorePercent {
                    Text(String(format: "%.0f%%", pct)).font(.caption2).foregroundStyle(.secondary)
                }
            }
        }
        .padding(.vertical, 6)
        .padding(.leading, 20)
    }
}

private func gradeColor(_ grade: String) -> Color {
    switch grade.prefix(1) {
    case "A": return .canopyGreen
    case "B": return .blue
    case "C": return .orange
    case "D": return .red
    default:  return .secondary
    }
}
