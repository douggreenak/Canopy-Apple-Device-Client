import SwiftUI

// MARK: - Main View (Settings ▸ Manage ▸ Schedule Disruptions)

private enum DisruptionDisplayMode: String, CaseIterable {
    case list = "List"
    case calendar = "Calendar"
}

struct ManageDisruptionsView: View {
    @Environment(CanopyStore.self) private var store
    @State private var editingDisruption: ScheduleDisruption?
    @State private var showAdd = false
    @State private var deleteTarget: ScheduleDisruption?
    @State private var showDeleteConfirm = false
    @State private var displayMode: DisruptionDisplayMode = .calendar

    private var upcoming: [ScheduleDisruption] {
        let today = DateFormatter.iso.string(from: .now)
        return store.disruptions
            .filter { ($0.endDate?.nonEmpty ?? $0.date) >= today }
            .sorted { $0.date < $1.date }
    }

    private var past: [ScheduleDisruption] {
        let today = DateFormatter.iso.string(from: .now)
        return store.disruptions
            .filter { ($0.endDate?.nonEmpty ?? $0.date) < today }
            .sorted { $0.date > $1.date }
    }

    var body: some View {
        ZStack {
            CanopyBackground()
            VStack(spacing: 0) {
                Picker("Display", selection: $displayMode) {
                    ForEach(DisruptionDisplayMode.allCases, id: \.self) { Text($0.rawValue).tag($0) }
                }
                .pickerStyle(.segmented)
                .padding(.horizontal, 16).padding(.top, 8).padding(.bottom, 4)

                switch displayMode {
                case .calendar:
                    ScrollView {
                        VStack(alignment: .leading, spacing: 10) {
                            Text("School is treated as in session every day by default — add a \"No School\" entry with an end date to mark a break (summer, winter, etc.) or any other day off.")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .fixedSize(horizontal: false, vertical: true)
                            DisruptionCalendarView()
                        }
                        .padding(.horizontal, 16)
                        .padding(.top, 8)
                        .padding(.bottom, 24)
                    }
                case .list:
                    if store.disruptions.isEmpty {
                        ContentUnavailableView(
                            "No Disruptions",
                            systemImage: "calendar.badge.exclamationmark",
                            description: Text("Schedule disruptions (half days, assemblies, etc.) appear here.")
                        )
                        .frame(maxHeight: .infinity)
                    } else {
                        disruptionList
                    }
                }
            }
        }
        .navigationTitle("Disruptions")
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button { showAdd = true } label: {
                    Image(systemName: "plus.circle.fill").font(.title3)
                }
                .accessibilityLabel("Add")
            }
        }
        .sheet(isPresented: $showAdd) { DisruptionEditorSheet(disruption: nil).presentationDetents([.large]) }
        .sheet(item: $editingDisruption) { d in DisruptionEditorSheet(disruption: d).presentationDetents([.large]) }
        .alert("Delete disruption?", isPresented: $showDeleteConfirm, presenting: deleteTarget) { d in
            Button("Delete", role: .destructive) {
                Task { await store.deleteDisruption(d) }
            }
            Button("Cancel", role: .cancel) { }
        } message: { d in
            Text(disruptionDeleteMessage(d))
        }
        .refreshable { await store.loadAll() }
    }

    private var disruptionList: some View {
        List {
            if !upcoming.isEmpty {
                Section {
                    ForEach(upcoming) { d in listRow(d) }
                } header: {
                    Label("Upcoming", systemImage: "clock").foregroundStyle(Color.accentColor).font(.subheadline.bold())
                }
            }

            if !past.isEmpty {
                Section {
                    ForEach(past) { d in listRow(d) }
                } header: {
                    Text("Past").foregroundStyle(.secondary).font(.subheadline.bold())
                }
            }
        }
        .insetGroupedListStyle()
        .scrollContentBackground(.hidden)
    }

    private func listRow(_ d: ScheduleDisruption) -> some View {
        DisruptionListRow(disruption: d)
            .contentShape(Rectangle())
            .onTapGesture { editingDisruption = d }
            .accessibilityAddTraits(.isButton)
            .swipeActions(edge: .trailing) {
                Button(role: .destructive) {
                    deleteTarget = d
                    showDeleteConfirm = true
                } label: { Label("Delete", systemImage: "trash") }
                Button { editingDisruption = d } label: {
                    Label("Edit", systemImage: "pencil")
                }.tint(.blue)
            }
    }
}

