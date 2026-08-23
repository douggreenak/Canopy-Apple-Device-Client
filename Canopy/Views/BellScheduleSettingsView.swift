import SwiftUI

struct BellScheduleSettingsView: View {
    @Environment(CanopyStore.self) private var store
    @State private var lathropOn = false
    @State private var earlyOut: [Int: DayTime] = [:]
    @State private var isSaving = false
    @State private var message: String?
    @State private var showApplyDefaultConfirm = false
    @State private var applyingDefault = false

    private let periods = Array(1...7)

    var body: some View {
        List {
            Section {
                Toggle(isOn: $lathropOn) {
                    Label("Lathrop Mode", systemImage: "building.columns")
                }
                .onChange(of: lathropOn) { _, on in
                    Task { await store.saveLathropMode(on) }
                }
            } header: {
                Text("School Bell Schedule")
            } footer: {
                Text("Lathrop Mode applies Lathrop High's A/B block bell schedule to synced classes automatically.")
            }

            Section {
                ForEach(periods, id: \.self) { p in
                    let included = Binding<Bool>(
                        get: { earlyOut[p] != nil },
                        set: { on in
                            if on { earlyOut[p] = ScheduleEngine.lathropEarlyOut[p] ?? DayTime(startTime: "08:00", endTime: "08:40") }
                            else { earlyOut[p] = nil }
                        }
                    )
                    VStack(alignment: .leading, spacing: 6) {
                        Toggle("Period \(p)", isOn: included)
                        if let dt = earlyOut[p] {
                            HStack {
                                Spacer()
                                timePicker(period: p, isStart: true, value: dt.startTime)
                                Text("–").foregroundStyle(.secondary)
                                timePicker(period: p, isStart: false, value: dt.endTime)
                            }
                        }
                    }
                }
                Button {
                    earlyOut = ScheduleEngine.buildLathropEarlyOutTemplate(classes: store.classes)
                } label: {
                    Label("Use Lathrop Template", systemImage: "wand.and.stars")
                }
            } header: {
                Text("Early-Out Bell Schedule")
            } footer: {
                Text("Per-period times used when you create an Early-Out disruption.")
            }

            Section {
                Button {
                    Task { await save() }
                } label: {
                    Label(isSaving ? "Saving…" : "Save Early-Out Schedule", systemImage: "square.and.arrow.down")
                }
                .disabled(isSaving)
                if let message { Text(message).font(.footnote).foregroundStyle(.green) }
            }

            Section {
                Button {
                    showApplyDefaultConfirm = true
                } label: {
                    Label(applyingDefault ? "Applying…" : "Apply Default Bell Schedule", systemImage: "calendar.badge.clock")
                }
                .disabled(applyingDefault || store.classes.isEmpty)
            } header: {
                Text("Full Weekly Schedule")
            } footer: {
                Text("Applies Lathrop High's full A/B rotation to every class's everyday start/end time and days, matching by period 1–6 or an Extension/Advisory-style name. This overwrites each matched class's schedule.")
            }
        }
        .insetGroupedListStyle()
        .background(CanopyBackground())
        .scrollContentBackground(.hidden)
        .navigationTitle("Bell Schedule")
        .navigationBarTitleInline()
        .onAppear(perform: prefill)
        .alert("Apply Default Bell Schedule?", isPresented: $showApplyDefaultConfirm) {
            Button("Apply", role: .destructive) { Task { await applyDefaultBellSchedule() } }
            Button("Cancel", role: .cancel) { }
        } message: {
            Text("This overwrites the start/end time and days for every matching class (period 1–6, or Extension/Advisory). This cannot be undone.")
        }
    }

    private func applyDefaultBellSchedule() async {
        applyingDefault = true; defer { applyingDefault = false }
        let result = ScheduleEngine.applyLathropWeekSchedule(classes: store.classes)
        for cls in result.updatedClasses {
            try? await store.saveClass(cls, isNew: false)
        }
        message = result.skippedCount > 0
            ? "Applied to \(result.appliedCount) class\(result.appliedCount == 1 ? "" : "es"). \(result.skippedCount) skipped (no period 1-6 or Extension)."
            : "Applied to \(result.appliedCount) class\(result.appliedCount == 1 ? "" : "es")."
    }

    private func timePicker(period: Int, isStart: Bool, value: String) -> some View {
        DatePicker("", selection: Binding(
            get: { value.asTimeDate },
            set: { newVal in
                var dt = earlyOut[period] ?? DayTime(startTime: "08:00", endTime: "08:40")
                if isStart { dt.startTime = newVal.timeString } else { dt.endTime = newVal.timeString }
                earlyOut[period] = dt
            }
        ), displayedComponents: .hourAndMinute)
        .datePickerStyle(.compact)
        .labelsHidden()
        .fixedSize()
    }

    private func prefill() {
        lathropOn = store.settings.lathropEnabled
        if let tpl = store.settings.earlyOutTemplate {
            var out: [Int: DayTime] = [:]
            for (k, v) in tpl { if let p = Int(k) { out[p] = v } }
            earlyOut = out
        }
    }

    private func save() async {
        isSaving = true; defer { isSaving = false }
        var map: [String: DayTime] = [:]
        for (p, dt) in earlyOut { map[String(p)] = dt }
        try? await store.saveEarlyOut(map)
        message = "Saved."
    }
}

// MARK: - Time string helpers

extension String {
    var asTimeDate: Date {
        let parts = split(separator: ":").compactMap { Int($0) }
        var comps = Calendar.current.dateComponents([.year, .month, .day], from: .now)
        comps.hour = parts.first ?? 8
        comps.minute = parts.count > 1 ? parts[1] : 0
        return Calendar.current.date(from: comps) ?? .now
    }
}

extension Date {
    var timeString: String {
        let cal = Calendar.current
        return String(format: "%02d:%02d", cal.component(.hour, from: self), cal.component(.minute, from: self))
    }
}
