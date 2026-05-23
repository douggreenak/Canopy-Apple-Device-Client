import SwiftUI

struct SettingsView: View {
    @Environment(AuthStore.self) private var authStore
    @Environment(CanopyStore.self) private var store
    @AppStorage("colorScheme") private var colorSchemeRaw = "system"
    @AppStorage("backgroundOpacity") private var backgroundOpacity: Double = 0.75
    @State private var showDeleteConfirm = false
    @State private var showSchoolEditor = false
    @State private var showLunchEditor = false

    var body: some View {
        NavigationStack {
            List {
                accountSection
                schoolSection
                manageSection
                appearanceSection
                aboutSection
                actionsSection
            }
            .insetGroupedListStyle()
            .background(CanopyBackground())
            .scrollContentBackground(.hidden)
            .navigationTitle("Settings")
            .alert("Delete Account?", isPresented: $showDeleteConfirm) {
                Button("Delete", role: .destructive, action: performDelete)
                Button("Cancel", role: .cancel, action: {})
            } message: {
                Text("All your data will be permanently deleted and cannot be recovered.")
            }
            .sheet(isPresented: $showSchoolEditor) {
                SchoolInfoEditorSheet().presentationDetents([.large])
            }
            .sheet(isPresented: $showLunchEditor) {
                LunchTimesEditorSheet().presentationDetents([.large])
            }
        }
    }

    // MARK: - Account
    private var accountSection: some View {
        Section("Account") {
            HStack(spacing: 14) {
                ZStack {
                    Circle().fill(Color.accentColor.gradient)
                    Text(authStore.user?.username.prefix(1).uppercased() ?? "?")
                        .font(.title2.bold()).foregroundStyle(.white)
                }
                .frame(width: 48, height: 48)
                .shadow(color: Color.accentColor.opacity(0.3), radius: 6, y: 2)
                VStack(alignment: .leading, spacing: 3) {
                    Text(authStore.user?.username ?? "").font(.headline)
                    Text("Canopy account").font(.caption).foregroundStyle(.secondary)
                }
            }
            .padding(.vertical, 4)
        }
    }

    // MARK: - School
    private var schoolSection: some View {
        Section("School") {
            if let name = store.settings.schoolName, !name.isEmpty {
                LabeledContent("Name", value: name)
            } else {
                Text("No school configured")
                    .foregroundStyle(.secondary)
            }
            if let start = store.settings.semesterStart, !start.isEmpty {
                LabeledContent("Semester Start", value: start.dueDateLabel)
            }
            if let end = store.settings.semesterEnd, !end.isEmpty {
                LabeledContent("Semester End", value: end.dueDateLabel)
            }
            Button {
                showSchoolEditor = true
            } label: {
                Label("Edit School Info", systemImage: "pencil")
            }
            Button {
                showLunchEditor = true
            } label: {
                Label("Edit Lunch Times", systemImage: "fork.knife")
            }
        }
    }

    // MARK: - Manage
    private var manageSection: some View {
        Section("Manage") {
            NavigationLink {
                ManageClassesView()
            } label: {
                Label("Classes (\(store.classes.count))", systemImage: "books.vertical")
            }
            NavigationLink {
                ManageExamsView()
            } label: {
                Label("Exams (\(store.exams.count))", systemImage: "pencil.and.list.clipboard")
            }
            NavigationLink {
                ManageDisruptionsView()
            } label: {
                Label("Schedule Disruptions (\(store.disruptions.count))", systemImage: "calendar.badge.exclamationmark")
            }
        }
    }

    // MARK: - Appearance
    private var appearanceSection: some View {
        Section("Appearance") {
            Picker("Color Scheme", selection: $colorSchemeRaw) {
                Label("System", systemImage: "circle.lefthalf.filled").tag("system")
                Label("Light",  systemImage: "sun.max").tag("light")
                Label("Dark",   systemImage: "moon").tag("dark")
            }
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Label("Background", systemImage: "rectangle.inset.filled")
                    Spacer()
                    Text(backgroundOpacity < 0.15 ? "Translucent"
                         : backgroundOpacity < 0.45 ? "Subtle"
                         : backgroundOpacity < 0.75 ? "Medium"
                         : "Solid")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Slider(value: $backgroundOpacity, in: 0...1) {
                    EmptyView()
                } minimumValueLabel: {
                    Image(systemName: "sun.max")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                } maximumValueLabel: {
                    Image(systemName: "rectangle.fill")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
                .tint(.accentColor)
            }
            .padding(.vertical, 4)
        }
    }

    // MARK: - About
    private var aboutSection: some View {
        Section("About") {
            LabeledContent("App", value: "Canopy")
            LabeledContent("Version", value: Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0")
        }
    }

    // MARK: - Actions
    private var actionsSection: some View {
        Section {
            Button(action: performLogout) {
                Label("Sign Out", systemImage: "rectangle.portrait.and.arrow.right")
            }
            Button(role: .destructive, action: { showDeleteConfirm = true }) {
                Label("Delete Account", systemImage: "person.crop.circle.badge.minus")
            }
        } header: {
            Text("Account Actions")
        } footer: {
            Text("Deleting your account is permanent and cannot be undone.")
                .font(.caption)
        }
    }

    // MARK: - Actions
    private func performLogout() {
        Task { @MainActor in await authStore.logout() }
    }

    private func performDelete() {
        Task { @MainActor in try? await authStore.deleteAccount() }
    }
}

// MARK: - School Info Editor

struct SchoolInfoEditorSheet: View {
    @Environment(CanopyStore.self) private var store
    @Environment(\.dismiss) private var dismiss