/// Web delete-confirm copy: "Remove {label} on {MMM d, yyyy}[ – {MMM d, yyyy}]? This can't be undone."
func disruptionDeleteMessage(_ d: ScheduleDisruption) -> String {
    var s = "Remove \(d.displayLabel)"
    if let start = d.date.asDate {
        s += " on \(DateFormatter.monthDayYear.string(from: start))"
        if let end = d.endDate?.nonEmpty?.asDate {
            s += " – \(DateFormatter.monthDayYear.string(from: end))"
        }
    }
    return s + "? This can't be undone."
}

// MARK: - Disruption List Row

struct DisruptionListRow: View {
    let disruption: ScheduleDisruption

    private var typeIcon: String {
        switch disruption.type {
        case "early_out": return "sun.and.horizon"
        case "no_school": return "xmark.circle"
        case "late_start": return "clock.arrow.circlepath"
        case "assembly": return "person.3"
        case "1_6": return "6.circle"
        case "day_swap": return "arrow.left.arrow.right"
        case "custom": return "star.circle"
        default: return "calendar.badge.exclamationmark"
        }
    }

    // Single source of truth for color, shared with web's DISRUPTION_TYPES.
    private var typeColor: Color { Color(hex: ScheduleEngine.disruptionColorHex(for: disruption.type)) }

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: typeIcon)
                .font(.title3)
                .foregroundStyle(typeColor)
                .frame(width: 32)

            VStack(alignment: .leading, spacing: 3) {
                Text(disruption.displayLabel)
                    .font(.body.weight(.medium))
                HStack(spacing: 6) {
                    if let end = disruption.endDate, !end.isEmpty, end != disruption.date {
                        Text("\(disruption.date.dueDateLabel) – \(end.dueDateLabel)")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    } else {
                        Text(disruption.date.dueDateLabel)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Text("·")
                        .foregroundStyle(.tertiary)
                    Text(ScheduleEngine.disruptionTypeLabel(disruption.type))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    if disruption.type == "day_swap", let src = disruption.sourceDayOfWeek,
                       ScheduleEngine.weekdayNames.indices.contains(src) {
                        Text("· \(ScheduleEngine.weekdayNames[src])")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                if !disruption.periodOverrides.isEmpty {
                    Text("\(disruption.periodOverrides.count) period override\(disruption.periodOverrides.count == 1 ? "" : "s")")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }
            }
        }
        .padding(.vertical, 4)
    }
}

// MARK: - Disruption Editor Sheet (web Add/Edit Disruption dialog)

struct DisruptionEditorSheet: View {
    @Environment(CanopyStore.self) private var store
    @Environment(\.dismiss) private var dismiss

    let disruption: ScheduleDisruption?
    private var isNew: Bool { disruption == nil }

    @State private var label = ""
    @State private var type = "early_out"
    @State private var date: Date
    @State private var hasEndDate = false
    @State private var endDate: Date
    @State private var sourceDayOfWeek: Int?
    @State private var isSaving = false
    @State private var error: String?
    @State private var periodOverrides: [PeriodOverride] = []
    @State private var autoTime = "13:00"
    @State private var showDeleteConfirm = false

    /// `prefillDate` seeds the date when adding a new disruption from a
    /// specific day (e.g. tapping an empty day on DisruptionCalendarView).
    /// Ignored when editing an existing disruption — prefill() overwrites it.
    init(disruption: ScheduleDisruption?, prefillDate: Date = .now) {
        self.disruption = disruption
        _date = State(initialValue: prefillDate)
        _endDate = State(initialValue: prefillDate)
    }

    private var supportsAutoGenerate: Bool { ["early_out", "late_start", "1_6", "assembly"].contains(type) }
    private var needsAutoGenerateTime: Bool { type == "early_out" || type == "late_start" }
    private var formValid: Bool { type != "day_swap" || sourceDayOfWeek != nil }

    private var autoGenerateInfo: String {
        switch type {
        case "1_6":
            return "Auto-generate a straight 1-6 schedule: every period meets once, in order, using each class’s standard period time — overriding the normal A/B block pattern for this day."
        case "assembly":
            return "Auto-generate a compressed schedule: the Extension/Advisory block is dropped, every other period that normally meets this day runs back-to-back, Lunch keeps its usual relative position, and a 45-minute Assembly block is added at the end. This is a general compression, not necessarily the school’s exact published assembly-day times — adjust below if needed."
        default:
            return "Auto-generate adjusted times: set the \(type == "early_out" ? "new end time" : "new start time") and periods will be proportionally adjusted."
        }
    }

