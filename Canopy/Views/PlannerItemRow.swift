import SwiftUI

// Shared building blocks for the Planner (Homework & Tasks) screen — port of
// web TaskRow.tsx + ItemDetailDialog.tsx. Tasks and (legacy, manually-added)
// Homework are the same concept here, so both are adapted into one
// `PlannerItemData` shape and rendered by one row / one detail sheet.

// MARK: - Kind / reference

enum PlannerKind: String, Hashable {
    case homework, task
    var label: String { self == .homework ? "Homework" : "Task" }
}

/// Identifies a live item by kind + id. Sheets hold a ref (not a snapshot) so
/// they always render the store's current value — e.g. right after a stage tap.
struct PlannerItemRef: Identifiable, Hashable {
    let kind: PlannerKind
    let id: String
    var key: String { "\(kind.rawValue)-\(id)" }
}

// MARK: - Adapted item

struct PlannerItemData: Identifiable {
    let ref: PlannerItemRef
    var id: String { ref.key }
    let title: String
    let description: String
    let dueDate: String
    let completed: Bool
    let stages: [TaskStage]
    let stageId: String?
    let priority: String
    let category: String
    let classId: String?
    let dueTiming: DueTiming?

    init(homework h: Homework) {
        ref = PlannerItemRef(kind: .homework, id: h.id)
        title = h.title; description = h.description; dueDate = h.dueDate
        completed = h.completed; stages = h.stages ?? []; stageId = h.stageId
        priority = h.priority; category = "Homework"
        classId = h.classId.nonEmpty
        dueTiming = h.dueTiming.flatMap(DueTiming.init(rawValue:))
    }

    init(task t: SchoolTask) {
        ref = PlannerItemRef(kind: .task, id: t.id)
        title = t.title; description = t.description; dueDate = t.dueDate
        completed = t.completed; stages = t.stages ?? []; stageId = t.stageId
        priority = t.priority; category = t.category
        classId = t.classId?.nonEmpty
        dueTiming = t.dueTiming.flatMap(DueTiming.init(rawValue:))
    }

    /// Web: `!completed && dayjs(dueDate).isBefore(dayjs(), 'day')`.
    var isOverdue: Bool { !completed && !dueDate.isEmpty && dueDate.isOverdue }

    /// Current stage for the list chip — only mid-pipeline and not yet done.
    var currentStage: TaskStage? {
        guard !completed, !stages.isEmpty, let stageId else { return nil }
        return stages.first { $0.id == stageId }
    }
}

extension CanopyStore {
    /// Live lookup of a planner item by reference (nil once deleted).
    func plannerItem(_ ref: PlannerItemRef) -> PlannerItemData? {
        switch ref.kind {
        case .task: return tasks.first { $0.id == ref.id }.map { PlannerItemData(task: $0) }
        case .homework: return homework.first { $0.id == ref.id }.map { PlannerItemData(homework: $0) }
        }
    }
}

extension Array where Element == SchoolClass {
    /// Web Tasks page `sortedClasses`: period, then name.
    var plannerOrdered: [SchoolClass] {
        sorted { a, b in
            if a.period != b.period { return a.period < b.period }
            return a.name.localizedCaseInsensitiveCompare(b.name) == .orderedAscending
        }
    }
}

extension Array where Element == TaskStage {
    /// Trim labels and drop blanks — nothing blank is ever saved (web StageListEditor rule).
    var plannerCleaned: [TaskStage] {
        compactMap { s in
            let l = s.label.trimmingCharacters(in: .whitespacesAndNewlines)
            return l.isEmpty ? nil : TaskStage(id: s.id, label: l)
        }
    }
}

// MARK: - Wrapping chip layout

/// Minimal left-to-right wrapping layout for chip rows.
struct PlannerFlowLayout: Layout {
    var spacing: CGFloat = 6

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let maxW = proposal.width ?? .infinity
        var x: CGFloat = 0, y: CGFloat = 0, rowH: CGFloat = 0, maxX: CGFloat = 0
        for s in subviews {
            let sz = s.sizeThatFits(.unspecified)
            if x > 0, x + sz.width > maxW { x = 0; y += rowH + spacing; rowH = 0 }
            x += sz.width + spacing
            rowH = Swift.max(rowH, sz.height)
            maxX = Swift.max(maxX, x - spacing)
        }
        return CGSize(width: maxW.isFinite ? maxW : maxX, height: y + rowH)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let maxW = bounds.width
        var x: CGFloat = 0, y: CGFloat = 0, rowH: CGFloat = 0
        for s in subviews {
            let sz = s.sizeThatFits(.unspecified)
            if x > 0, x + sz.width > maxW { x = 0; y += rowH + spacing; rowH = 0 }
            s.place(at: CGPoint(x: bounds.minX + x, y: bounds.minY + y), anchor: .topLeading, proposal: .unspecified)
            x += sz.width + spacing
            rowH = Swift.max(rowH, sz.height)
        }
    }
}

