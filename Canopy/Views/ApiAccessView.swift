import SwiftUI

// Port of web Settings → "API & MCP access" (src/components/ApiAccessSection.tsx).
//
// Security notes:
//  - The raw token exists only in @State of the reveal sheet. It is never
//    written to disk, Keychain, UserDefaults or logs, and is dropped the
//    moment the sheet is dismissed (the server can't show it again either).
//  - Creating a token needs the account password again (server-enforced).
//  - Copying uses Clipboard.copySensitive (local-only, auto-expiring).
struct ApiAccessView: View {
    @Environment(AuthStore.self) private var authStore
    @State private var tokens: [ApiTokenInfo] = []
    @State private var maxTokens = 10
    @State private var loading = true
    @State private var loadError: String?
    @State private var showCreate = false
    @State private var revealed: CreatedApiToken?
    @State private var pendingRevoke: ApiTokenInfo?
    @State private var toast: ToastMessage?

    var body: some View {
        List {
            Section {
                Text("Let your own tools or AI assistants (via MCP) read your planner. A token only ever sees your data, is shown once, and can be revoked any time. Treat it like a password.")
                    .font(.subheadline).foregroundStyle(.secondary)
            }

            Section {
                Button { showCreate = true } label: { Label("New Token", systemImage: "plus") }
                    .disabled(tokens.count >= maxTokens)
            } footer: {
                if tokens.count >= maxTokens { Text("You can have at most \(maxTokens) active tokens. Revoke one first.") }
            }

            Section("Active Tokens") {
                if loading && tokens.isEmpty {
                    ProgressView()
                } else if let loadError {
                    Text(loadError).foregroundStyle(.red).font(.footnote)
                } else if tokens.isEmpty {
                    Text("No active tokens.").foregroundStyle(.secondary)
                }
                ForEach(tokens) { t in
                    TokenRow(token: t)
                        .swipeActions {
                            Button("Revoke", role: .destructive) { pendingRevoke = t }
                        }
                        .accessibilityIdentifier("token-row-\(t.name)")
                }
            }

            Section("Connect an assistant") {
                LabeledContent("MCP URL") {
                    Text("\(APIClient.shared.baseURL)/api/mcp").font(.caption.monospaced()).textSelection(.enabled)
                }
                Text("Send the token as the header  Authorization: Bearer <token>. See docs/API.md for Claude Code and REST examples.")
                    .font(.footnote).foregroundStyle(.secondary)
            }
        }
        .insetGroupedListStyle()
        .background(CanopyBackground())
        .scrollContentBackground(.hidden)
        .navigationTitle("API & MCP Access")
        .navigationBarTitleInline()
        .refreshable { await load() }
        .task { await load() }
        .sheet(isPresented: $showCreate) {
            CreateTokenSheet { created in
                revealed = created
                Task { await load() }
            }
            .presentationDetents([.large])
        }
        .sheet(item: $revealed) { created in
            TokenRevealSheet(created: created).interactiveDismissDisabled()
        }
        .confirmationDialog("Revoke \(pendingRevoke?.name ?? "token")?",
                            isPresented: Binding(get: { pendingRevoke != nil }, set: { if !$0 { pendingRevoke = nil } }),
                            titleVisibility: .visible) {
            Button("Revoke", role: .destructive) {
                if let t = pendingRevoke { Task { await revoke(t) } }
                pendingRevoke = nil
            }
        } message: {
            Text("Anything using this token loses access immediately.")
        }
        .toast($toast)
    }

    private func load() async {
        do {
            let list = try await APIClient.shared.getApiTokens()
            tokens = list.tokens; maxTokens = list.max; loadError = nil
        } catch {
            loadError = error.localizedDescription
        }
        loading = false
    }

    private func revoke(_ t: ApiTokenInfo) async {
        do {
            try await APIClient.shared.revokeApiToken(id: t.id)
            tokens.removeAll { $0.id == t.id }
            toast = ToastMessage(text: "Token revoked.", kind: .success)
        } catch {
            toast = ToastMessage(text: error.localizedDescription, kind: .error)
        }
    }
}

extension CreatedApiToken: Identifiable {}

