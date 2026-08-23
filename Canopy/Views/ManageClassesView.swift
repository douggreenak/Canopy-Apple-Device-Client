import SwiftUI

private let classColors = [
    "#4285F4", "#EA4335", "#FBBC04", "#34A853",
    "#FF6D01", "#46BDC6", "#7BAAF7", "#F07B72",
    "#A142F4", "#24C1E0", "#F538A0", "#185ABC"
]

private let dayNames = [0: "Sun", 1: "Mon", 2: "Tue", 3: "Wed", 4: "Thu", 5: "Fri", 6: "Sat"]

// MARK: - Main View

struct ManageClassesView: View {
    @Environment(CanopyStore.self) private var store
    @State private var editingClass: SchoolClass?
    @State private var showAdd = false
    @State private var deleteTarget: SchoolClass?
    @State private var showDeleteConfirm = false
    @State private var errorMessage: String?

    var body: some View {
        ZStack {
            CanopyBackground()
            if store.classes.isEmpty {
                emptyState
            } else {
                classList
            }
        }
        .navigationTitle("Classes")
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button { showAdd = true } label: {
                    Image(systemName: "plus.circle.fill").font(.title3)
                }
            }
        }
        .sheet(isPresented: $showAdd) {
            ClassEditorSheet(cls: nil).presentationDetents([.large])
        }
        .sheet(item: $editingClass) { cls in
            ClassEditorSheet(cls: cls).presentationDetents([.large])
        }
        .alert("Delete Class?", isPresented: $showDeleteConfirm, presenting: deleteTarget) { cls in
            Button("Delete", role: .destructive) {
                Task { await store.deleteClass(cls) }
            }
            Button("Cancel", role: .cancel) { }
        } message: { cls in
            Text("Remove \"\(cls.name)\" permanently? This cannot be undone.")
        }
        .refreshable { await store.loadAll() }
    }

    private var emptyState: some View {
        ContentUnavailableView(
            "No Classes",
            systemImage: "books.vertical",
            description: Text("Add your first class to get started.")
        )
    }

    private var classList: some View {
        ScrollView {
            LazyVStack(spacing: 12) {
                ForEach(store.classes.sorted { $0.period < $1.period }) { cls in
                    Button { editingClass = cls } label: {
                        ClassCard(cls: cls)
                    }
                    .buttonStyle(.plain)
                    .contextMenu {
                        Button { editingClass = cls } label: {
                            Label("Edit", systemImage: "pencil")
                        }
                        Button(role: .destructive) {
                            deleteTarget = cls
                            showDeleteConfirm = true
                        } label: {
                            Label("Delete", systemImage: "trash")
                        }
                    }
                }
            }
            .padding(16)
            .padding(.bottom, 32)
        }
    }
}

// MARK: - Class Card

struct ClassCard: View {
    let cls: SchoolClass

    var body: some View {
        VStack(spacing: 0) {
            // Color strip
            Color(hex: cls.color)
                .frame(height: 5)
                .clipShape(UnevenRoundedRectangle(
                    topLeadingRadius: 14, bottomLeadingRadius: 0,
                    bottomTrailingRadius: 0, topTrailingRadius: 14
                ))

            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text(cls.name)
                        .font(.headline)
                        .foregroundStyle(Color(hex: cls.color))
                    Spacer()
                    Text("Period \(cls.period)")
                        .font(.caption.bold())
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3)
                        .background(Color(hex: cls.color).opacity(0.12), in: Capsule())
                        .foregroundStyle(Color(hex: cls.color))
                }

                VStack(alignment: .leading, spacing: 4) {
                    if !cls.teacher.isEmpty {
                        Label(cls.teacher, systemImage: "person")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                    if !cls.room.isEmpty {
                        Label("Room \(cls.room)", systemImage: "door.right.hand.open")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                    Label("\(cls.startTime) – \(cls.endTime)", systemImage: "clock")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }

                HStack(spacing: 4) {
                    ForEach(cls.days.sorted(), id: \.self) { d in
                        Text(dayNames[d] ?? "?")
                            .font(.caption2.bold())
                            .padding(.horizontal, 7)
                            .padding(.vertical, 3)
                            .background(Color(hex: cls.color).opacity(0.10), in: Capsule())
                            .foregroundStyle(Color(hex: cls.color))
                            .overlay(Capsule().strokeBorder(Color(hex: cls.color).opacity(0.3), lineWidth: 0.5))
                    }

                    Spacer()

                    if !cls.semester.isEmpty {
                        Text(cls.semester)
                            .font(.caption2)
                            .foregroundStyle(.tertiary)
                    }
                }
            }
            .padding(14)
        }
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .shadow(color: .black.opacity(0.06), radius: 6, y: 2)
    }
}

