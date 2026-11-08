import SwiftUI

// MARK: - Tab wrapper (used by MainTabView for the `.exams` tab)

/// Self-contained Exams tab: wraps `ManageExamsView` in its own NavigationStack.
/// Settings ▸ Manage keeps pushing `ManageExamsView()` directly.
struct ExamsTabView: View {
    var body: some View {
        NavigationStack { ManageExamsView() }
    }
}

// MARK: - Main View (web src/app/exams/page.tsx)

private enum ExamTab: Hashable { case upcoming, past }

struct ManageExamsView: View {
    @Environment(CanopyStore.self) private var store
    @State private var tab: ExamTab = .upcoming
    @State private var editingExam: Exam?
    @State private var showAdd = false
    @State private var deleteTarget: Exam?
    @State private var showDeleteConfirm = false
    @State private var toast: ToastMessage?

    private var today: String { DateFormatter.iso.string(from: .now) }

    /// date ≥ today, ascending.
    private var upcoming: [Exam] {
        store.exams.filter { $0.date >= today }.sorted { $0.date < $1.date }
    }

    /// date < today, ascending (web keeps one ascending sort for both tabs).
    private var past: [Exam] {
        store.exams.filter { $0.date < today }.sorted { $0.date < $1.date }
    }

    var body: some View {
        ZStack {
            CanopyBackground()
            if store.exams.isEmpty {
                emptyState
            } else {
                content
            }
        }
        .navigationTitle("Exams")
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button { showAdd = true } label: {
                    Image(systemName: "plus.circle.fill").font(.title3)
                }
                .accessibilityLabel("Add Exam")
            }
        }
        .sheet(isPresented: $showAdd) { ExamEditorSheet(exam: nil).presentationDetents([.large]) }
        .sheet(item: $editingExam) { exam in ExamEditorSheet(exam: exam).presentationDetents([.large]) }
        .alert("Delete Exam?", isPresented: $showDeleteConfirm, presenting: deleteTarget) { exam in
            Button("Delete", role: .destructive) {
                Task { await store.deleteExam(exam) }
            }
            Button("Cancel", role: .cancel) { }
        } message: { exam in
            Text("Remove \"\(exam.title)\" permanently?")
        }
        .refreshable { await store.loadAll() }
        .toast($toast)
        .onChange(of: store.lastMutationError) { _, msg in
            guard let msg else { return }
            toast = ToastMessage(text: msg, kind: .error)
            store.lastMutationError = nil
        }
    }

    // MARK: Content

    private var subtitle: some View {
        Text("Upcoming tests and exams — set a weight to see how the score could affect your grade.")
            .font(.subheadline).foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var content: some View {
        List {
            Section {
                VStack(alignment: .leading, spacing: 12) {
                    subtitle
                    Picker("Tab", selection: $tab) {
                        Text("Upcoming (\(upcoming.count))").tag(ExamTab.upcoming)
                        Text("Past (\(past.count))").tag(ExamTab.past)
                    }
                    .pickerStyle(.segmented)
                }
                .listRowBackground(Color.clear)
                .listRowSeparator(.hidden)
                .listRowInsets(EdgeInsets(top: 4, leading: 16, bottom: 8, trailing: 16))
            }

            let shown = tab == .upcoming ? upcoming : past
            if shown.isEmpty {
                Section {
                    Text(tab == .upcoming ? "No upcoming exams." : "No past exams yet.")
                        .font(.subheadline).foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 32)
                        .listRowBackground(Color.clear)
                        .listRowSeparator(.hidden)
                }
            } else {
                Section {
                    ForEach(shown) { exam in
                        examCard(exam, isPast: tab == .past)
                    }
                }
            }
        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
    }

    @ViewBuilder
    private func examCard(_ exam: Exam, isPast: Bool) -> some View {
        ExamRow(exam: exam, store: store, isPast: isPast)
            .padding(14)
            .glassEffect(.regular, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous)
                .strokeBorder(Color.secondary.opacity(0.12), lineWidth: 0.5))
            .contentShape(Rectangle())
            .onTapGesture { editingExam = exam }
            .accessibilityAddTraits(.isButton)
            .listRowBackground(Color.clear)
            .listRowSeparator(.hidden)
            .listRowInsets(EdgeInsets(top: 6, leading: 16, bottom: 6, trailing: 16))
            .swipeActions(edge: .trailing) {
                Button(role: .destructive) {
                    deleteTarget = exam
                    showDeleteConfirm = true
                } label: { Label("Delete", systemImage: "trash") }
                Button { editingExam = exam } label: {
                    Label("Edit", systemImage: "pencil")
                }.tint(.blue)
            }
            .contextMenu {
                Button { editingExam = exam } label: { Label("Edit", systemImage: "pencil") }
                Button(role: .destructive) {
                    deleteTarget = exam
                    showDeleteConfirm = true
                } label: { Label("Delete", systemImage: "trash") }
            }
    }

    // MARK: Empty state (web copy)

    private var emptyState: some View {
        VStack(spacing: 10) {
            subtitle
                .padding(.horizontal, 16).padding(.top, 8)
            Spacer()
            Image(systemName: "pencil.and.list.clipboard")
                .font(.system(size: 40)).foregroundStyle(.secondary)
            Text("No exams scheduled")
                .font(.headline).foregroundStyle(.secondary)
            Text("Add upcoming exams to track dates and see how they affect your grade.")
                .font(.subheadline).foregroundStyle(.tertiary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)
            Button { showAdd = true } label: {
                Label("Add Exam", systemImage: "plus")
                    .padding(.horizontal, 6).padding(.vertical, 4)
            }
            .buttonStyle(.glass)
            .buttonBorderShape(.capsule)
            .padding(.top, 6)
            Spacer()
            Spacer()
        }
        .frame(maxWidth: .infinity)
    }
}