// MARK: - Tinted checkbox (web: class-coloured for Homework, success green for Tasks)

struct PlannerCheckButton: View {
    let checked: Bool
    var tint: Color = .green
    let action: () -> Void
    @State private var bounce: CGFloat = 1.0

    var body: some View {
        Button {
            withAnimation(.spring(response: 0.13, dampingFraction: 0.35)) { bounce = 1.28 }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.08) {
                withAnimation(.spring(response: 0.3, dampingFraction: 0.6)) { bounce = 1.0 }
            }
            action()
        } label: {
            ZStack {
                Circle().fill(checked ? tint : Color.clear)
                Circle().strokeBorder(checked ? tint : tint.opacity(0.55), lineWidth: 1.5)
                Image(systemName: "checkmark")
                    .font(.caption2.weight(.bold))
                    .foregroundStyle(.white)
                    .opacity(checked ? 1 : 0)
                    .scaleEffect(checked ? 1 : 0.4)
            }
            .frame(width: 26, height: 26)
            .scaleEffect(bounce)
            .animation(.spring(response: 0.3, dampingFraction: 0.65), value: checked)
            .frame(width: 44, height: 44)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(checked ? "Mark not done" : "Mark done")
    }
}

// MARK: - Priority chip (web: low default, medium warning, high error — always shown)

struct PlannerPriorityChip: View {
    let priority: String
    var filledLow = false
    var body: some View {
        switch priority {
        case "high": TintedChip(text: priority, color: .red)
        case "medium": TintedChip(text: priority, color: .orange)
        default:
            if filledLow { TintedChip(text: priority, color: .secondary) }
            else { OutlinedChip(text: priority, color: .secondary) }
        }
    }
}

// MARK: - Row (web TaskRow, mobile layout)

struct PlannerItemRow: View {
    let item: PlannerItemData
    let cls: SchoolClass?
    var classCancelled = false
    var rebalance: RebalanceSuggestion? = nil
    let onToggle: () -> Void

    private static let startBy: DateFormatter = {
        let f = DateFormatter(); f.dateFormat = "EEE MMM d"; return f
    }()

    private var checkboxTint: Color {
        if item.ref.kind == .homework, let cls { return Color(hex: cls.color) }
        return .green
    }

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            PlannerCheckButton(checked: item.completed, tint: checkboxTint, action: onToggle)
                .padding(.top, -6)

            VStack(alignment: .leading, spacing: 4) {
                Text(item.title)
                    .font(.body.weight(.medium))
                    .strikethrough(item.completed, color: .secondary)
                    .foregroundStyle(item.completed ? .secondary : .primary)
                    .animation(.easeInOut(duration: 0.2), value: item.completed)

                if !item.description.isEmpty {
                    Text(item.description)
                        .font(.caption).foregroundStyle(.secondary).lineLimit(1)
                }

                PlannerFlowLayout(spacing: 5) {
                    if let cls { ClassChip(name: cls.name, hex: cls.color, compact: true) }
                    OutlinedChip(text: item.category)
                    if let t = item.dueTiming {
                        OutlinedChip(text: t.label, systemImage: t.systemImage)
                    }
                    if classCancelled && !item.completed {
                        OutlinedChip(text: "Class cancelled", systemImage: "exclamationmark.triangle", color: .orange)
                            .help("This class is cancelled that day — you may want to reschedule")
                    }
                    if let stage = item.currentStage {
                        OutlinedChip(text: stage.label, color: .blue)
                    }
                    if !item.dueDate.isEmpty {
                        Text((item.isOverdue ? "OVERDUE • " : "") + GradesUtil.fullDueLabel(item.dueDate))
                            .font(.caption2.weight(item.isOverdue ? .semibold : .regular))
                            .foregroundStyle(item.isOverdue ? Color.red : Color.secondary)
                            .padding(.vertical, 2)
                    }
                }

                if let rebalance, !item.completed, let d = rebalance.startBy.asDate {
                    HStack(spacing: 3) {
                        Image(systemName: "arrow.left.arrow.right")
                            .font(.system(size: 10, weight: .semibold))
                        Text("Start by \(Self.startBy.string(from: d)) — \(rebalance.reason)")
                            .font(.caption2.weight(.medium))
                    }
                    .foregroundStyle(.orange)
                }
            }