private struct TokenRow: View {
    let token: ApiTokenInfo
    private static let df: DateFormatter = { let f = DateFormatter(); f.dateStyle = .medium; return f }()
    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(token.name).fontWeight(.semibold)
                Text("…\(token.hint)").font(.caption.monospaced()).foregroundStyle(.secondary)
                Spacer()
                Text(token.scope.label)
                    .font(.caption2.weight(.semibold))
                    .padding(.horizontal, 8).padding(.vertical, 3)
                    .background((token.scope == .write ? Color.orange : Color.secondary).opacity(0.18), in: Capsule())
            }
            Text("Created \(Self.df.string(from: token.created)) · expires \(Self.df.string(from: token.expires)) · "
                 + (token.lastUsed.map { "last used \(Self.df.string(from: $0))" } ?? "never used"))
                .font(.caption).foregroundStyle(.secondary)
        }
    }
}

// MARK: - Create

private struct CreateTokenSheet: View {
    @Environment(\.dismiss) private var dismiss
    var onCreated: (CreatedApiToken) -> Void

    @State private var name = ""
    @State private var scope: ApiTokenScope = .read
    @State private var days = 90
    @State private var password = ""
    @State private var showPassword = false
    @State private var busy = false
    @State private var error: String?

    var body: some View {
        NavigationStack {
            List {
                Section("Name") {
                    TextField("e.g. Claude Desktop", text: $name)
                        .autocorrectionDisabled()
                        .accessibilityIdentifier("token-name")
                }
                Section {
                    Picker("Access", selection: $scope) {
                        ForEach(ApiTokenScope.allCases) { Text($0.label).tag($0) }
                    }
                    Picker("Expires", selection: $days) {
                        Text("30 days").tag(30); Text("90 days").tag(90); Text("1 year").tag(365)
                    }
                } footer: {
                    Text(scope == .write
                         ? "Write access lets the token add and edit your tasks and mark assignments done. It can never change grades, settings or credentials."
                         : "Read-only tokens can view your classes, assignments, tasks, exams and grades. Recommended.")
                }
                Section {
                    PasswordField("Confirm your password", text: $password, isRevealed: $showPassword)
                        .textContentType(.password)
                        .accessibilityIdentifier("token-password")
                } header: { Text("Confirm it's you") }
                if let error { Section { Text(error).foregroundStyle(.red).font(.footnote) } }
            }
            .insetGroupedListStyle()
            .background(CanopyBackground())
            .scrollContentBackground(.hidden)
            .navigationTitle("New Token")
            .navigationBarTitleInline()
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button(busy ? "Creating…" : "Create") { Task { await create() } }
                        .fontWeight(.semibold)
                        .disabled(busy || name.trimmingCharacters(in: .whitespaces).isEmpty || password.isEmpty)
                        .accessibilityIdentifier("token-create")
                }
            }
        }
    }

    private func create() async {
        busy = true; error = nil; defer { busy = false }
        do {
            let created = try await APIClient.shared.createApiToken(
                name: name.trimmingCharacters(in: .whitespaces), scope: scope, expiresInDays: days, password: password)
            password = ""
            dismiss()
            onCreated(created)
        } catch {
            self.error = error.localizedDescription
        }
    }
}

// MARK: - One-time reveal

private struct TokenRevealSheet: View {
    @Environment(\.dismiss) private var dismiss
    let created: CreatedApiToken
    @State private var copied = false

    var body: some View {
        NavigationStack {
            List {
                Section {
                    Label("Copy this token now — it won't be shown again.", systemImage: "exclamationmark.triangle.fill")
                        .foregroundStyle(.orange)
                }
                Section("Token for “\(created.name)” (\(created.scope.label))") {
                    Text(created.token)
                        .font(.footnote.monospaced())
                        .textSelection(.enabled)
                        .accessibilityIdentifier("token-value")
                    Button {
                        Clipboard.copySensitive(created.token); copied = true
                    } label: {
                        Label(copied ? "Copied (clears in 2 min)" : "Copy Token", systemImage: copied ? "checkmark" : "doc.on.doc")
                    }
                }
                Section("Use it") {
                    Text("MCP URL: \(APIClient.shared.baseURL)/api/mcp\nHeader: Authorization: Bearer <token>")
                        .font(.footnote.monospaced())
                }
            }
            .insetGroupedListStyle()
            .background(CanopyBackground())
            .scrollContentBackground(.hidden)
            .navigationTitle("Token Created")
            .navigationBarTitleInline()
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }.fontWeight(.semibold).accessibilityIdentifier("token-done")
                }
            }
        }
    }
}
