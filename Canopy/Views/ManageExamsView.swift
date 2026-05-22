import SwiftUI

// MARK: - Main View

struct ManageExamsView: View {
    @Environment(CanopyStore.self) private var store
    @State private var editingExam: Exam?
    @State private var showAdd = false
    @State private var deleteTarget: Exam?
    @State private var showDeleteConfirm = false

    private var upcoming: [Exam] {
        let today = DateFormatter.iso.string(from: .now)
        return store.exams
            .filter { $0.date >= today }
            .sorted { $0.date < $1.date }
    }

    private var past: [Exam] {
        let today = DateFormatter.iso.string(from: .now)
        return store.exams
            .filter { $0.date < today }
            .sorted { $0.date > $1.date }
    }

    var body: some View {
        ZStack {
            CanopyBackground()
            if store.exams.isEmpty {
                ContentUnavailableView(
                    "No Exams",
                    systemImage: "pencil.and.list.clipboard",
                    description: Text("Tap + to schedule your first exam.")
                )
            } else {
                examList
            }
        }
        .navigationTitle("Exams")
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button { showAdd = true } label: {
                    Image(systemName: "plus.circle.fill").font(.title3)
                }
            }
        }
        .sheet(isPresented: $showAdd) { ExamEditorSheet(exam: nil) }
        .sheet(item: $editingExam) { exam in ExamEditorSheet(exam: exam) }
        .alert("Delete Exam?", isPresented: $showDeleteConfirm, presenting: deleteTarget) { exam in
            Button("Delete", role: .destructive) {
                Task { await store.deleteExam(exam) }
            }
            Button("Cancel", role: .cancel) { }
        } message: { exam in
            Text("Remove \"\(exam.title)\" permanently?")
        }
        .refreshable { await store.loadAll() }
    }

    private var examList: some View {
        List {
            if !upcoming.isEmpty {
                Section {
                    ForEach(upcoming) { exam in
                        ExamRow(exam: exam, store: store, isPast: false)
                            .contentShape(Rectangle())
                            .onTapGesture { editingExam = exam }
                            .swipeActions(edge: .trailing) {
                                Button(role: .destructive) {
                                    deleteTarget = exam
                                    showDeleteConfirm = true
                                } label: { Label("Delete", systemImage: "trash") }
                                Button { editingExam = exam } label: {
                                    Label("Edit", systemImage: "pencil")
                                }.tint(.blue)
                            }
                    }
                } header: {
                    Label("Upcoming", systemImage: "clock")
                        .foregroundStyle(Color.accentColor)
                        .font(.subheadline.bold())
                }
            }

            if !past.isEmpty {
                Section {
                    ForEach(past) { exam in
                        ExamRow(exam: exam, store: store, isPast: true)
                            .contentShape(Rectangle())
                            .onTapGesture { editingExam = exam }
                            .swipeActions(edge: .trailing) {
                                Button(role: .destructive) {
                                    deleteTarget = exam
                                    showDeleteConfirm = true
                                } label: { Label("Delete", systemImage: "trash") }
                                Button { editingExam = exam } label: {
                                    Label("Edit", systemImage: "pencil")
                                }.tint(.blue)
                            }
                    }
                } header: {
                    Text("Past")
                        .foregroundStyle(.secondary)
                        .font(.subheadline.bold())
                }
            }
        }
        .insetGroupedListStyle()
        .scrollContentBackground(.hidden)
    }
}

// MARK: - Exam Row

struct ExamRow: View {
    let exam: Exam
    let store: CanopyStore
    let isPast: Bool

    private var cls: SchoolClass? { store.schoolClass(exam.classId) }
    private var daysUntil: Int {
        guard let d = exam.date.asDate else { return 0 }
        return Calendar.current.dateComponents([.day], from: Calendar.current.startOfDay(for: .now), to: d).day ?? 0
    }

