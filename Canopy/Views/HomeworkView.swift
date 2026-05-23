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
    @State private var showClearAlert = false

    // Manual homework only — PowerSchool assignments live in Grades
    private var manualHomework: [Homework] {
        store.homework.filter { $0.source != "powerschool" }
    }

    private var allItems: [HWItem] {
        let hwItems = manualHomework.map { HWItem.homework($0) }
        let taskItems = store.tasks.map { HWItem.task($0) }
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

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                // Top Bar
                VStack(spacing: 0) {
                    Picker("Filter", selection: $filter) {
                        Text("Upcoming (\(pendingCount))").tag(HWFilter.upcoming)
                        Text("Done (\(doneCount))").tag(HWFilter.done)
                        Text("All (\(allItems.count))").tag(HWFilter.all)
                    }
                    .pickerStyle(.segmented)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 8)
                    
                    if filter != .done && !store.classes.isEmpty {
                        Divider()
                        quickAddRow
                            .padding(.horizontal, 12)
                            .padding(.vertical, 6)
                    }
                    
                    if filter == .done && doneCount > 0 {
                        Divider()
                        clearDoneBar
                            .padding(.horizontal, 12)
                            .padding(.vertical, 6)
                    }
                    Divider()
                }
                .background(.bar)
                
                ZStack { CanopyBackground()
                    if allItems.isEmpty && store.isLoading {
                        VStack { Spacer(); ProgressView(); Spacer() }
                    } else if filtered.isEmpty {
                        emptyState
                    } else {
                        itemList
                    }
                }
            }
            .navigationTitle("Homework & Tasks")
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
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
            }
            .sheet(isPresented: $showAddHWSheet) { HomeworkEditSheet(hw: nil) }
            .sheet(isPresented: $showAddTaskSheet) { TaskEditSheet(task: nil) }
            .sheet(item: $editingHW) { hw in HomeworkEditSheet(hw: hw) }
            .sheet(item: $editingTask) { task in TaskEditSheet(task: task) }
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
        .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous)
            .strokeBorder(Color.secondary.opacity(0.2), lineWidth: 0.5))
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
            HWListRow(hw: hw, store: store)
                .contentShape(Rectangle())
                .onTapGesture { editingHW = hw }
                .accessibilityAddTraits(.isButton)
                .swipeActions(edge: .leading) {
                    Button { Task { await store.toggleHomework(hw) } } label: {
                        Label(hw.completed ? "Undo" : "Done",
                              systemImage: hw.completed ? "arrow.uturn.left" : "checkmark")
                    }.tint(Color.accentColor)
                }
                .swipeActions(edge: .trailing) {
                    Button(role: .destructive) {
                        Task { await store.deleteHomework(hw) }
                    } label: { Label("Delete", systemImage: "trash") }
                    Button { editingHW = hw } label: {
                        Label("Edit", systemImage: "pencil")
                    }.tint(.blue)
                }

        case .task(let task):
            TaskListRow(task: task, store: store)
                .contentShape(Rectangle())
                .onTapGesture { editingTask = task }
                .accessibilityAddTraits(.isButton)
                .swipeActions(edge: .leading) {
                    Button { Task { await store.toggleTask(task) } } label: {
                        Label(task.completed ? "Undo" : "Done",
                              systemImage: task.completed ? "arrow.uturn.left" : "checkmark")
                    }.tint(Color.accentColor)
                }
                .swipeActions(edge: .trailing) {
                    Button(role: .destructive) {
                        Task { await store.deleteTask(task) }
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
                    ? "Add homework or tasks with the + button."
                    : "Use Quick Add or + to get started.")
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
    }

    private func save() async {
        isSaving = true; defer { isSaving = false }
        let item = Homework(
            id: hw?.id ?? UUID().uuidString,
            classId: classId,
            title: title,
            description: description,
            dueDate: DateFormatter.iso.string(from: dueDate),
            completed: hw?.completed ?? false,
            priority: priority,
            source: hw?.source ?? "manual"
        )
        do {
            try await store.saveHomework(item, isNew: isNew)
            dismiss()
        } catch { self.error = error.localizedDescription }
    }
}
