import SwiftUI

/// Web ClassDialog COLORS (12 swatches).
private let classColors = [
    "#4285F4", "#EA4335", "#FBBC04", "#34A853",
    "#FF6D01", "#46BDC6", "#7BAAF7", "#F07B72",
    "#A142F4", "#24C1E0", "#F538A0", "#185ABC"
]

private let dayNames = [0: "Sun", 1: "Mon", 2: "Tue", 3: "Wed", 4: "Thu", 5: "Fri", 6: "Sat"]

// MARK: - Tab wrapper (used by MainTabView for the `.classes` tab)

/// Self-contained Classes tab: wraps `ManageClassesView` in its own NavigationStack.
/// Settings ▸ Manage keeps pushing `ManageClassesView()` directly.
struct ClassesTabView: View {
    var body: some View {
        NavigationStack { ManageClassesView() }
    }
}

// MARK: - Main View (web src/app/classes/page.tsx)

struct ManageClassesView: View {
    @Environment(CanopyStore.self) private var store
    @State private var editingClass: SchoolClass?
    @State private var showAdd = false
    @State private var deleteTarget: SchoolClass?
    @State private var showDeleteConfirm = false
    @State private var rosterTarget: RosterTarget?
    @State private var schoolFilter: String?
    @State private var toast: ToastMessage?
    #if os(iOS)
    @State private var editMode: EditMode = .inactive
    #endif

    private struct RosterTarget: Identifiable { let id: String }

    /// Distinct school names (sorted). The whole filter row stays hidden for
    /// a single-school user (no class carries a schoolName).
    private var schoolNames: [String] {
        Array(Set(store.classes.compactMap { $0.schoolName?.nonEmpty })).sorted()
    }

    private var visibleClasses: [SchoolClass] {
        let ordered = store.orderedClasses
        guard let f = schoolFilter else { return ordered }
        return ordered.filter { $0.schoolName == f }
    }

    var body: some View {
        ZStack {
            CanopyBackground()
            if store.classes.isEmpty {
                emptyState
            } else {
                classList
            }
        }
        #if os(iOS)
        .environment(\.editMode, $editMode)
        #endif
        .navigationTitle("Classes")
        .toolbar {
            ToolbarItemGroup(placement: .primaryAction) {
                #if os(iOS)
                if store.classes.count > 1 {
                    Button(editMode.isEditing ? "Done" : "Reorder") {
                        withAnimation { editMode = editMode.isEditing ? .inactive : .active }
                    }
                }
                #endif
                Button { showAdd = true } label: {
                    Image(systemName: "plus.circle.fill").font(.title3)
                }
                .accessibilityLabel("Add Class")
            }
        }
        .sheet(isPresented: $showAdd) {
            ClassEditorSheet(cls: nil).presentationDetents([.large])
        }
        .sheet(item: $editingClass) { cls in
            ClassEditorSheet(cls: cls).presentationDetents([.large])
        }
        .sheet(item: $rosterTarget) { target in
            ClassRosterSheet(classId: target.id) { cls in editingClass = cls }
                .presentationDetents([.medium, .large])
        }
        .alert("Delete class?", isPresented: $showDeleteConfirm, presenting: deleteTarget) { cls in
            Button("Delete", role: .destructive) { Task { await delete(cls) } }
            Button("Cancel", role: .cancel) { }
        } message: { cls in
            Text("Remove **\(cls.name)** permanently? This can't be undone.")
        }
        .refreshable { await store.loadAll() }
        .toast($toast)
        .onChange(of: store.lastMutationError) { _, msg in
            guard let msg else { return }
            toast = ToastMessage(text: msg, kind: .error)
            store.lastMutationError = nil
        }
        .onChange(of: store.classes.count) { _, n in
            #if os(iOS)
            if n < 2 { editMode = .inactive }
            #endif
            if let f = schoolFilter, !schoolNames.contains(f) { schoolFilter = nil }
        }
    }

    // MARK: Header pieces

