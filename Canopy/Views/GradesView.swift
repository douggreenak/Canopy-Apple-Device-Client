import SwiftUI

// MARK: - Main View

enum GradeSort: String, CaseIterable {
    case grade = "Grade"
    case name  = "Name"
}

struct GradesView: View {
    @Environment(CanopyStore.self) private var store
    @State private var selectedClass: SchoolClass?
    @State private var sort: GradeSort = .grade

    private var gradedClasses: [SchoolClass] {
        let base = store.classes.filter { $0.grade != nil || $0.gradePercent != nil }
        switch sort {
        case .grade: return base.sorted { ($0.gradePercent ?? 0) > ($1.gradePercent ?? 0) }
        case .name:  return base.sorted { $0.name < $1.name }
        }
    }
    private var ungradedClasses: [SchoolClass] {
        store.classes
            .filter { $0.grade == nil && $0.gradePercent == nil }
            .sorted { $0.name < $1.name }
    }

    private var overallAverage: Double? {
        let pcts = gradedClasses.compactMap(\.gradePercent)
        guard !pcts.isEmpty else { return nil }
        return pcts.reduce(0, +) / Double(pcts.count)
    }

    var body: some View {
        NavigationStack {
            ZStack { CanopyBackground()
                if store.classes.isEmpty {
                    ContentUnavailableView("No Classes",
                        systemImage: "books.vertical",
                        description: Text("Add classes in the web app to see grades here."))
                } else {
                    ScrollView {
                        LazyVStack(alignment: .leading, spacing: 24) {
                            if let avg = overallAverage {
                                statsStrip(avg: avg)
                            }
                            if !gradedClasses.isEmpty {
                                gradeSection
                            }
                            if !ungradedClasses.isEmpty {
                                ungradedSection
                            }
                        }
                        .padding(16)
                        .padding(.bottom, 24)
                    }
                }
            }
            .navigationTitle("")
            .navigationBarTitleInline()
            .iosHideNavigationBar()
            .safeAreaInset(edge: .top, spacing: 0) {
                HStack {
                    Spacer()
                    Button {
                        withAnimation(.spring(response: 0.25, dampingFraction: 0.7)) {
                            sort = sort == .grade ? .name : .grade
                        }
                    } label: {
                        Label(
                            sort == .grade ? "Sort by Name" : "Sort by Grade",
                            systemImage: sort == .grade ? "textformat.abc" : "percent"
                        )
                        .font(.subheadline)
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 10)
                }
                .background(.ultraThinMaterial)
            }
            .refreshable { await store.loadAll() }
            .sheet(item: $selectedClass) { cls in
                ClassDetailSheet(
                    cls: cls,
                    assignments: psAssignments(for: cls),
                    allHomework: store.homework.filter { $0.classId == cls.id && $0.source != "powerschool" }
                )
            }
        }
    }

    // MARK: Stats strip
    private func statsStrip(avg: Double) -> some View {
        let psHW = store.homework.filter { $0.source == "powerschool" }
        let missingCount = psHW.filter { $0.flags?.lowercased().contains("missing") == true }.count
        let lateCount    = psHW.filter { $0.flags?.lowercased().contains("late")    == true }.count

        return HStack(spacing: 0) {
            statCell(value: String(format: "%.1f%%", avg), label: "Average",
                     color: gradeColor(letterGrade(from: avg)))
            Divider().frame(height: 32)
            statCell(value: "\(gradedClasses.count)", label: "Graded", color: .secondary)
            if missingCount > 0 {
                Divider().frame(height: 32)
                statCell(value: "\(missingCount)", label: "Missing", color: .red)
            }
            if lateCount > 0 {
                Divider().frame(height: 32)
                statCell(value: "\(lateCount)", label: "Late", color: .orange)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 12)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
    }

    private func statCell(value: String, label: String, color: Color) -> some View {
        VStack(spacing: 2) {
            Text(value).font(.headline).fontDesign(.rounded).foregroundStyle(color)
            Text(label).font(.caption2).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
    }

    // MARK: Graded section
    private var gradeSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            SectionLabel(text: "Graded")
            AdaptiveGrid {
                ForEach(gradedClasses) { cls in
                    Button { selectedClass = cls } label: {
                        GradeCard(cls: cls)
                    }
                    .buttonStyle(CardPressStyle())
                }
            }
        }
    }

    // MARK: Ungraded section
    private var ungradedSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            SectionLabel(text: "No Grade")
            AdaptiveGrid {
                ForEach(ungradedClasses) { cls in
                    Button { selectedClass = cls } label: {
                        UngradedCard(cls: cls)
                    }
                    .buttonStyle(CardPressStyle())
                }
            }
        }
    }

    private func psAssignments(for cls: SchoolClass) -> [Homework] {
        store.homework
            .filter { $0.classId == cls.id && $0.source == "powerschool" }
            .sorted { $0.dueDate > $1.dueDate }
    }
}

// MARK: - Adaptive Grid

