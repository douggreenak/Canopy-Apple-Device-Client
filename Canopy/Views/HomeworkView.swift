import SwiftUI

// MARK: - Filter

enum HWFilter: String, CaseIterable {
    case upcoming = "Upcoming"
    case done     = "Done"
    case all      = "All"
}

// Combined item for the unified list
private enum HWItem: Identifiable {
    case homework(Homework)
    case task(SchoolTask)

    var id: String {
        switch self {
        case .homework(let h): return "hw-\(h.id)"
        case .task(let t):     return "task-\(t.id)"
        }
    }
    var completed: Bool {
        switch self {
        case .homework(let h): return h.completed
        case .task(let t):     return t.completed
        }
    }
    var dueDate: String {
        switch self {
        case .homework(let h): return h.dueDate
        case .task(let t):     return t.dueDate
        }
    }
}

// MARK: - Main View

struct HomeworkView: View {
    @Environment(CanopyStore.self) private var store
    @State private var filter: HWFilter = .upcoming
    @State private var showAddHWSheet = false
    @State private var showAddTaskSheet = false
    @State private var editingHW: Homework?
    @State private var editingTask: SchoolTask?
    @State private var detailTask: SchoolTask?
    @State private var detailHW: Homework?
    @State private var showClearAlert = false

    // Deferred-delete state: swiping Delete hides the item immediately and
    // shows an Undo toast for 5s before the API call actually fires, mirroring
    // web's snackbar-with-Undo instead of Apple's previous immediate delete.
    @State private var pendingDeletionIds: Set<String> = []
    @State private var undoToast: UndoToast?

    struct UndoToast: Identifiable {
        let id = UUID()
        let message: String
        let undo: () -> Void
    }

    // Manual homework only — PowerSchool assignments live in Grades
    private var manualHomework: [Homework] {
        store.homework.filter { $0.source != "powerschool" }
    }

    private var allItems: [HWItem] {
        let hwItems = manualHomework
            .filter { !pendingDeletionIds.contains("hw-\($0.id)") }
            .map { HWItem.homework($0) }
        let taskItems = store.tasks
            .filter { !pendingDeletionIds.contains("task-\($0.id)") }
            .map { HWItem.task($0) }
        return hwItems + taskItems
    }

    private var filtered: [HWItem] {
        switch filter {
        case .upcoming: return allItems.filter { !$0.completed }
        case .done:     return allItems.filter {  $0.completed }
        case .all:      return allItems
        }
    }

    // Group by due date. No-date items always go at the end.
    private var grouped: [(String, [HWItem])] {
        let ascending = filter != .done
        return Dictionary(grouping: filtered, by: \.dueDate)
            .sorted { a, b in
                let ak = a.key, bk = b.key
                if ak.isEmpty && bk.isEmpty { return false }
                if ak.isEmpty { return false }
                if bk.isEmpty { return true }
                return ascending ? ak < bk : ak > bk
            }
            .map { ($0.key, $0.value) }
    }

    private var pendingCount: Int { allItems.filter { !$0.completed }.count }
    private var doneCount: Int    { allItems.filter {  $0.completed }.count }

    private var rebalanceSuggestionsByHwId: [String: RebalanceSuggestion] {
        let suggestions = suggestRebalancing(homework: manualHomework)
        return Dictionary(uniqueKeysWithValues: suggestions.map { ($0.homework.id, $0) })
    }

