import SwiftUI

// MARK: - Cross-platform clipboard

enum Clipboard {
    static func copy(_ text: String) {
        #if os(macOS)
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
        #else
        UIPasteboard.general.string = text
        #endif
    }
}

// MARK: - PowerSchool Import (web Settings "PowerSchool Import" section)
//
// The server runs syncs in the background: Sync Now kicks one off and this
// screen waits on PowerSchoolSyncStore for the terminal status. A sync that
// is already running when the screen opens (another device, the daily cron)
// is resumed rather than left looking idle.
struct PowerSchoolSettingsView: View {
    @Environment(CanopyStore.self) private var store
    @Environment(\.colorScheme) private var scheme
    private var syncStore = PowerSchoolSyncStore.shared

    @State private var url = ""
    @State private var username = ""
    @State private var password = ""
    @State private var showPassword = false
    @State private var saveStatus: AutosaveStatus = .idle
    @State private var syncing = false
    @State private var showLog = false
    @State private var showClearConfirm = false
    @State private var showSyncReminder = false
    @State private var toast: ToastMessage?

    // Scheduled Sync toggle state (shared component with the reminder sheet)
    @State private var autoSync = true
    @State private var showTurnOffConfirm = false
    @State private var autoSyncError: String?

    init() {}

    private var hasSaved: Bool { store.setupStatus?.hasPowerschool ?? false }
    private var fieldsFilled: Bool { !url.isEmpty && !username.isEmpty && !password.isEmpty }
    private var isSyncing: Bool { syncing || store.isSyncing }

    var body: some View {
        List {
            headerSection
            credentialsSection
            optionsSection
            actionsSection
            if !store.lastSyncLog.isEmpty { logSection }
            Section {
                Text("Canopy is an independent, unofficial tool and isn't affiliated with or endorsed by PowerSchool. You connect your account at your own risk — use of your credentials here is your own responsibility.")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
                    .listRowBackground(Color.clear)
            }
        }
        .insetGroupedListStyle()
        .background(CanopyBackground())
        .scrollContentBackground(.hidden)
        .navigationTitle("PowerSchool")
        .navigationBarTitleInline()
        .onAppear {
            syncStore.subscribe()
            autoSync = store.settings.autoSyncEnabled
        }
        .onDisappear { syncStore.unsubscribe() }
        .task { await loadStatus(); await resumeIfRunning() }
        .onChange(of: store.settings.autoSyncEnabled) { _, v in autoSync = v }
        .alert("Clear Saved Login?", isPresented: $showClearConfirm) {
            Button("Clear", role: .destructive) { Task { await clearCredentials() } }
            Button("Cancel", role: .cancel) { }
        } message: {
            Text("This removes your saved PowerSchool credentials. You can reconnect anytime from this screen.")
        }
        .sheet(isPresented: $showSyncReminder) {
            SyncReminderSheet { Task { await syncNow() } }
        }
        .toast($toast)
    }

    // MARK: Sections

    private var headerSection: some View {
        Section {
            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 8) {
                    Image(systemName: "arrow.triangle.2.circlepath").foregroundStyle(Color.accentColor)
                    Text("PowerSchool Import").font(.headline)
                    OutlinedChip(text: "Optional")
                    if hasSaved {
                        TintedChip(text: "Login saved", systemImage: "checkmark.circle.fill", color: CanopyPalette.success(scheme))
                    }
                    Spacer(minLength: 0)
                    InlineSaveIndicator(status: saveStatus)
                }
                PowerSchoolLoginWarningBanner(onFix: {})
                Text("Import your class schedule, assignments, and current grades from PowerSchool. Log in once — future imports reuse the saved credentials so you can sync with a single click.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            .padding(.vertical, 4)
        }
    }

    private var credentialsSection: some View {
        Section {
            VStack(alignment: .leading, spacing: 4) {
                TextField("PowerSchool URL", text: $url, prompt: Text("https://your-school.powerschool.com"))
                    .textAutocapNever()
                    .autocorrectionDisabled()
                    #if os(iOS)
                    .keyboardType(.URL)
                    #endif
                Text("Any URL from your school's PowerSchool portal — the domain will be extracted automatically")
                    .font(.caption).foregroundStyle(.secondary)
            }
            TextField("Student Username", text: $username)
                .textAutocapNever()
                .autocorrectionDisabled()
            VStack(alignment: .leading, spacing: 4) {
                PasswordField(hasSaved ? "Password (leave blank to use saved)" : "Student Password",
                              text: $password, isRevealed: $showPassword)
                Text(hasSaved
                     ? "Leave blank to reuse the saved password, or type a new one to update."
                     : "Saved securely on the server after your first import.")
                    .font(.caption).foregroundStyle(.secondary)
            }
        } header: {
            Text("PowerSchool Login")
        }
    }