            Spacer(minLength: 0)

            PlannerPriorityChip(priority: item.priority)
                .padding(.top, 2)
        }
        .padding(.vertical, 6)
        .opacity(item.completed ? 0.7 : 1)
        .animation(.easeInOut(duration: 0.25), value: item.completed)
    }
}

// MARK: - Due-timing toggle group (web DueTimingField: exclusive, tap selected → none)

struct DueTimingToggle: View {
    @Binding var value: DueTiming?

    var body: some View {
        HStack(spacing: 8) {
            ForEach(DueTiming.allCases, id: \.self) { t in
                let selected = value == t
                Button {
                    withAnimation(.spring(response: 0.25, dampingFraction: 0.7)) {
                        value = selected ? nil : t
                    }
                } label: {
                    Label(t.label, systemImage: t.systemImage)
                        .font(.subheadline.weight(selected ? .semibold : .regular))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 8)
                        .background(selected ? Color.accentColor.opacity(0.13) : Color.clear,
                                    in: RoundedRectangle(cornerRadius: 9, style: .continuous))
                        .overlay(RoundedRectangle(cornerRadius: 9, style: .continuous)
                            .strokeBorder(selected ? Color.accentColor.opacity(0.45) : Color.secondary.opacity(0.25), lineWidth: 1))
                        .foregroundStyle(selected ? Color.accentColor : .secondary)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        }
    }
}

// MARK: - Detail sheet (web ItemDetailDialog) — live lookup by ref

struct PlannerItemDetailSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(CanopyStore.self) private var store
    let ref: PlannerItemRef
    let onEdit: (PlannerItemRef) -> Void
    /// Routed through the parent's undo-delete path (never a direct delete).
    let onDelete: (PlannerItemRef) -> Void

    private var item: PlannerItemData? { store.plannerItem(ref) }
    private var isGone: Bool { item == nil }

    var body: some View {
        NavigationStack {
            ZStack {
                CanopyBackground()
                if let item {
                    ScrollView {
                        VStack(alignment: .leading, spacing: 0) {
                            Rectangle().fill(Color.accentColor).frame(height: 6)
                            content(item)
                                .padding(16).padding(.bottom, 32)
                        }
                    }
                }
            }
            .navigationTitle(ref.kind.label)
            .navigationBarTitleInline()
            .toolbar {
                ToolbarItem(placement: .confirmationAction) { Button("Close") { dismiss() } }
            }
        }
        .onAppear { if isGone { dismiss() } }
        .onChange(of: isGone) { _, gone in if gone { dismiss() } }
    }