    private var subtitle: some View {
        Text("Your class roster — used for schedule, grades, and task organization.")
            .font(.subheadline).foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity, alignment: .leading)
    }

    @ViewBuilder
    private var schoolFilterRow: some View {
        let names = schoolNames
        if !names.isEmpty {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    filterChip("All Schools", selected: schoolFilter == nil) { schoolFilter = nil }
                    ForEach(names, id: \.self) { name in
                        filterChip(name, selected: schoolFilter == name) { schoolFilter = name }
                    }
                }
                .padding(.vertical, 2)
            }
        }
    }

    private func filterChip(_ text: String, selected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(text)
                .font(.caption.weight(.medium))
                .padding(.horizontal, 10).padding(.vertical, 5)
                .background(selected ? Color.accentColor : Color.secondary.opacity(0.15), in: Capsule())
                .foregroundStyle(selected ? Color.white : Color.primary)
        }
        .buttonStyle(.plain)
    }

    // MARK: List

    private var classList: some View {
        List {
            Section {
                VStack(alignment: .leading, spacing: 10) {
                    subtitle
                    schoolFilterRow
                }
                .listRowBackground(Color.clear)
                .listRowSeparator(.hidden)
                .listRowInsets(EdgeInsets(top: 4, leading: 16, bottom: 6, trailing: 16))
                .moveDisabled(true)
            }

            Section {
                ForEach(visibleClasses) { cls in
                    ClassCard(cls: cls, showSchool: !schoolNames.isEmpty,
                              onEdit: { editingClass = cls },
                              onDelete: { deleteTarget = cls; showDeleteConfirm = true })
                        .contentShape(Rectangle())
                        .onTapGesture { rosterTarget = RosterTarget(id: cls.id) }
                        .accessibilityAddTraits(.isButton)
                        .contextMenu {
                            Button { rosterTarget = RosterTarget(id: cls.id) } label: {
                                Label("Details", systemImage: "info.circle")
                            }
                            Button { editingClass = cls } label: { Label("Edit", systemImage: "pencil") }
                            Divider()
                            Button(role: .destructive) {
                                deleteTarget = cls; showDeleteConfirm = true
                            } label: { Label("Delete", systemImage: "trash") }
                        }
                        .listRowBackground(Color.clear)
                        .listRowSeparator(.hidden)
                        .listRowInsets(EdgeInsets(top: 6, leading: 16, bottom: 6, trailing: 16))
                }
                .onMove(perform: move)
            } footer: {
                if store.classes.count > 1 {
                    Text(reorderHint)
                        .font(.caption).foregroundStyle(.tertiary)
                        .frame(maxWidth: .infinity, alignment: .center)
                        .padding(.top, 4)
                }
            }
        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
    }

    private var reorderHint: String {
        #if os(iOS)
        return editMode.isEditing ? "Drag the handles to reorder your classes." : "Tap Reorder to drag classes into your preferred order."
        #else
        return "Drag classes to reorder them."
        #endif
    }

    // MARK: Actions

    /// Moves within the visible (possibly school-filtered) list, then writes
    /// the FULL id order back (web PATCH /api/classes { order }).
    private func move(from source: IndexSet, to destination: Int) {
        var vis = visibleClasses
        vis.move(fromOffsets: source, toOffset: destination)
        var full = store.orderedClasses
        let visibleIds = Set(vis.map(\.id))
        let slots = full.indices.filter { visibleIds.contains(full[$0].id) }
        for (slot, item) in zip(slots, vis) { full[slot] = item }
        Task {
            do { try await store.reorderClasses(full) }
            catch { toast = ToastMessage(text: "Could not save the new class order.", kind: .error) }
        }
    }

    private func delete(_ cls: SchoolClass) async {
        do { try await store.deleteClass(cls) }
        catch { toast = ToastMessage(text: "Could not delete class: \(error.localizedDescription)", kind: .error) }
    }

    // MARK: Empty state (web copy)

    private var emptyState: some View {
        VStack(spacing: 10) {
            subtitle
                .padding(.horizontal, 16).padding(.top, 8)
            Spacer()
            Image(systemName: "books.vertical")
                .font(.system(size: 40)).foregroundStyle(.secondary)
            Text("No classes yet")
                .font(.headline).foregroundStyle(.secondary)
            Text("Add classes manually, or connect PowerSchool in Settings to import them automatically.")
                .font(.subheadline).foregroundStyle(.tertiary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)
            HStack(spacing: 12) {
                Button { showAdd = true } label: {
                    Label("Add Class", systemImage: "plus")
                        .padding(.horizontal, 6).padding(.vertical, 4)
                }
                .buttonStyle(.borderedProminent)
                .buttonBorderShape(.capsule)
                Button("Connect PowerSchool") {
                    AppNavigation.shared.goToSettings(section: "powerschool")
                }
                .buttonStyle(.bordered)
                .buttonBorderShape(.capsule)
            }
            .padding(.top, 6)
            Spacer()
            Spacer()
        }
        .frame(maxWidth: .infinity)
    }
}