struct AdaptiveGrid<Content: View>: View {
    let content: Content
    init(@ViewBuilder content: () -> Content) { self.content = content() }

    private let columns = [GridItem(.adaptive(minimum: 140, maximum: 240), spacing: 12)]

    var body: some View {
        LazyVGrid(columns: columns, spacing: 12) {
            content
        }
    }
}

// MARK: - Grade Card

struct GradeCard: View {
    let cls: SchoolClass
    var body: some View {
        let displayGrade = cls.grade ?? cls.gradePercent.map { letterGrade(from: $0) }

        VStack(spacing: 0) {
            // Color accent strip
            Color(hex: cls.color)
                .frame(height: 4)

            VStack(alignment: .leading, spacing: 6) {
                // Class name
                Text(cls.name)
                    .font(.caption.bold())
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)

                Spacer(minLength: 4)

                // Large grade
                HStack(alignment: .lastTextBaseline, spacing: 0) {
                    if let grade = displayGrade {
                        Text(grade)
                            .font(.system(size: 44, weight: .bold, design: .rounded))
                            .foregroundStyle(gradeColor(grade))
                    } else {
                        Text("—")
                            .font(.system(size: 44, weight: .light, design: .rounded))
                            .foregroundStyle(.tertiary)
                    }
                    Spacer()
                    Image(systemName: "chevron.right")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                        .padding(.bottom, 8)
                }

                // Percentage
                if let pct = cls.gradePercent {
                    Text(String(format: "%.1f%%", pct))
                        .font(.callout.monospacedDigit())
                        .foregroundStyle(.secondary)
                } else {
                    Text("No grade")
                        .font(.callout)
                        .foregroundStyle(.tertiary)
                }
            }
            .padding(.horizontal, 14)
            .padding(.top, 12)
            .padding(.bottom, 14)
        }
        .frame(minHeight: 140)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .shadow(color: .black.opacity(0.06), radius: 8, y: 2)
    }
}

// MARK: - Ungraded Card

struct UngradedCard: View {
    let cls: SchoolClass

    var body: some View {
        VStack(spacing: 0) {
            Color(hex: cls.color).frame(height: 4)
            VStack(alignment: .leading, spacing: 6) {
                Text(cls.name)
                    .font(.caption.bold())
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)
                Spacer(minLength: 4)
                Text("—")
                    .font(.system(size: 44, weight: .light, design: .rounded))
                    .foregroundStyle(.tertiary)
                Text("No grade")
                    .font(.callout)
                    .foregroundStyle(.tertiary)
            }
            .padding(.horizontal, 14)
            .padding(.top, 12)
            .padding(.bottom, 14)
        }
        .frame(minHeight: 120)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .shadow(color: .black.opacity(0.06), radius: 8, y: 2)
    }
}

// MARK: - Section Label

struct SectionLabel: View {
    let text: String
    var body: some View {
        Text(text.uppercased())
            .font(.caption.bold())
            .foregroundStyle(.secondary)
            .tracking(1)
    }
}

// MARK: - Class Detail Sheet

struct ClassDetailSheet: View {
    @Environment(\.dismiss) private var dismiss
    let cls: SchoolClass
    let assignments: [Homework]   // PowerSchool
    let allHomework: [Homework]   // Manual

    var body: some View {
        NavigationStack {
            ZStack { CanopyBackground()
                ScrollView {
                    VStack(spacing: 20) {
                        gradeHero
                        if !assignments.isEmpty {
                            assignmentsSection
                        }
                        if !allHomework.isEmpty {
                            homeworkSection
                        }
                        if assignments.isEmpty && allHomework.isEmpty {
                            ContentUnavailableView(
                                "No Assignments",
                                systemImage: "tray",
                                description: Text("Synced assignments will appear here.")
                            )
                            .padding(.top, 40)
                        }
                    }
                    .padding(16)
                    .padding(.bottom, 32)
                }
            }
            .navigationTitle(cls.name)
            .navigationBarTitleInline()
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }

    // MARK: Grade Hero
    private var gradeHero: some View {
        HStack(spacing: 0) {
            // Colored left bar
            Color(hex: cls.color)
                .frame(width: 5)
                .clipShape(UnevenRoundedRectangle(
                    topLeadingRadius: 14, bottomLeadingRadius: 14,
                    bottomTrailingRadius: 0, topTrailingRadius: 0
                ))

            HStack(spacing: 20) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(cls.name)
                        .font(.title3.bold())
                    if !cls.teacher.isEmpty {
                        Text(cls.teacher)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                    if !cls.room.isEmpty {
                        Label("Room \(cls.room)", systemImage: "door.right.hand.open")
                            .font(.caption)
                            .foregroundStyle(.tertiary)
                    }
                }
                Spacer()
                VStack(alignment: .trailing, spacing: 2) {
                    let displayGrade = cls.grade ?? cls.gradePercent.map { letterGrade(from: $0) }
                    if let grade = displayGrade {
                        Text(grade)
                            .font(.system(size: 52, weight: .bold, design: .rounded))
                            .foregroundStyle(gradeColor(grade))
                    }
                    if let pct = cls.gradePercent {
                        Text(String(format: "%.1f%%", pct))
                            .font(.callout.monospacedDigit())
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 18)
        }
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .shadow(color: .black.opacity(0.06), radius: 8, y: 2)
    }

    // MARK: Assignments
    private var assignmentsSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            SectionLabel(text: "Assignments from PowerSchool")
            VStack(spacing: 0) {
                ForEach(Array(assignments.enumerated()), id: \.element.id) { idx, hw in
                    AssignmentDetailRow(hw: hw)
                    if idx < assignments.count - 1 {
                        Divider().padding(.leading, 16)
                    }
                }
            }
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        }
    }

