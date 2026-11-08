import SwiftUI

// MARK: - Filter

enum HWFilter: String, CaseIterable {
    case todo = "To Do"
    case done = "Done"
    case all  = "All"
}

// MARK: - Main View (web src/app/tasks/page.tsx — "Homework & Tasks")

struct HomeworkView: View {
    @Environment(CanopyStore.self) private var store
    @State private var filter: HWFilter = .todo
    @State private var showAddTask = false
    @State private var editingHW: Homework?
    @State private var editingTask: SchoolTask?
    @State private var detailRef: PlannerItemRef?
    @State private var showClearAlert = false
    @State private var isClearing = false
    @State private var toast: ToastMessage?

    // Deferred delete (web: hide row → "Item deleted" + Undo for 5 s → then
    // the API call). Starting a second delete commits the first immediately.
    @State private var hiddenKeys: Set<String> = []
    @State private var pendingDelete: PlannerItemRef?
    @State private var pendingDeleteTimer: Task<Void, Never>?

    private static let quickAddDue: DateFormatter = {
        let f = DateFormatter(); f.dateFormat = "EEE, MMM d"; return f
    }()

    // Manual homework only — PowerSchool assignments live in Grades
    private var manualHomework: [Homework] {
        store.homework.filter { $0.source != "powerschool" }
    }

    private var sortedClasses: [SchoolClass] { store.classes.plannerOrdered }

    private var allItems: [PlannerItemData] {
        let hw = manualHomework.map { PlannerItemData(homework: $0) }
        let tk = store.tasks.map { PlannerItemData(task: $0) }
        return (hw + tk).filter { !hiddenKeys.contains($0.id) }
    }

    private var filtered: [PlannerItemData] {
        switch filter {
        case .todo: return allItems.filter { !$0.completed }
        case .done: return allItems.filter {  $0.completed }
        case .all:  return allItems
        }
    }

    // Group by due date (web is a flat list by due date; sections keep the same
    // order). Undated items always go last.
    private var grouped: [(String, [PlannerItemData])] {
        // Completed items read newest → oldest (most recent due date first);
        // everything else stays soonest → latest. Undated items always last.
        let newestFirst = filter == .done
        return Dictionary(grouping: filtered, by: \.dueDate)
            .sorted { a, b in
                let ak = a.key, bk = b.key
                if ak.isEmpty && bk.isEmpty { return false }
                if ak.isEmpty { return false }
                if bk.isEmpty { return true }
                return newestFirst ? ak > bk : ak < bk
            }
            .map { ($0.key, $0.value.sorted { $0.title.localizedCaseInsensitiveCompare($1.title) == .orderedAscending }) }
    }

    private var pendingCount: Int { allItems.filter { !$0.completed }.count }
    private var doneCount: Int    { allItems.filter {  $0.completed }.count }

    private var rebalanceByHwId: [String: RebalanceSuggestion] {
        Dictionary(suggestRebalancing(homework: manualHomework).map { ($0.homework.id, $0) },
                   uniquingKeysWith: { a, _ in a })
    }

    /// `classId::dueDate` for every in-class item whose class is cancelled
    /// that day (web `disruptedClassInstances`).
    private var cancelledKeys: Set<String> {
        guard !store.disruptions.isEmpty, !store.classes.isEmpty else { return [] }
        let dates = Set(allItems.compactMap { i -> String? in
            guard i.dueTiming == .inClass, i.classId != nil, !i.dueDate.isEmpty else { return nil }
            return i.dueDate
        })
        guard !dates.isEmpty else { return [] }
        return store.cancelledKeys(forDates: dates)
    }

    var body: some View {
        NavigationStack {
            ZStack { CanopyBackground()
                if allItems.isEmpty && store.isLoading {
                    VStack { Spacer(); ProgressView(); Spacer() }
                } else {
                    itemList
                }
            }
            .navigationTitle("")
            .navigationBarTitleInline()
            .iosHideNavigationBar()
            .sheet(isPresented: $showAddTask) { TaskEditSheet(task: nil) }
            .sheet(item: $editingHW) { hw in HomeworkEditSheet(hw: hw) }
            .sheet(item: $editingTask) { task in TaskEditSheet(task: task) }
            .sheet(item: $detailRef) { ref in
                PlannerItemDetailSheet(ref: ref, onEdit: { edit($0) }, onDelete: { deferDelete($0) })
            }
            .alert("Clear all done?", isPresented: $showClearAlert) {
                Button("Cancel", role: .cancel) { }
                Button("Delete all done", role: .destructive) { Task { await clearDone() } }
            } message: {
                Text("Permanently delete \(doneCount) completed \(doneCount == 1 ? "item" : "items"). This can't be undone.")
            }
            .refreshable { await store.loadAll() }
            .toast($toast)
            .onChange(of: store.lastMutationError) { _, msg in
                guard let msg else { return }
                toast = ToastMessage(text: msg, kind: .error)
                store.lastMutationError = nil
            }
        }
    }