// MARK: - Class Card (web Classes page card)

struct ClassCard: View {
    let cls: SchoolClass
    var showSchool = false
    var onEdit: () -> Void = {}
    var onDelete: () -> Void = {}

    private var color: Color { Color(hex: cls.color) }

    var body: some View {
        VStack(spacing: 0) {
            color.frame(height: 6)

            VStack(alignment: .leading, spacing: 10) {
                HStack(alignment: .top, spacing: 8) {
                    Text(cls.name)
                        .font(.title3.weight(.semibold))
                        .foregroundStyle(color)
                        .fixedSize(horizontal: false, vertical: true)
                    Spacer(minLength: 0)
                    Menu {
                        Button { onEdit() } label: { Label("Edit", systemImage: "pencil") }
                        Button(role: .destructive) { onDelete() } label: { Label("Delete", systemImage: "trash") }
                    } label: {
                        Image(systemName: "ellipsis.circle")
                            .font(.title3)
                            .foregroundStyle(.secondary)
                            .frame(width: 32, height: 32)
                            .contentShape(Rectangle())
                    }
                    .menuStyle(.borderlessButton)
                    .menuIndicator(.hidden)
                    .fixedSize()
                    .accessibilityLabel("Class actions")
                }

                VStack(alignment: .leading, spacing: 4) {
                    if let teacher = cls.displayTeacher {
                        Label(teacher, systemImage: "person")
                    }
                    if !cls.room.isEmpty {
                        Label("Room \(cls.room)", systemImage: "mappin.and.ellipse")
                    }
                    Label("Period \(cls.period) • \(cls.startTime) – \(cls.endTime)", systemImage: "clock")
                }
                .font(.subheadline)
                .foregroundStyle(.secondary)

                if !cls.days.isEmpty {
                    PlannerFlowLayout(spacing: 5) {
                        ForEach(cls.days.sorted(), id: \.self) { d in
                            OutlinedChip(text: dayNames[d] ?? "?")
                        }
                    }
                }

                PlannerFlowLayout(spacing: 5) {
                    if !cls.semester.isEmpty {
                        ClassChip(name: cls.semester, hex: cls.color)
                    }
                    if showSchool, let school = cls.schoolName?.nonEmpty {
                        OutlinedChip(text: school)
                    }
                }
            }
            .padding(14)
        }
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous)
            .strokeBorder(Color.secondary.opacity(0.12), lineWidth: 0.5))
        .shadow(color: .black.opacity(0.06), radius: 6, y: 2)
    }
}