    // MARK: Homework
    private var homeworkSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            SectionLabel(text: "Homework")
            VStack(spacing: 0) {
                ForEach(Array(allHomework.enumerated()), id: \.element.id) { idx, hw in
                    HomeworkDetailRow(hw: hw)
                    if idx < allHomework.count - 1 {
                        Divider().padding(.leading, 16)
                    }
                }
            }
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        }
    }
}

// MARK: - Assignment Detail Row

struct AssignmentDetailRow: View {
    let hw: Homework

    private var flagInfo: (label: String, color: Color)? {
        guard let f = hw.flags, !f.isEmpty else { return nil }
        let lower = f.lowercased()
        if lower.contains("missing")   { return ("Missing", .red) }
        if lower.contains("late")      { return ("Late", .orange) }
        if lower.contains("collected") { return ("Collected", .blue) }
        return (f, .secondary)
    }

    var body: some View {
        HStack(spacing: 12) {
            Circle()
                .fill(hw.completed ? Color.accentColor : Color.systemFill)
                .frame(width: 8, height: 8)
                .padding(.leading, 16)
            VStack(alignment: .leading, spacing: 3) {
                Text(hw.title)
                    .font(.subheadline)
                    .lineLimit(2)
                HStack(spacing: 6) {
                    if let cat = hw.category, !cat.isEmpty {
                        Text(cat)
                            .font(.caption2)
                            .foregroundStyle(.tertiary)
                    }
                    if let flag = flagInfo {
                        Text(flag.label)
                            .font(.caption2.bold())
                            .padding(.horizontal, 5).padding(.vertical, 1)
                            .background(flag.color.opacity(0.12), in: Capsule())
                            .foregroundStyle(flag.color)
                    }
                }
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 2) {
                if let score = hw.score {
                    Text(score)
                        .font(.subheadline.bold().monospacedDigit())
                }
                if let pct = hw.scorePercent {
                    Text(String(format: "%.0f%%", pct))
                        .font(.caption2)
                        .foregroundStyle(scoreColor(pct))
                }
            }
            .padding(.trailing, 16)
        }
        .padding(.vertical, 12)
    }

    private func scoreColor(_ pct: Double) -> Color {
        switch pct {
        case 90...: return .accentColor
        case 80..<90: return .blue
        case 70..<80: return .orange
        default: return .red
        }
    }
}

// MARK: - Homework Detail Row

struct HomeworkDetailRow: View {
    let hw: Homework
    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: hw.completed ? "checkmark.circle.fill" : "circle")
                .foregroundStyle(hw.completed ? Color.accentColor : .secondary)
                .padding(.leading, 16)
            VStack(alignment: .leading, spacing: 2) {
                Text(hw.title)
                    .font(.subheadline)
                    .strikethrough(hw.completed)
                    .foregroundStyle(hw.completed ? .secondary : .primary)
                    .lineLimit(2)
                Text(hw.dueDate.dueDateLabel)
                    .font(.caption2)
                    .foregroundStyle(hw.dueDate.isOverdue && !hw.completed ? Color.red : Color.secondary.opacity(0.6))
            }
            Spacer()
            PriorityDot(priority: hw.priority)
                .padding(.trailing, 16)
        }
        .padding(.vertical, 12)
    }
}

// MARK: - Card Press Style

struct CardPressStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.96 : 1.0)
            .animation(.spring(response: 0.2, dampingFraction: 0.7), value: configuration.isPressed)
    }
}

// MARK: - Grade letter fallback

func letterGrade(from pct: Double) -> String {
    switch pct {
    case 97...: return "A+"
    case 93...: return "A"
    case 90...: return "A-"
    case 87...: return "B+"
    case 83...: return "B"
    case 80...: return "B-"
    case 77...: return "C+"
    case 73...: return "C"
    case 70...: return "C-"
    case 67...: return "D+"
    case 63...: return "D"
    case 60...: return "D-"
    default:    return "F"
    }
}

// MARK: - Grade color helper

func gradeColor(_ grade: String) -> Color {
    switch grade.prefix(1) {
    case "A": return .accentColor
    case "B": return .blue
    case "C": return .orange
    case "D": return .red
    default:  return .secondary
    }
}