    var body: some View {
        NavigationStack {
            ZStack { CanopyBackground()
                if allItems.isEmpty && store.isLoading {
                    VStack { Spacer(); ProgressView(); Spacer() }
                } else if filtered.isEmpty {
                    emptyState
                } else {
                    itemList
                }
            }
            .safeAreaInset(edge: .top, spacing: 0) {
                VStack(spacing: 0) {
                    HStack(spacing: 10) {
                        Picker("Filter", selection: $filter) {
                            Text("Upcoming (\(pendingCount))").tag(HWFilter.upcoming)
                            Text("Done (\(doneCount))").tag(HWFilter.done)
                            Text("All (\(allItems.count))").tag(HWFilter.all)
                        }
                        .pickerStyle(.segmented)
                        Menu {
                            Button { showAddHWSheet = true } label: {
                                Label("Add Homework", systemImage: "book")
                            }
                            Button { showAddTaskSheet = true } label: {
                                Label("Add Task", systemImage: "checklist")
                            }
                        } label: {
                            Image(systemName: "plus.circle.fill").font(.title3)
                        }
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 8)

                    if filter != .done && !store.classes.isEmpty {
                        quickAddRow
                            .padding(.horizontal, 12)
                            .padding(.vertical, 6)
                    }

                    if filter == .done && doneCount > 0 {
                        clearDoneBar
                            .padding(.horizontal, 12)
                            .padding(.vertical, 6)
                    }
                }
                .background(.ultraThinMaterial)
            }
            .navigationTitle("")
            .navigationBarTitleInline()
            .iosHideNavigationBar()
            .sheet(isPresented: $showAddHWSheet) { HomeworkEditSheet(hw: nil) }
            .sheet(isPresented: $showAddTaskSheet) { TaskEditSheet(task: nil) }
            .sheet(item: $editingHW) { hw in HomeworkEditSheet(hw: hw) }
            .sheet(item: $editingTask) { task in TaskEditSheet(task: task) }
            .sheet(item: $detailTask) { task in
                TaskDetailSheet(task: task) { editingTask = task }
            }
            .sheet(item: $detailHW) { hw in
                HomeworkDetailSheet(hw: hw) { editingHW = hw }
            }
            .alert("Delete all \(doneCount) completed items?", isPresented: $showClearAlert) {
                Button("Cancel", role: .cancel) { }
                Button("Delete All", role: .destructive) {
                    Task {
                        await store.clearDoneHomework()
                        await store.clearDoneTasks()
                    }
                }
            } message: { Text("This cannot be undone.") }
            .refreshable { await store.loadAll() }
            .overlay(alignment: .bottom) { undoToastView }
        }
    }

    // MARK: - Undo toast
    @ViewBuilder
    private var undoToastView: some View {
        if let toast = undoToast {
            HStack(spacing: 12) {
                Text(toast.message).font(.subheadline).lineLimit(1)
                Spacer(minLength: 8)
                Button("Undo") { toast.undo() }
                    .font(.subheadline.bold())
            }
            .padding(.horizontal, 16).padding(.vertical, 12)
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            .shadow(color: .black.opacity(0.15), radius: 10, y: 3)
            .padding(.horizontal, 16)
            .padding(.bottom, 12)
            .transition(.move(edge: .bottom).combined(with: .opacity))
            .id(toast.id)
        }
    }

    // MARK: - Deferred delete (5s undo window)
    private func deferDeleteHomework(_ hw: Homework) {
        let key = "hw-\(hw.id)"
        withAnimation(.spring(response: 0.3)) { pendingDeletionIds.insert(key) }
        let workItem = DispatchWorkItem {
            Task { await store.deleteHomework(hw) }
            pendingDeletionIds.remove(key)
        }
        withAnimation(.spring(response: 0.3)) {
            undoToast = UndoToast(message: "\"\(hw.title)\" deleted") {
                workItem.cancel()
                withAnimation(.spring(response: 0.3)) {
                    pendingDeletionIds.remove(key)
                    undoToast = nil
                }
            }
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 5, execute: workItem)
        DispatchQueue.main.asyncAfter(deadline: .now() + 5.05) {
            withAnimation { if !pendingDeletionIds.contains(key) { undoToast = nil } }
        }
    }

    private func deferDeleteTask(_ task: SchoolTask) {
        let key = "task-\(task.id)"
        withAnimation(.spring(response: 0.3)) { pendingDeletionIds.insert(key) }
        let workItem = DispatchWorkItem {
            Task { await store.deleteTask(task) }
            pendingDeletionIds.remove(key)
        }
        withAnimation(.spring(response: 0.3)) {
            undoToast = UndoToast(message: "\"\(task.title)\" deleted") {
                workItem.cancel()
                withAnimation(.spring(response: 0.3)) {
                    pendingDeletionIds.remove(key)
                    undoToast = nil
                }
            }
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 5, execute: workItem)
        DispatchQueue.main.asyncAfter(deadline: .now() + 5.05) {
            withAnimation { if pendingDeletionIds.contains(key) == false { undoToast = nil } }
        }
    }