// MARK: - Class Editor Sheet (web ClassDialog)

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
    @State private var isAp = false
    /// Until the user flips the switch, a NEW class's AP flag follows the name.
    @State private var apTouched = false
    @State private var weightRows: [WeightRow] = []
    @State private var weightSource: String?
    @State private var showWeights = false
    @State private var dayTimeOverrides: [String: DayTime] = [:]
    @State private var isSaving = false
    @State private var error: String?

    private struct WeightRow: Identifiable {
        let id = UUID()
        var category: String
        var weight: String
    }

    private var weightsTotal: Double {
        weightRows.reduce(0) { $0 + (Double($1.weight.trimmingCharacters(in: .whitespaces)) ?? 0) }
    }
    private var weightsOff: Bool { abs(weightsTotal - 100) > 0.5 }

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
                                HStack(spacing: 10) {
                                    Label("Period", systemImage: "number").font(.body)
                                    Spacer()
                                    TextField("1", value: $period, format: .number)
                                        .multilineTextAlignment(.trailing)
                                        .frame(width: 48)
                                        #if !os(macOS)
                                        .keyboardType(.numberPad)
                                        #endif
                                    Stepper("", value: $period, in: 0...999)
                                        .labelsHidden()
                                }
                                .padding(.horizontal, 16).padding(.vertical, 10)
                                Divider().padding(.leading, 16)
                                HStack {
                                    Label("Start Time", systemImage: "clock").font(.body)
                                    Spacer()
                                    MinuteTimeField(time: $startTime)
                                }
                                .padding(.horizontal, 16).padding(.vertical, 8)
                                Divider().padding(.leading, 16)
                                HStack {
                                    Label("End Time", systemImage: "clock.badge.checkmark").font(.body)
                                    Spacer()
                                    MinuteTimeField(time: $endTime)
                                }
                                .padding(.horizontal, 16).padding(.vertical, 8)
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
                                    ForEach([1, 2, 3, 4, 5, 6, 0], id: \.self) { day in
                                        let label = dayNames[day] ?? "?"
                                        let selected = selectedDays.contains(day)
                                        Button {
                                            withAnimation(.spring(response: 0.2)) {
                                                if selected { selectedDays.remove(day) } else { selectedDays.insert(day) }
                                            }
                                        } label: {
                                            Text(label)
                                                .font(.caption.bold())
                                                .frame(maxWidth: .infinity)
                                                .padding(.vertical, 8)
                                                .background(selected ? Color.accentColor.opacity(0.15) : Color.clear,
                                                            in: RoundedRectangle(cornerRadius: 8))
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

                        // Color — 12 web swatches
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
                                                    Circle().strokeBorder(selectedColor == hex ? Color.primary : Color.clear, lineWidth: 2.5)
                                                        .padding(-3)
                                                )
                                                .overlay(
                                                    Image(systemName: "checkmark")
                                                        .font(.caption.weight(.bold))
                                                        .foregroundStyle(Color.contrastText(on: hex))
                                                        .opacity(selectedColor == hex ? 1 : 0)
                                                )
                                        }
                                        .buttonStyle(.plain)
                                        .scaleEffect(selectedColor == hex ? 1.12 : 1)
                                        .animation(.spring(response: 0.2), value: selectedColor)
                                        .accessibilityLabel("Colour \(hex)")
                                    }
                                }
                                .padding(.horizontal, 16).padding(.bottom, 14)
                            }
                        }

                        // AP / weighted-GPA flag
                        FormEditCard {
                            Toggle(isOn: Binding(get: { isAp }, set: { apTouched = true; isAp = $0 })) {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text("AP Class").font(.body.weight(.medium))
                                    Text("Counts as weighted (+1.0) in the Transcript page's weighted GPA."
                                         + (isNew && !apTouched ? " Auto-detected from the class name — flip this if it's wrong." : ""))
                                        .font(.caption).foregroundStyle(.secondary)
                                        .fixedSize(horizontal: false, vertical: true)
                                }
                            }
                            .padding(.horizontal, 16).padding(.vertical, 13)
                        }

                        gradeWeightsCard

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
            .navigationTitle(isNew ? "Add Class" : "Edit Class")
            .navigationBarTitleInline()
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button(isSaving ? "Saving…" : (isNew ? "Add Class" : "Save")) { Task { await save() } }
                        .disabled(name.trimmingCharacters(in: .whitespaces).isEmpty || isSaving)
                        .fontWeight(.semibold)
                }
            }
        }
        .onAppear { prefill() }
        .onChange(of: name) { _, value in
            // Web updateName: a brand-new class live-suggests its AP flag from
            // the name until the switch is touched. Existing classes never do.
            if isNew && !apTouched { isAp = APDetection.detectApFromName(value) }
        }
    }

    // MARK: - Grade Weights (web ClassDialog)

    private var gradeWeightsCard: some View {
        FormEditCard {
            VStack(alignment: .leading, spacing: 0) {
                HStack {
                    HStack(spacing: 6) {
                        Text("Grade Weights").font(.body.weight(.semibold))
                        if weightSource == "manual" {
                            Text("(manual override)").font(.caption).foregroundStyle(.secondary)
                        }
                    }
                    Spacer()
                    Button(showWeights ? "Hide" : "Set up") {
                        withAnimation(.spring(response: 0.3)) { showWeights.toggle() }
                    }
                    .font(.subheadline)
                }
                .padding(.horizontal, 16).padding(.top, 13).padding(.bottom, showWeights ? 10 : 4)

                if !showWeights {
                    Text("Optional — enables what-if calculator, grade transparency, and missing-work impact.")
                        .font(.caption).foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.horizontal, 16).padding(.bottom, 13)
                } else {
                    Divider().padding(.leading, 16)
                    ForEach($weightRows) { $row in
                        HStack(spacing: 8) {
                            TextField("e.g. Tests", text: $row.category)
                                .font(.body)
                                .onChange(of: row.category) { _, _ in markManual() }
                            Spacer(minLength: 4)
                            TextField("%", text: $row.weight)
                                .multilineTextAlignment(.trailing)
                                .foregroundStyle(.secondary)
                                .frame(width: 56)
                                #if !os(macOS)
                                .keyboardType(.decimalPad)
                                #endif
                                .onChange(of: row.weight) { _, _ in markManual() }
                            Text("%").foregroundStyle(.secondary)
                            Button {
                                withAnimation(.spring(response: 0.25)) {
                                    weightRows.removeAll { $0.id == row.id }
                                }
                                markManual()
                            } label: {
                                Image(systemName: "xmark")
                                    .font(.caption.weight(.semibold))
                                    .foregroundStyle(.secondary)
                                    .frame(width: 24, height: 24)
                            }
                            .buttonStyle(.plain)
                            .accessibilityLabel("Remove")
                        }
                        .padding(.horizontal, 16).padding(.vertical, 10)
                        Divider().padding(.leading, 16)
                    }

                    HStack(alignment: .firstTextBaseline, spacing: 12) {
                        Button {
                            withAnimation(.spring(response: 0.25)) {
                                weightRows.append(WeightRow(category: "", weight: ""))
                            }
                            markManual()
                        } label: {
                            Label("Add Category", systemImage: "plus").font(.subheadline)
                        }
                        .buttonStyle(.bordered)
                        .buttonBorderShape(.capsule)
                        .controlSize(.small)

                        if !weightRows.isEmpty {
                            Text(String(format: "Total: %.0f%%", weightsTotal) + (weightsOff ? " — should sum to 100%" : ""))
                                .font(.caption)
                                .foregroundStyle(weightsOff ? Color.red : Color.secondary)
                        }
                        Spacer(minLength: 0)
                        if weightSource == "manual" {
                            Button("Reset to auto-detected") {
                                withAnimation(.spring(response: 0.25)) { weightRows = [] }
                                weightSource = nil
                            }
                            .font(.caption)
                        }
                    }
                    .padding(.horizontal, 16).padding(.vertical, 12)
                }
            }
        }
    }

    /// Any manual edit of the rows marks the weights as a manual override.
    private func markManual() { weightSource = "manual" }

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
                    MinuteTimeField(time: Binding(
                        get: { dt.startTime },
                        set: { dayTimeOverrides[key]?.startTime = $0 }
                    ))
                    Text("–").foregroundStyle(.secondary)
                    MinuteTimeField(time: Binding(
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

    // MARK: - Prefill / Save

    private func prefill() {
        guard let cls else {
            apTouched = false
            return
        }
        name = cls.name
        teacher = cls.teacher
        room = cls.room
        period = cls.period
        startTime = cls.startTime
        endTime = cls.endTime
        semester = cls.semester
        selectedDays = Set(cls.days)
        selectedColor = cls.color
        isAp = cls.isAp ?? false
        apTouched = true // never auto-suggest on an existing class
        dayTimeOverrides = cls.dayTimes ?? [:]
        weightSource = cls.weightSource
        if let cw = cls.categoryWeights, !cw.isEmpty {
            weightRows = cw.sorted { $0.key < $1.key }.map { k, v in
                // Preserve fractional weights (e.g. 33.33) — don't truncate to Int.
                let display = v.truncatingRemainder(dividingBy: 1) == 0 ? String(Int(v)) : String(format: "%.2f", v)
                return WeightRow(category: k, weight: display)
            }
        }
        showWeights = !weightRows.isEmpty
    }

    /// Web rowsToWeights: rows with a non-blank category and a weight string →
    /// { trimmed category: parseFloat(weight) || 0 }; nil when none qualify.
    private func rowsToWeights() -> [String: Double]? {
        let valid = weightRows.filter {
            !$0.category.trimmingCharacters(in: .whitespaces).isEmpty
                && !$0.weight.trimmingCharacters(in: .whitespaces).isEmpty
        }
        guard !valid.isEmpty else { return nil }
        return Dictionary(valid.map { ($0.category.trimmingCharacters(in: .whitespaces),
                                       Double($0.weight.trimmingCharacters(in: .whitespaces)) ?? 0) },
                          uniquingKeysWith: { _, last in last })
    }

    private func save() async {
        isSaving = true; defer { isSaving = false }
        // Start from the original so server-owned fields (source, grade,
        // schoolName, sortOrder…) round-trip untouched.
        var item = cls ?? SchoolClass(
            id: UUID().uuidString, name: "", teacher: "", room: "", color: "#4285F4", period: 1,
            startTime: "08:00", endTime: "08:50", days: [1, 2, 3, 4, 5], dayTimes: nil,
            semester: "Spring 2026", source: nil, sourceId: nil, grade: nil, gradePercent: nil,
            categoryWeights: nil, weightSource: nil, isAp: false, sortOrder: nil, schoolName: nil
        )
        // Drop overrides for days no longer selected.
        let prunedDayTimes = dayTimeOverrides.filter { selectedDays.contains(Int($0.key) ?? -1) }
        let weights = rowsToWeights()

        item.name = name.trimmingCharacters(in: .whitespaces)
        item.teacher = teacher
        item.room = room
        item.color = selectedColor
        item.period = max(0, period)
        item.startTime = startTime
        item.endTime = endTime
        item.days = Array(selectedDays).sorted()
        item.dayTimes = prunedDayTimes.isEmpty ? nil : prunedDayTimes
        item.semester = semester
        item.isAp = isAp
        item.categoryWeights = weights
        item.weightSource = weights != nil ? (weightSource ?? "manual") : nil

        do {
            try await store.saveClass(item, isNew: isNew)
            store.psMatrixSuggestions.removeValue(forKey: item.id)
            dismiss()
        } catch { self.error = "Couldn't save: \(error.localizedDescription)" }
    }
}

// MARK: - Minute-precision time field ("HH:mm" string ⇄ DatePicker)

struct MinuteTimeField: View {
    @Binding var time: String

    private var dateBinding: Binding<Date> {
        Binding(
            get: {
                let m = ScheduleEngine.timeToMinutes(time)
                return Calendar.current.date(bySettingHour: m / 60, minute: m % 60, second: 0, of: .now) ?? .now
            },
            set: { d in
                let c = Calendar.current.dateComponents([.hour, .minute], from: d)
                time = String(format: "%02d:%02d", c.hour ?? 0, c.minute ?? 0)
            }
        )
    }

    var body: some View {
        DatePicker("", selection: dateBinding, displayedComponents: .hourAndMinute)
            .labelsHidden()
            .datePickerStyle(.compact)
            .fixedSize()
    }
}

/// Kept for source compatibility — now minute-precision like the web `type="time"` inputs.
struct TimeInputField: View {
    @Binding var time: String
    var body: some View { MinuteTimeField(time: $time) }
}