    var body: some View {
        HStack(spacing: 12) {
            // Class color stripe
            if let cls {
                RoundedRectangle(cornerRadius: 2)
                    .fill(Color(hex: cls.color))
                    .frame(width: 4, height: 44)
            }

            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text(exam.title)
                        .font(.body.weight(.medium))
                        .foregroundStyle(isPast ? .secondary : .primary)

                    if !isPast && daysUntil <= 3 {
                        Text(daysUntil == 0 ? "Today!" : "\(daysUntil)d")
                            .font(.caption2.bold())
                            .padding(.horizontal, 6).padding(.vertical, 2)
                            .background(Color.red.opacity(0.12), in: Capsule())
                            .foregroundStyle(.red)
                    }
                    Spacer()
                }

                if let cls {
                    Text(cls.name)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                HStack(spacing: 8) {
                    Label(exam.date.dueDateLabel, systemImage: "calendar")
                        .font(.caption)
                        .foregroundStyle(isPast ? .tertiary : .secondary)

                    if !exam.startTime.isEmpty {
                        Text(formatTime(exam.startTime))
                            .font(.caption)
                            .foregroundStyle(.tertiary)
                    }

                    if !exam.location.isEmpty {
                        Label(exam.location, systemImage: "location")
                            .font(.caption)
                            .foregroundStyle(.tertiary)
                    }
                }
            }
        }
        .padding(.vertical, 4)
        .opacity(isPast ? 0.6 : 1)
    }

    private func formatTime(_ t: String) -> String {
        let parts = t.split(separator: ":").compactMap { Int($0) }
        guard parts.count == 2 else { return t }
        let h = parts[0], m = parts[1]
        let period = h >= 12 ? "PM" : "AM"
        let h12 = h % 12 == 0 ? 12 : h % 12
        return String(format: "%d:%02d %@", h12, m, period)
    }
}

// MARK: - Exam Editor Sheet

struct ExamEditorSheet: View {
    @Environment(CanopyStore.self) private var store
    @Environment(\.dismiss) private var dismiss

    let exam: Exam?
    private var isNew: Bool { exam == nil }

    @State private var title = ""
    @State private var classId = ""
    @State private var date = Date.now.addingTimeInterval(7 * 86400)
    @State private var location = ""
    @State private var notes = ""
    @State private var isSaving = false
    @State private var error: String?

    var body: some View {
        NavigationStack {
            ZStack { CanopyBackground()
                ScrollView {
                    VStack(spacing: 16) {

                        FormEditCard {
                            VStack(spacing: 0) {
                                TextField("Exam Title", text: $title)
                                    .font(.body)
                                    .padding(.horizontal, 16).padding(.vertical, 13)
                                Divider().padding(.leading, 16)
                                TextField("Location (optional)", text: $location)
                                    .font(.body)
                                    .padding(.horizontal, 16).padding(.vertical, 13)
                                Divider().padding(.leading, 16)
                                TextField("Notes (optional)", text: $notes, axis: .vertical)
                                    .font(.body)
                                    .lineLimit(2...4)
                                    .padding(.horizontal, 16).padding(.vertical, 13)
                            }
                        }

                        // Date
                        FormEditCard {
                            VStack(spacing: 0) {
                                Label("Date", systemImage: "calendar")
                                    .font(.body)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                    .padding(.horizontal, 16).padding(.top, 13).padding(.bottom, 10)
                                Divider().padding(.leading, 16)
                                DatePicker("", selection: $date, displayedComponents: .date)
                                    .datePickerStyle(.graphical)
                                    .padding(.horizontal, 8).padding(.bottom, 4)
                            }
                        }

                        // Class
                        if !store.classes.isEmpty {
                            FormEditCard {
                                HStack {
                                    Label("Class", systemImage: "person.2").font(.body)
                                    Spacer()
                                    Picker("", selection: $classId) {
                                        Text("None").tag("")
                                        ForEach(store.classes.sorted { $0.period < $1.period }) { cls in
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
                                Image(systemName: "exclamationmark.triangle.fill").font(.caption)
                                Text(e).font(.caption)
                            }
                            .foregroundStyle(.red)
                            .padding(12)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background(.red.opacity(0.08), in: RoundedRectangle(cornerRadius: 10))
                        }
                    }
                    .padding(16).padding(.bottom, 32)
                }
            }
            .navigationTitle(isNew ? "New Exam" : "Edit Exam")
            .navigationBarTitleInline()
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button(isSaving ? "Saving…" : "Save") { Task { await save() } }
                        .disabled(title.trimmingCharacters(in: .whitespaces).isEmpty || isSaving)
                        .fontWeight(.semibold)
                }
            }
        }
        .onAppear { prefill() }
    }

    private func prefill() {
        guard let exam else {
            classId = store.classes.sorted { $0.period < $1.period }.first?.id ?? ""
            return
        }
        title = exam.title
        classId = exam.classId
        date = exam.date.asDate ?? Date.now.addingTimeInterval(7 * 86400)
        location = exam.location
        notes = exam.notes
    }

    private func save() async {
        isSaving = true; defer { isSaving = false }
        let item = Exam(
            id: exam?.id ?? UUID().uuidString,
            classId: classId,
            title: title.trimmingCharacters(in: .whitespaces),
            date: DateFormatter.iso.string(from: date),
            startTime: exam?.startTime ?? "",
            endTime: exam?.endTime ?? "",
            location: location,
            notes: notes
        )
        do {
            try await store.saveExam(item, isNew: isNew)
            dismiss()
        } catch { self.error = error.localizedDescription }
    }
}