    // MARK: - Quick add
    private var quickAddRow: some View {
        VStack(alignment: .leading, spacing: 6) {
            Label("Quick add homework · due next class", systemImage: "bolt.fill")
                .font(.caption.bold())
                .foregroundStyle(.secondary)
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(store.classes.sorted { $0.period < $1.period }) { cls in
                        QuickAddChip(cls: cls) {
                            Task { await quickAdd(for: cls) }
                        }
                    }
                }
                .padding(.vertical, 2)
            }
        }
        .padding(12)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
    }

    // MARK: - Clear done bar
    private var clearDoneBar: some View {
        HStack {
            Text("\(doneCount) completed item\(doneCount == 1 ? "" : "s")")
                .font(.subheadline).foregroundStyle(.secondary)
            Spacer()
            Button(role: .destructive) { showClearAlert = true } label: {
                Label("Clear All", systemImage: "trash").font(.subheadline.bold())
            }
        }
        .padding(.horizontal, 14).padding(.vertical, 10)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous)
            .strokeBorder(Color.red.opacity(0.25), lineWidth: 0.5))
    }

    // MARK: - List
    private var itemList: some View {
        List {
            ForEach(grouped, id: \.0) { date, items in
                itemSection(date: date, items: items)
            }
        }
        .insetGroupedListStyle()
        .scrollContentBackground(.hidden)
    }

    @ViewBuilder
    private func itemSection(date: String, items: [HWItem]) -> some View {
        let isOverdue = date.isOverdue && filter != .done
        let label = date.isEmpty ? "No Date" : date.dueDateLabel

        Section {
            ForEach(items) { item in
                itemRow(item)
            }
        } header: {
            Text(label)
                .font(.footnote.bold())
                .foregroundStyle(isOverdue ? Color.red : Color.secondary)
        }
    }

    @ViewBuilder
    private func itemRow(_ item: HWItem) -> some View {
        switch item {
        case .homework(let hw):
            HWListRow(hw: hw, store: store, rebalanceSuggestion: rebalanceSuggestionsByHwId[hw.id])
                .contentShape(Rectangle())
                .onTapGesture { detailHW = hw }
                .accessibilityAddTraits(.isButton)
                .swipeActions(edge: .leading) {
                    Button { Task { await store.toggleHomework(hw) } } label: {
                        Label(hw.completed ? "Undo" : "Done",
                              systemImage: hw.completed ? "arrow.uturn.left" : "checkmark")
                    }.tint(Color.accentColor)
                }
                .swipeActions(edge: .trailing) {
                    Button(role: .destructive) {
                        deferDeleteHomework(hw)
                    } label: { Label("Delete", systemImage: "trash") }
                    Button { editingHW = hw } label: {
                        Label("Edit", systemImage: "pencil")
                    }.tint(.blue)
                }

        case .task(let task):
            TaskListRow(task: task, store: store)
                .contentShape(Rectangle())
                .onTapGesture { detailTask = task }
                .accessibilityAddTraits(.isButton)
                .swipeActions(edge: .leading) {
                    Button { Task { await store.toggleTask(task) } } label: {
                        Label(task.completed ? "Undo" : "Done",
                              systemImage: task.completed ? "arrow.uturn.left" : "checkmark")
                    }.tint(Color.accentColor)
                }
                .swipeActions(edge: .trailing) {
                    Button(role: .destructive) {
                        deferDeleteTask(task)
                    } label: { Label("Delete", systemImage: "trash") }
                    Button { editingTask = task } label: {
                        Label("Edit", systemImage: "pencil")
                    }.tint(.blue)
                }
        }
    }

    // MARK: - Empty state
    private var emptyState: some View {
        ContentUnavailableView(
            filter == .done ? "No Completed Items" : filter == .all ? "No Items" : "All Caught Up!",
            systemImage: filter == .upcoming ? "checkmark.circle.fill" : "tray",
            description: Text(filter == .done
                ? "Completed homework and tasks appear here."
                : filter == .all
                    ? "Tap + above to add homework or a task."
                    : "Use Quick Add or tap + above to get started.")
        )
    }

    // MARK: - Quick add logic (creates a Task, matching web behaviour)
    private func quickAdd(for cls: SchoolClass) async {
        let task = SchoolTask(
            id: UUID().uuidString,
            title: "Homework",
            description: "",
            dueDate: nextMeetingDate(for: cls.days),
            completed: false,
            priority: "medium",
            category: "Homework",
            classId: cls.id
        )
        try? await store.saveTask(task, isNew: true)
    }

    private func nextMeetingDate(for days: [Int]) -> String {
        let cal = Calendar.current
        var date = cal.date(byAdding: .day, value: 1, to: .now)!
        for _ in 0..<14 {
            let weekday = cal.component(.weekday, from: date) - 1
            if days.contains(weekday) { return DateFormatter.iso.string(from: date) }
            date = cal.date(byAdding: .day, value: 1, to: date)!
        }
        return DateFormatter.iso.string(from: cal.date(byAdding: .day, value: 1, to: .now)!)
    }
}

