import SwiftUI

private let taskCategories = ["General", "Ask", "Homework", "Study", "Project", "Reading", "Practice", "Other"]

// Note: this file also defines TaskListRow, TaskDetailSheet, and TaskEditSheet
// below, which HomeworkView.swift's unified Planner list actively uses. A
// standalone `TasksView` (Tasks-only screen) previously lived here but was
// never wired into any navigation — removed as dead code.

// MARK: - Row

struct TaskListRow: View {
    let task: SchoolTask
    let store: CanopyStore

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            AnimatedCheckButton(checked: task.completed) {
                Task { await store.toggleTask(task) }
            }
            .padding(.top, 2)

            VStack(alignment: .leading, spacing: 5) {
                Text(task.title)
                    .font(.body.weight(.medium))
                    .strikethrough(task.completed, color: .secondary)
                    .foregroundStyle(task.completed ? .secondary : .primary)
                    .animation(.easeInOut(duration: 0.2), value: task.completed)

                HStack(spacing: 6) {
                    CategoryBadge(category: task.category)
                    if let cid = task.classId, !cid.isEmpty,
                       let cls = store.schoolClass(cid) {
                        ClassColorDot(hex: cls.color, size: 7)
                        Text(cls.name).font(.caption2).foregroundStyle(.secondary)
                    }
                    if !task.dueDate.isEmpty {
                        Text(task.dueDate.dueDateLabel)
                            .font(.caption2)
                            .foregroundStyle(
                                task.dueDate.isOverdue && !task.completed ? Color.red : Color.secondary
                            )
                    }
                }

                if !task.description.isEmpty {
                    Text(task.description)
                        .font(.caption).foregroundStyle(.secondary).lineLimit(1)
                }
            }

            Spacer(minLength: 0)

            if task.priority == "high" || task.priority == "medium" {
                PriorityDot(priority: task.priority).padding(.top, 6)
            }
        }
        .padding(.vertical, 6)
        .opacity(task.completed ? 0.55 : 1)
        .animation(.easeInOut(duration: 0.25), value: task.completed)
    }
}



// MARK: - Task Detail Sheet