    @State private var schoolName = ""
    @State private var semesterStart = Date.now
    @State private var semesterEnd = Date.now.addingTimeInterval(90 * 86400)
    @State private var hasStart = false
    @State private var hasEnd = false
    @State private var isSaving = false
    @State private var error: String?

    var body: some View {
        NavigationStack {
            List {
                Section("School Name") {
                    TextField("e.g. Lincoln High School", text: $schoolName)
                }
                Section("Semester") {
                    Toggle("Semester Start Date", isOn: $hasStart.animation())
                    if hasStart {
                        DatePicker("Start Date", selection: $semesterStart, displayedComponents: .date)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    Toggle("Semester End Date", isOn: $hasEnd.animation())
                    if hasEnd {
                        DatePicker("End Date", selection: $semesterEnd, displayedComponents: .date)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
                if let e = error {
                    Section {
                        Text(e)
                            .foregroundStyle(.red)
                            .font(.footnote)
                    }
                }
            }
            .insetGroupedListStyle()
            .background(CanopyBackground())
            .scrollContentBackground(.hidden)
            .navigationTitle("Edit School Info")
            .navigationBarTitleInline()
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button(isSaving ? "Saving…" : "Save") { Task { await save() } }
                        .fontWeight(.semibold)
                        .disabled(isSaving)
                }
            }
        }
        .onAppear { prefill() }
    }

    private func prefill() {
        schoolName = store.settings.schoolName ?? ""
        if let s = store.settings.semesterStart, !s.isEmpty, let d = s.asDate {
            hasStart = true; semesterStart = d
        }
        if let e = store.settings.semesterEnd, !e.isEmpty, let d = e.asDate {
            hasEnd = true; semesterEnd = d
        }
    }

    private func save() async {
        isSaving = true; defer { isSaving = false }
        do {
            try await store.saveSettings(
                schoolName: schoolName.isEmpty ? nil : schoolName,
                start: hasStart ? DateFormatter.iso.string(from: semesterStart) : nil,
                end: hasEnd ? DateFormatter.iso.string(from: semesterEnd) : nil
            )
            dismiss()
        } catch {
            self.error = error.localizedDescription
        }
    }
}

// MARK: - Lunch Times Editor

struct LunchTimesEditorSheet: View {
    @Environment(CanopyStore.self) private var store
    @Environment(\.dismiss) private var dismiss

    @State private var lunchTimes: [String: DayTime] = [:]
    @State private var isSaving = false
    @State private var error: String?

    private let days: [(String, String)] = [
        ("1", "Monday"), ("2", "Tuesday"), ("3", "Wednesday"),
        ("4", "Thursday"), ("5", "Friday")
    ]

    var body: some View {
        NavigationStack {
            List {
                Section {
                    ForEach(days, id: \.0) { key, dayName in
                        let binding = Binding<DayTime>(
                            get: { lunchTimes[key] ?? DayTime(startTime: "10:26", endTime: "10:57") },
                            set: { lunchTimes[key] = $0 }
                        )
                        HStack {
                            Text(dayName).font(.subheadline)
                            Spacer()
                            HStack(spacing: 4) {
                                DatePicker("Start", selection: Binding(
                                    get: { timeStringToDate(binding.wrappedValue.startTime) },
                                    set: { binding.wrappedValue.startTime = dateToTimeString($0) }
                                ), displayedComponents: .hourAndMinute)
                                .datePickerStyle(.compact)
                                .labelsHidden()
                                .fixedSize()

                                Text("–").foregroundStyle(.secondary)

                                DatePicker("End", selection: Binding(
                                    get: { timeStringToDate(binding.wrappedValue.endTime) },
                                    set: { binding.wrappedValue.endTime = dateToTimeString($0) }
                                ), displayedComponents: .hourAndMinute)
                                .datePickerStyle(.compact)
                                .labelsHidden()
                                .fixedSize()
                            }
                        }
                    }
                } header: {
                    Text("Lunch Schedule by Day")
                } footer: {
                    Text("Tap a time to adjust when lunch starts and ends each day.")
                }
            }
            .insetGroupedListStyle()
            .background(CanopyBackground())
            .scrollContentBackground(.hidden)
            .navigationTitle("Lunch Times")
            .navigationBarTitleInline()
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button(isSaving ? "Saving…" : "Save") { Task { await save() } }
                        .fontWeight(.semibold)
                        .disabled(isSaving)
                }
            }
        }
        .onAppear { prefill() }
    }

    private func timeStringToDate(_ time: String) -> Date {
        let parts = time.split(separator: ":").compactMap { Int($0) }
        var comps = Calendar.current.dateComponents([.year, .month, .day], from: .now)
        comps.hour = parts.first ?? 10
        comps.minute = parts.last ?? 0
        return Calendar.current.date(from: comps) ?? .now
    }

    private func dateToTimeString(_ date: Date) -> String {
        let cal = Calendar.current
        return String(format: "%02d:%02d",
                      cal.component(.hour, from: date),
                      cal.component(.minute, from: date))
    }

    private func prefill() {
        lunchTimes = store.settings.lunchTimes ?? AppSettings.defaultLunchTimes
    }

    private func save() async {
        isSaving = true; defer { isSaving = false }
        do {
            let encoder = JSONEncoder()
            if let data = try? encoder.encode(lunchTimes),
               let json = String(data: data, encoding: .utf8) {
                try await APIClient.shared.saveSetting(key: "lunchTimes", value: json)
                store.settings.lunchTimes = lunchTimes
            }
            dismiss()
        } catch {
            self.error = error.localizedDescription
        }
    }
}