    // MARK: - Header (title, subtitle, tabs, quick add / clear bar)

    private var header: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .top, spacing: 12) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Homework & Tasks")
                        .font(.title2.bold()).fontDesign(.rounded)
                    Text("Personal homework and tasks — PowerSchool assignments are on the Grades page.")
                        .font(.caption).foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 0)
                Button { showAddTask = true } label: {
                    Image(systemName: "plus.circle.fill").font(.title2)
                }
                .accessibilityLabel("Add Task")
            }

            Picker("Filter", selection: $filter) {
                Text("To Do (\(pendingCount))").tag(HWFilter.todo)
                Text("Done").tag(HWFilter.done)
                Text("All").tag(HWFilter.all)
            }
            .pickerStyle(.segmented)

            if filter != .done && !sortedClasses.isEmpty {
                quickAddCard
            }

            if filter == .done && doneCount > 0 {
                clearDoneBar
            }
        }
        .padding(.vertical, 8)
    }

    // MARK: - Quick add (web "Quick add task · due next class meeting")

    private var quickAddCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                Image(systemName: "doc.text.fill")
                    .font(.caption).foregroundStyle(Color.accentColor)
                Text("QUICK ADD TASK")
                    .font(.caption2.weight(.semibold)).tracking(0.6)
                    .foregroundStyle(.secondary)
                Text("· due next class meeting")
                    .font(.caption2).foregroundStyle(.tertiary)
            }
            // Side-scroll only: a fixed height means there is never vertical
            // content to drag, and vertical bounce is disabled so trackpad or
            // diagonal finger drags can't rubber-band the row up and down.
            ScrollView(.horizontal) {
                HStack(spacing: 8) {
                    ForEach(sortedClasses) { cls in
                        QuickAddChip(cls: cls) { Task { await quickAdd(for: cls) } }
                            .help("Adds Homework for \(cls.name), due next class")
                    }
                }
                .padding(.vertical, 2)
            }
            .frame(height: 36)
            .scrollIndicators(.hidden)
            .scrollBounceBehavior(.basedOnSize, axes: [.vertical])
            .scrollClipDisabled(false)
        }
        .padding(12)
        .glassEffect(.regular, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous)
            .strokeBorder(Color.secondary.opacity(0.15), lineWidth: 0.5))
    }

    // MARK: - Clear done bar (web: "{n} completed" + "Clear all done")

    private var clearDoneBar: some View {
        HStack {
            Text("\(doneCount) completed")
                .font(.subheadline).foregroundStyle(.secondary)
            Spacer()
            Button(role: .destructive) { showClearAlert = true } label: {
                Label(isClearing ? "Clearing…" : "Clear all done", systemImage: "trash")
                    .font(.subheadline.weight(.semibold))
            }
            .disabled(isClearing)
        }
        .padding(.horizontal, 14).padding(.vertical, 10)
        .glassEffect(.regular, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous)
            .strokeBorder(Color.red.opacity(0.25), lineWidth: 0.5))
    }

    // MARK: - List

    private var itemList: some View {
        List {
            // Title, filter tabs and quick add live INSIDE the list so they
            // scroll away and leave the whole screen for tasks.
            Section {
                header
                    .listRowBackground(Color.clear)
                    .listRowSeparator(.hidden)
                    .listRowInsets(EdgeInsets(top: 0, leading: 16, bottom: 0, trailing: 16))
            }
            if filtered.isEmpty {
                Section {
                    emptyState
                        .listRowBackground(Color.clear)
                        .listRowSeparator(.hidden)
                }
            }
            ForEach(grouped, id: \.0) { date, items in
                itemSection(date: date, items: items)
            }
            if filter == .todo && !filtered.isEmpty {
                Section {
                    addTaskButton
                        .listRowBackground(Color.clear)
                        .listRowSeparator(.hidden)
                }
            }
        }
        .insetGroupedListStyle()
        .scrollContentBackground(.hidden)
        .contentMargins(.top, 0, for: .scrollContent)
    }

    @ViewBuilder
    private func itemSection(date: String, items: [PlannerItemData]) -> some View {
        let isOverdue = date.isOverdue && filter != .done
        let label = date.isEmpty ? "No date" : date.dueDateLabel
        let cancelled = cancelledKeys

        Section {
            ForEach(items) { item in
                itemRow(item, cancelled: cancelled)
            }
        } header: {
            Text(label)
                .font(.footnote.bold())
                .foregroundStyle(isOverdue ? Color.red : Color.secondary)
        }
    }

    @ViewBuilder
    private func itemRow(_ item: PlannerItemData, cancelled: Set<String>) -> some View {
        let cls = item.classId.flatMap { store.schoolClass($0) }
        let isCancelled = item.classId.map { cancelled.contains("\($0)::\(item.dueDate)") } ?? false
        let rebalance = item.ref.kind == .homework ? rebalanceByHwId[item.ref.id] : nil

        PlannerItemRow(item: item, cls: cls, classCancelled: isCancelled, rebalance: rebalance) {
            toggle(item.ref)
        }
        .contentShape(Rectangle())
        .onTapGesture { detailRef = item.ref }
        .accessibilityAddTraits(.isButton)
        .listRowBackground(rowBackground(overdue: item.isOverdue))
        .swipeActions(edge: .leading) {
            Button { toggle(item.ref) } label: {
                Label(item.completed ? "Undo" : "Done",
                      systemImage: item.completed ? "arrow.uturn.left" : "checkmark")
            }.tint(.green)
        }
        .swipeActions(edge: .trailing) {
            Button(role: .destructive) { deferDelete(item.ref) } label: {
                Label("Delete", systemImage: "trash")
            }.tint(.red)
            Button { edit(item.ref) } label: { Label("Edit", systemImage: "pencil") }.tint(.blue)
        }
        .contextMenu {
            Button { detailRef = item.ref } label: { Label("Details", systemImage: "info.circle") }
            Button { edit(item.ref) } label: { Label("Edit", systemImage: "pencil") }
            Button { toggle(item.ref) } label: {
                Label(item.completed ? "Mark not done" : "Mark done",
                      systemImage: item.completed ? "circle" : "checkmark.circle")
            }
            Divider()
            Button(role: .destructive) { deferDelete(item.ref) } label: { Label("Delete", systemImage: "trash") }
        }
    }

    /// Web: overdue rows get a 3px red left border + a faint red wash.
    @ViewBuilder
    private func rowBackground(overdue: Bool) -> some View {
        if overdue {
            ZStack(alignment: .leading) {
                Rectangle().fill(.regularMaterial)
                Color.red.opacity(0.06)
                Color.red.frame(width: 3)
            }
        } else {
            Rectangle().fill(.regularMaterial)
        }
    }

    private var addTaskButton: some View {
        Button { showAddTask = true } label: {
            Label("Add Task", systemImage: "plus")
                .font(.subheadline.weight(.medium))
                .frame(maxWidth: .infinity)
                .padding(.vertical, 11)
                .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .strokeBorder(style: StrokeStyle(lineWidth: 1, dash: [5, 4]))
                    .foregroundStyle(Color.secondary.opacity(0.5)))
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .foregroundStyle(.secondary)
    }

    // MARK: - Empty state (web copy)

    private var emptyState: some View {
        VStack(spacing: 10) {
            Image(systemName: filter == .todo ? "checkmark.circle.fill" : "tray")
                .font(.system(size: 40))
                .foregroundStyle(filter == .todo ? Color.green : Color.secondary)
            Text(filter == .todo ? "All caught up!" : filter == .done ? "Nothing completed yet." : "No items yet.")
                .font(.headline).foregroundStyle(.secondary)
            if filter != .done {
                Text("Use the + button to add a task.")
                    .font(.subheadline).foregroundStyle(.tertiary)
                addTaskButton
                    .frame(maxWidth: 320)
                    .padding(.top, 8)
            }
        }
        .padding(.vertical, 40)
        .frame(maxWidth: .infinity)
    }

    // MARK: - Actions

    private func toggle(_ ref: PlannerItemRef) {
        Task {
            switch ref.kind {
            case .task: if let t = store.tasks.first(where: { $0.id == ref.id }) { await store.toggleTask(t) }
            case .homework: if let h = store.homework.first(where: { $0.id == ref.id }) { await store.toggleHomework(h) }
            }
        }
    }

    private func edit(_ ref: PlannerItemRef) {
        switch ref.kind {
        case .task: editingTask = store.tasks.first { $0.id == ref.id }
        case .homework: editingHW = store.homework.first { $0.id == ref.id }
        }
    }

    // MARK: - Deferred delete (5 s undo window)

    private func deferDelete(_ ref: PlannerItemRef) {
        if let prev = pendingDelete {
            pendingDeleteTimer?.cancel()
            commitDelete(prev)
        }
        withAnimation(.spring(response: 0.3)) { _ = hiddenKeys.insert(ref.key) }
        pendingDelete = ref
        pendingDeleteTimer = Task {
            try? await Task.sleep(for: .seconds(5))
            guard !Task.isCancelled, pendingDelete == ref else { return }
            pendingDelete = nil
            pendingDeleteTimer = nil
            commitDelete(ref)
        }
        toast = ToastMessage(text: "Item deleted", actionLabel: "Undo") { undoDelete() }
    }

    /// Store deletes are optimistic (removed locally before the request), so
    /// the row never reappears between un-hiding and the server reply.
    private func commitDelete(_ ref: PlannerItemRef) {
        Task {
            switch ref.kind {
            case .task:
                if let t = store.tasks.first(where: { $0.id == ref.id }) { await store.deleteTask(t) }
            case .homework:
                if let h = store.homework.first(where: { $0.id == ref.id }) { await store.deleteHomework(h) }
            }
            hiddenKeys.remove(ref.key)
        }
    }

    private func undoDelete() {
        guard let ref = pendingDelete else { return }
        pendingDeleteTimer?.cancel()
        pendingDeleteTimer = nil
        pendingDelete = nil
        withAnimation(.spring(response: 0.3)) { _ = hiddenKeys.remove(ref.key) }
    }

    // MARK: - Quick add (creates a Task, matching web)

    private func quickAdd(for cls: SchoolClass) async {
        let tomorrow = DateFormatter.iso.string(from: Calendar.current.date(byAdding: .day, value: 1, to: .now) ?? .now)
        let due = ScheduleEngine.nextMeetingDate(days: cls.days).nonEmpty ?? tomorrow
        let template = StageTemplate.load()
        let task = SchoolTask(
            id: UUID().uuidString,
            title: "Homework",
            description: "",
            dueDate: due,
            completed: false,
            priority: "medium",
            category: "Homework",
            classId: cls.id,
            stages: template.isEmpty ? nil : template,
            stageId: nil,
            dueTiming: DueTiming.inClass.rawValue
        )
        do {
            try await store.saveTask(task, isNew: true)
            let dueText = due.asDate.map { Self.quickAddDue.string(from: $0) } ?? due
            toast = ToastMessage(text: "Added \"Homework\" for \(cls.name) — due \(dueText)", kind: .success)
        } catch {
            toast = ToastMessage(text: "Couldn't add: \(error.localizedDescription)", kind: .error)
        }
    }

    // MARK: - Clear done (batch)

    private func clearDone() async {
        isClearing = true
        defer { isClearing = false }
        do {
            let n = try await store.clearDone()
            toast = ToastMessage(text: "Cleared \(n) completed items", kind: .success)
        } catch {
            toast = ToastMessage(text: "Couldn't clear: \(error.localizedDescription)", kind: .error)
        }
    }
}