    private var optionsSection: some View {
        Section {
            Toggle(isOn: Binding(
                get: { store.settings.lathropEnabled },
                set: { on in Task { if let msg = await store.saveLathropMode(on) { toast = ToastMessage(text: msg, kind: .success) } } }
            )) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Lathrop Mode")
                    Text("Automatically apply the Lathrop HS bell schedule after every sync")
                        .font(.caption).foregroundStyle(.secondary)
                }
            }

            ScheduledSyncToggle(
                autoSync: $autoSync,
                showTurnOffConfirm: $showTurnOffConfirm,
                saveError: $autoSyncError,
                caption: "Automatically sync PowerSchool once a day around 4 AM Alaska time. The UTC schedule shifts by an hour during standard time."
                    + (hasSaved ? "" : " Save a PowerSchool login above first."),
                disabled: !hasSaved
            )
            if let autoSyncError {
                Text(autoSyncError).font(.caption).foregroundStyle(.red)
            }
        } header: {
            Text("Options")
        }
    }

    private var actionsSection: some View {
        Section {
            Button {
                Task { await saveCredentials() }
            } label: {
                Label(saveStatus == .saving ? "Saving…" : "Save Login", systemImage: "lock.shield")
            }
            .disabled(saveStatus == .saving || !fieldsFilled)

            Button {
                if hasSaved { showSyncReminder = true } else { Task { await syncNow() } }
            } label: {
                HStack {
                    Label(isSyncing ? "Syncing…" : hasSaved ? "Sync Now" : "Import from PowerSchool",
                          systemImage: "arrow.triangle.2.circlepath")
                    Spacer()
                    if isSyncing { ProgressView().controlSize(.small) }
                }
            }
            .disabled(isSyncing || (!hasSaved && !fieldsFilled))

            if hasSaved {
                Button(role: .destructive) {
                    showClearConfirm = true
                } label: {
                    Label("Clear Saved Login", systemImage: "trash")
                }
                .disabled(isSyncing)
            }
        } footer: {
            if let last = store.settings.lastSyncAt, let d = CanopyStore.parseISO(last) {
                Text("Last synced \(d.formatted(.relative(presentation: .named)))")
            } else {
                Text("Pull your classes, assignments, and grades from PowerSchool.")
            }
        }
    }

    private var logSection: some View {
        Section {
            DisclosureGroup("Import Log (\(store.lastSyncLog.count) entries)", isExpanded: $showLog) {
                ForEach(Array(store.lastSyncLog.enumerated()), id: \.offset) { _, line in
                    Text(line)
                        .font(.caption.monospaced())
                        .foregroundStyle(.secondary)
                        .textSelection(.enabled)
                }
            }
        }
    }

    // MARK: Actions

    private func loadStatus() async {
        await store.refreshSetupStatus()
        if let s = store.setupStatus {
            if url.isEmpty { url = s.powerschoolUrl }
            if username.isEmpty { username = s.powerschoolUsername }
        }
    }

    /// Web: if a sync is already running when the page loads, resume
    /// watching it instead of leaving the Sync button looking idle.
    private func resumeIfRunning() async {
        let s = await syncStore.fetchNow()
        guard s.isRunning else { return }
        syncing = true
        if let final = await store.resumeSyncIfRunning() {
            announce(final)
        }
        syncing = false
    }

    private func saveCredentials() async {
        saveStatus = .saving
        do {
            try await APIClient.shared.savePowerSchool(url: url, username: username, password: password)
            await store.refreshSetupStatus()
            password = ""
            saveStatus = .saved
            try? await Task.sleep(nanoseconds: 2_000_000_000)
            if saveStatus == .saved { saveStatus = .idle }
        } catch {
            saveStatus = .error
            toast = ToastMessage(text: error.localizedDescription, kind: .error)
        }
    }

    private func clearCredentials() async {
        do {
            try await APIClient.shared.clearPowerSchool()
            url = ""; username = ""; password = ""
            await store.refreshSetupStatus()
            toast = ToastMessage(text: "Saved PowerSchool login cleared.", kind: .info)
        } catch {
            toast = ToastMessage(text: "Failed to clear saved login.", kind: .error)
        }
    }

    private func syncNow() async {
        syncing = true
        defer { syncing = false }
        showLog = false
        do {
            // Typed password → one-off credentials; blank → the saved login.
            let oneOff = !password.isEmpty
            let status = try await store.syncPowerSchool(
                url: oneOff ? url : nil,
                username: oneOff ? username : nil,
                password: oneOff ? password : nil
            )
            announce(status)
        } catch {
            toast = ToastMessage(text: "Connection error: \(error.localizedDescription)", kind: .error)
        }
    }

    /// Web `handleSyncOutcome` snackbar copy.
    private func announce(_ status: PowerSchoolStatus) {
        switch status.status {
        case "success":
            toast = ToastMessage(text: status.result?.settingsSummary ?? "PowerSchool sync complete.", kind: .success)
        case "error":
            toast = ToastMessage(text: status.error ?? "PowerSchool import failed", kind: .error)
            showLog = true
        default:
            toast = ToastMessage(text: "Still syncing in the background — check back in a bit, or reload to see the latest status.", kind: .info)
        }
    }
}