    // Single source of truth, shared with web's DISRUPTION_TYPES.
    private let types = ScheduleEngine.disruptionTypes

    var body: some View {
        NavigationStack {
            ZStack { CanopyBackground()
                ScrollView {
                    VStack(spacing: 16) {
                        FormEditCard {
                            VStack(alignment: .leading, spacing: 4) {
                                Text("Label (optional)").font(.caption).foregroundStyle(.secondary)
                                TextField("e.g., Early Release — Teacher PD — leave blank to just show the type", text: $label, axis: .vertical)
                                    .font(.body)
                                    .lineLimit(1...2)
                            }
                            .padding(.horizontal, 16).padding(.vertical, 12)
                        }

                        FormEditCard {
                            HStack {
                                Label("Type", systemImage: "exclamationmark.circle").font(.body)
                                Spacer()
                                Picker("", selection: $type) {
                                    ForEach(types, id: \.value) { t in
                                        Text(t.label).tag(t.value)
                                    }
                                }
                                .labelsHidden()
                            }
                            .padding(.horizontal, 16).padding(.vertical, 13)
                        }

                        FormEditCard {
                            VStack(spacing: 0) {
                                DatePicker(selection: $date, displayedComponents: .date) {
                                    Label("Date", systemImage: "calendar")
                                }
                                .padding(.horizontal, 16).padding(.vertical, 10)
                                .onChange(of: date) { _, new in
                                    // Keep endDate valid — an end before the new start makes no sense.
                                    if endDate < new { endDate = new }
                                }
                                Divider().padding(.leading, 16)
                                Toggle(isOn: $hasEndDate.animation(.spring(response: 0.3, dampingFraction: 0.8))) {
                                    VStack(alignment: .leading, spacing: 2) {
                                        Label("End Date (optional)", systemImage: "calendar.badge.plus")
                                        Text("Leave blank for a single day").font(.caption).foregroundStyle(.secondary)
                                    }
                                }
                                .padding(.horizontal, 16).padding(.vertical, 12)
                                if hasEndDate {
                                    Divider().padding(.leading, 16)
                                    DatePicker("End Date", selection: $endDate, in: date..., displayedComponents: .date)
                                        .padding(.horizontal, 16).padding(.vertical, 10)
                                }
                            }
                        }

                        if type == "day_swap" { daySwapCard }

                        if supportsAutoGenerate { autoGenerateCard }

                        periodOverrideCard

                        if !isNew {
                            Button(role: .destructive) {
                                showDeleteConfirm = true
                            } label: {
                                Label("Delete", systemImage: "trash")
                                    .frame(maxWidth: .infinity)
                                    .padding(.vertical, 6)
                            }
                            .buttonStyle(.glass)
                            .tint(.red)
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
            .navigationTitle(isNew ? "Add Disruption" : "Edit Disruption")
            .navigationBarTitleInline()
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button(isSaving ? "Saving…" : (isNew ? "Add" : "Save")) { Task { await save() } }
                        .disabled(!formValid || isSaving)
                        .fontWeight(.semibold)
                        .keyboardShortcut(.defaultAction)
                }
            }
            .alert("Delete disruption?", isPresented: $showDeleteConfirm) {
                Button("Delete", role: .destructive) {
                    if let disruption {
                        Task {
                            await store.deleteDisruption(disruption)
                            dismiss()
                        }
                    }
                }
                Button("Cancel", role: .cancel) { }
            } message: {
                if let disruption { Text(disruptionDeleteMessage(disruption)) }
            }
        }
        .onAppear { prefill() }
    }

    // MARK: - Day swap
    private var daySwapCard: some View {
        FormEditCard {
            VStack(alignment: .leading, spacing: 10) {
                infoText("Runs another weekday's normal class list and times on this date instead — e.g. set a Thursday schedule on a Monday. Any classes that don't meet on the chosen weekday won't show up at all that day.")
                HStack {
                    Label("Use schedule from", systemImage: "arrow.left.arrow.right").font(.body)
                    Spacer()
                    Picker("", selection: $sourceDayOfWeek) {
                        Text("Choose…").tag(Int?.none)
                        ForEach(Array(ScheduleEngine.weekdayNames.enumerated()), id: \.offset) { i, name in
                            Text(name).tag(Int?.some(i))
                        }
                    }
                    .labelsHidden()
                }
            }
            .padding(.horizontal, 16).padding(.vertical, 13)
        }
    }

    // MARK: - Auto-generate
    private var autoGenerateCard: some View {
        FormEditCard {
            VStack(alignment: .leading, spacing: 10) {
                infoText(autoGenerateInfo)
                HStack(spacing: 12) {
                    if needsAutoGenerateTime {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(type == "early_out" ? "Early End Time" : "Late Start Time")
                                .font(.caption).foregroundStyle(.secondary)
                            DatePicker("", selection: Binding(
                                get: { autoTime.asTimeDate },
                                set: { autoTime = $0.timeString }
                            ), displayedComponents: .hourAndMinute)
                            .datePickerStyle(.compact).labelsHidden().fixedSize()
                        }
                    }
                    Button {
                        autoGenerate()
                    } label: {
                        Label("Auto Generate", systemImage: "wand.and.stars")
                    }
                    .buttonStyle(.glass)
                    Spacer(minLength: 0)
                }
            }
            .padding(.horizontal, 16).padding(.vertical, 13)
        }
    }

    private func infoText(_ s: String) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: "info.circle.fill").foregroundStyle(.blue).font(.caption)
            Text(s).font(.caption).foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.blue.opacity(0.08), in: RoundedRectangle(cornerRadius: 8))
    }

    // MARK: - Period overrides (only when non-empty, web parity; manual add kept)
    @ViewBuilder
    private var periodOverrideCard: some View {
        FormEditCard {
            VStack(alignment: .leading, spacing: 0) {
                HStack {
                    Label("Period Overrides", systemImage: "clock.badge").font(.body)
                    Spacer()
                    Button {
                        addOverrideRow()
                    } label: {
                        Label("Add", systemImage: "plus.circle").font(.subheadline)
                    }
                }
                .padding(.horizontal, 16).padding(.top, 13).padding(.bottom, periodOverrides.isEmpty ? 13 : 8)

                if !periodOverrides.isEmpty {
                    Divider().padding(.leading, 16)
                    ForEach($periodOverrides) { $ov in
                        VStack(spacing: 6) {
                            HStack {
                                Text(ScheduleEngine.periodLabel(ov.period))
                                    .font(.caption.weight(.semibold))
                                    .padding(.horizontal, 8).padding(.vertical, 3)
                                    .background(Color.secondary.opacity(0.15), in: Capsule())
                                Spacer()
                                Toggle("Cancel", isOn: $ov.cancelled).labelsHidden()
                                Text("Cancel").font(.caption).foregroundStyle(.secondary)
                                Button(role: .destructive) {
                                    periodOverrides.removeAll { $0.period == ov.period }
                                } label: {
                                    Image(systemName: "minus.circle.fill").foregroundStyle(.red)
                                }
                                .buttonStyle(.plain)
                                .accessibilityLabel("Remove override")
                            }
                            HStack {
                                Spacer()
                                DatePicker("", selection: Binding(
                                    get: { ov.startTime.asTimeDate },
                                    set: { ov.startTime = $0.timeString }
                                ), displayedComponents: .hourAndMinute)
                                .datePickerStyle(.compact).labelsHidden().fixedSize()
                                .disabled(ov.cancelled)
                                Text("–").foregroundStyle(.secondary)
                                DatePicker("", selection: Binding(
                                    get: { ov.endTime.asTimeDate },
                                    set: { ov.endTime = $0.timeString }
                                ), displayedComponents: .hourAndMinute)
                                .datePickerStyle(.compact).labelsHidden().fixedSize()
                                .disabled(ov.cancelled)
                            }
                            .opacity(ov.cancelled ? 0.5 : 1)
                        }
                        .padding(.horizontal, 16).padding(.vertical, 8)
                        Divider().padding(.leading, 16)
                    }
                }
            }
        }
    }

    // MARK: - Auto-generate inputs (web handleAutoGenerate)
    private func autoGenerate() {
        let dow = Calendar.current.component(.weekday, from: date) - 1
        let dayClasses = store.classes.filter { $0.days.contains(dow) }
        let hasLunch = store.lunchTime(for: date) != nil
        switch type {
        case "early_out":
            // Template precedence: saved early_out_schedule → Lathrop default (when on) → proportional.
            var template: [Int: DayTime]? = nil
            if let saved = store.settings.earlyOutTemplate {
                var m: [Int: DayTime] = [:]
                for (k, v) in saved { if let p = Int(k) { m[p] = v } }
                template = m.isEmpty ? nil : m
            } else if store.settings.lathropEnabled {
                template = ScheduleEngine.buildLathropEarlyOutTemplate(classes: nil)
            }
            periodOverrides = ScheduleEngine.generateEarlyOutOverrides(
                classes: dayClasses, earlyEndTime: autoTime, dayOfWeek: dow, template: template)
        case "late_start":
            periodOverrides = ScheduleEngine.generateLateStartOverrides(
                classes: dayClasses, lateStartTime: autoTime, dayOfWeek: dow)
        case "no_school":
            periodOverrides = dayClasses.map { c in
                PeriodOverride(period: c.period,
                               startTime: c.dayTimes?[String(dow)]?.startTime.nonEmpty ?? c.startTime,
                               endTime: c.dayTimes?[String(dow)]?.endTime.nonEmpty ?? c.endTime,
                               cancelled: true)
            }
        case "1_6":
            // Full class list (not day-filtered): a 1-6 day overrides the A/B pattern.
            periodOverrides = ScheduleEngine.generateOneToSixOverrides(classes: store.classes, hasLunch: hasLunch)
        case "assembly":
            periodOverrides = ScheduleEngine.generateAssemblyOverrides(classes: store.classes, dayOfWeek: dow, hasLunch: hasLunch)
        default:
            break
        }
        periodOverrides = dedupe(periodOverrides)
    }

    /// PeriodOverride is Identifiable by period — keep one row per period.
    private func dedupe(_ list: [PeriodOverride]) -> [PeriodOverride] {
        var seen = Set<Int>()
        return list.filter { seen.insert($0.period).inserted }
    }

    private func addOverrideRow() {
        let used = Set(periodOverrides.map(\.period))
        let dow = Calendar.current.component(.weekday, from: date) - 1
        let dayClasses = store.classes.filter { $0.days.contains(dow) }.sorted { $0.period < $1.period }
        if let next = dayClasses.first(where: { !used.contains($0.period) }) {
            periodOverrides.append(PeriodOverride(
                period: next.period,
                startTime: next.dayTimes?[String(dow)]?.startTime.nonEmpty ?? next.startTime,
                endTime: next.dayTimes?[String(dow)]?.endTime.nonEmpty ?? next.endTime,
                cancelled: false))
        } else if !used.contains(0) {
            let lunch = store.lunchTime(for: date) ?? DayTime(startTime: "10:50", endTime: "11:20")
            periodOverrides.append(PeriodOverride(period: 0, startTime: lunch.startTime, endTime: lunch.endTime, cancelled: false))
        } else {
            var nextNum = (periodOverrides.map(\.period).max() ?? 0) + 1
            while used.contains(nextNum) { nextNum += 1 }
            periodOverrides.append(PeriodOverride(period: nextNum, startTime: "08:00", endTime: "08:50", cancelled: false))
        }
        periodOverrides = dedupe(periodOverrides)
    }

    private func prefill() {
        guard let disruption else { return }
        label = disruption.label
        type = disruption.type
        date = disruption.date.asDate ?? .now
        if let ed = disruption.endDate, !ed.isEmpty, let d = ed.asDate {
            hasEndDate = true
            endDate = d
        } else {
            endDate = date
        }
        sourceDayOfWeek = disruption.sourceDayOfWeek
        periodOverrides = dedupe(disruption.periodOverrides)
    }

    private func save() async {
        isSaving = true; defer { isSaving = false }
        let item = ScheduleDisruption(
            id: disruption?.id ?? UUID().uuidString,
            date: DateFormatter.iso.string(from: date),
            endDate: hasEndDate ? DateFormatter.iso.string(from: max(date, endDate)) : nil,
            type: type,
            label: label.trimmingCharacters(in: .whitespaces),
            periodOverrides: periodOverrides,
            sourceDayOfWeek: type == "day_swap" ? sourceDayOfWeek : nil
        )
        do {
            try await store.saveDisruption(item, isNew: isNew)
            dismiss()
        } catch { self.error = error.localizedDescription }
    }
}