// MARK: - Quick Add Chip (web: "+" icon, 4px class-colour left border, colour @ .1)

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
                Image(systemName: "plus").font(.caption.weight(.bold))
                Text(cls.name).font(.caption.weight(.medium)).lineLimit(1)
            }
            .padding(.leading, 12).padding(.trailing, 10).padding(.vertical, 7)
            .background(Color(hex: cls.color).opacity(0.1))
            .overlay(alignment: .leading) { Color(hex: cls.color).frame(width: 4) }
            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        }
        .buttonStyle(.plain)
        .scaleEffect(pressed ? 0.91 : 1.0)
    }
}

// MARK: - Legacy Homework edit sheet (web "Edit Homework")

struct HomeworkEditSheet: View {
    @Environment(CanopyStore.self) private var store
    @Environment(\.dismiss) private var dismiss

    let hw: Homework?

    @State private var title = ""
    @State private var description = ""
    @State private var dueDate = Date.now
    @State private var priority = "medium"
    @State private var classId = ""
    @State private var dueTiming: DueTiming? = .inClass
    @State private var stages: [TaskStage] = []
    @State private var isSaving = false
    @State private var error: String?

    private var isNew: Bool { hw == nil }
    private var sortedClasses: [SchoolClass] { store.classes.plannerOrdered }
    private var canSave: Bool {
        !title.trimmingCharacters(in: .whitespaces).isEmpty && !classId.isEmpty && !isSaving
    }