// MARK: - Quick Add Chip

struct QuickAddChip: View {
    let cls: SchoolClass
    let action: () -> Void
    @State private var pressed = false

    var body: some View {
        Button {
            withAnimation(.spring(duration: 0.2)) { pressed = true }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) {
                withAnimation { pressed = false }
            }
            action()
        } label: {
            HStack(spacing: 5) {
                ClassColorDot(hex: cls.color, size: 7)
                Text(cls.name).font(.caption.bold()).lineLimit(1)
            }
            .padding(.horizontal, 10).padding(.vertical, 6)
            .background(Color(hex: cls.color).opacity(0.14),
                        in: RoundedRectangle(cornerRadius: 8, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 8, style: .continuous)
                .strokeBorder(Color(hex: cls.color).opacity(0.4), lineWidth: 0.5))
        }
        .buttonStyle(.plain)
        .scaleEffect(pressed ? 0.91 : 1.0)
    }
}

// MARK: - Homework Row

struct HWListRow: View {
    let hw: Homework
    let store: CanopyStore
    var rebalanceSuggestion: RebalanceSuggestion? = nil

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            AnimatedCheckButton(checked: hw.completed) {
                Task { await store.toggleHomework(hw) }
            }
            .padding(.top, 2)

            VStack(alignment: .leading, spacing: 5) {
                Text(hw.title)
                    .font(.body.weight(.medium))
                    .strikethrough(hw.completed, color: .secondary)
                    .foregroundStyle(hw.completed ? .secondary : .primary)
                    .animation(.easeInOut(duration: 0.2), value: hw.completed)

                HStack(spacing: 6) {
                    if let cls = store.schoolClass(hw.classId) {
                        ClassColorDot(hex: cls.color, size: 7)
                        Text(cls.name).font(.caption).foregroundStyle(.secondary)
                    }
                    if let cat = hw.category, !cat.isEmpty {
                        CategoryBadge(category: cat)
                    }
                    if !hw.dueDate.isEmpty {
                        Text(hw.dueDate.dueDateLabel)
                            .font(.caption2)
                            .foregroundStyle(
                                hw.dueDate.isOverdue && !hw.completed ? Color.red : Color.secondary
                            )
                    }
                }

                if !hw.description.isEmpty {
                    Text(hw.description)
                        .font(.caption).foregroundStyle(.secondary).lineLimit(1)
                }

                if let suggestion = rebalanceSuggestion {
                    Text(suggestion.reason)
                        .font(.caption2)
                        .foregroundStyle(.orange)
                }
            }

            Spacer(minLength: 0)

            if hw.priority == "high" || hw.priority == "medium" {
                PriorityDot(priority: hw.priority).padding(.top, 6)
            }
        }
        .padding(.vertical, 6)
        .opacity(hw.completed ? 0.55 : 1)
        .animation(.easeInOut(duration: 0.25), value: hw.completed)
    }
}

// MARK: - Add / Edit Homework Sheet

struct HomeworkEditSheet: View {
    @Environment(CanopyStore.self) private var store
    @Environment(\.dismiss) private var dismiss

    let hw: Homework?

    @State private var title = ""
    @State private var description = ""
    @State private var dueDate = Date.now
    @State private var priority = "medium"
    @State private var classId = ""
    @State private var stages: [TaskStage] = []
    @State private var isSaving = false
    @State private var error: String?

    private var isNew: Bool { hw == nil }

