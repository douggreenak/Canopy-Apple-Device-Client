import SwiftUI

// Port of web src/app/settings/page.tsx. Web sections: Appearance, School,
// Bell Schedule, PowerSchool (+ Other Schools), Class Schedule, Calendar,
// Account. Sub-screens live in IntegrationSettingsViews / OtherSchoolsView /
// BellScheduleSettingsView; this file is the hub plus the inline editors.
struct SettingsView: View {
    @Environment(AuthStore.self) private var authStore
    @Environment(CanopyStore.self) private var store
    @Environment(\.colorScheme) private var systemScheme
    @Bindable private var nav = AppNavigation.shared

    @AppStorage("colorScheme") private var colorSchemeRaw = "system"
    @AppStorage("accentPreset") private var accentPresetRaw = AccentPalette.defaultAccent
    @AppStorage("backgroundOpacity") private var backgroundOpacity: Double = 0.75

    @State private var path: [SettingsRoute] = []
    @State private var showDeleteAccount = false
    @State private var showLunchEditor = false
    @State private var showChangePassword = false
    @State private var toast: ToastMessage?

    // Database health banner (web liveHealth)
    @State private var dbUnreachable = false
    @State private var dbError: String?
    @State private var retryingHealth = false

    // School Information autosave (web debouncedSaveSchool, 600 ms)
    @State private var schoolName = ""
    @State private var schoolSaveStatus: AutosaveStatus = .idle
    @State private var schoolSaveTask: Task<Void, Never>?
    @State private var schoolPrefilled = false

    enum SettingsRoute: Hashable {
        case powerschool, otherSchools, calendar, bellSchedule, timezone, classes, exams, disruptions
    }

    /// The scheme actually rendering, so accent swatches preview the right calibration.
    private var resolvedScheme: ColorScheme {
        switch colorSchemeRaw {
        case "light": return .light
        case "dark":  return .dark
        default:      return systemScheme
        }
    }

    var body: some View {
        NavigationStack(path: $path) {
            List {
                if dbUnreachable { databaseBanner }
                accountSection
                appearanceSection
                schoolSection
                bellScheduleSection
                integrationsSection
                manageSection
                aboutSection
                actionsSection
            }
            .insetGroupedListStyle()
            .background(CanopyBackground())
            .scrollContentBackground(.hidden)
            .navigationTitle("Settings")
            .navigationBarTitleInline()
            .iosHideNavigationBar()
            .navigationDestination(for: SettingsRoute.self) { route in
                switch route {
                case .powerschool:  PowerSchoolSettingsView()
                case .otherSchools: OtherSchoolsView()
                case .calendar:     CalendarExportView()
                case .bellSchedule: BellScheduleSettingsView()
                case .timezone:     TimezonePickerView(selection: timezoneBinding)
                case .classes:      ManageClassesView()
                case .exams:        ManageExamsView()
                case .disruptions:  ManageDisruptionsView()
                }
            }
            .sheet(isPresented: $showLunchEditor) {
                LunchTimesEditorSheet().presentationDetents([.large])
            }
            .sheet(isPresented: $showChangePassword) {
                ChangePasswordSheet { toast = ToastMessage(text: "Password changed successfully.", kind: .success) }
                    .presentationDetents([.medium, .large])
            }
            .sheet(isPresented: $showDeleteAccount) {
                DeleteAccountSheet().presentationDetents([.medium, .large])
            }
            .toast($toast)
        }
        .task { await checkHealth(force: false) }
        .onAppear { prefillSchool(); consumeSectionRequest() }
        .onChange(of: nav.settingsSection) { _, _ in consumeSectionRequest() }
        .onChange(of: store.settings.schoolName) { _, new in
            // Keep the field in step with server refreshes unless mid-edit.
            if schoolSaveStatus != .saving, schoolSaveTask == nil { schoolName = new ?? "" }
        }
    }