// MARK: - Calendar Feed (iCal)

struct CalendarExportView: View {
    @Environment(AuthStore.self) private var authStore
    @Environment(CanopyStore.self) private var store
    @Environment(\.openURL) private var openURL
    @State private var feedURL = ""
    @State private var regenerating = false
    @State private var showRegenerateConfirm = false
    @State private var toast: ToastMessage?

    private var webcalURL: URL? {
        guard !feedURL.isEmpty else { return nil }
        return URL(string: feedURL.replacingOccurrences(of: "^https?://", with: "webcal://", options: .regularExpression))
    }

    var body: some View {
        List {
            Section {
                Text("Subscribe once and your schedule, exams, and homework stay up to date automatically — including cancellations and schedule changes. This link is unique to your account.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }

            Section {
                Button {
                    if let u = webcalURL { openURL(u) }
                } label: {
                    Label("Subscribe in Calendar App", systemImage: "calendar.badge.plus")
                }
                .disabled(webcalURL == nil)
            } footer: {
                Text("Opens your device's default calendar app (Apple Calendar, Google Calendar, Outlook) and subscribes automatically.")
            }

            Section {
                if feedURL.isEmpty {
                    HStack { ProgressView(); Text("Loading…").foregroundStyle(.secondary) }
                } else {
                    Text(feedURL)
                        .font(.caption.monospaced())
                        .textSelection(.enabled)
                        .lineLimit(4)
                    Button {
                        Clipboard.copy(feedURL)
                        toast = ToastMessage(text: "Calendar URL copied to clipboard!", kind: .success)
                    } label: {
                        Label("Copy", systemImage: "doc.on.doc")
                    }
                }
            } header: {
                Text("Or copy the URL manually")
            }

            Section {
                instructionRow(app: "Google Calendar", steps: "Settings → \"Add calendar\" → \"From URL\" → paste")
                instructionRow(app: "Apple Calendar", steps: "File → \"New Calendar Subscription\" → paste")
                instructionRow(app: "Outlook", steps: "\"Add calendar\" → \"Subscribe from web\" → paste")
            } header: {
                Text("Instructions")
            }

            Section {
                Button(role: .destructive) {
                    showRegenerateConfirm = true
                } label: {
                    Label(regenerating ? "Regenerating…" : "Regenerate link (invalidates old one)", systemImage: "arrow.triangle.2.circlepath")
                }
                .disabled(regenerating || feedURL.isEmpty)
            } footer: {
                Text("Keep this link private — anyone with it can read your schedule.")
            }
        }
        .insetGroupedListStyle()
        .background(CanopyBackground())
        .scrollContentBackground(.hidden)
        .navigationTitle("Calendar Feed (iCal)")
        .navigationBarTitleInline()
        .task { await loadFeedURL(regenerate: false) }
        .alert("Regenerate Calendar Link?", isPresented: $showRegenerateConfirm) {
            Button("Regenerate", role: .destructive) { Task { await loadFeedURL(regenerate: true) } }
            Button("Cancel", role: .cancel) { }
        } message: {
            Text("The current link will stop working immediately — update any calendar subscriptions using it.")
        }
        .toast($toast)
    }

    private func instructionRow(app: String, steps: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(app).font(.subheadline.weight(.semibold))
            Text(steps).font(.caption).foregroundStyle(.secondary)
        }
    }

    private func loadFeedURL(regenerate: Bool) async {
        if regenerate { regenerating = true }
        let token = regenerate ? await store.regenerateCalendarToken() : await store.ensureCalendarToken()
        if let uid = authStore.user?.id {
            feedURL = "\(APIClient.shared.baseURL)/api/calendar?userId=\(uid)&token=\(token)"
        }
        if regenerate { regenerating = false }
    }
}
