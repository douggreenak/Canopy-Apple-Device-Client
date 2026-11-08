import SwiftUI

// Port of web src/components/OtherSchoolsSection.tsx — secondary PowerSchool
// logins for students who take classes at more than one school. Only has
// content once a school is added; the primary login in PowerSchool settings
// is unaffected.
struct OtherSchoolsView: View {
    @Environment(CanopyStore.self) private var store
    @State private var showAdd = false
    @State private var syncingId: String?
    @State private var confirmDelete: SchoolAccountSummary?
    @State private var toast: ToastMessage?

    var body: some View {
        List {
            Section {
                HStack(spacing: 8) {
                    Text("Other Schools").font(.headline)
                    OutlinedChip(text: "Optional")
                    if !store.schoolAccounts.isEmpty {
                        TintedChip(text: "\(store.schoolAccounts.count)")
                    }
                }
                .listRowSeparator(.hidden)
                Text("If you take classes at more than one school — each with its own PowerSchool login — add the extra ones here. Your main PowerSchool login above is unaffected.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }

            if !store.schoolAccounts.isEmpty {
                Section("Schools") {
                    ForEach(store.schoolAccounts) { account in
                        HStack(spacing: 12) {
                            Image(systemName: "graduationcap.fill").foregroundStyle(Color.accentColor)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(account.schoolName).font(.body)
                                Text(account.username).font(.caption).foregroundStyle(.secondary)
                            }
                            Spacer()
                            Button {
                                Task { await sync(account) }
                            } label: {
                                if syncingId == account.id {
                                    ProgressView().controlSize(.small)
                                } else {
                                    Image(systemName: "arrow.triangle.2.circlepath")
                                }
                            }
                            .buttonStyle(.borderless)
                            .disabled(syncingId == account.id)
                            .help("Sync now")
                            .accessibilityLabel("Sync now")

                            Button(role: .destructive) {
                                confirmDelete = account
                            } label: {
                                Image(systemName: "trash")
                            }
                            .buttonStyle(.borderless)
                            .foregroundStyle(.red)
                            .help("Remove")
                            .accessibilityLabel("Remove")
                        }
                        .swipeActions(edge: .trailing) {
                            Button(role: .destructive) { confirmDelete = account } label: { Label("Remove", systemImage: "trash") }
                        }
                    }
                }
            }

            Section {
                Button {
                    showAdd = true
                } label: {
                    Label("Add Another School", systemImage: "plus")
                }
            }
        }
        .insetGroupedListStyle()
        .background(CanopyBackground())
        .scrollContentBackground(.hidden)
        .navigationTitle("Other Schools")
        .navigationBarTitleInline()
        .task { await store.loadSchoolAccounts() }
        .refreshable { await store.loadSchoolAccounts() }
        .sheet(isPresented: $showAdd) {
            AddSchoolSheet { toast = ToastMessage(text: "School added.", kind: .success) }
                .presentationDetents([.large])
        }
        .alert(
            "Remove \(confirmDelete?.schoolName ?? "")?",
            isPresented: Binding(get: { confirmDelete != nil }, set: { if !$0 { confirmDelete = nil } }),
            presenting: confirmDelete
        ) { account in
            Button("Cancel", role: .cancel) { confirmDelete = nil }
            Button("Remove", role: .destructive) { Task { await remove(account) } }
        } message: { _ in
            Text("This stops syncing that school. Classes already imported from it stay in your roster — you can delete them individually from the Classes page if you want them gone too.")
        }
        .toast($toast)
    }

    private func sync(_ account: SchoolAccountSummary) async {
        syncingId = account.id
        do {
            try await APIClient.shared.syncSchoolAccount(id: account.id)
            // The scrape runs in the background (same pattern as the primary
            // sync) — there's no fine-grained status to poll for a secondary
            // school, so give it a reasonable window before refetching.
            try? await Task.sleep(nanoseconds: 15_000_000_000)
            await store.loadAll()
            await store.loadSchoolAccounts()
        } catch {
            toast = ToastMessage(text: error.localizedDescription, kind: .error)
        }
        if syncingId == account.id { syncingId = nil }
    }

    private func remove(_ account: SchoolAccountSummary) async {
        confirmDelete = nil
        do {
            try await APIClient.shared.deleteSchoolAccount(id: account.id)
            await store.loadSchoolAccounts()
        } catch {
            toast = ToastMessage(text: error.localizedDescription, kind: .error)
        }
    }
}

// MARK: - Add a School (web dialog)
private struct AddSchoolSheet: View {
    @Environment(CanopyStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    var onAdded: () -> Void

    @State private var schoolName = ""
    @State private var url = ""
    @State private var username = ""
    @State private var password = ""
    @State private var showPassword = false
    @State private var saving = false
    @State private var error: String?

    var body: some View {
        NavigationStack {
            List {
                Section {
                    TextField("School Name", text: $schoolName, prompt: Text("e.g. Lathrop High School"))
                    TextField("PowerSchool URL", text: $url, prompt: Text("https://your-school.powerschool.com"))
                        .textAutocapNever()
                        .autocorrectionDisabled()
                        #if os(iOS)
                        .keyboardType(.URL)
                        #endif
                    TextField("Student Username", text: $username)
                        .textAutocapNever()
                        .autocorrectionDisabled()
                    PasswordField("Student Password", text: $password, isRevealed: $showPassword)
                }
                if let error {
                    Section { Text(error).font(.footnote).foregroundStyle(.red) }
                }
            }
            .insetGroupedListStyle()
            .background(CanopyBackground())
            .scrollContentBackground(.hidden)
            .navigationTitle("Add a School")
            .navigationBarTitleInline()
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button(saving ? "Saving…" : "Add School") { Task { await add() } }
                        .fontWeight(.semibold)
                        .disabled(saving)
                }
            }
        }
    }

    private func add() async {
        let name = schoolName.trimmingCharacters(in: .whitespaces)
        let u = url.trimmingCharacters(in: .whitespaces)
        let user = username.trimmingCharacters(in: .whitespaces)
        guard !name.isEmpty, !u.isEmpty, !user.isEmpty, !password.isEmpty else {
            error = "All fields are required."
            return
        }
        saving = true; defer { saving = false }
        error = nil
        do {
            try await APIClient.shared.addSchoolAccount(schoolName: name, url: u, username: user, password: password)
            await store.loadSchoolAccounts()
            onAdded()
            dismiss()
        } catch {
            self.error = "Could not save this school. Check the details and try again."
        }
    }
}