    // MARK: - Database status (web liveHealth alert)
    private var databaseBanner: some View {
        Section {
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: "externaldrive.badge.xmark").foregroundStyle(.red).font(.title3)
                VStack(alignment: .leading, spacing: 6) {
                    Text("\(Text("Database unreachable.").bold()) \(dbError ?? "Check that DATABASE_URL is set correctly.")")
                        .font(.subheadline)
                    Button(retryingHealth ? "Retrying…" : "Retry") { Task { await checkHealth(force: true) } }
                        .font(.caption.bold())
                        .disabled(retryingHealth)
                }
                Spacer(minLength: 0)
            }
            .padding(.vertical, 4)
            .listRowBackground(Color.red.opacity(0.12))
        }
    }

    // MARK: - Account header
    private var accountSection: some View {
        Section {
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
                    Text("Configure your school, appearance, and PowerSchool integration. Your data syncs across every device automatically.")
                        .font(.caption).foregroundStyle(.secondary)
                }
            }
            .padding(.vertical, 4)
        }
    }

    // MARK: - Appearance
    private var appearanceSection: some View {
        Section {
            Picker("Theme", selection: $colorSchemeRaw) {
                Label("Light",  systemImage: "sun.max").tag("light")
                Label("Dark",   systemImage: "moon").tag("dark")
                Label("System", systemImage: "circle.lefthalf.filled").tag("system")
            }
            .onChange(of: colorSchemeRaw) { _, new in
                Task { await store.saveAppearance(theme: new, accent: nil) }
            }

            VStack(alignment: .leading, spacing: 10) {
                Label("Accent Color", systemImage: "paintpalette")
                Text("Pick the accent color used for buttons, icons, and highlights throughout the app.")
                    .font(.caption).foregroundStyle(.secondary)
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 56), spacing: 10)], spacing: 12) {
                    ForEach(AccentPalette.presets) { preset in
                        let selected = AccentPalette.resolve(accentPresetRaw).name == preset.name
                        Button {
                            accentPresetRaw = preset.name
                            Task { await store.saveAppearance(theme: nil, accent: preset.name) }
                        } label: {
                            VStack(spacing: 4) {
                                Circle()
                                    .fill(preset.color(for: resolvedScheme))
                                    .frame(width: 38, height: 38)
                                    .overlay(
                                        Circle().strokeBorder(selected ? Color.primary : Color.clear, lineWidth: 3)
                                    )
                                    .scaleEffect(selected ? 1.0 : 0.94)
                                Text(preset.name)
                                    .font(.caption2.weight(selected ? .semibold : .regular))
                                    .foregroundStyle(selected ? .primary : .secondary)
                            }
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel(preset.name)
                        .accessibilityAddTraits(selected ? .isSelected : [])
                    }
                }
                .animation(.spring(response: 0.25, dampingFraction: 0.7), value: accentPresetRaw)
            }
            .padding(.vertical, 4)

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
                    Image(systemName: "sun.max").font(.caption2).foregroundStyle(.secondary)
                } maximumValueLabel: {
                    Image(systemName: "rectangle.fill").font(.caption2).foregroundStyle(.secondary)
                }
                .tint(.accentColor)
            }
            .padding(.vertical, 4)

            Button {
                nav.showKeyboardShortcuts = true
            } label: {
                Label("Show keyboard shortcuts", systemImage: "keyboard")
            }
        } header: {
            Text("Appearance")
        } footer: {
            Text("Theme mode — System follows your device preference.")
        }
    }

    // MARK: - School Information
    private var schoolSection: some View {
        Section {
            TextField("School Name", text: $schoolName, prompt: Text("e.g., Lincoln High School"))
                .onChange(of: schoolName) { old, new in
                    guard schoolPrefilled, old != new else { return }
                    scheduleSchoolSave()
                }
            NavigationLink(value: SettingsRoute.timezone) {
                VStack(alignment: .leading, spacing: 3) {
                    HStack {
                        Label("Timezone", systemImage: "globe")
                        Spacer()
                        Text(TimezonePickerView.displayLabel(store.settings.timezone ?? TimeZone.current.identifier))
                            .font(.caption).foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                    Text("Used for calendar feed events — auto-detected from your device")
                        .font(.caption).foregroundStyle(.secondary)
                }
            }
            VStack(alignment: .leading, spacing: 8) {
                Text("Your Dashboard and Schedule treat school as in session every day, all year — there's no semester range to set. Add exceptions like summer or winter break below.")
                    .font(.caption).foregroundStyle(.secondary)
                Button {
                    nav.goToSchedule()
                } label: {
                    Label("Manage School Breaks", systemImage: "calendar.badge.exclamationmark")
                }
                Text("Add summer break, winter break, holidays, and other days off from the Disruptions calendar on the Schedule page — set an end date to cover a whole range at once.")
                    .font(.caption2).foregroundStyle(.tertiary)
            }
            .padding(.vertical, 2)
            Button {
                NotificationCenter.default.post(name: .openSetupWizard, object: nil)
            } label: {
                Label("Re-run Setup Wizard", systemImage: "wand.and.stars")
            }
        } header: {
            HStack {
                Text("School Information")
                Spacer()
                InlineSaveIndicator(status: schoolSaveStatus)
            }
        }
    }

    private var timezoneBinding: Binding<String> {
        Binding(
            get: { store.settings.timezone ?? TimeZone.current.identifier },
            set: { tz in
                Task {
                    schoolSaveStatus = .saving
                    do {
                        try await store.saveSchoolInfo(schoolName: nil, timezone: tz)
                        markSchoolSaved()
                    } catch { schoolSaveStatus = .error }
                }
            }
        )
    }

    // MARK: - Bell schedule
    private var bellScheduleSection: some View {
        Section("Bell Schedule") {
            NavigationLink(value: SettingsRoute.bellSchedule) {
                HStack {
                    Label("Bell Schedule", systemImage: "bell")
                    Spacer()
                    Text(store.settings.lathropEnabled ? "Lathrop Mode" : "Custom")
                        .font(.caption).foregroundStyle(.secondary)
                }
            }
            Button {
                showLunchEditor = true
            } label: {
                Label("Lunch Times", systemImage: "fork.knife")
            }
        }
    }

    // MARK: - Integrations (PowerSchool, other schools, calendar)
    private var integrationsSection: some View {
        Section("Integrations") {
            NavigationLink(value: SettingsRoute.powerschool) {
                HStack {
                    Label("PowerSchool", systemImage: "arrow.triangle.2.circlepath")
                    Spacer()
                    if store.isSyncing {
                        ProgressView().controlSize(.small)
                    } else {
                        Text((store.setupStatus?.hasPowerschool ?? false) ? "Connected" : "Set up")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                }
            }
            NavigationLink(value: SettingsRoute.otherSchools) {
                HStack {
                    Label("Other Schools", systemImage: "graduationcap")
                    Spacer()
                    if !store.schoolAccounts.isEmpty {
                        Text("\(store.schoolAccounts.count)").font(.caption).foregroundStyle(.secondary)
                    } else {
                        Text("Optional").font(.caption).foregroundStyle(.secondary)
                    }
                }
            }
            NavigationLink(value: SettingsRoute.calendar) {
                Label("Calendar Feed (iCal)", systemImage: "calendar.badge.plus")
            }
        }
    }

    // MARK: - Manage
    private var manageSection: some View {
        Section("Manage") {
            NavigationLink(value: SettingsRoute.classes) {
                Label("Classes (\(store.classes.count))", systemImage: "books.vertical")
            }
            NavigationLink(value: SettingsRoute.exams) {
                Label("Exams (\(store.exams.count))", systemImage: "pencil.and.list.clipboard")
            }
            NavigationLink(value: SettingsRoute.disruptions) {
                Label("Schedule Disruptions (\(store.disruptions.count))", systemImage: "calendar.badge.exclamationmark")
            }
        }
    }

    // MARK: - About
    private var aboutSection: some View {
        Section("About") {
            LabeledContent("App", value: "Canopy")
            LabeledContent("Version", value: Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0")
        }
    }

    // MARK: - Account actions
    private var actionsSection: some View {
        Section {
            Button { showChangePassword = true } label: {
                Label("Change Password", systemImage: "key")
            }
            Button(action: performLogout) {
                Label("Sign Out", systemImage: "rectangle.portrait.and.arrow.right")
            }
            Button(role: .destructive, action: { showDeleteAccount = true }) {
                Label("Delete My Account", systemImage: "person.crop.circle.badge.minus")
            }
        } header: {
            Text("Account")
        } footer: {
            Text("Permanently delete your account and all associated data — classes, grades, homework, tasks, and settings. This cannot be undone.")
                .font(.caption)
        }
    }

    // MARK: - Logic

    private func consumeSectionRequest() {
        guard let section = nav.settingsSection else { return }
        nav.settingsSection = nil
        switch section {
        case "powerschool":   path = [.powerschool]
        case "calendar":      path = [.calendar]
        case "bell":          path = [.bellSchedule]
        case "other-schools": path = [.otherSchools]
        default: break
        }
    }

    private func checkHealth(force: Bool) async {
        retryingHealth = force
        defer { retryingHealth = false }
        guard let h = try? await APIClient.shared.getHealth(force: force) else { return }
        dbUnreachable = !h.ok
        dbError = h.error
    }

    private func prefillSchool() {
        guard !schoolPrefilled else { return }
        schoolName = store.settings.schoolName ?? ""
        // Defer the flag a beat so the initial assignment doesn't trigger a save.
        DispatchQueue.main.async { schoolPrefilled = true }
    }

    private func scheduleSchoolSave() {
        schoolSaveTask?.cancel()
        schoolSaveStatus = .saving
        let value = schoolName
        schoolSaveTask = Task {
            try? await Task.sleep(nanoseconds: 600_000_000)
            guard !Task.isCancelled else { return }
            do {
                try await store.saveSchoolInfo(schoolName: value, timezone: nil)
                markSchoolSaved()
            } catch {
                schoolSaveStatus = .error
            }
            schoolSaveTask = nil
        }
    }

    private func markSchoolSaved() {
        schoolSaveStatus = .saved
        Task {
            try? await Task.sleep(nanoseconds: 2_000_000_000)
            if schoolSaveStatus == .saved { schoolSaveStatus = .idle }
        }
    }

    private func performLogout() {
        Task { @MainActor in await authStore.logout() }
    }
}

// MARK: - Change Password (web Account → Change Password)

struct ChangePasswordSheet: View {
    @Environment(AuthStore.self) private var authStore
    @Environment(\.dismiss) private var dismiss
    var onSuccess: () -> Void = {}

    @State private var current = ""
    @State private var new = ""
    @State private var confirm = ""
    @State private var showCurrent = false
    @State private var showNew = false
    @State private var isSaving = false
    @State private var error: String?

    private var mismatch: Bool { !confirm.isEmpty && confirm != new }
    private var canSave: Bool { !current.isEmpty && !new.isEmpty && new == confirm && !isSaving }

    var body: some View {
        NavigationStack {
            List {
                Section("Current Password") {
                    PasswordField("Current Password", text: $current, isRevealed: $showCurrent)
                        .textContentType(.password)
                }
                Section {
                    PasswordField("New Password", text: $new, isRevealed: $showNew)
                        .textContentType(.newPassword)
                    // Web shares the "show" state between New and Confirm.
                    Group {
                        if showNew { TextField("Confirm New Password", text: $confirm).textAutocapNever().autocorrectionDisabled() }
                        else { SecureField("Confirm New Password", text: $confirm) }
                    }
                    .textContentType(.newPassword)
                } header: {
                    Text("New Password")
                } footer: {
                    if mismatch {
                        Text("Passwords do not match").foregroundStyle(.red)
                    }
                }
                if let error {
                    Section { Text(error).foregroundStyle(.red).font(.footnote) }
                }
            }
            .insetGroupedListStyle()
            .background(CanopyBackground())
            .scrollContentBackground(.hidden)
            .navigationTitle("Change Password")
            .navigationBarTitleInline()
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button(isSaving ? "Saving…" : "Change Password") { Task { await save() } }
                        .fontWeight(.semibold)
                        .disabled(!canSave)
                }
            }
        }
    }

    private func save() async {
        error = nil
        guard new == confirm else { error = "New passwords do not match."; return }
        isSaving = true; defer { isSaving = false }
        do {
            try await authStore.changePassword(current: current, new: new)
            onSuccess()
            dismiss()
        } catch {
            self.error = error.localizedDescription
        }
    }
}

