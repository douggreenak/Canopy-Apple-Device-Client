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

private let canopyBaseURL = "https://canopy.apexengineeringak.com"

// MARK: - PowerSchool

struct PowerSchoolSettingsView: View {
    @Environment(CanopyStore.self) private var store
    @State private var url = ""
    @State private var username = ""
    @State private var password = ""
    @State private var hasSaved = false
    @State private var isSaving = false
    @State private var statusMessage: String?
    @State private var isError = false
    @State private var showLog = false

    var body: some View {
        List {
            Section {
                TextField("PowerSchool URL", text: $url)
                    .textAutocapNever()
                TextField("Username", text: $username)
                    .textAutocapNever()
                SecureField("Password", text: $password)
            } header: {
                Text("PowerSchool Login")
            } footer: {
                Text(hasSaved
                     ? "Connected (saved login). Your password is stored encrypted and never shown."
                     : "Enter your district PowerSchool address and login. The password is encrypted at rest.")
            }

            Section {
                Button {
                    Task { await saveCredentials() }
                } label: {
                    Label(isSaving ? "Saving…" : "Save Login", systemImage: "lock.shield")
                }
                .disabled(isSaving || url.isEmpty || username.isEmpty || password.isEmpty)

                if hasSaved {
                    Button(role: .destructive) {
                        Task { await clearCredentials() }
                    } label: {
                        Label("Clear Saved Login", systemImage: "trash")
                    }
                }
            }

            Section {
                Button {
                    Task { await syncNow() }
                } label: {
                    HStack {
                        Label("Sync Now", systemImage: "arrow.triangle.2.circlepath")
                        Spacer()
                        if store.isSyncing { ProgressView() }
                    }
                }
                .disabled(store.isSyncing || (!hasSaved && (url.isEmpty || username.isEmpty || password.isEmpty)))
            } footer: {
                if let last = store.settings.lastSyncAt, let d = CanopyStore.parseISO(last) {
                    Text("Last synced \(d.formatted(.relative(presentation: .named)))")
                } else {
                    Text("Pull your classes, assignments, and grades from PowerSchool.")
                }
            }

            if let statusMessage {
                Section {
                    Text(statusMessage)
                        .font(.footnote)
                        .foregroundStyle(isError ? .red : .green)
                }
            }

            if !store.lastSyncLog.isEmpty {
                Section {
                    DisclosureGroup("Sync Log (\(store.lastSyncLog.count) lines)", isExpanded: $showLog) {
                        ForEach(Array(store.lastSyncLog.enumerated()), id: \.offset) { _, line in
                            Text(line)
                                .font(.caption.monospaced())
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            }
        }
        .insetGroupedListStyle()
        .background(CanopyBackground())
        .scrollContentBackground(.hidden)
        .navigationTitle("PowerSchool")
        .navigationBarTitleInline()
        .task { await loadStatus() }
    }

    private func loadStatus() async {
        if let s = try? await APIClient.shared.getSetupStatus() {
            url = s.powerschoolUrl
            username = s.powerschoolUsername
            hasSaved = s.hasPowerschool
        }
    }

    private func saveCredentials() async {
        isSaving = true; defer { isSaving = false }
        do {
            try await APIClient.shared.savePowerSchool(url: url, username: username, password: password)
            hasSaved = true
            password = ""
            statusMessage = "Login saved."
            isError = false
        } catch {
            statusMessage = error.localizedDescription
            isError = true
        }
    }

    private func clearCredentials() async {
        do {
            try await APIClient.shared.clearPowerSchool()
            hasSaved = false; url = ""; username = ""; password = ""
            statusMessage = "Saved login cleared."
            isError = false
        } catch {
            statusMessage = error.localizedDescription
            isError = true
        }
    }

    private func syncNow() async {
        statusMessage = nil
        do {
            let oneOff = !password.isEmpty
            let result = try await store.syncPowerSchool(
                url: oneOff ? url : nil,
                username: oneOff ? username : nil,
                password: oneOff ? password : nil
            )
            if result.success {
                let c = (result.classAdded ?? 0) + (result.classUpdated ?? 0)
                let a = (result.assignmentAdded ?? 0) + (result.assignmentUpdated ?? 0)
                statusMessage = "Synced \(c) classes, \(a) assignments."
                isError = false
            } else {
                statusMessage = result.error ?? "Sync failed."
                isError = true
                showLog = true
            }
        } catch {
            statusMessage = error.localizedDescription
            isError = true
        }
    }
}

// MARK: - Integrations (setup codes + Google Classroom)

struct IntegrationsSettingsView: View {
    @State private var passphrase = ""
    @State private var generatedCode: String?
    @State private var importCode = ""
    @State private var importPassphrase = ""
    @State private var clientId = ""
    @State private var clientSecret = ""
    @State private var message: String?
    @State private var isError = false
    @State private var busy = false

    var body: some View {
        List {
            Section {
                SecureField("Passphrase", text: $passphrase)
                Button {
                    Task { await generate() }
                } label: {
                    Label(busy ? "Working…" : "Generate Setup Code", systemImage: "qrcode")
                }
                .disabled(busy || passphrase.isEmpty)
                if let generatedCode {
                    VStack(alignment: .leading, spacing: 6) {
                        Text(generatedCode)
                            .font(.caption.monospaced())
                            .textSelection(.enabled)
                            .lineLimit(3)
                        Button {
                            Clipboard.copy(generatedCode)
                        } label: { Label("Copy Code", systemImage: "doc.on.doc") }
                            .font(.caption)
                    }
                }
            } header: {
                Text("Export Setup Code")
            } footer: {
                Text("Bundle your PowerSchool + Google Classroom config into an encrypted code you can use on another device.")
            }

            Section {
                TextField("Setup code (SP2-…)", text: $importCode).textAutocapNever()
                SecureField("Passphrase", text: $importPassphrase)
                Button {
                    Task { await useCode() }
                } label: {
                    Label("Apply Setup Code", systemImage: "square.and.arrow.down")
                }
                .disabled(busy || importCode.isEmpty || importPassphrase.isEmpty)
            } header: {
                Text("Import Setup Code")
            }

            Section {
                TextField("Client ID", text: $clientId).textAutocapNever()
                SecureField("Client Secret", text: $clientSecret)
                Button {
                    Task { await saveClassroom() }
                } label: {
                    Label("Save Google Classroom OAuth", systemImage: "graduationcap")
                }
                .disabled(busy || clientId.isEmpty || clientSecret.isEmpty)
            } header: {
                Text("Google Classroom")
            } footer: {
                Text("Configure Google Classroom OAuth credentials for assignment import.")
            }

            if let message {
                Section { Text(message).font(.footnote).foregroundStyle(isError ? .red : .green) }
            }
        }
        .insetGroupedListStyle()
        .background(CanopyBackground())
        .scrollContentBackground(.hidden)
        .navigationTitle("Setup & Integrations")
        .navigationBarTitleInline()
    }

    private func generate() async {
        busy = true; defer { busy = false }
        do {
            let r = try await APIClient.shared.generateSetupCode(passphrase: passphrase)
            if r.success, let code = r.setupCode {
                generatedCode = code; message = nil
            } else {
                message = r.error ?? "Could not generate code."; isError = true
            }
        } catch { message = error.localizedDescription; isError = true }
    }

    private func useCode() async {
        busy = true; defer { busy = false }
        do {
            let r = try await APIClient.shared.useSetupCode(importCode, passphrase: importPassphrase)
            if r.success {
                message = "Setup applied."; isError = false
            } else {
                message = r.error ?? "Invalid code or passphrase."; isError = true
            }
        } catch { message = error.localizedDescription; isError = true }
    }

    private func saveClassroom() async {
        busy = true; defer { busy = false }
        do {
            try await APIClient.shared.saveClassroomOAuth(clientId: clientId, clientSecret: clientSecret)
            message = "Google Classroom OAuth saved."; isError = false
        } catch { message = error.localizedDescription; isError = true }
    }
}

// MARK: - Calendar export (iCal feed)

struct CalendarExportView: View {
    @Environment(AuthStore.self) private var authStore
    @Environment(CanopyStore.self) private var store
    @State private var feedURL = ""
    @State private var copied = false

    var body: some View {
        List {
            Section {
                if feedURL.isEmpty {
                    HStack { ProgressView(); Text("Preparing feed…").foregroundStyle(.secondary) }
                } else {
                    Text(feedURL)
                        .font(.caption.monospaced())
                        .textSelection(.enabled)
                        .lineLimit(4)
                    Button {
                        Clipboard.copy(feedURL)
                        copied = true
                    } label: {
                        Label(copied ? "Copied!" : "Copy Calendar URL", systemImage: copied ? "checkmark" : "doc.on.doc")
                    }
                }
            } header: {
                Text("Subscribe URL")
            } footer: {
                Text("Add this URL in Apple Calendar (File ▸ New Calendar Subscription) to see your classes, exams, and homework due dates. Keep it private — anyone with the link can read your schedule.")
            }
        }
        .insetGroupedListStyle()
        .background(CanopyBackground())
        .scrollContentBackground(.hidden)
        .navigationTitle("Calendar Feed")
        .navigationBarTitleInline()
        .task {
            let token = await store.ensureCalendarToken()
            if let uid = authStore.user?.id {
                feedURL = "\(canopyBaseURL)/api/calendar?userId=\(uid)&token=\(token)"
            }
        }
    }
}