// MARK: - Class Editor Sheet

struct ClassEditorSheet: View {
    @Environment(CanopyStore.self) private var store
    @Environment(\.dismiss) private var dismiss

    let cls: SchoolClass?
    private var isNew: Bool { cls == nil }

    @State private var name = ""
    @State private var teacher = ""
    @State private var room = ""
    @State private var period = 1
    @State private var startTime = "08:00"
    @State private var endTime = "08:50"
    @State private var semester = "Spring 2026"
    @State private var selectedDays: Set<Int> = [1, 2, 3, 4, 5]
    @State private var selectedColor = "#4285F4"
    @State private var weightRows: [(category: String, weight: String)] = []
    @State private var showWeights = false
    @State private var resetWeightSourceRequested = false
    @State private var dayTimeOverrides: [String: DayTime] = [:]
    @State private var isSaving = false
    @State private var error: String?

    private var weightsTotal: Double {
        weightRows.compactMap { Double($0.weight) }.reduce(0, +)
    }

    var body: some View {
        NavigationStack {
            ZStack { CanopyBackground()
                ScrollView {
                    VStack(spacing: 16) {
                        // PowerSchool schedule-matrix suggestion (only while editing
                        // an existing class the last sync surfaced a guess for).
                        if let cls, let suggestion = store.psMatrixSuggestions[cls.id] {
                            matrixSuggestionBanner(suggestion, classId: cls.id)
                        }

                        // Name, Teacher, Room
                        FormEditCard {
                            VStack(spacing: 0) {
                                TextField("Class Name", text: $name)
                                    .font(.body)
                                    .padding(.horizontal, 16).padding(.vertical, 13)
                                Divider().padding(.leading, 16)
                                TextField("Teacher", text: $teacher)
                                    .font(.body)
                                    .padding(.horizontal, 16).padding(.vertical, 13)
                                Divider().padding(.leading, 16)
                                TextField("Room", text: $room)
                                    .font(.body)
                                    .padding(.horizontal, 16).padding(.vertical, 13)
                            }
                        }

                        // Period and Time
                        FormEditCard {
                            VStack(spacing: 0) {
                                HStack {
                                    Label("Period", systemImage: "number").font(.body)
                                    Spacer()
                                    Stepper("\(period)", value: $period, in: 1...10)
                                        .fixedSize()
                                }
                                .padding(.horizontal, 16).padding(.vertical, 13)
                                Divider().padding(.leading, 16)
                                HStack {
                                    Label("Start", systemImage: "clock").font(.body)
                                    Spacer()
                                    TimeInputField(time: $startTime)
                                }
                                .padding(.horizontal, 16).padding(.vertical, 10)
                                Divider().padding(.leading, 16)
                                HStack {
                                    Label("End", systemImage: "clock.badge.checkmark").font(.body)
                                    Spacer()
                                    TimeInputField(time: $endTime)
                                }
                                .padding(.horizontal, 16).padding(.vertical, 10)
                            }
                        }

                        // Semester
                        FormEditCard {
                            HStack {
                                Label("Semester", systemImage: "calendar").font(.body)
                                Spacer()
                                TextField("e.g. Spring 2026", text: $semester)
                                    .multilineTextAlignment(.trailing)
                                    .foregroundStyle(.secondary)
                            }
                            .padding(.horizontal, 16).padding(.vertical, 13)
                        }

                        // Days
                        FormEditCard {
                            VStack(alignment: .leading, spacing: 10) {
                                Label("Days", systemImage: "calendar.day.timeline.left")
                                    .font(.body)
                                    .padding(.horizontal, 16).padding(.top, 13)
                                HStack(spacing: 6) {
                                    ForEach([1,2,3,4,5,6,0], id: \.self) { day in
                                        let label = dayNames[day] ?? "?"
                                        let selected = selectedDays.contains(day)
                                        Button {
                                            withAnimation(.spring(response: 0.2)) {
                                                if selected { selectedDays.remove(day) }
                                                else { selectedDays.insert(day) }
                                            }
                                        } label: {
                                            Text(label)
                                                .font(.caption.bold())
                                                .frame(maxWidth: .infinity)
                                                .padding(.vertical, 8)
                                                .background(
                                                    selected ? Color.accentColor.opacity(0.15) : Color.clear,
                                                    in: RoundedRectangle(cornerRadius: 8)
                                                )
                                                .overlay(RoundedRectangle(cornerRadius: 8)
                                                    .strokeBorder(selected ? Color.accentColor.opacity(0.6) : Color.secondary.opacity(0.25), lineWidth: 1))
                                                .foregroundStyle(selected ? Color.accentColor : .secondary)
                                        }
                                        .buttonStyle(.plain)
                                    }
                                }
                                .padding(.horizontal, 12).padding(.bottom, 12)
                            }
                        }

                        // Per-Day Time Overrides (optional)
                        if !selectedDays.isEmpty {
                            FormEditCard {
                                VStack(alignment: .leading, spacing: 0) {
                                    Label("Per-Day Time Overrides", systemImage: "clock.arrow.2.circlepath")
                                        .font(.body)
                                        .padding(.horizontal, 16).padding(.top, 13).padding(.bottom, 4)
                                    Text("Override the start/end time for specific days — e.g. a longer Tuesday block.")
                                        .font(.caption).foregroundStyle(.secondary)
                                        .padding(.horizontal, 16).padding(.bottom, 8)
                                    Divider().padding(.leading, 16)
                                    let sortedDays = selectedDays.sorted()
                                    ForEach(sortedDays, id: \.self) { day in
                                        dayOverrideRow(day)
                                        if day != sortedDays.last { Divider().padding(.leading, 16) }
                                    }
                                }
                            }
                        }

                        // Category Weights
                        FormEditCard {
                            VStack(alignment: .leading, spacing: 0) {
                                Button {
                                    withAnimation(.spring(response: 0.3)) { showWeights.toggle() }
                                } label: {
                                    HStack {
                                        Label("Grade Weights", systemImage: "percent").font(.body)
                                        Spacer()
                                        Text(showWeights ? "Hide" : (weightRows.isEmpty ? "Set Up" : "Edit"))
                                            .font(.subheadline)
                                            .foregroundStyle(.secondary)
                                        Image(systemName: showWeights ? "chevron.up" : "chevron.down")
                                            .font(.caption)
                                            .foregroundStyle(.tertiary)
                                    }
                                    .padding(.horizontal, 16).padding(.vertical, 13)
                                }
                                .buttonStyle(.plain)

                                if showWeights {
                                    Divider().padding(.leading, 16)
                                    ForEach(weightRows.indices, id: \.self) { i in
                                        HStack(spacing: 8) {
                                            TextField("Category", text: Binding(
                                                get: { weightRows[i].category },
                                                set: { weightRows[i].category = $0 }
                                            ))
                                            .font(.body)
                                            Spacer()
                                            TextField("0", text: Binding(
                                                get: { weightRows[i].weight },
                                                set: { weightRows[i].weight = $0 }
                                            ))
                                            #if !os(macOS)
                                            .keyboardType(.decimalPad)
                                            #endif
                                            .multilineTextAlignment(.trailing)
                                            .foregroundStyle(.secondary)
                                            .frame(width: 60)
                                            Text("%").foregroundStyle(.secondary)
                                            Button {
                                                weightRows.remove(at: i)
                                            } label: {
                                                Image(systemName: "minus.circle.fill")
                                                    .foregroundStyle(.red)
                                            }
                                            .buttonStyle(.plain)
                                        }
                                        .padding(.horizontal, 16).padding(.vertical, 10)
                                        if i < weightRows.count - 1 {
                                            Divider().padding(.leading, 16)
                                        }
                                    }

                                    HStack {
                                        Button {
                                            weightRows.append((category: "", weight: ""))
                                        } label: {
                                            Label("Add Category", systemImage: "plus.circle")
                                                .font(.subheadline)
                                        }
                                        Spacer()
                                        let total = weightsTotal
                                        Text(String(format: "Total: %.0f%%", total))
                                            .font(.caption)
                                            .foregroundStyle(abs(total - 100) < 0.5 ? Color.green : Color.orange)
                                    }
                                    .padding(.horizontal, 16).padding(.vertical, 10)

                                    if cls?.weightSource == "manual" {
                                        Divider().padding(.leading, 16)
                                        Button(role: .destructive) {
                                            weightRows = []
                                            resetWeightSourceRequested = true
                                        } label: {
                                            Label("Reset to Auto-Detected", systemImage: "arrow.counterclockwise")
                                                .font(.caption)
                                        }
                                        .padding(.horizontal, 16).padding(.vertical, 10)
                                    }
                                }
                            }
                        }

                        // Color
                        FormEditCard {
                            VStack(alignment: .leading, spacing: 10) {
                                Label("Color", systemImage: "paintpalette")
                                    .font(.body)
                                    .padding(.horizontal, 16).padding(.top, 13)
                                LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: 6), spacing: 10) {
                                    ForEach(classColors, id: \.self) { hex in
                                        Button {
                                            withAnimation(.spring(response: 0.2)) { selectedColor = hex }
                                        } label: {
                                            Circle()
                                                .fill(Color(hex: hex))
                                                .frame(width: 32, height: 32)
                                                .overlay(
                                                    Circle().strokeBorder(
                                                        selectedColor == hex ? Color.primary : Color.clear,
                                                        lineWidth: 2.5
                                                    )
                                                    .padding(-3)
                                                )
                                                .overlay(
                                                    Image(systemName: "checkmark")
                                                        .font(.caption.weight(.bold))
                                                        .foregroundStyle(.white)
                                                        .opacity(selectedColor == hex ? 1 : 0)
                                                )
                                        }
                                        .buttonStyle(.plain)
                                        .scaleEffect(selectedColor == hex ? 1.12 : 1)
                                        .animation(.spring(response: 0.2), value: selectedColor)
                                    }
                                }
                                .padding(.horizontal, 16).padding(.bottom, 14)
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
                    .padding(16).padding(.bottom, 32)
                }
            }
            .navigationTitle(isNew ? "New Class" : "Edit Class")
            .navigationBarTitleInline()
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button(isSaving ? "Saving…" : "Save") { Task { await save() } }
                        .disabled(name.trimmingCharacters(in: .whitespaces).isEmpty || isSaving)
                        .fontWeight(.semibold)
                }
            }
        }
        .onAppear { prefill() }
    }

    // MARK: - Per-day override row
    private func dayOverrideRow(_ day: Int) -> some View {
        let key = String(day)
        let hasOverride = Binding<Bool>(
            get: { dayTimeOverrides[key] != nil },
            set: { on in
                if on { dayTimeOverrides[key] = DayTime(startTime: startTime, endTime: endTime) }
                else { dayTimeOverrides[key] = nil }
            }
        )
        return VStack(spacing: 6) {
            Toggle(dayNames[day] ?? "?", isOn: hasOverride)
            if let dt = dayTimeOverrides[key] {
                HStack {
                    Spacer()
                    TimeInputField(time: Binding(
                        get: { dt.startTime },
                        set: { dayTimeOverrides[key]?.startTime = $0 }
                    ))
                    Text("–").foregroundStyle(.secondary)
                    TimeInputField(time: Binding(
                        get: { dt.endTime },
                        set: { dayTimeOverrides[key]?.endTime = $0 }
                    ))
                }
            }
        }
        .padding(.horizontal, 16).padding(.vertical, 8)
    }

    // MARK: - PowerSchool suggestion banner
    private func matrixSuggestionBanner(_ suggestion: MatrixSuggestion, classId: String) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: "wand.and.stars").foregroundStyle(.blue)
            VStack(alignment: .leading, spacing: 4) {
                Text("PowerSchool suggestion").font(.subheadline.bold())
                let dayLabels = suggestion.days.sorted().map { dayNames[$0] ?? "?" }.joined(separator: ", ")
                let timeLabel = suggestion.startTime.map { s in
                    " · \(s)" + (suggestion.endTime.map { "–\($0)" } ?? "")
                } ?? ""
                Text(dayLabels + timeLabel).font(.caption).foregroundStyle(.secondary)
                HStack(spacing: 14) {
                    Button("Apply suggestion") { applyMatrixSuggestion(suggestion) }
                        .font(.caption.bold())
                    Button("Dismiss") { store.psMatrixSuggestions.removeValue(forKey: classId) }
                        .font(.caption).foregroundStyle(.secondary)
                }
            }
            Spacer()
        }
        .padding(12)
        .background(Color.blue.opacity(0.08), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
    }

    /// Applies to local editor state only — not persisted until Save, matching
    /// web's "Applied PowerSchool suggestion (not yet saved)" behavior.
    private func applyMatrixSuggestion(_ suggestion: MatrixSuggestion) {
        withAnimation(.spring(response: 0.25)) {
            selectedDays = Set(suggestion.days)
            if let s = suggestion.startTime {
                let e = suggestion.endTime ?? s
                var newOverrides: [String: DayTime] = [:]
                for d in suggestion.days { newOverrides[String(d)] = DayTime(startTime: s, endTime: e) }
                dayTimeOverrides = newOverrides
            }
        }
    }

    private func prefill() {
        guard let cls else { return }
        name = cls.name
        teacher = cls.teacher
        room = cls.room
        period = cls.period
        startTime = cls.startTime
        endTime = cls.endTime
        semester = cls.semester
        selectedDays = Set(cls.days)
        selectedColor = cls.color
        dayTimeOverrides = cls.dayTimes ?? [:]
        if let cw = cls.categoryWeights, !cw.isEmpty {
            weightRows = cw.sorted { $0.key < $1.key }.map { k, v in
                // Preserve fractional weights (e.g. 33.33) — don't truncate to Int.
                let display = v.truncatingRemainder(dividingBy: 1) == 0 ? String(Int(v)) : String(format: "%.2f", v)
                return (category: k, weight: display)
            }
        }
    }

    private func save() async {
        isSaving = true; defer { isSaving = false }
        // Validate: any row with a weight value must have a category name.
        if weightRows.contains(where: { !$0.weight.isEmpty && $0.category.trimmingCharacters(in: .whitespaces).isEmpty }) {
            error = "Each weight row must have a category name."
            isSaving = false
            return
        }
        // Build category weights from rows (only non-empty, valid entries)
        var newWeights: [String: Double]? = nil
        var newWeightSource: String? = cls?.weightSource
        if resetWeightSourceRequested {
            // Clears manually-set weights back to letting PowerSchool-derived
            // weights take over on the next sync.
            newWeights = nil
            newWeightSource = nil
        } else {
            let validRows = weightRows.filter { !$0.category.trimmingCharacters(in: .whitespaces).isEmpty }
            if !validRows.isEmpty {
                newWeights = Dictionary(uniqueKeysWithValues: validRows.compactMap { row -> (String, Double)? in
                    guard let v = Double(row.weight), v > 0 else { return nil }
                    return (row.category.trimmingCharacters(in: .whitespaces), v)
                })
                // If user edited weights, mark as manual
                if newWeights != cls?.categoryWeights {
                    newWeightSource = "manual"
                }
            }
        }
        // Drop overrides for days no longer selected.
        let prunedDayTimes = dayTimeOverrides.filter { selectedDays.contains(Int($0.key) ?? -1) }
        let item = SchoolClass(
            id: cls?.id ?? UUID().uuidString,
            name: name.trimmingCharacters(in: .whitespaces),
            teacher: teacher,
            room: room,
            color: selectedColor,
            period: period,
            startTime: startTime,
            endTime: endTime,
            days: Array(selectedDays).sorted(),
            dayTimes: prunedDayTimes.isEmpty ? nil : prunedDayTimes,
            semester: semester,
            source: cls?.source,
            sourceId: cls?.sourceId,
            grade: cls?.grade,
            gradePercent: cls?.gradePercent,
            categoryWeights: newWeights,
            weightSource: newWeightSource
        )
        do {
            try await store.saveClass(item, isNew: isNew)
            store.psMatrixSuggestions.removeValue(forKey: item.id)
            dismiss()
        } catch { self.error = error.localizedDescription }
    }
}

