import SwiftUI

/// Global re-trigger signal — Settings posts this to reopen the wizard from
/// anywhere, mirroring web's `window.dispatchEvent(new Event('open-setup-wizard'))`.
extension Notification.Name {
    static let openSetupWizard = Notification.Name("open-setup-wizard")
}

/// First-run / re-run onboarding: School Info + optional PowerSchool connect.
/// Presented as a `.fullScreenCover` from ContentView. One adaptive layout at
/// every size — unlike web, which forks a desktop `Stepper` vs. a mobile
/// progress bar, SwiftUI doesn't need two layouts to keep in sync.
struct SetupWizardView: View {
    /// Required on first registration: no close button, cannot be dismissed
    /// except by finishing (or explicitly skipping) each step.
    let required: Bool

    @Environment(CanopyStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    @AppStorage("sp-wizard-dismissed") private var wizardDismissed = false

    enum WizardStep: Int, CaseIterable {
        case welcome, schoolInfo, powerSchool, done
    }

    @State private var step: WizardStep = .welcome

    // School Info
    @State private var schoolName = ""
    @State private var semesterStart = Date.now
    @State private var semesterEnd = Date.now.addingTimeInterval(120 * 86400)
    @State private var timezone = TimeZone.current.identifier
    @State private var savingSchoolInfo = false
    @State private var schoolInfoError: String?

    // PowerSchool
    @State private var psURL = ""
    @State private var psUsername = ""
    @State private var psPassword = ""
    @State private var showPSPassword = false
    @State private var connecting = false
    @State private var psError: String?
    @State private var psSummary: String?
    @State private var showLog = false

    private var psFieldsFilled: Bool { !psURL.isEmpty && !psUsername.isEmpty && !psPassword.isEmpty }

    var body: some View {
        NavigationStack {
            ZStack {
                CanopyBackground()
                VStack(spacing: 0) {
                    header
                    ScrollView {
                        VStack(spacing: 20) {
                            switch step {
                            case .welcome:     welcomeStep
                            case .schoolInfo:  schoolInfoStep
                            case .powerSchool: powerSchoolStep
                            case .done:        doneStep
                            }
                        }
                        .padding(20)
                        .padding(.bottom, 24)
                    }
                }
            }
            .navigationBarTitleInline()
            .toolbar {
                if !required {
                    ToolbarItem(placement: .cancellationAction) {
                        Button { finish() } label: { Image(systemName: "xmark") }
                    }
                }
            }
        }
        .interactiveDismissDisabled(required)
    }

    // MARK: - Header
    // A slim step indicator shown at every size — no separate desktop Stepper.
    private var header: some View {
        VStack(spacing: 8) {
            HStack(spacing: 8) {
                Image(systemName: "building.columns.fill").foregroundStyle(Color.accentColor)
                Text("Setup Wizard").font(.headline)
                Spacer()
                Text("Step \(step.rawValue + 1) of \(WizardStep.allCases.count)")
                    .font(.caption).foregroundStyle(.secondary)
            }
            ProgressView(value: Double(step.rawValue + 1), total: Double(WizardStep.allCases.count))
                .tint(Color.accentColor)
        }
        .padding(.horizontal, 20).padding(.top, 16).padding(.bottom, 12)
        .background(.ultraThinMaterial)
    }

    // MARK: - Step 0: Welcome
    private var welcomeStep: some View {
        VStack(spacing: 16) {
            CanopyIconView(size: 84)
            Text("Welcome to Canopy").font(.title2.bold()).fontDesign(.rounded)
            Text("Your classes, schedule, grades, and homework live in one place. Let's get your school set up.")
                .font(.subheadline).foregroundStyle(.secondary).multilineTextAlignment(.center)

            HStack(spacing: 8) {
                Image(systemName: "checkmark.shield.fill").foregroundStyle(.green)
                Text("Your data is stored securely — no spreadsheet setup needed.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color.green.opacity(0.1), in: RoundedRectangle(cornerRadius: 12, style: .continuous))

            primaryButton("Get Started") { step = .schoolInfo }

            if !required {
                Button("Skip — I'll set up in Settings") { finish() }
                    .font(.subheadline).foregroundStyle(.secondary)
            }
        }
        .padding(.top, 12)
    }

    // MARK: - Step 1: School Info
    private var schoolInfoStep: some View {
        VStack(spacing: 16) {
            FormEditCard {
                TextField("School Name", text: $schoolName)
                    .padding(.horizontal, 16).padding(.vertical, 13)
            }

            FormEditCard {
                VStack(spacing: 0) {
                    DatePicker("Semester Start", selection: $semesterStart, displayedComponents: .date)
                        .padding(.horizontal, 16).padding(.vertical, 13)
                    Divider().padding(.leading, 16)
                    DatePicker("Semester End", selection: $semesterEnd, displayedComponents: .date)
                        .padding(.horizontal, 16).padding(.vertical, 13)
                }
            }

            HStack(alignment: .top, spacing: 8) {
                Image(systemName: "info.circle").foregroundStyle(.blue)
                Text("Dashboard and Schedule will look empty outside these dates.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color.blue.opacity(0.08), in: RoundedRectangle(cornerRadius: 12, style: .continuous))

            NavigationLink {
                TimezonePickerView(selection: $timezone)
            } label: {
                FormEditCard {
                    HStack {
                        Label("Timezone", systemImage: "globe")
                        Spacer()
                        Text(timezone.replacingOccurrences(of: "_", with: " ")).foregroundStyle(.secondary)
                        Image(systemName: "chevron.right").font(.caption2).foregroundStyle(.tertiary)
                    }
                    .padding(.horizontal, 16).padding(.vertical, 13)
                }
            }
            .buttonStyle(.plain)

            if let schoolInfoError {
                Text(schoolInfoError).font(.caption).foregroundStyle(.red)
            }

            primaryButton(savingSchoolInfo ? "Saving…" : "Save & Continue") {
                Task { await saveSchoolInfo() }
            }
            .disabled(savingSchoolInfo)

            HStack {
                Button("Back") { step = .welcome }
                if !required {
                    Spacer()
                    Button("Skip") { step = .powerSchool }
                }
            }
            .font(.subheadline).foregroundStyle(.secondary)
        }
    }

    // MARK: - Step 2: PowerSchool (optional)
    private var powerSchoolStep: some View {
        VStack(spacing: 16) {
            HStack {
                Text("Connect PowerSchool to automatically sync classes, assignments, and grades.")
                    .font(.subheadline).foregroundStyle(.secondary)
                Spacer()
            }
            Text("OPTIONAL")
                .font(.caption2.bold()).foregroundStyle(.secondary)
                .padding(.horizontal, 8).padding(.vertical, 3)
                .background(Color.secondary.opacity(0.12), in: Capsule())
                .frame(maxWidth: .infinity, alignment: .leading)

            FormEditCard {
                VStack(spacing: 0) {
                    TextField("PowerSchool URL", text: $psURL)
                        .textAutocapNever()
                        .padding(.horizontal, 16).padding(.vertical, 13)
                    Divider().padding(.leading, 16)
                    TextField("Student Username", text: $psUsername)
                        .textAutocapNever()
                        .padding(.horizontal, 16).padding(.vertical, 13)
                    Divider().padding(.leading, 16)
                    HStack {
                        Group {
                            if showPSPassword { TextField("Student Password", text: $psPassword) }
                            else { SecureField("Student Password", text: $psPassword) }
                        }
                        .textAutocapNever()
                        Button { showPSPassword.toggle() } label: {
                            Image(systemName: showPSPassword ? "eye.slash" : "eye").foregroundStyle(.secondary)
                        }
                    }
                    .padding(.horizontal, 16).padding(.vertical, 13)
                }
            }

            if let psError {
                Text(psError).font(.caption).foregroundStyle(.red)
            }

            if !store.lastSyncLog.isEmpty {
                syncLogDisclosure
            }

            primaryButton(connecting ? "Connecting…" : "Connect & Sync") {
                Task { await connectAndSync() }
            }
            .disabled(!psFieldsFilled || connecting)

            HStack {
                Button("Back") { step = .schoolInfo }
                Spacer()
                Button("Skip") { step = .done }
            }
            .font(.subheadline).foregroundStyle(.secondary)
        }
    }

    // MARK: - Step 3: Done
    private var doneStep: some View {
        VStack(spacing: 16) {
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 64)).foregroundStyle(.green)
            Text("You're all set!").font(.title2.bold()).fontDesign(.rounded)

            if let psSummary {
                Text(psSummary).font(.subheadline).foregroundStyle(.secondary).multilineTextAlignment(.center)
                if !store.lastSyncLog.isEmpty { syncLogDisclosure }
            } else {
                Text("You can finish connecting PowerSchool or adjust anything else anytime in Settings.")
                    .font(.subheadline).foregroundStyle(.secondary).multilineTextAlignment(.center)
            }

            HStack(spacing: 10) {
                Button("Back") { step = .powerSchool }.foregroundStyle(.secondary)
                primaryButton("Go to Dashboard") { finish() }
            }
        }
        .padding(.top, 12)
    }

    // MARK: - Shared bits
    private var syncLogDisclosure: some View {
        DisclosureGroup("Sync Log (\(store.lastSyncLog.count) lines)", isExpanded: $showLog) {
            VStack(alignment: .leading, spacing: 4) {
                ForEach(Array(store.lastSyncLog.enumerated()), id: \.offset) { _, line in
                    Text(line).font(.caption.monospaced()).foregroundStyle(.secondary)
                }
            }
            .padding(.top, 4)
        }
        .padding(12)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
    }

    private func primaryButton(_ title: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(.headline).foregroundStyle(.white)
                .frame(maxWidth: .infinity).frame(height: 50)
                .background(Color.accentColor, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        }
    }

    // MARK: - Actions
    private func saveSchoolInfo() async {
        savingSchoolInfo = true; defer { savingSchoolInfo = false }
        schoolInfoError = nil
        do {
            try await store.saveSettings(
                schoolName: schoolName.isEmpty ? nil : schoolName,
                start: DateFormatter.iso.string(from: semesterStart),
                end: DateFormatter.iso.string(from: semesterEnd)
            )
            await store.saveTimezone(timezone)
            step = .powerSchool
        } catch {
            schoolInfoError = error.localizedDescription
        }
    }

    private func connectAndSync() async {
        connecting = true; defer { connecting = false }
        psError = nil
        do {
            try await APIClient.shared.savePowerSchool(url: psURL, username: psUsername, password: psPassword)
            let result = try await store.syncPowerSchool(url: psURL, username: psUsername, password: psPassword)
            if result.success {
                let c = (result.classAdded ?? 0) + (result.classUpdated ?? 0)
                let a = (result.assignmentAdded ?? 0) + (result.assignmentUpdated ?? 0)
                psSummary = "\(c) class\(c == 1 ? "" : "es") added, \(a) assignment\(a == 1 ? "" : "s") synced."
                step = .done
            } else {
                psError = result.error ?? "Sync failed."
                showLog = true
            }
        } catch {
            psError = error.localizedDescription
        }
    }

    private func finish() {
        wizardDismissed = true
        dismiss()
    }
}