// MARK: - Delete account (web "Delete account?" dialog)

struct DeleteAccountSheet: View {
    @Environment(AuthStore.self) private var authStore
    @Environment(\.dismiss) private var dismiss

    @State private var password = ""
    @State private var showPassword = false
    @State private var confirmText = ""
    @State private var deleting = false
    @State private var error: String?

    private var canDelete: Bool { !deleting && confirmText == "DELETE" && !password.isEmpty }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    Text("This will permanently erase your account and every piece of data stored in Canopy — classes, grades, homework, tasks, and settings. This cannot be undone.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                Section {
                    PasswordField("Enter your password", text: $password, isRevealed: $showPassword)
                        .textContentType(.password)
                    TextField("Type \"DELETE\" to confirm", text: $confirmText)
                        .textAutocapNever()
                        .autocorrectionDisabled()
                }
                if let error {
                    Section { Text(error).foregroundStyle(.red).font(.footnote) }
                }
                Section {
                    Button(role: .destructive) {
                        Task { await performDelete() }
                    } label: {
                        HStack {
                            Spacer()
                            if deleting { ProgressView().controlSize(.small) }
                            Label(deleting ? "Deleting…" : "Delete Forever", systemImage: "trash.fill")
                                .fontWeight(.semibold)
                            Spacer()
                        }
                    }
                    .disabled(!canDelete)
                }
            }
            .insetGroupedListStyle()
            .background(CanopyBackground())
            .scrollContentBackground(.hidden)
            .navigationTitle("Delete account?")
            .navigationBarTitleInline()
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
            }
        }
    }

    private func performDelete() async {
        deleting = true; defer { deleting = false }
        error = nil
        do {
            try await authStore.deleteAccount(password: password)
            dismiss()
        } catch {
            self.error = error.localizedDescription
        }
    }
}

// MARK: - Lunch Times Editor (web Class Schedule → Lunch Times)

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
                    Text("Lunch Times")
                } footer: {
                    Text("Set when lunch starts and ends each day. Lunch is shown on your schedule and skipped when it overlaps a class.")
                }
                if let error {
                    Section { Text(error).foregroundStyle(.red).font(.footnote) }
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
        comps.minute = parts.count > 1 ? parts[1] : 0
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
            try await store.saveLunchTimes(lunchTimes)
            dismiss()
        } catch {
            self.error = error.localizedDescription
        }
    }
}