// MARK: - Time Input Helper

struct TimeInputField: View {
    @Binding var time: String

    // Parse time string into hours/minutes
    private var components: (Int, Int) {
        let parts = time.split(separator: ":").compactMap { Int($0) }
        return (parts.first ?? 8, parts.last ?? 0)
    }

    var body: some View {
        let (hours, minutes) = components
        HStack(spacing: 2) {
            Picker("Hour", selection: Binding(
                get: { hours },
                set: { newH in time = String(format: "%02d:%02d", newH, minutes) }
            )) {
                ForEach(0...23, id: \.self) { h in
                    Text(String(format: "%02d", h)).tag(h)
                }
            }
            .wheelPickerStyle()
            #if !os(macOS)
            .frame(width: 55, height: 80)
            .clipped()
            #endif

            Text(":").font(.title3.bold()).foregroundStyle(.secondary)

            Picker("Minute", selection: Binding(
                get: { minutes },
                set: { newM in time = String(format: "%02d:%02d", hours, newM) }
            )) {
                ForEach([0, 5, 10, 15, 20, 25, 30, 35, 40, 45, 50, 55], id: \.self) { m in
                    Text(String(format: "%02d", m)).tag(m)
                }
            }
            .wheelPickerStyle()
            #if !os(macOS)
            .frame(width: 55, height: 80)
            .clipped()
            #endif
        }
    }
}
