import SwiftUI

struct HomeworkView: View {
    @Environment(CanopyStore.self) private var store
    @State private var showAddSheet = false
    @State private var editingHW: Homework?
    @State private var showCompleted = false

    private var filtered: [Homework] {
        store.homework
            .filter { $0.completed == showCompleted }
            .sorted { showCompleted ? $0.dueDate > $1.dueDate : $0.dueDate < $1.dueDate }
    }

    private var grouped: [(String, [Homework])] {
        Dictionary(grouping: filtered, by: \.dueDate)
            .sorted { showCompleted ? $0.key > $1.key : $0.key < $1.key }
            .map { ($0.key, $0.value.sorted { $0.priority.priorityOrder < $1.priority.priorityOrder }) }
    }

    var body: some View {
        NavigationStack {
            ZStack { CanopyBackground()
                Group {
                    if store.homework.isEmpty && store.isLoading {
                        ProgressView()
                    } else if filtered.isEmpty {
                        ContentUnavailableView(
                            showCompleted ? "No Completed Homework" : "All Caught Up!",
                            systemImage: showCompleted ? "tray" : "checkmark.circle.fill",
                            description: Text(showCompleted ? "Completed homework will appear here." : "No upcoming homework.")
                        )
                    } else {
                        List {
                            ForEach(grouped, id: \.0) { date, items in
                                hwSection(date: date, items: items)
                            }
                        }
                        .listStyle(.insetGrouped)
                        .scrollContentBackground(.hidden)
                    }
                }
            }
            .navigationTitle("Homework")
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Picker("", selection: $showCompleted) {
                        Text("Upcoming").tag(false)
                        Text("Done").tag(true)
                    }
                    .pickerStyle(.segmented)
                    .frame(width: 160)
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button { showAddSheet = true } label: {
                        Image(systemName: "plus.circle.fill").font(.title3)
                    }
                }
            }
            .sheet(isPresented: $showAddSheet) {
                HomeworkEditSheet(hw: nil)
            }
            .sheet(item: $editingHW) { hw in
                HomeworkEditSheet(hw: hw)
            }
            .refreshable { await store.loadAll() }
        }
    }

    @ViewBuilder
    private func hwSection(date: String, items: [Homework]) -> some View {
        let headerColor: Color = date.isOverdue && !showCompleted ? .red : .primary
        Section(header: Text(date.dueDateLabel).font(.subheadline.bold()).foregroundStyle(headerColor)) {
            ForEach(items) { hw in
                HWListRow(hw: hw, store: store)
                    .onTapGesture { editingHW = hw }
                    .swipeActions(edge: .leading) {
                        Button { Task { await store.toggleHomework(hw) } } label: {
                            Label(hw.completed ? "Undo" : "Done",
                                  systemImage: hw.completed ? "arrow.uturn.left" : "checkmark")
                        }
                        .tint(Color.canopyGreen)
                    }
                    .swipeActions(edge: .trailing) {
                        Button(role: .destructive) { Task { await store.deleteHomework(hw) } } label: {
                            Label("Delete", systemImage: "trash")
                        }
                    }
            }
        }
    }
}

// MARK: - Row
struct HWListRow: View {
    let hw: Homework; let store: CanopyStore
    var body: some View {
        HStack(spacing: 12) {
            PriorityDot(priority: hw.priority)
            VStack(alignment: .leading, spacing: 3) {
                Text(hw.title)
                    .font(.body)
                    .strikethrough(hw.completed)
                    .foregroundStyle(hw.completed ? .secondary : .primary)
                HStack(spacing: 6) {
                    if let cls = store.schoolClass(hw.classId) {
                        ClassColorDot(hex: cls.color, size: 8)
                        Text(cls.name).font(.caption).foregroundStyle(.secondary)
                    }
                    if let cat = hw.category, !cat.isEmpty {
                        Text("· \(cat)").font(.caption).foregroundStyle(.secondary)
                    }
                }
            }
            Spacer()
            Image(systemName: hw.completed ? "checkmark.circle.fill" : "circle")
                .foregroundStyle(hw.completed ? Color.canopyGreen : Color(uiColor: .systemFill))
                .font(.title3)
                .onTapGesture { Task { await store.toggleHomework(hw) } }
        }
        .padding(.vertical, 4)
    }
}

// MARK: - Add / Edit Sheet
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
            Form {
                Section("Details") {
                    TextField("Title", text: $title)
                    TextField("Description (optional)", text: $description, axis: .vertical)
                        .lineLimit(3...6)
                }
                Section("Due Date") {
                    DatePicker("", selection: $dueDate, displayedComponents: .date)
                        .datePickerStyle(.graphical)
                        .tint(.canopyGreen)
                }
                Section("Priority") {
                    Picker("Priority", selection: $priority) {
                        Text("High").tag("high")
                        Text("Medium").tag("medium")
                        Text("Low").tag("low")
                    }
                    .pickerStyle(.segmented)
                }
                Section("Class") {
                    Picker("Class", selection: $classId) {
                        Text("None").tag("")
                        ForEach(store.classes) { cls in
                            HStack {
                                ClassColorDot(hex: cls.color)
                                Text(cls.name)
                            }.tag(cls.id)
                        }
                    }
                }
                if let e = error {
                    Section { Text(e).foregroundStyle(.red).font(.caption) }
                }
            }
            .scrollContentBackground(.hidden)
            .background(CanopyBackground())
            .navigationTitle(isNew ? "New Homework" : "Edit Homework")
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
        guard let hw else { return }
        title = hw.title; description = hw.description
        dueDate = hw.dueDate.asDate ?? .now
        priority = hw.priority; classId = hw.classId
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