struct TaskDetailSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(CanopyStore.self) private var store
    let task: SchoolTask
    let onEdit: () -> Void

    var body: some View {
        NavigationStack {
            ZStack { CanopyBackground()
                ScrollView {
                    VStack(alignment: .leading, spacing: 16) {
                        // Header card
                        VStack(alignment: .leading, spacing: 10) {
                            HStack {
                                CategoryBadge(category: task.category)
                                Spacer()
                                HStack(spacing: 4) {
                                    PriorityDot(priority: task.priority)
                                    Text(task.priority.capitalized)
                                        .font(.caption).foregroundStyle(.secondary)
                                }
                            }
                            Text(task.title)
                                .font(.title2.bold())
                                .strikethrough(task.completed)
                                .foregroundStyle(task.completed ? .secondary : .primary)
                            if !task.description.isEmpty {
                                Text(task.description)
                                    .font(.body).foregroundStyle(.secondary)
                            }
                            Divider()
                            HStack(spacing: 20) {
                                if let cid = task.classId, !cid.isEmpty,
                                   let cls = store.schoolClass(cid) {
                                    Label {
                                        Text(cls.name).font(.subheadline)
                                    } icon: {
                                        ClassColorDot(hex: cls.color, size: 9)
                                    }
                                }
                                if !task.dueDate.isEmpty {
                                    Label(task.dueDate.dueDateLabel, systemImage: "calendar")
                                        .font(.subheadline)
                                        .foregroundStyle(
                                            task.dueDate.isOverdue && !task.completed ? Color.red : Color.secondary
                                        )
                                }
                                Spacer()
                            }
                        }
                        .padding(16)
                        .glassCard(cornerRadius: 16)

                        // Actions — stage tracker (custom pipeline) or a plain checkbox.
                        if let stages = task.stages, !stages.isEmpty {
                            VStack(alignment: .leading, spacing: 10) {
                                SectionLabel(text: "Progress")
                                StageTrackerView(stages: stages, currentStageId: task.stageId) { newId in
                                    Task { await store.setTaskStage(task, stageId: newId) }
                                }
                                .padding(12)
                                .glassCard(cornerRadius: 14)
                                if task.stageId != nil {
                                    Button("Reset to not started") {
                                        Task { await store.setTaskStage(task, stageId: nil) }
                                    }
                                    .font(.caption).foregroundStyle(.secondary)
                                }
                            }
                        } else {
                            Button {
                                Task { await store.toggleTask(task); dismiss() }
                            } label: {
                                Label(task.completed ? "Mark Incomplete" : "Mark Complete",
                                      systemImage: task.completed ? "arrow.uturn.left" : "checkmark.circle.fill")
                                    .frame(maxWidth: .infinity)
                                    .padding(.vertical, 12)
                            }
                            .tint(task.completed ? .secondary : .accentColor)
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
                                Task { await store.deleteTask(task); dismiss() }
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
            .navigationTitle("Task Detail")
            .navigationBarTitleInline()
            .toolbar {
                ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } }
            }
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
    @State private var category = "General"
    @State private var classId = ""
    @State private var stages: [TaskStage] = []
    @State private var isSaving = false
    @State private var error: String?

    private var isNew: Bool { task == nil }

    var body: some View {
        NavigationStack {
            ZStack { CanopyBackground()
                ScrollView {
                    VStack(spacing: 16) {
                        // ── Details ──────────────────────────────────────
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

                        // ── Category ─────────────────────────────────────
                        FormEditCard {
                            HStack {
                                Label("Category", systemImage: "tag")
                                    .font(.body)
                                    .foregroundStyle(.primary)
                                Spacer()
                                Picker("", selection: $category) {
                                    ForEach(taskCategories, id: \.self) { Text($0).tag($0) }
                                }
                                .labelsHidden()
                            }
                            .padding(.horizontal, 16).padding(.vertical, 13)
                        }

                        // ── Priority ─────────────────────────────────────
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

                        // ── Due Date ─────────────────────────────────────
                        FormEditCard {
                            VStack(spacing: 0) {
                                Toggle(isOn: $hasDueDate.animation(.spring(response: 0.3, dampingFraction: 0.8))) {
                                    Label("Due Date", systemImage: "calendar")
                                        .font(.body)
                                }
                                .padding(.horizontal, 16).padding(.vertical, 13)
                                if hasDueDate {
                                    Divider().padding(.leading, 16)
                                    DatePicker("", selection: $dueDate, displayedComponents: .date)
                                        .datePickerStyle(.compact)
                                        .labelsHidden()
                                        .padding(.horizontal, 16).padding(.vertical, 10)
                                        .frame(maxWidth: .infinity, alignment: .leading)
                                }
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
                                Image(systemName: "exclamationmark.triangle.fill")
                                    .font(.footnote)
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
            .navigationTitle(isNew ? "New Task" : "Edit Task")
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

    // ── Helpers ───────────────────────────────────────────────────────────────



    private func prefill() {
        guard let task else { return }
        title = task.title; description = task.description
        priority = task.priority; category = task.category
        classId = task.classId ?? ""
        stages = task.stages ?? []
        if !task.dueDate.isEmpty, let d = task.dueDate.asDate {
            hasDueDate = true; dueDate = d
        }
    }

    private func save() async {
        isSaving = true; defer { isSaving = false }
        // Preserve the current stage only if it still refers to a stage that
        // survived editing; `completed` always stays derived from it.
        let validStageId = (task?.stageId).flatMap { id in stages.contains { $0.id == id } ? id : nil }
        let item = SchoolTask(
            id: task?.id ?? UUID().uuidString,
            title: title, description: description,
            dueDate: hasDueDate ? DateFormatter.iso.string(from: dueDate) : "",
            completed: stages.isEmpty ? (task?.completed ?? false) : store.completedForStage(stages, validStageId),
            priority: priority, category: category,
            classId: classId.isEmpty ? nil : classId,
            stages: stages.isEmpty ? nil : stages,
            stageId: stages.isEmpty ? nil : validStageId
        )
        do {
            try await store.saveTask(item, isNew: isNew)
            dismiss()
        } catch { self.error = error.localizedDescription }
    }
}