// MARK: - Exam card content (web renderExamCard)
//
// Also embedded by DashboardView — this is the card's CONTENT; the Exams
// screen wraps it in a glass card background.

struct ExamRow: View {
    let exam: Exam
    let store: CanopyStore
    let isPast: Bool

    private var cls: SchoolClass? { store.schoolClass(exam.classId) }

    private var daysUntil: Int {
        guard let d = exam.date.asDate else { return 0 }
        let cal = Calendar.current
        return cal.dateComponents([.day], from: cal.startOfDay(for: .now), to: cal.startOfDay(for: d)).day ?? 0
    }

    // The exam happens during the class's normal period: time/room derive
    // from the linked class, falling back to legacy fields on the exam row.
    private var startTime: String { cls?.startTime.nonEmpty ?? exam.startTime }
    private var endTime: String { cls?.endTime.nonEmpty ?? exam.endTime }
    private var room: String { cls?.room.nonEmpty ?? exam.location }

    private var dateLine: String {
        var s = GradesUtil.fullDueLabel(exam.date)
        if !startTime.isEmpty, !endTime.isEmpty {
            s += " • \(ScheduleEngine.formatTime12(startTime)) – \(ScheduleEngine.formatTime12(endTime))"
        }
        if cls != nil { s += " (in class)" }
        return s
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            HStack(spacing: 8) {
                Text(exam.title)
                    .font(.headline)
                    .foregroundStyle(isPast ? .secondary : .primary)
                if !isPast && daysUntil <= 3 {
                    TintedChip(text: daysUntil == 0 ? "Today!" : "\(daysUntil)d", color: .red)
                }
                Spacer(minLength: 0)
            }

            ClassChip(name: cls?.name ?? "Unknown", hex: cls?.color ?? "#9E9E9E")

            HStack(alignment: .top, spacing: 5) {
                Image(systemName: "clock").font(.caption)
                Text(dateLine)
            }
            .font(.subheadline).foregroundStyle(.secondary)

            if !room.isEmpty {
                HStack(spacing: 5) {
                    Image(systemName: "mappin.and.ellipse").font(.caption)
                    Text("Room \(room)")
                }
                .font(.subheadline).foregroundStyle(.secondary)
            }

            if !exam.notes.isEmpty {
                Text(exam.notes)
                    .font(.subheadline).italic()
                    .foregroundStyle(.secondary)
            }

            // Stakes framing — only when a weight is set and the class has a live grade.
            if let wp = exam.weightPercent, wp > 0, let gp = cls?.gradePercent {
                if let stakes = ExamStakes.text(currentGrade: gp, weight: wp) {
                    Text(stakes)
                        .font(.caption.weight(.medium))
                        .foregroundStyle(.orange)
                } else {
                    Text(ExamStakes.fallbackText(weight: wp))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .opacity(isPast ? 0.6 : 1)
    }
}

// MARK: - Exam Editor Sheet (web Add/Edit Exam dialog)

struct ExamEditorSheet: View {
    @Environment(CanopyStore.self) private var store
    @Environment(\.dismiss) private var dismiss

    let exam: Exam?
    private var isNew: Bool { exam == nil }

    @State private var title = ""
    @State private var classId = ""
    @State private var date = Date.now.addingTimeInterval(7 * 86400)
    @State private var weightPercentText = ""
    @State private var notes = ""
    // Advanced (legacy per-exam fields; normally derived from the class)
    @State private var showAdvanced = false
    @State private var location = ""
    @State private var hasTime = false
    @State private var startTime = "08:00"
    @State private var endTime = "08:50"
    @State private var isSaving = false
    @State private var error: String?

    private var sortedClasses: [SchoolClass] { store.classes.plannerOrdered }

    private var weightValid: Bool {
        let t = weightPercentText.trimmingCharacters(in: .whitespaces)
        if t.isEmpty { return true }
        guard let v = Double(t) else { return false }
        return v >= 0 && v <= 100
    }

    private var canSave: Bool {
        !title.trimmingCharacters(in: .whitespaces).isEmpty && !classId.isEmpty && weightValid && !isSaving
    }

    var body: some View {
        NavigationStack {
            ZStack { CanopyBackground()
                ScrollView {
                    VStack(spacing: 16) {
                        FormEditCard {
                            TextField("Title", text: $title)
                                .font(.body)
                                .padding(.horizontal, 16).padding(.vertical, 13)
                        }

                        // Class — required
                        FormEditCard {
                            VStack(alignment: .leading, spacing: 0) {
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
                                if sortedClasses.isEmpty {
                                    Text("Exams are linked to a class — add one on the Classes page first.")
                                        .font(.caption).foregroundStyle(.secondary)
                                        .padding(.horizontal, 16).padding(.bottom, 12)
                                }
                            }
                        }

                        // Date (default today + 7)
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

                        // Weight % of grade (optional)
                        FormEditCard {
                            VStack(alignment: .leading, spacing: 4) {
                                HStack {
                                    Label("Weight % of grade (optional)", systemImage: "percent").font(.body)
                                    Spacer()
                                    TextField("e.g. 20", text: $weightPercentText)
                                        .multilineTextAlignment(.trailing)
                                        .foregroundStyle(weightValid ? Color.secondary : Color.red)
                                        .frame(width: 70)
                                        #if !os(macOS)
                                        .keyboardType(.decimalPad)
                                        #endif
                                    Text("%").font(.subheadline).foregroundStyle(.secondary)
                                }
                                Text(weightValid ? "Enables stakes framing on the card" : "Enter a value from 0 to 100")
                                    .font(.caption).foregroundStyle(weightValid ? Color.secondary : Color.red)
                            }
                            .padding(.horizontal, 16).padding(.vertical, 13)
                        }

                        // Notes
                        FormEditCard {
                            TextField("Notes", text: $notes, axis: .vertical)
                                .font(.body)
                                .lineLimit(2...5)
                                .padding(.horizontal, 16).padding(.vertical, 13)
                        }

                        // Advanced — legacy per-exam location/time overrides
                        FormEditCard {
                            VStack(alignment: .leading, spacing: 0) {
                                Button {
                                    withAnimation(.spring(response: 0.3)) { showAdvanced.toggle() }
                                } label: {
                                    HStack {
                                        Label("Advanced", systemImage: "slider.horizontal.3").font(.body)
                                        Spacer()
                                        Image(systemName: showAdvanced ? "chevron.up" : "chevron.down")
                                            .font(.caption).foregroundStyle(.tertiary)
                                    }
                                    .padding(.horizontal, 16).padding(.vertical, 13)
                                    .contentShape(Rectangle())
                                }
                                .buttonStyle(.plain)

                                if showAdvanced {
                                    Divider().padding(.leading, 16)
                                    Text("Time and room normally come from the linked class. Set these only if the exam happens somewhere or sometime else.")
                                        .font(.caption).foregroundStyle(.secondary)
                                        .padding(.horizontal, 16).padding(.vertical, 10)
                                    Divider().padding(.leading, 16)
                                    TextField("Location (optional)", text: $location)
                                        .font(.body)
                                        .padding(.horizontal, 16).padding(.vertical, 13)
                                    Divider().padding(.leading, 16)
                                    Toggle(isOn: $hasTime.animation(.spring(response: 0.3, dampingFraction: 0.8))) {
                                        Label("Set Start/End Time", systemImage: "clock").font(.body)
                                    }
                                    .padding(.horizontal, 16).padding(.vertical, 13)
                                    if hasTime {
                                        Divider().padding(.leading, 16)
                                        HStack {
                                            Label("Start", systemImage: "clock").font(.body)
                                            Spacer()
                                            MinuteTimeField(time: $startTime)
                                        }
                                        .padding(.horizontal, 16).padding(.vertical, 8)
                                        Divider().padding(.leading, 16)
                                        HStack {
                                            Label("End", systemImage: "clock.badge.checkmark").font(.body)
                                            Spacer()
                                            MinuteTimeField(time: $endTime)
                                        }
                                        .padding(.horizontal, 16).padding(.vertical, 8)
                                    }
                                }
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
            .navigationTitle(isNew ? "Add Exam" : "Edit Exam")
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
        guard let exam else {
            classId = sortedClasses.first?.id ?? ""
            return
        }
        title = exam.title
        classId = exam.classId
        date = exam.date.asDate ?? Date.now.addingTimeInterval(7 * 86400)
        location = exam.location
        notes = exam.notes
        if !exam.startTime.isEmpty {
            hasTime = true
            startTime = exam.startTime
            endTime = exam.endTime.isEmpty ? exam.startTime : exam.endTime
        }
        showAdvanced = !exam.location.isEmpty || !exam.startTime.isEmpty
        if let wp = exam.weightPercent, wp > 0 {
            weightPercentText = wp == wp.rounded() ? String(Int(wp)) : String(wp)
        }
        if classId.isEmpty || store.schoolClass(classId) == nil {
            classId = sortedClasses.first?.id ?? classId
        }
    }

    private func save() async {
        isSaving = true; defer { isSaving = false }
        var item = exam ?? Exam(id: UUID().uuidString, classId: "", title: "", date: "", startTime: "",
                                endTime: "", location: "", notes: "", weightPercent: nil)
        item.classId = classId
        item.title = title.trimmingCharacters(in: .whitespaces)
        item.date = DateFormatter.iso.string(from: date)
        item.startTime = hasTime ? startTime : ""
        item.endTime = hasTime ? endTime : ""
        item.location = location
        item.notes = notes
        let w = weightPercentText.trimmingCharacters(in: .whitespaces)
        item.weightPercent = w.isEmpty ? nil : Double(w)
        do {
            try await store.saveExam(item, isNew: isNew)
            dismiss()
        } catch { self.error = "Couldn't save: \(error.localizedDescription)" }
    }
}
