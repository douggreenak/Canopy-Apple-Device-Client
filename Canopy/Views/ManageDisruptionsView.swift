import SwiftUI

// MARK: - Main View

struct ManageDisruptionsView: View {
    @Environment(CanopyStore.self) private var store
    @State private var editingDisruption: ScheduleDisruption?
    @State private var showAdd = false
    @State private var deleteTarget: ScheduleDisruption?
    @State private var showDeleteConfirm = false

    private var upcoming: [ScheduleDisruption] {
        let today = DateFormatter.iso.string(from: .now)
        return store.disruptions
            .filter { $0.date >= today }
            .sorted { $0.date < $1.date }
    }

    private var past: [ScheduleDisruption] {
        let today = DateFormatter.iso.string(from: .now)
        return store.disruptions
            .filter { $0.date < today }
            .sorted { $0.date > $1.date }
    }

    var body: some View {
        ZStack {
            CanopyBackground()
            if store.disruptions.isEmpty {
                ContentUnavailableView(
                    "No Disruptions",
                    systemImage: "calendar.badge.exclamationmark",
                    description: Text("Schedule disruptions (half days, assemblies, etc.) appear here.")
                )
            } else {
                disruptionList
            }
        }
        .navigationTitle("Disruptions")
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button { showAdd = true } label: {
                    Image(systemName: "plus.circle.fill").font(.title3)
                }
            }
        }
        .sheet(isPresented: $showAdd) { DisruptionEditorSheet(disruption: nil).presentationDetents([.large]) }
        .sheet(item: $editingDisruption) { d in DisruptionEditorSheet(disruption: d).presentationDetents([.large]) }
        .alert("Delete Disruption?", isPresented: $showDeleteConfirm, presenting: deleteTarget) { d in
            Button("Delete", role: .destructive) {
                Task { await store.deleteDisruption(d) }
            }
            Button("Cancel", role: .cancel) { }
        } message: { d in
            Text("Remove the \"\(d.label)\" disruption on \(d.date.dueDateLabel)?")
        }
        .refreshable { await store.loadAll() }
    }

    private var disruptionList: some View {
        List {
            if !upcoming.isEmpty {
                Section {
                    ForEach(upcoming) { d in
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
                } header: {
                    Label("Upcoming", systemImage: "clock").foregroundStyle(Color.accentColor).font(.subheadline.bold())
                }
            }

            if !past.isEmpty {
                Section {
                    ForEach(past) { d in
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
                } header: {
                    Text("Past").foregroundStyle(.secondary).font(.subheadline.bold())
                }
            }
        }
        .insetGroupedListStyle()
        .scrollContentBackground(.hidden)
    }
}

// MARK: - Disruption List Row

struct DisruptionListRow: View {
    let disruption: ScheduleDisruption

    private var typeIcon: String {
        switch disruption.type {
        case "half_day": return "sun.and.horizon"
        case "no_school": return "xmark.circle"
        case "late_start": return "clock.arrow.circlepath"
        case "early_release": return "arrow.left.to.line"
        default: return "calendar.badge.exclamationmark"
        }
    }

    private var typeColor: Color {
        switch disruption.type {
        case "no_school": return .red
        case "half_day": return .orange
        case "late_start": return .yellow
        case "early_release": return .teal
        default: return .secondary
        }
    }

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: typeIcon)
                .font(.title3)
                .foregroundStyle(typeColor)
                .frame(width: 32)

            VStack(alignment: .leading, spacing: 3) {
                Text(disruption.label)
                    .font(.body.weight(.medium))
                HStack(spacing: 6) {
                    Text(disruption.date.dueDateLabel)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Text("·")
                        .foregroundStyle(.tertiary)
                    Text(disruption.type.replacingOccurrences(of: "_", with: " ").capitalized)
                        .font(.caption)
                        .foregroundStyle(.secondary)
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

// MARK: - Disruption Editor Sheet

struct DisruptionEditorSheet: View {
    @Environment(CanopyStore.self) private var store
    @Environment(\.dismiss) private var dismiss

    let disruption: ScheduleDisruption?
    private var isNew: Bool { disruption == nil }

    @State private var label = ""
    @State private var type = "half_day"
    @State private var date = Date.now
    @State private var isSaving = false
    @State private var error: String?
    @State private var periodOverrides: [PeriodOverride] = []
    @State private var autoTime = Date.now

    private var supportsAutoGenerate: Bool { type == "early_release" || type == "late_start" }

    private let types = [
        ("half_day", "Half Day"),
        ("no_school", "No School"),
        ("late_start", "Late Start"),
        ("early_release", "Early Release"),
        ("assembly", "Assembly"),
        ("other", "Other")
    ]

    var body: some View {
        NavigationStack {
            ZStack { CanopyBackground()
                ScrollView {
                    VStack(spacing: 16) {

                        FormEditCard {
                            TextField("Label (e.g. Half Day – Parent Conferences)", text: $label)
                                .font(.body)
                                .padding(.horizontal, 16).padding(.vertical, 13)
                        }

                        FormEditCard {
                            HStack {
                                Label("Type", systemImage: "exclamationmark.circle").font(.body)
                                Spacer()
                                Picker("", selection: $type) {
                                    ForEach(types, id: \.0) { t in
                                        Text(t.1).tag(t.0)
                                    }
                                }
                                .labelsHidden()
                            }
                            .padding(.horizontal, 16).padding(.vertical, 13)
                        }

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

                        periodOverrideCard

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
            .navigationTitle(isNew ? "New Disruption" : "Edit Disruption")
            .navigationBarTitleInline()
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button(isSaving ? "Saving…" : "Save") { Task { await save() } }
                        .disabled(label.trimmingCharacters(in: .whitespaces).isEmpty || isSaving)
                        .fontWeight(.semibold)
                }
            }
        }
        .onAppear { prefill() }
    }

    // MARK: - Period overrides editor
    @ViewBuilder
    private var periodOverrideCard: some View {
        if type != "no_school" {
            FormEditCard {
                VStack(alignment: .leading, spacing: 0) {
                    HStack {
                        Label("Period Times", systemImage: "clock.badge")
                        Spacer()
                        if supportsAutoGenerate {
                            DatePicker("", selection: $autoTime, displayedComponents: .hourAndMinute)
                                .datePickerStyle(.compact).labelsHidden().fixedSize()
                        }
                    }
                    .font(.body)
                    .padding(.horizontal, 16).padding(.top, 13).padding(.bottom, 8)

                    if supportsAutoGenerate {
                        Button {
                            autoGenerate()
                        } label: {
                            Label(type == "early_release" ? "Generate from end time" : "Generate from start time",
                                  systemImage: "wand.and.stars")
                                .font(.subheadline)
                        }
                        .padding(.horizontal, 16).padding(.bottom, 8)
                    }

                    Divider().padding(.leading, 16)

                    if periodOverrides.isEmpty {
                        Text("No period overrides. \(supportsAutoGenerate ? "Set a time and tap Generate, or " : "")Add classes' adjusted times below.")
                            .font(.caption).foregroundStyle(.secondary)
                            .padding(16)
                    } else {
                        ForEach($periodOverrides, id: \.period) { $ov in
                            VStack(spacing: 6) {
                                HStack {
                                    Text("Period \(ov.period)").font(.subheadline.bold())
                                    Spacer()
                                    Toggle("Cancelled", isOn: $ov.cancelled).labelsHidden()
                                    Text("Cancel").font(.caption).foregroundStyle(.secondary)
                                }
                                if !ov.cancelled {
                                    HStack {
                                        Spacer()
                                        DatePicker("", selection: Binding(
                                            get: { ov.startTime.asTimeDate },
                                            set: { ov.startTime = $0.timeString }
                                        ), displayedComponents: .hourAndMinute)
                                        .datePickerStyle(.compact).labelsHidden().fixedSize()
                                        Text("–").foregroundStyle(.secondary)
                                        DatePicker("", selection: Binding(
                                            get: { ov.endTime.asTimeDate },
                                            set: { ov.endTime = $0.timeString }
                                        ), displayedComponents: .hourAndMinute)
                                        .datePickerStyle(.compact).labelsHidden().fixedSize()
                                    }
                                }
                            }
                            .padding(.horizontal, 16).padding(.vertical, 8)
                            Divider().padding(.leading, 16)
                        }
                    }

                    Button {
                        addOverrideRow()
                    } label: {
                        Label("Add Period Override", systemImage: "plus.circle")
                            .font(.subheadline)
                    }
                    .padding(16)
                }
            }
        }
    }

    private func autoGenerate() {
        let dayClasses = store.classes(for: date)
        let dow = Calendar.current.component(.weekday, from: date) - 1
        if type == "early_release" {
            let template: [Int: DayTime]? = store.settings.lathropEnabled
                ? ScheduleEngine.buildLathropEarlyOutTemplate(classes: dayClasses)
                : store.settings.earlyOutTemplate.flatMap { tpl in
                    var m: [Int: DayTime] = [:]; for (k, v) in tpl { if let p = Int(k) { m[p] = v } }; return m.isEmpty ? nil : m
                }
            periodOverrides = ScheduleEngine.generateEarlyOutOverrides(
                classes: dayClasses, earlyEndTime: autoTime.timeString, dayOfWeek: dow, template: template)
        } else {
            periodOverrides = ScheduleEngine.generateLateStartOverrides(
                classes: dayClasses, lateStartTime: autoTime.timeString, dayOfWeek: dow)
        }
    }

    private func addOverrideRow() {
        let used = Set(periodOverrides.map(\.period))
        let dayClasses = store.classes(for: date)
        if let next = dayClasses.first(where: { !used.contains($0.period) }) {
            periodOverrides.append(PeriodOverride(period: next.period, startTime: next.startTime, endTime: next.endTime, cancelled: false))
        } else {
            let nextNum = (periodOverrides.map(\.period).max() ?? 0) + 1
            periodOverrides.append(PeriodOverride(period: nextNum, startTime: "08:00", endTime: "08:50", cancelled: false))
        }
        periodOverrides.sort { $0.period < $1.period }
    }

    private func prefill() {
        guard let disruption else { return }
        label = disruption.label
        type = disruption.type
        date = disruption.date.asDate ?? .now
        periodOverrides = disruption.periodOverrides.sorted { $0.period < $1.period }
    }

    private func save() async {
        isSaving = true; defer { isSaving = false }
        let item = ScheduleDisruption(
            id: disruption?.id ?? UUID().uuidString,
            date: DateFormatter.iso.string(from: date),
            type: type,
            label: label.trimmingCharacters(in: .whitespaces),
            periodOverrides: type == "no_school" ? [] : periodOverrides
        )
        do {
            try await store.saveDisruption(item, isNew: isNew)
            dismiss()
        } catch { self.error = error.localizedDescription }
    }
}