    var body: some View {
        NavigationStack {
            ZStack { CanopyBackground()
                ScrollView {
                    VStack(spacing: 16) {
                        // ── Details ───────────────────────────────────────
                        FormEditCard {
                            VStack(spacing: 0) {
                                TextField("Title", text: $title)
                                    .font(.body)
                                    .padding(.horizontal, 16).padding(.vertical, 13)
                                Divider().padding(.leading, 16)
                                TextField("Description (optional)", text: $description, axis: .vertical)
                                    .font(.body)
                                    .lineLimit(3...6)
                                    .padding(.horizontal, 16).padding(.vertical, 13)
                            }
                        }

                        // ── Due Date ──────────────────────────────────────
                        FormEditCard {
                            VStack(spacing: 0) {
                                Label("Due Date", systemImage: "calendar")
                                    .font(.body)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                    .padding(.horizontal, 16).padding(.top, 13).padding(.bottom, 10)
                                Divider().padding(.leading, 16)
                                DatePicker("", selection: $dueDate, displayedComponents: .date)
                                    .datePickerStyle(.graphical)
                                    .padding(.horizontal, 8).padding(.bottom, 4)
                            }
                        }

                        // ── Priority ──────────────────────────────────────
                        FormEditCard {
                            VStack(alignment: .leading, spacing: 10) {
                                Label("Priority", systemImage: "chart.bar")
                                    .font(.body)
                                    .padding(.horizontal, 16).padding(.top, 13)
                                HStack(spacing: 8) {
                                    PriorityPill(value: "high", label: "High", color: .red, selection: $priority)
                                    PriorityPill(value: "medium", label: "Medium", color: .orange, selection: $priority)
                                    PriorityPill(value: "low", label: "Low", color: .secondary, selection: $priority)
                                }
                                .padding(.horizontal, 12).padding(.bottom, 12)
                            }
                        }

                        // ── Class ─────────────────────────────────────────
                        if !store.classes.isEmpty {
                            FormEditCard {
                                HStack {
                                    Label("Class", systemImage: "person.2")
                                        .font(.body)
                                    Spacer()
                                    Picker("", selection: $classId) {
                                        Text("None").tag("")
                                        ForEach(store.classes) { cls in
                                            HStack {
                                                ClassColorDot(hex: cls.color)
                                                Text(cls.name)
                                            }.tag(cls.id)
                                        }
                                    }
                                    .labelsHidden()
                                }
                                .padding(.horizontal, 16).padding(.vertical, 13)
                            }
                        }

                        // ── Completion Stages ────────────────────────────
                        StageListEditorView(stages: $stages)

                        if let e = error {
                            HStack(spacing: 8) {
                                Image(systemName: "exclamationmark.triangle.fill").font(.footnote)
                                Text(e).font(.footnote)
                            }
                            .foregroundStyle(.red)
                            .padding(12)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background(.red.opacity(0.08), in: RoundedRectangle(cornerRadius: 10))
                        }
                    }
                    .padding(16).padding(.bottom, 24)
                }
            }
            .navigationTitle(isNew ? "New Homework" : "Edit Homework")
            .navigationBarTitleInline()
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button(isSaving ? "Saving…" : "Save") { Task { await save() } }
                        .disabled(title.isEmpty || isSaving)
                        .fontWeight(.semibold)
                }
            }
        }
        .onAppear { prefill() }
    }



    private func prefill() {
        guard let hw else { return }
        title = hw.title
        description = hw.description
        dueDate = hw.dueDate.asDate ?? .now
        priority = hw.priority
        classId = hw.classId
        stages = hw.stages ?? []
    }

    private func save() async {
        isSaving = true; defer { isSaving = false }
        // Preserve the current stage only if it still refers to a stage that
        // survived editing; `completed` always stays derived from it.
        let validStageId = (hw?.stageId).flatMap { id in stages.contains { $0.id == id } ? id : nil }
        let item = Homework(
            id: hw?.id ?? UUID().uuidString,
            classId: classId,
            title: title,
            description: description,
            dueDate: DateFormatter.iso.string(from: dueDate),
            completed: stages.isEmpty ? (hw?.completed ?? false) : store.completedForStage(stages, validStageId),
            priority: priority,
            source: hw?.source ?? "manual",
            sourceId: hw?.sourceId,
            score: hw?.score,
            scorePercent: hw?.scorePercent,
            category: hw?.category,
            flags: hw?.flags,
            stages: stages.isEmpty ? nil : stages,
            stageId: stages.isEmpty ? nil : validStageId
        )
        do {
            try await store.saveHomework(item, isNew: isNew)
            dismiss()
        } catch { self.error = error.localizedDescription }
    }
}

