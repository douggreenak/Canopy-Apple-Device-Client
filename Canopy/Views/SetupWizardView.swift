import SwiftUI

/// Global re-trigger signal — Settings posts this to reopen the wizard from
/// anywhere, mirroring web's `window.dispatchEvent(new Event('open-setup-wizard'))`.
extension Notification.Name {
    static let openSetupWizard = Notification.Name("open-setup-wizard")
}

// Port of web src/components/SetupWizard.tsx — steps: Welcome, Bell Schedule,
// PowerSchool, School Info, Done. PowerSchool runs verify-then-background-
// sync: a fast login check, then the real sync is kicked off and NOT awaited;
// the Done step shows its live status from PowerSchoolSyncStore.
struct SetupWizardView: View {
    /// Required on first registration: no close button, cannot be dismissed
    /// except by finishing (or explicitly skipping) each step.
    let required: Bool

    @Environment(CanopyStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var scheme
    @AppStorage("sp-wizard-dismissed") private var wizardDismissed = false
    private var syncStore = PowerSchoolSyncStore.shared

    init(required: Bool) { self.required = required }

    enum WizardStep: Int, CaseIterable {
        case welcome, bellSchedule, powerSchool, schoolInfo, done
        var title: String {
            switch self {
            case .welcome: return "Welcome"
            case .bellSchedule: return "Bell Schedule"
            case .powerSchool: return "PowerSchool"
            case .schoolInfo: return "School Info"
            case .done: return "Done"
            }
        }
    }

    struct SchoolBreak: Identifiable, Equatable {
        let id: String
        var label: String
        var start: String
        var end: String
    }

    @State private var step: WizardStep = .welcome
    @State private var error: String?

    // Bell Schedule (mandatory choice)
    @State private var lathropChoice: Bool?
    @State private var savingLathropChoice = false
    /// Backs the Done step's manual-setup nudge; server default is ON.
    @State private var manualLathropEnabled = true

    // PowerSchool
    @State private var psURL = ""
    @State private var psUsername = ""
    @State private var psPassword = ""
    @State private var showPSPassword = false
    @State private var psLog: [String] = []
    @State private var showPSLog = false
    @State private var verifying = false
    @State private var busy = false
    @State private var confirmSkipPS = false
    @State private var declinedPowerSchool = false
    /// True once THIS wizard run kicked off a background sync — gates the
    /// Done step's live banner so a stale earlier status never shows.
    @State private var syncStarted = false
    @State private var handledOutcome = false

    // School Info
    @State private var schoolName = ""
    @State private var timezone = TimeZone.current.identifier
    @State private var breaks: [SchoolBreak] = []
    @State private var breakLabel = ""
    @State private var breakStart = Calendar.current.startOfDay(for: .now)
    @State private var breakEnd = Calendar.current.startOfDay(for: .now)

    private var psFieldsFilled: Bool {
        !psURL.trimmingCharacters(in: .whitespaces).isEmpty
        && !psUsername.trimmingCharacters(in: .whitespaces).isEmpty
        && !psPassword.trimmingCharacters(in: .whitespaces).isEmpty
    }

    var body: some View {
        NavigationStack {
            ZStack {
                CanopyBackground()
                VStack(spacing: 0) {
                    header
                    ScrollView {
                        VStack(spacing: 20) {
                            if let error { errorBanner(error) }
                            switch step {
                            case .welcome:      welcomeStep
                            case .bellSchedule: bellScheduleStep
                            case .powerSchool:  powerSchoolStep
                            case .schoolInfo:   schoolInfoStep
                            case .done:         doneStep
                            }
                        }
                        .padding(20)
                        .padding(.bottom, 24)
                        .frame(maxWidth: 640)
                        .frame(maxWidth: .infinity)
                    }
                }
            }
            .navigationBarTitleInline()
            .toolbar {
                if !required {
                    ToolbarItem(placement: .cancellationAction) {
                        Button { finish() } label: { Image(systemName: "xmark") }
                            .accessibilityLabel("Close")
                    }
                }
            }
        }
        .interactiveDismissDisabled(required)
        .onAppear {
            syncStore.subscribe()
            manualLathropEnabled = store.settings.lathropEnabled
            if schoolName.isEmpty { schoolName = store.settings.schoolName ?? "" }
            if let tz = store.settings.timezone, !tz.isEmpty { timezone = tz }
        }
        .onDisappear { syncStore.unsubscribe() }
        .onChange(of: breakStart) { _, new in if breakEnd < new { breakEnd = new } }
        .task(id: syncStore.status.status) {
            // Web: handleSyncOutcome once the background sync reaches success.
            guard syncStarted, !handledOutcome, syncStore.status.status == "success" else { return }
            handledOutcome = true
            await store.handleSyncOutcome(syncStore.status)
        }
    }

    // MARK: - Header
    private var header: some View {
        VStack(spacing: 8) {
            HStack(spacing: 8) {
                Image(systemName: "building.columns.fill").foregroundStyle(Color.accentColor)
                Text("Setup Wizard").font(.headline)
                Spacer()
                Text("Step \(step.rawValue + 1) of \(WizardStep.allCases.count)")
                    .font(.caption).foregroundStyle(.secondary)
            }
            HStack {
                Text(step.title).font(.subheadline.weight(.semibold))
                Spacer()
            }
            ProgressView(value: Double(step.rawValue + 1), total: Double(WizardStep.allCases.count))
                .tint(Color.accentColor)
        }
        .padding(.horizontal, 20).padding(.top, 16).padding(.bottom, 12)
        .background(.ultraThinMaterial)
        .animation(.easeInOut(duration: 0.2), value: step)
    }

    private func errorBanner(_ text: String) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.red)
            Text(text).font(.subheadline)
            Spacer(minLength: 0)
            Button { error = nil } label: { Image(systemName: "xmark").font(.caption.bold()).foregroundStyle(.secondary) }
                .buttonStyle(.plain)
                .accessibilityLabel("Dismiss")
        }
        .padding(12)
        .background(Color.red.opacity(0.12), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
    }

    // MARK: - Step 0: Welcome
    private var welcomeStep: some View {
        VStack(spacing: 16) {
            CanopyIconView(size: 84)
            Text("Welcome to Canopy!").font(.title2.bold()).fontDesign(.rounded)
            Text("Your data is securely stored and synced across all your devices. We'll start by connecting PowerSchool (it does most of the setup for you), then fill in a few school details.")
                .font(.subheadline).foregroundStyle(.secondary).multilineTextAlignment(.center)

            primaryButton("Get Started", systemImage: "arrow.right") { go(.bellSchedule) }

            if !required {
                Button("Skip — I'll set up in Settings") { finish() }
                    .font(.subheadline).foregroundStyle(.secondary)
            }
        }
        .padding(.top, 12)
    }

    // MARK: - Step 1: Bell Schedule (Lathrop Mode)
    private var bellScheduleStep: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Bell Schedule").font(.title3.bold()).fontDesign(.rounded)
            Text("If your school follows Lathrop High School's bell schedule, Canopy can fill in each class's period times automatically — after every PowerSchool sync, and with a one-click button when setting up classes manually. Otherwise, you'll set your own period times from the Classes/Settings pages.")
                .font(.subheadline).foregroundStyle(.secondary)

            VStack(spacing: 10) {
                choiceButton("Use Lathrop Mode", selected: lathropChoice == true) { lathropChoice = true }
                choiceButton("My school is different", selected: lathropChoice == false) { lathropChoice = false }
            }

            primaryButton(savingLathropChoice ? "Saving…" : "Continue", systemImage: "arrow.right") {
                Task { await confirmLathropChoice() }
            }
            .disabled(lathropChoice == nil || savingLathropChoice)

            HStack {
                Button("Back") { go(.welcome) }.disabled(savingLathropChoice)
                Spacer()
            }
            .font(.subheadline).foregroundStyle(.secondary)
        }
    }

    private func choiceButton(_ title: String, selected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 8) {
                if selected { Image(systemName: "checkmark.circle.fill") }
                Text(title).font(.headline)
            }
            .frame(maxWidth: .infinity).frame(height: 50)
            .foregroundStyle(selected ? Color.white : Color.accentColor)
            .background(selected ? Color.accentColor : Color.clear, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(Color.accentColor, lineWidth: selected ? 0 : 1.5))
        }
        .buttonStyle(.plain)
        .animation(.easeInOut(duration: 0.15), value: selected)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }

    // MARK: - Step 2: PowerSchool
    @ViewBuilder
    private var powerSchoolStep: some View {
        if confirmSkipPS {
            skipConfirmation
        } else {
            VStack(alignment: .leading, spacing: 16) {
                HStack(spacing: 8) {
                    Image(systemName: "arrow.triangle.2.circlepath").foregroundStyle(Color.accentColor)
                    Text("Connect PowerSchool").font(.title3.bold()).fontDesign(.rounded)
                }
                Text("This is the fastest way to set up Canopy — it imports your classes and schedule automatically, keeps your grades in sync, and unlocks grade analytics (velocity alerts, missing-work triage, what-if calculator). Credentials are saved securely so future syncs need just one click.")
                    .font(.subheadline).foregroundStyle(.secondary)

                FormEditCard {
                    VStack(spacing: 0) {
                        VStack(alignment: .leading, spacing: 4) {
                            TextField("PowerSchool URL", text: $psURL, prompt: Text("https://your-school.powerschool.com"))
                                .textAutocapNever()
                                .autocorrectionDisabled()
                                #if os(iOS)
                                .keyboardType(.URL)
                                #endif
                                .onChange(of: psURL) { _, _ in error = nil }
                            Text("Any URL from your school's PowerSchool portal").font(.caption).foregroundStyle(.secondary)
                        }
                        .padding(.horizontal, 16).padding(.vertical, 13)
                        Divider().padding(.leading, 16)
                        VStack(alignment: .leading, spacing: 4) {
                            TextField("Student Username", text: $psUsername)
                                .textAutocapNever()
                                .autocorrectionDisabled()
                                .onChange(of: psUsername) { _, _ in error = nil }
                            Text("e.g. s123456").font(.caption).foregroundStyle(.secondary)
                        }
                        .padding(.horizontal, 16).padding(.vertical, 13)
                        Divider().padding(.leading, 16)
                        PasswordField("Student Password", text: $psPassword, isRevealed: $showPSPassword)
                            .textContentType(.password)
                            .onChange(of: psPassword) { _, _ in error = nil }
                            .padding(.horizontal, 16).padding(.vertical, 13)
                    }
                }

                if !psLog.isEmpty {
                    DisclosureGroup("Login log (\(psLog.count) entries)", isExpanded: $showPSLog) {
                        ScrollView {
                            VStack(alignment: .leading, spacing: 3) {
                                ForEach(Array(psLog.enumerated()), id: \.offset) { _, line in
                                    Text(line).font(.caption2.monospaced()).foregroundStyle(.secondary)
                                        .frame(maxWidth: .infinity, alignment: .leading)
                                }
                            }
                            .padding(8)
                        }
                        .frame(maxHeight: 160)
                        .background(Color.secondary.opacity(0.08), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                        .padding(.top, 4)
                    }
                    .padding(12)
                    .glassEffect(.regular, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                }

                primaryButton(verifying ? "Verifying…" : busy ? "Starting sync…" : "Verify & Continue",
                              systemImage: "checkmark.seal", busy: busy) {
                    Task { await verifyAndContinue() }
                }
                .disabled(!psFieldsFilled || busy)

                HStack {
                    Button("Back") { go(.bellSchedule) }
                    Spacer()
                    Button("Skip") { confirmSkipPS = true }
                }
                .font(.subheadline).foregroundStyle(.secondary)
                .disabled(busy)

                Text("Canopy is an independent, unofficial tool and isn't affiliated with or endorsed by PowerSchool. You connect your account at your own risk — use of your credentials here is your own responsibility.")
                    .font(.caption2).foregroundStyle(.tertiary).multilineTextAlignment(.center)
                    .frame(maxWidth: .infinity)
            }
        }
    }

    /// Shown in place of the form so declining is a deliberate choice.
    private var skipConfirmation: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Skip PowerSchool?").font(.title3.bold()).fontDesign(.rounded)
            Text("Without PowerSchool connected, Canopy can't automatically:")
                .font(.subheadline).foregroundStyle(.secondary)
            VStack(alignment: .leading, spacing: 6) {
                ForEach([
                    "Import your classes, teachers, and room numbers",
                    "Sync your grades and assignments",
                    "Show grade velocity alerts and missing-work triage",
                    "Run the what-if and final-exam grade calculators",
                    "Keep any of the above updated automatically over time",
                ], id: \.self) { line in
                    HStack(alignment: .top, spacing: 8) {
                        Text("✕").foregroundStyle(.red).bold()
                        Text(line)
                    }
                    .font(.subheadline)
                }
            }
            .padding(.leading, 8)
            Text("You can still set up your schedule manually — including a one-click Lathrop High School bell schedule — and connect PowerSchool anytime later from Settings.")
                .font(.subheadline).foregroundStyle(.secondary)

            HStack(spacing: 10) {
                Button {
                    confirmSkipPS = false
                } label: {
                    Label("Go back", systemImage: "arrow.left")
                        .font(.headline).frame(maxWidth: .infinity).frame(height: 50)
                }
                .buttonStyle(.glass)
                Button {
                    declinedPowerSchool = true
                    confirmSkipPS = false
                    go(.schoolInfo)
                } label: {
                    Text("Continue without PowerSchool")
                        .font(.headline).frame(maxWidth: .infinity).frame(height: 50)
                }
                .buttonStyle(.glassProminent)
                .tint(.red)
            }
        }
    }

    // MARK: - Step 3: School Info
    private var schoolInfoStep: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 8) {
                Image(systemName: "graduationcap.fill").foregroundStyle(Color.accentColor)
                Text("School Information").font(.title3.bold()).fontDesign(.rounded)
            }
            Text("These settings sync across all your devices automatically. Every field below already has a sensible default — change only what you need to.")
                .font(.subheadline).foregroundStyle(.secondary)

            FormEditCard {
                VStack(spacing: 0) {
                    VStack(alignment: .leading, spacing: 4) {
                        TextField("School Name", text: $schoolName, prompt: Text("e.g. Lincoln High School"))
                        Text("Shown as a label throughout the app — optional").font(.caption).foregroundStyle(.secondary)
                    }
                    .padding(.horizontal, 16).padding(.vertical, 13)
                    Divider().padding(.leading, 16)
                    NavigationLink {
                        TimezonePickerView(selection: $timezone)
                    } label: {
                        VStack(alignment: .leading, spacing: 4) {
                            HStack {
                                Label("Your timezone", systemImage: "globe")
                                Spacer()
                                Text(TimezonePickerView.displayLabel(timezone)).foregroundStyle(.secondary).lineLimit(1)
                                Image(systemName: "chevron.right").font(.caption2).foregroundStyle(.tertiary)
                            }
                            Text("Used for calendar feed and schedule display").font(.caption).foregroundStyle(.secondary)
                        }
                        .padding(.horizontal, 16).padding(.vertical, 13)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
            }

            HStack(alignment: .top, spacing: 8) {
                Image(systemName: "info.circle").foregroundStyle(CanopyPalette.info(scheme))
                Text("Canopy treats school as in session every day, all year — there's no semester range to set. Add any breaks below (optional) and they'll be skipped automatically; you can add more anytime from the Schedule page.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(CanopyPalette.info(scheme).opacity(0.1), in: RoundedRectangle(cornerRadius: 12, style: .continuous))

            breaksEditor

            primaryButton(busy ? "Saving…" : "Save & Continue", systemImage: "arrow.right", busy: busy) {
                Task { await saveSchoolInfo() }
            }
            .disabled(busy)

            HStack {
                Button("Back") { go(.powerSchool) }
                if !required {
                    Spacer()
                    Button("Skip") { go(.done) }
                }
            }
            .font(.subheadline).foregroundStyle(.secondary)
            .disabled(busy)
        }
    }

    private var breaksEditor: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("School Breaks (optional)").font(.subheadline.weight(.semibold))
            if !breaks.isEmpty {
                VStack(spacing: 6) {
                    ForEach(breaks) { b in
                        HStack(spacing: 10) {
                            Image(systemName: "calendar.badge.minus").foregroundStyle(.secondary)
                            Text(breakSummary(b)).font(.subheadline)
                            Spacer()
                            Button {
                                breaks.removeAll { $0.id == b.id }
                            } label: {
                                Image(systemName: "trash").foregroundStyle(.secondary)
                            }
                            .buttonStyle(.plain)
                            .accessibilityLabel("Remove \(b.label.isEmpty ? "break" : b.label)")
                        }
                        .padding(.horizontal, 12).padding(.vertical, 8)
                        .background(Color.secondary.opacity(0.08), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                    }
                }
            }
            FormEditCard {
                VStack(spacing: 0) {
                    TextField("Label", text: $breakLabel, prompt: Text("e.g. Summer Break"))
                        .padding(.horizontal, 16).padding(.vertical, 13)
                    Divider().padding(.leading, 16)
                    DatePicker("Start", selection: $breakStart, displayedComponents: .date)
                        .padding(.horizontal, 16).padding(.vertical, 10)
                    Divider().padding(.leading, 16)
                    DatePicker("End", selection: $breakEnd, in: breakStart..., displayedComponents: .date)
                        .padding(.horizontal, 16).padding(.vertical, 10)
                    Divider().padding(.leading, 16)
                    Button {
                        addBreak()
                    } label: {
                        Label("Add", systemImage: "plus")
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 12)
                    }
                }
            }
        }
    }

    private func breakSummary(_ b: SchoolBreak) -> String {
        let name = b.label.isEmpty ? "No School" : b.label
        let s = b.start.asDate.map { DateFormatter.monthDay.string(from: $0) } ?? b.start
        if b.end != b.start, let e = b.end.asDate {
            return "\(name) — \(s) – \(DateFormatter.monthDay.string(from: e))"
        }
        return "\(name) — \(s)"
    }

    private func addBreak() {
        let start = DateFormatter.iso.string(from: breakStart)
        let end = DateFormatter.iso.string(from: max(breakEnd, breakStart))
        breaks.append(SchoolBreak(id: UUID().uuidString.lowercased(),
                                  label: breakLabel.trimmingCharacters(in: .whitespaces),
                                  start: start, end: end))
        breakLabel = ""
        breakStart = Calendar.current.startOfDay(for: .now)
        breakEnd = breakStart
    }

    // MARK: - Step 4: Done
    private var doneStep: some View {
        VStack(spacing: 16) {
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 64)).foregroundStyle(CanopyPalette.success(scheme))
            Text("You're all set!").font(.title2.bold()).fontDesign(.rounded)

            if syncStarted { syncBanner }

            if declinedPowerSchool { manualSetupCard }

            Text("Head to the \(Text("Dashboard").bold()) to see your schedule, or visit \(Text("Settings").bold()) to configure the iCal calendar feed and PowerSchool sync.")
                .font(.subheadline).foregroundStyle(.secondary).multilineTextAlignment(.center)

            HStack(spacing: 10) {
                Button("Back") { go(.schoolInfo) }.foregroundStyle(.secondary)
                primaryButton("Go to Dashboard", systemImage: "arrow.right") { finish() }
            }
        }
        .padding(.top, 12)
    }

    /// Live PowerSchool sync status — the sync was kicked off back on the
    /// PowerSchool step and keeps running regardless of which step is showing.
    private var syncBanner: some View {
        let s = syncStore.status
        let isRunning = s.status == "running" || s.status == "idle"
        let title = s.status == "success" ? "PowerSchool sync complete"
            : s.status == "error" ? "PowerSchool sync failed"
            : "Canopy is syncing with PowerSchool…"
        let detail: String = {
            switch s.status {
            case "success": return syncResultSummary(s.result)
            case "error": return s.error ?? "You can retry anytime from Settings."
            default: return "Running in the background — this can take a minute or two. Feel free to head to the Dashboard now; it'll keep going, and you can check progress anytime from Settings."
            }
        }()
        let tint: Color = s.status == "error" ? CanopyPalette.error(scheme)
            : s.status == "success" ? CanopyPalette.success(scheme)
            : CanopyPalette.info(scheme)
        return HStack(alignment: .top, spacing: 12) {
            if isRunning {
                ProgressView().controlSize(.small)
            } else {
                Image(systemName: s.status == "error" ? "exclamationmark.triangle.fill" : "checkmark.circle.fill")
                    .foregroundStyle(tint)
            }
            VStack(alignment: .leading, spacing: 4) {
                Text(title).font(.subheadline.weight(.semibold))
                Text(detail).font(.caption).foregroundStyle(.secondary)
            }
            Spacer(minLength: 0)
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(tint.opacity(0.12), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .animation(.easeInOut(duration: 0.2), value: s.status)
    }

    /// Web syncResultSummary — "X classes added, Y updated, Z removed, N assignments synced".
    private func syncResultSummary(_ r: SyncResultSummary?) -> String {
        guard let r else { return "Sync complete — no changes." }
        var parts: [String] = []
        if let n = r.classAdded, n > 0 { parts.append("\(n) classes added") }
        if let n = r.classUpdated, n > 0 { parts.append("\(n) updated") }
        if let n = r.classRemoved, n > 0 { parts.append("\(n) removed") }
        if let n = r.assignmentCount, n > 0 { parts.append("\(n) assignments synced") }
        return parts.isEmpty ? "Sync complete — no changes." : parts.joined(separator: ", ")
    }

    private var manualSetupCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Image(systemName: "graduationcap").foregroundStyle(CanopyPalette.info(scheme))
                Text("Set up your schedule manually").font(.subheadline.weight(.semibold))
            }
            Text("If your school follows Lathrop High School's bell schedule, turn this on and Canopy fills in each class's period times automatically once you've added your classes. Otherwise, add classes yourself anytime from the Classes page.")
                .font(.caption).foregroundStyle(.secondary)
            Button {
                let next = !manualLathropEnabled
                manualLathropEnabled = next
                Task { await store.saveLathropMode(next) }
            } label: {
                Label(manualLathropEnabled ? "Lathrop Mode enabled" : "Enable Lathrop Mode",
                      systemImage: manualLathropEnabled ? "checkmark.circle.fill" : "circle")
                    .font(.subheadline.weight(.semibold))
            }
            .buttonStyle(.glass)
            .tint(manualLathropEnabled ? Color.accentColor : .secondary)
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).strokeBorder(CanopyPalette.info(scheme).opacity(0.5), lineWidth: 1))
    }

    // MARK: - Shared bits
    private func primaryButton(_ title: String, systemImage: String? = nil, busy: Bool = false, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 8) {
                if busy { ProgressView().tint(.white).controlSize(.small) }
                Text(title).font(.headline)
                if let systemImage, !busy { Image(systemName: systemImage).font(.subheadline.weight(.semibold)) }
            }
            .foregroundStyle(.white)
            .frame(maxWidth: .infinity).frame(height: 50)
            .background(Color.accentColor, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        }
        .buttonStyle(.plain)
    }

    private func go(_ next: WizardStep) {
        error = nil
        withAnimation(.easeInOut(duration: 0.2)) { step = next }
    }

    // MARK: - Actions

    /// Persists the mandatory Bell Schedule choice (the one place the user's
    /// real decision is saved rather than the registration default).
    private func confirmLathropChoice() async {
        guard let choice = lathropChoice else { return }
        savingLathropChoice = true
        defer { savingLathropChoice = false }
        error = nil
        do {
            try await APIClient.shared.saveSetting(key: "lathropMode", value: choice ? "true" : "false")
            store.settings.lathropMode = choice ? "true" : "false"
            manualLathropEnabled = choice
            go(.powerSchool)
        } catch {
            self.error = "Failed to save your Bell Schedule choice."
        }
    }

    /// Two-phase: fast login-only verify, then save credentials and start the
    /// real sync as a background job the wizard does NOT wait on.
    private func verifyAndContinue() async {
        error = nil
        psLog = []
        verifying = true
        busy = true
        defer { verifying = false; busy = false }
        do {
            let verify = try await APIClient.shared.verifyPowerSchool(url: psURL, username: psUsername, password: psPassword)
            if let log = verify.log { psLog = log }
            guard verify.ok else {
                error = verify.error ?? "Could not log in to PowerSchool — check your URL, username, and password."
                showPSLog = !psLog.isEmpty
                return
            }
            verifying = false

            try await APIClient.shared.savePowerSchool(url: psURL, username: psUsername, password: psPassword)
            let kick = try await APIClient.shared.startPowerSchoolSync(url: psURL, username: psUsername, password: psPassword)
            guard kick.success else {
                error = kick.error ?? "Verified, but could not start the sync. You can retry from Settings."
                return
            }
            syncStarted = true
            handledOutcome = false
            declinedPowerSchool = false
            syncStore.poke()
            // A proven login is exactly the case to default scheduled sync on.
            try? await store.saveAutoSync(true)
            await store.refreshSetupStatus()
            go(.schoolInfo)
        } catch {
            self.error = "Connection error: \(error.localizedDescription)"
        }
    }

    private func saveSchoolInfo() async {
        error = nil
        busy = true
        defer { busy = false }
        do {
            let name = schoolName.trimmingCharacters(in: .whitespaces)
            try await store.saveSchoolInfo(schoolName: name.isEmpty ? nil : name,
                                           timezone: timezone.isEmpty ? nil : timezone)
            // Each break becomes a "No School" disruption spanning its range.
            for b in breaks {
                let d = ScheduleDisruption(id: b.id, date: b.start,
                                           endDate: b.end != b.start ? b.end : nil,
                                           type: "no_school", label: b.label,
                                           periodOverrides: [], sourceDayOfWeek: nil)
                try? await store.saveDisruption(d, isNew: true)
            }
            go(.done)
        } catch {
            self.error = "Failed to save school info."
        }
    }

    private func finish() {
        wizardDismissed = true
        dismiss()
    }
}
