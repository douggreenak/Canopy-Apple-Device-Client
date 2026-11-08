import SwiftUI

// Port of the web Settings page's Lathrop Mode switch, "Apply Default Bell
// Schedule" button and the "Early Dismissal Times" accordion (class-aware
// early-out editor with 600 ms debounced autosave).
struct BellScheduleSettingsView: View {
    @Environment(CanopyStore.self) private var store
    @State private var lathropOn = true
    @State private var earlyOut: [Int: DayTime] = [:]
    @State private var saveStatus: AutosaveStatus = .idle
    @State private var saveTask: Task<Void, Never>?
    @State private var toast: ToastMessage?
    @State private var applyingDefault = false
    @State private var showApplyDefaultConfirm = false
    @State private var savingLathrop = false

    var body: some View {
        List {
            lathropSection
            earlyOutSection
        }
        .insetGroupedListStyle()
        .background(CanopyBackground())
        .scrollContentBackground(.hidden)
        .navigationTitle("Bell Schedule")
        .navigationBarTitleInline()
        .onAppear(perform: prefill)
        .toast($toast)
        .alert("Apply Default Bell Schedule?", isPresented: $showApplyDefaultConfirm) {
            Button("Apply", role: .destructive) { Task { await applyDefaultBellSchedule() } }
            Button("Cancel", role: .cancel) { }
        } message: {
            Text("This overwrites the start/end time and days for every matching class (period 1–6, or Extension/Advisory). This cannot be undone.")
        }
    }

    // MARK: - Lathrop Mode + Apply Default Bell Schedule
    private var lathropSection: some View {
        Section {
            Toggle(isOn: Binding(
                get: { lathropOn },
                set: { on in Task { await setLathropMode(on) } }
            )) {
                VStack(alignment: .leading, spacing: 2) {
                    Label("Lathrop Mode", systemImage: "building.columns")
                    Text("Automatically apply the Lathrop HS bell schedule after every sync")
                        .font(.caption).foregroundStyle(.secondary)
                }
            }
            .disabled(savingLathrop)

            VStack(alignment: .leading, spacing: 4) {
                Button {
                    showApplyDefaultConfirm = true
                } label: {
                    Label(applyingDefault ? "Applying…" : "Apply Default Bell Schedule", systemImage: "calendar.badge.clock")
                }
                .disabled(!lathropOn || applyingDefault || store.isSyncing || store.classes.isEmpty)
                if !lathropOn {
                    Text("Turn on Lathrop Mode above to use the default bell schedule.")
                        .font(.caption).foregroundStyle(.secondary)
                }
            }
        } header: {
            Text("School Bell Schedule")
        } footer: {
            Text("Applies Lathrop High's full A/B rotation to every class's everyday start/end time and days, matching by period 1–6 or an Extension/Advisory-style name.")
        }
    }