// MARK: - Homework Detail Sheet
// Mirrors TasksView.swift's TaskDetailSheet so Homework gets the same
// detail-before-edit interaction (previously taps went straight to edit),
// including the stage tracker when the item has custom completion stages.
struct HomeworkDetailSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(CanopyStore.self) private var store
    let hw: Homework
    let onEdit: () -> Void

    var body: some View {
        NavigationStack {
            ZStack { CanopyBackground()
                ScrollView {
                    VStack(alignment: .leading, spacing: 16) {
                        VStack(alignment: .leading, spacing: 10) {
                            HStack {
                                if let cat = hw.category, !cat.isEmpty { CategoryBadge(category: cat) }
                                Spacer()
                                HStack(spacing: 4) {
                                    PriorityDot(priority: hw.priority)
                                    Text(hw.priority.capitalized)
                                        .font(.caption).foregroundStyle(.secondary)
                                }
                            }
                            Text(hw.title)
                                .font(.title2.bold())
                                .strikethrough(hw.completed)
                                .foregroundStyle(hw.completed ? .secondary : .primary)
                            if !hw.description.isEmpty {
                                Text(hw.description)
                                    .font(.body).foregroundStyle(.secondary)
                            }
                            Divider()
                            HStack(spacing: 20) {
                                if let cls = store.schoolClass(hw.classId) {
                                    Label {
                                        Text(cls.name).font(.subheadline)
                                    } icon: {
                                        ClassColorDot(hex: cls.color, size: 9)
                                    }
                                }
                                if !hw.dueDate.isEmpty {
                                    Label(hw.dueDate.dueDateLabel, systemImage: "calendar")
                                        .font(.subheadline)
                                        .foregroundStyle(
                                            hw.dueDate.isOverdue && !hw.completed ? Color.red : Color.secondary
                                        )
                                }
                                Spacer()
                            }
                        }
                        .padding(16)
                        .glassCard(cornerRadius: 16)

                        // Stage tracker (custom pipeline) or a plain Mark Complete button.
                        if let stages = hw.stages, !stages.isEmpty {
                            VStack(alignment: .leading, spacing: 10) {
                                SectionLabel(text: "Progress")
                                StageTrackerView(stages: stages, currentStageId: hw.stageId) { newId in
                                    Task { await store.setHomeworkStage(hw, stageId: newId) }
                                }
                                .padding(12)
                                .glassCard(cornerRadius: 14)
                                if hw.stageId != nil {
                                    Button("Reset to not started") {
                                        Task { await store.setHomeworkStage(hw, stageId: nil) }
                                    }
                                    .font(.caption).foregroundStyle(.secondary)
                                }
                            }
                        } else {
                            Button {
                                Task { await store.toggleHomework(hw); dismiss() }
                            } label: {
                                Label(hw.completed ? "Mark Incomplete" : "Mark Complete",
                                      systemImage: hw.completed ? "arrow.uturn.left" : "checkmark.circle.fill")
                                    .frame(maxWidth: .infinity)
                                    .padding(.vertical, 12)
                            }
                            .tint(hw.completed ? .secondary : .accentColor)
                            .buttonStyle(.borderedProminent)
                            .buttonBorderShape(.roundedRectangle(radius: 12))
                        }

                        HStack(spacing: 10) {
                            Button {
                                dismiss()
                                DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) { onEdit() }
                            } label: {
                                Label("Edit", systemImage: "pencil")
                                    .frame(maxWidth: .infinity).padding(.vertical, 12)
                            }
                            .buttonStyle(.bordered)
                            .buttonBorderShape(.roundedRectangle(radius: 12))

                            Button(role: .destructive) {
                                Task { await store.deleteHomework(hw); dismiss() }
                            } label: {
                                Label("Delete", systemImage: "trash")
                                    .frame(maxWidth: .infinity).padding(.vertical, 12)
                            }
                            .buttonStyle(.bordered)
                            .buttonBorderShape(.roundedRectangle(radius: 12))
                            .tint(.red)
                        }
                    }
                    .padding(16).padding(.bottom, 32)
                }
            }
            .navigationTitle("Homework Detail")
            .navigationBarTitleInline()
            .toolbar {
                ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } }
            }
        }
    }
}