    var body: some View {
        NavigationStack {
            ZStack { CanopyBackground()
                ScrollView {
                    VStack(spacing: 16) {
                        FormEditCard {
                            VStack(spacing: 0) {
                                TextField("Title", text: $title)
                                    .font(.body)
                                    .padding(.horizontal, 16).padding(.vertical, 13)
                                Divider().padding(.leading, 16)
                                TextField("Description", text: $description, axis: .vertical)
                                    .font(.body)
                                    .lineLimit(2...6)
                                    .padding(.horizontal, 16).padding(.vertical, 13)
                            }
                        }

                        // Class — required for homework
                        FormEditCard {
                            HStack {
                                Label("Class", systemImage: "person.2").font(.body)
                                Spacer()
                                if sortedClasses.isEmpty {
                                    Text("No classes yet").font(.subheadline).foregroundStyle(.secondary)
                                } else {
                                    Picker("", selection: $classId) {
                                        ForEach(sortedClasses) { cls in
                                            HStack {
                                                ClassColorDot(hex: cls.color)
                                                Text(cls.name)
                                            }.tag(cls.id)
                                        }
                                    }
                                    .labelsHidden()
                                }
                            }
                            .padding(.horizontal, 16).padding(.vertical, 13)
                        }

                        // Due Date
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

                        // Priority
                        FormEditCard {
                            VStack(alignment: .leading, spacing: 10) {
                                Label("Priority", systemImage: "flag")
                                    .font(.body)
                                    .padding(.horizontal, 16).padding(.top, 13)
                                HStack(spacing: 8) {
                                    PriorityPill(value: "low", label: "Low", color: .secondary, selection: $priority)
                                    PriorityPill(value: "medium", label: "Medium", color: .orange, selection: $priority)
                                    PriorityPill(value: "high", label: "High", color: .red, selection: $priority)
                                }
                                .padding(.horizontal, 12).padding(.bottom, 12)
                            }
                        }

                        // Due timing
                        FormEditCard {
                            VStack(alignment: .leading, spacing: 10) {
                                Label("Due", systemImage: "clock")
                                    .font(.body)
                                    .padding(.horizontal, 16).padding(.top, 13)
                                DueTimingToggle(value: $dueTiming)
                                    .padding(.horizontal, 12).padding(.bottom, 12)
                            }
                        }

                        Divider().padding(.vertical, 4)

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
            .navigationTitle(isNew ? "Add Homework" : "Edit Homework")
            .navigationBarTitleInline()
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button(isSaving ? "Saving…" : (isNew ? "Add" : "Save")) { Task { await save() } }
                        .disabled(!canSave)
                        .fontWeight(.semibold)
                }
            }
        }
        .onAppear { prefill() }
    }

    private func prefill() {
        if let hw {
            title = hw.title
            description = hw.description
            dueDate = hw.dueDate.asDate ?? .now
            priority = hw.priority
            classId = hw.classId
            dueTiming = hw.dueTiming.flatMap(DueTiming.init(rawValue:))
            stages = hw.stages ?? []
        } else {
            stages = StageTemplate.load()
        }
        if classId.isEmpty || store.schoolClass(classId) == nil {
            classId = sortedClasses.first?.id ?? ""
        }
    }

    private func save() async {
        isSaving = true; defer { isSaving = false }
        // Start from the original so every server field (teacherNote, score,
        // flags, source…) round-trips untouched.
        var item = hw ?? Homework(
            id: UUID().uuidString, classId: "", title: "", description: "", dueDate: "",
            completed: false, priority: "medium", source: "manual", sourceId: nil, score: nil,
            scorePercent: nil, category: nil, flags: nil, stages: nil, stageId: nil,
            dueTiming: nil, teacherNote: nil
        )
        let cleanStages = stages.plannerCleaned
        let validStageId = (hw?.stageId).flatMap { id in cleanStages.contains { $0.id == id } ? id : nil }
        item.title = title.trimmingCharacters(in: .whitespaces)
        item.description = description
        item.classId = classId
        item.dueDate = DateFormatter.iso.string(from: dueDate)
        item.priority = priority
        item.dueTiming = dueTiming?.rawValue
        item.stages = cleanStages.isEmpty ? nil : cleanStages
        item.stageId = cleanStages.isEmpty ? nil : validStageId
        item.completed = cleanStages.isEmpty ? (hw?.completed ?? false) : store.completedForStage(cleanStages, validStageId)
        do {
            try await store.saveHomework(item, isNew: isNew)
            dismiss()
        } catch { self.error = "Couldn't save: \(error.localizedDescription)" }
    }
}