    // MARK: - Early Dismissal Times
    private var earlyOutSection: some View {
        Section {
            Text("Set your school's exact period times for early-out days — used instead of estimating whenever a disruption on the Schedule page is marked \"Early Out\".")
                .font(.subheadline).foregroundStyle(.secondary)

            HStack(spacing: 10) {
                Text("Early-Out Schedule").font(.subheadline.weight(.semibold))
                if lathropOn {
                    Button("Auto-fill Lathrop") { autofillLathrop() }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                }
                Spacer()
                InlineSaveIndicator(status: saveStatus)
            }

            ForEach(earlyOut.keys.sorted(), id: \.self) { period in
                periodRow(period)
            }

            let missing = classesMissingFromSchedule
            if !missing.isEmpty {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Add from your classes:").font(.caption).foregroundStyle(.secondary)
                    CalendarFlowLayout(spacing: 6, rowSpacing: 6) {
                        ForEach(missing) { cls in
                            Button {
                                addPeriod(cls.period)
                            } label: {
                                Label("P\(cls.period) – \(shortName(cls.name, 14))", systemImage: "plus")
                                    .font(.caption.weight(.medium))
                                    .padding(.horizontal, 9).padding(.vertical, 5)
                                    .background(Color.secondary.opacity(0.12), in: Capsule())
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
                .padding(.vertical, 4)
            }
        } header: {
            Label("Early Dismissal Times", systemImage: "calendar")
        }
    }

    private func periodRow(_ period: Int) -> some View {
        let name = store.classes.first { $0.period == period }.map { shortName($0.name, 12) }
        return HStack(spacing: 8) {
            VStack(alignment: .leading, spacing: 1) {
                Text("P\(period)").font(.subheadline.weight(.semibold))
                if let name { Text(name).font(.caption2).foregroundStyle(.secondary).lineLimit(1) }
            }
            .frame(minWidth: 56, alignment: .leading)
            Spacer(minLength: 4)
            BellTimeField(label: "Start", time: Binding(
                get: { earlyOut[period]?.startTime ?? "" },
                set: { v in updateTime(period, start: v, end: nil) }
            ))
            Text("–").foregroundStyle(.secondary)
            BellTimeField(label: "End", time: Binding(
                get: { earlyOut[period]?.endTime ?? "" },
                set: { v in updateTime(period, start: nil, end: v) }
            ))
            Button(role: .destructive) {
                removePeriod(period)
            } label: {
                Image(systemName: "trash").foregroundStyle(.red)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Remove P\(period)")
        }
    }

    // MARK: - Derived
    /// One chip per class whose period isn't in the schedule yet (sorted by period).
    private var classesMissingFromSchedule: [SchoolClass] {
        var seen = Set<Int>()
        return store.classes
            .filter { earlyOut[$0.period] == nil }
            .sorted { $0.period < $1.period }
            .filter { seen.insert($0.period).inserted }
    }

    /// First segment before "," or "/", trimmed, clipped to `max` characters (web).
    private func shortName(_ name: String, _ max: Int) -> String {
        let first = name.split(whereSeparator: { $0 == "," || $0 == "/" }).first.map(String.init) ?? name
        return String(first.trimmingCharacters(in: .whitespaces).prefix(max))
    }

    // MARK: - Actions
    private func setLathropMode(_ on: Bool) async {
        savingLathrop = true; defer { savingLathrop = false }
        lathropOn = on
        let msg = await store.saveLathropMode(on)
        if on, earlyOut.isEmpty, let tpl = store.settings.earlyOutTemplate {
            var out: [Int: DayTime] = [:]
            for (k, v) in tpl { if let p = Int(k) { out[p] = v } }
            earlyOut = out
        }
        if let msg { toast = ToastMessage(text: msg, kind: .success) }
    }

    private func applyDefaultBellSchedule() async {
        applyingDefault = true; defer { applyingDefault = false }
        let msg = await store.applyLathropSchedule()
        toast = ToastMessage(text: msg, kind: .success)
    }

    private func autofillLathrop() {
        earlyOut = ScheduleEngine.buildLathropEarlyOutTemplate(classes: store.classes)
        scheduleSave()
    }

    private func updateTime(_ period: Int, start: String?, end: String?) {
        var dt = earlyOut[period] ?? DayTime(startTime: "", endTime: "")
        if let start { dt.startTime = start }
        if let end { dt.endTime = end }
        earlyOut[period] = dt
        scheduleSave()
    }

    private func addPeriod(_ period: Int) {
        guard earlyOut[period] == nil else { return }
        earlyOut[period] = DayTime(startTime: "", endTime: "")
        scheduleSave()
    }

    private func removePeriod(_ period: Int) {
        earlyOut[period] = nil
        scheduleSave()
    }

    /// Debounced autosave (web useDebouncedCallback 600 ms) with Saving…/Saved/error.
    private func scheduleSave() {
        saveTask?.cancel()
        let snapshot = earlyOut
        saveTask = Task {
            try? await Task.sleep(nanoseconds: 600_000_000)
            guard !Task.isCancelled else { return }
            saveStatus = .saving
            var map: [String: DayTime] = [:]
            for (p, dt) in snapshot { map[String(p)] = dt }
            do {
                try await store.saveEarlyOut(map)
                guard !Task.isCancelled else { return }
                saveStatus = .saved
                try? await Task.sleep(nanoseconds: 2_500_000_000)
                if !Task.isCancelled, saveStatus == .saved { saveStatus = .idle }
            } catch {
                guard !Task.isCancelled else { return }
                saveStatus = .error
            }
        }
    }

    /// Initial state: saved template if any; else the Lathrop template when
    /// Lathrop Mode is on (unsaved until edited) — web settings load.
    private func prefill() {
        lathropOn = store.settings.lathropEnabled
        if let tpl = store.settings.earlyOutTemplate {
            var out: [Int: DayTime] = [:]
            for (k, v) in tpl { if let p = Int(k) { out[p] = v } }
            earlyOut = out
        } else if lathropOn {
            earlyOut = ScheduleEngine.buildLathropEarlyOutTemplate(classes: nil)
        } else {
            earlyOut = [:]
        }
    }
}

// MARK: - Time field that tolerates an empty value (web `<input type="time">`)

private struct BellTimeField: View {
    let label: String
    @Binding var time: String

    var body: some View {
        if time.isEmpty {
            Button {
                time = label == "Start" ? "08:00" : "08:40"
            } label: {
                Text(label)
                    .font(.caption)
                    .padding(.horizontal, 8).padding(.vertical, 5)
                    .background(Color.secondary.opacity(0.12), in: RoundedRectangle(cornerRadius: 6))
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Set \(label.lowercased()) time")
        } else {
            DatePicker("", selection: Binding(
                get: { time.asTimeDate },
                set: { time = $0.timeString }
            ), displayedComponents: .hourAndMinute)
            .datePickerStyle(.compact)
            .labelsHidden()
            .fixedSize()
            .accessibilityLabel(label)
        }
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
