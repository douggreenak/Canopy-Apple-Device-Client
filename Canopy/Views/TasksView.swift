import SwiftUI

/// Web Tasks page CATEGORIES.
let taskCategories = ["General", "Ask", "Homework", "Study", "Project", "Reading", "Practice", "Other"]

// Note: the unified Planner row and detail sheet live in PlannerItemRow.swift
// and the Planner screen itself in HomeworkView.swift. This file holds the
// Task add/edit sheet (web "Add Task" / "Edit Task" dialog).

// MARK: - Add / Edit Task sheet

struct TaskEditSheet: View {
    @Environment(CanopyStore.self) private var store
    @Environment(\.dismiss) private var dismiss

    var task: SchoolTask?

    @State private var title = ""
    @State private var description = ""
    @State private var dueDate = Date.now
    @State private var hasDueDate = true
    @State private var priority = "medium"
    @State private var category = "General"
    @State private var classId = ""
    @State private var dueTiming: DueTiming? = .inClass
    @State private var stages: [TaskStage] = []
    @State private var isSaving = false
    @State private var error: String?

    private var isNew: Bool { task == nil }
    private var sortedClasses: [SchoolClass] { store.classes.plannerOrdered }

    var body: some View {
        NavigationStack {
            ZStack { CanopyBackground()
                ScrollView {
                    VStack(spacing: 16) {
                        // ── Title / Description ──────────────────────────
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

                        // ── Due Date (default today; clearable) ──────────
                        FormEditCard {
                            VStack(spacing: 0) {
                                Toggle(isOn: $hasDueDate.animation(.spring(response: 0.3, dampingFraction: 0.8))) {
                                    Label("Due Date", systemImage: "calendar").font(.body)
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

                        // ── Priority ─────────────────────────────────────
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

                        // ── Category ─────────────────────────────────────
                        FormEditCard {
                            HStack {
                                Label("Category", systemImage: "tag").font(.body)
                                Spacer()
                                Picker("", selection: $category) {
                                    ForEach(taskCategories, id: \.self) { Text($0).tag($0) }
                                }
                                .labelsHidden()
                            }
                            .padding(.horizontal, 16).padding(.vertical, 13)
                        }

                        // ── Due timing ───────────────────────────────────
                        FormEditCard {
                            VStack(alignment: .leading, spacing: 10) {
                                Label("Due", systemImage: "clock")
                                    .font(.body)
                                    .padding(.horizontal, 16).padding(.top, 13)
                                DueTimingToggle(value: $dueTiming)
                                    .padding(.horizontal, 12).padding(.bottom, 12)
                            }
                        }

                        // ── Class (optional) ─────────────────────────────
                        if !sortedClasses.isEmpty {
                            FormEditCard {
                                HStack {
                                    Label("Class (optional)", systemImage: "person.2").font(.body)
                                    Spacer()
                                    Picker("", selection: $classId) {
                                        Text("None").tag("")
                                        ForEach(sortedClasses) { cls in
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

                        Divider().padding(.vertical, 4)

                        // ── Completion Stages (per item) ─────────────────
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
            .navigationTitle(isNew ? "Add Task" : "Edit Task")
            .navigationBarTitleInline()
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button(isSaving ? "Saving…" : (isNew ? "Add" : "Save")) { Task { await save() } }
                        .disabled(title.trimmingCharacters(in: .whitespaces).isEmpty || isSaving)
                        .fontWeight(.semibold)
                }
            }
        }
        .onAppear { prefill() }
    }

    // ── Helpers ───────────────────────────────────────────────────────────────

    private func prefill() {
        guard let task else {
            // Web openAdd: due today, in_class, last-used stage template.
            hasDueDate = true
            dueDate = .now
            dueTiming = .inClass
            stages = StageTemplate.load()
            return
        }
        title = task.title; description = task.description
        priority = task.priority; category = task.category
        classId = task.classId ?? ""
        dueTiming = task.dueTiming.flatMap(DueTiming.init(rawValue:))
        stages = task.stages ?? []
        if !task.dueDate.isEmpty, let d = task.dueDate.asDate {
            hasDueDate = true; dueDate = d
        } else {
            hasDueDate = false
        }
    }

    private func save() async {
        isSaving = true; defer { isSaving = false }
        // Start from the original so unknown/extra fields round-trip.
        var item = task ?? SchoolTask(
            id: UUID().uuidString, title: "", description: "", dueDate: "", completed: false,
            priority: "medium", category: "General", classId: nil, stages: nil, stageId: nil, dueTiming: nil
        )
        let cleanStages = stages.plannerCleaned
        // Preserve the current stage only if it still refers to a stage that
        // survived editing; `completed` stays derived from it.
        let validStageId = (task?.stageId).flatMap { id in cleanStages.contains { $0.id == id } ? id : nil }
        item.title = title.trimmingCharacters(in: .whitespaces)
        item.description = description
        item.dueDate = hasDueDate ? DateFormatter.iso.string(from: dueDate) : ""
        item.priority = priority
        item.category = category
        item.classId = classId.isEmpty ? nil : classId
        item.dueTiming = dueTiming?.rawValue
        item.stages = cleanStages.isEmpty ? nil : cleanStages
        item.stageId = cleanStages.isEmpty ? nil : validStageId
        item.completed = cleanStages.isEmpty ? (task?.completed ?? false) : store.completedForStage(cleanStages, validStageId)
        do {
            try await store.saveTask(item, isNew: isNew)
            dismiss()
        } catch { self.error = "Couldn't save: \(error.localizedDescription)" }
    }
}
