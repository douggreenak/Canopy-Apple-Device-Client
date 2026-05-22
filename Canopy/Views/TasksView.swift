import SwiftUI

private let categories = ["Homework", "Study", "Project", "Ask", "Other"]

struct TasksView: View {
    @Environment(CanopyStore.self) private var store
    @State private var showDone = false
    @State private var showAdd = false
    @State private var editing: SchoolTask?

    private var visible: [SchoolTask] {
        store.tasks
            .filter { $0.completed == showDone }
            .sorted { $0.priority.priorityOrder < $1.priority.priorityOrder }
    }

    var body: some View {
        NavigationStack {
            ZStack { CanopyBackground()
                Group {
                    if visible.isEmpty {
                        ContentUnavailableView(
                            showDone ? "No Completed Tasks" : "No Pending Tasks",
                            systemImage: showDone ? "tray" : "sparkles",
                            description: Text(showDone ? "Completed tasks appear here." : "All clear — add a task to get started.")
                        )
                    } else {
                        List {
                            ForEach(visible) { task in
                                TaskListRow(task: task, store: store)
                                    .onTapGesture { editing = task }
                                    .swipeActions(edge: .leading) {
                                        Button {
                                            Task { await store.toggleTask(task) }
                                        } label: {
                                            Label(task.completed ? "Undo" : "Done",
                                                  systemImage: task.completed ? "arrow.uturn.left" : "checkmark")
                                        }.tint(.canopyGreen)
                                    }
                                    .swipeActions(edge: .trailing) {
                                        Button(role: .destructive) {
                                            Task { await store.deleteTask(task) }
                                        } label: { Label("Delete", systemImage: "trash") }
                                    }
                            }
                        }
                        .listStyle(.insetGrouped)
                        .scrollContentBackground(.hidden)
                    }
                }
            }
            .navigationTitle("Tasks")
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Picker("", selection: $showDone) {
                        Text("Pending").tag(false)
                        Text("Done").tag(true)
                    }
                    .pickerStyle(.segmented)
                    .frame(width: 150)
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button { showAdd = true } label: {
                        Image(systemName: "plus.circle.fill").font(.title3)
                    }
                }
            }
            .sheet(isPresented: $showAdd) { TaskEditSheet(task: nil) }
            .sheet(item: $editing) { t in TaskEditSheet(task: t) }
            .refreshable { await store.loadAll() }
        }
    }
}

// MARK: - Row
struct TaskListRow: View {
    let task: SchoolTask; let store: CanopyStore
    var body: some View {
        HStack(spacing: 12) {
            Button { Task { await store.toggleTask(task) } } label: {
                Image(systemName: task.completed ? "checkmark.circle.fill" : "circle")
                    .font(.title2)
                    .foregroundStyle(task.completed ? Color.canopyGreen : Color(uiColor: .systemFill))
            }
            .buttonStyle(.plain)

            VStack(alignment: .leading, spacing: 3) {
                Text(task.title)
                    .strikethrough(task.completed)
                    .foregroundStyle(task.completed ? .secondary : .primary)
                HStack(spacing: 6) {
                    CategoryBadge(category: task.category)
                    if let cid = task.classId, !cid.isEmpty, let cls = store.schoolClass(cid) {
                        ClassColorDot(hex: cls.color, size: 7)
                        Text(cls.name).font(.caption2).foregroundStyle(.secondary)
                    }
                }
            }
            Spacer()
            PriorityDot(priority: task.priority)
        }
        .padding(.vertical, 4)
    }
}

struct CategoryBadge: View {
    let category: String
    var body: some View {
        Text(category)
            .font(.caption2.bold())
            .padding(.horizontal, 7).padding(.vertical, 2)
            .background(categoryColor.opacity(0.18), in: Capsule())
            .foregroundStyle(categoryColor)
    }
    private var categoryColor: Color {
        switch category {
        case "Ask":     return .orange
        case "Study":   return .blue
        case "Project": return .purple
        case "Homework": return .canopyGreen
        default:        return .secondary
        }
    }
}

// MARK: - Edit Sheet
struct TaskEditSheet: View {
    @Environment(CanopyStore.self) private var store
    @Environment(\.dismiss) private var dismiss

    var task: SchoolTask?

    @State private var title = ""
    @State private var description = ""
    @State private var dueDate = Date.now
    @State private var hasDueDate = false
    @State private var priority = "medium"
    @State private var category = "Other"
    @State private var classId = ""
    @State private var isSaving = false
    @State private var error: String?

    private var isNew: Bool { task == nil }

    var body: some View {
        NavigationStack {
            Form {
                Section("Details") {
                    TextField("Title", text: $title)
                    TextField("Description (optional)", text: $description, axis: .vertical)
                        .lineLimit(3...6)
                }
                Section("Category") {
                    Picker("Category", selection: $category) {
                        ForEach(categories, id: \.self) { Text($0).tag($0) }
                    }
                    .pickerStyle(.menu)
                }
                Section("Priority") {
                    Picker("Priority", selection: $priority) {
                        Text("High").tag("high")
                        Text("Medium").tag("medium")
                        Text("Low").tag("low")
                    }
                    .pickerStyle(.segmented)
                }
                Section("Due Date") {
                    Toggle("Has due date", isOn: $hasDueDate)
                    if hasDueDate {
                        DatePicker("", selection: $dueDate, displayedComponents: .date)
                            .datePickerStyle(.compact)
                            .tint(.canopyGreen)
                    }
                }
                Section("Class (optional)") {
                    Picker("Class", selection: $classId) {
                        Text("None").tag("")
                        ForEach(store.classes) { cls in
                            HStack { ClassColorDot(hex: cls.color); Text(cls.name) }.tag(cls.id)
                        }
                    }
                }
                if let e = error {
                    Section { Text(e).foregroundStyle(.red).font(.caption) }
                }
            }
            .scrollContentBackground(.hidden)
            .background(CanopyBackground())
            .navigationTitle(isNew ? "New Task" : "Edit Task")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button(isSaving ? "Saving…" : "Save") { Task { await save() } }
                        .disabled(title.isEmpty || isSaving)
                }
            }
        }
        .onAppear { prefill() }
    }

    private func prefill() {
        guard let task else { return }
        title = task.title; description = task.description
        priority = task.priority; category = task.category
        classId = task.classId ?? ""
        if !task.dueDate.isEmpty, let d = task.dueDate.asDate {
            hasDueDate = true; dueDate = d
        }
    }

    private func save() async {
        isSaving = true; defer { isSaving = false }
        let item = SchoolTask(
            id: task?.id ?? UUID().uuidString,
            title: title,
            description: description,
            dueDate: hasDueDate ? DateFormatter.iso.string(from: dueDate) : "",
            completed: task?.completed ?? false,
            priority: priority,
            category: category,
            classId: classId.isEmpty ? nil : classId
        )
        do {
            try await store.saveTask(item, isNew: isNew)
            dismiss()
        } catch { self.error = error.localizedDescription }
    }
}