    @ViewBuilder
    private func content(_ item: PlannerItemData) -> some View {
        let overdue = item.isOverdue
        let cls = item.classId.flatMap { store.schoolClass($0) }
        let usesStages = !item.stages.isEmpty

        VStack(alignment: .leading, spacing: 14) {
            // Header
            VStack(alignment: .leading, spacing: 4) {
                Text((ref.kind.label + (item.completed ? " · Done" : overdue ? " · Overdue" : "")).uppercased())
                    .font(.caption2.weight(.semibold)).tracking(0.8)
                    .foregroundStyle(.secondary)
                Text(item.title)
                    .font(.title2.weight(.medium)).fontDesign(.rounded)
                    .strikethrough(item.completed)
                    .foregroundStyle(item.completed ? .secondary : .primary)
            }

            // Description
            HStack(alignment: .top, spacing: 10) {
                Image(systemName: "text.alignleft").foregroundStyle(.secondary).frame(width: 20)
                if item.description.isEmpty {
                    Text("No description").font(.subheadline).foregroundStyle(.tertiary)
                } else {
                    Text(item.description).font(.subheadline)
                        .foregroundStyle(item.completed ? .secondary : .primary)
                }
            }

            Divider()

            // Meta rows
            VStack(alignment: .leading, spacing: 12) {
                HStack(alignment: .top, spacing: 10) {
                    Image(systemName: "calendar").foregroundStyle(.secondary).frame(width: 20)
                    VStack(alignment: .leading, spacing: 1) {
                        Text(dueLabel(item.dueDate) + (overdue ? " · Overdue" : ""))
                            .font(.subheadline.weight(.medium))
                            .foregroundStyle(overdue ? Color.red : Color.primary)
                        if let d = item.dueDate.asDate {
                            Text(DateFormatter.fullDate.string(from: d))
                                .font(.caption).foregroundStyle(.secondary)
                        }
                    }
                }
                HStack(spacing: 10) {
                    Image(systemName: "flag").foregroundStyle(.secondary).frame(width: 20)
                    PlannerPriorityChip(priority: item.priority.capitalized)
                }
                HStack(spacing: 10) {
                    Image(systemName: "tag").foregroundStyle(.secondary).frame(width: 20)
                    OutlinedChip(text: item.category.nonEmpty ?? "General")
                }
                if let t = item.dueTiming {
                    HStack(spacing: 10) {
                        Image(systemName: t.systemImage).foregroundStyle(.secondary).frame(width: 20)
                        OutlinedChip(text: t.detailLabel)
                    }
                }
                if let cls {
                    HStack(spacing: 10) {
                        Image(systemName: "graduationcap").foregroundStyle(.secondary).frame(width: 20)
                        PlannerFlowLayout(spacing: 8) {
                            Text(cls.name)
                                .font(.caption.weight(.medium))
                                .padding(.horizontal, 8).padding(.vertical, 3)
                                .overlay(Capsule().strokeBorder(Color.secondary.opacity(0.4), lineWidth: 1))
                                .overlay(alignment: .leading) {
                                    Capsule().fill(Color(hex: cls.color)).frame(width: 3).padding(.vertical, 1)
                                }
                            if let teacher = cls.displayTeacher {
                                Text(teacher + (cls.room.isEmpty ? "" : " · Rm \(cls.room)"))
                                    .font(.caption).foregroundStyle(.secondary)
                                    .padding(.vertical, 3)
                            }
                        }
                    }
                }
            }

            Divider()

            // Completion
            if usesStages {
                VStack(alignment: .leading, spacing: 8) {
                    StageTrackerView(stages: item.stages, currentStageId: item.stageId) { newId in
                        setStage(newId)
                    }
                    if item.stageId != nil {
                        Button("Reset to not started") { setStage(nil) }
                            .font(.caption).foregroundStyle(.secondary)
                            .buttonStyle(.plain)
                    }
                }
            } else {
                HStack(spacing: 10) {
                    Image(systemName: item.completed ? "checkmark.circle.fill" : "circle")
                        .foregroundStyle(item.completed ? Color.green : Color.secondary)
                        .frame(width: 20)
                    Text(item.completed ? "Completed" : "Not completed yet")
                        .font(.subheadline)
                        .foregroundStyle(item.completed ? Color.green : Color.secondary)
                }
            }

            if overdue {
                Text("This \(ref.kind.label.lowercased()) is overdue. Mark it done or move the due date.")
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(.red)
                    .padding(.horizontal, 12).padding(.vertical, 8)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color.red.opacity(0.08), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
            }

            // Actions
            HStack(spacing: 10) {
                Button(role: .destructive) {
                    dismiss()
                    onDelete(ref)
                } label: {
                    Label("Delete", systemImage: "trash")
                        .frame(maxWidth: .infinity).padding(.vertical, 10)
                }
                .buttonStyle(.bordered)
                .buttonBorderShape(.roundedRectangle(radius: 12))
                .tint(.red)

                Button {
                    dismiss()
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) { onEdit(ref) }
                } label: {
                    Label("Edit", systemImage: "pencil")
                        .frame(maxWidth: .infinity).padding(.vertical, 10)
                }
                .buttonStyle(.bordered)
                .buttonBorderShape(.roundedRectangle(radius: 12))

                if !usesStages {
                    Button {
                        toggle()
                    } label: {
                        Label(item.completed ? "Mark not done" : "Mark done",
                              systemImage: item.completed ? "circle" : "checkmark.circle.fill")
                            .frame(maxWidth: .infinity).padding(.vertical, 10)
                    }
                    .buttonStyle(.borderedProminent)
                    .buttonBorderShape(.roundedRectangle(radius: 12))
                    .tint(item.completed ? .secondary : .green)
                }
            }
            .font(.subheadline.weight(.medium))
            .padding(.top, 4)
        }
    }

    private func dueLabel(_ iso: String) -> String {
        iso.isEmpty ? "No due date" : GradesUtil.relativeDueLabel(iso)
    }

    private func toggle() {
        Task {
            switch ref.kind {
            case .task: if let t = store.tasks.first(where: { $0.id == ref.id }) { await store.toggleTask(t) }
            case .homework: if let h = store.homework.first(where: { $0.id == ref.id }) { await store.toggleHomework(h) }
            }
            dismiss()
        }
    }

    private func setStage(_ stageId: String?) {
        Task {
            switch ref.kind {
            case .task: if let t = store.tasks.first(where: { $0.id == ref.id }) { await store.setTaskStage(t, stageId: stageId) }
            case .homework: if let h = store.homework.first(where: { $0.id == ref.id }) { await store.setHomeworkStage(h, stageId: stageId) }
            }
        }
    }
}
