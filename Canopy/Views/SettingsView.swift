import SwiftUI

struct SettingsView: View {
    @Environment(AuthStore.self) private var authStore
    @Environment(CanopyStore.self) private var store
    @AppStorage("colorScheme") private var colorSchemeRaw = "system"
    @State private var showDeleteConfirm = false

    var body: some View {
        NavigationStack {
            ZStack {
                CanopyBackground()
                List {
                    accountSection
                    schoolSection
                    appearanceSection
                    aboutSection
                    actionsSection
                }
                .listStyle(.insetGrouped)
                .scrollContentBackground(.hidden)
            }
            .navigationTitle("Settings")
            .preferredColorScheme(preferredScheme)
            .alert("Delete Account?", isPresented: $showDeleteConfirm) {
                Button("Delete", role: .destructive, action: performDelete)
                Button("Cancel", role: .cancel, action: {})
            } message: {
                Text("All your data will be permanently deleted and cannot be recovered.")
            }
        }
    }

    // MARK: - Sections
    private var accountSection: some View {
        Section("Account") {
            HStack(spacing: 14) {
                ZStack {
                    Circle().fill(Color.canopyGreen)
                    Text(authStore.user?.username.prefix(1).uppercased() ?? "?")
                        .font(.title2.bold()).foregroundStyle(.white)
                }
                .frame(width: 48, height: 48)
                VStack(alignment: .leading, spacing: 3) {
                    Text(authStore.user?.username ?? "").font(.headline)
                    Text("Canopy account").font(.caption).foregroundStyle(.secondary)
                }
            }
            .padding(.vertical, 4)
        }
    }

    @ViewBuilder
    private var schoolSection: some View {
        if let name = store.settings.schoolName, !name.isEmpty {
            Section("School") {
                LabeledContent("School", value: name)
                if let start = store.settings.semesterStart, !start.isEmpty {
                    LabeledContent("Semester Start", value: start.dueDateLabel)
                }
                if let end = store.settings.semesterEnd, !end.isEmpty {
                    LabeledContent("Semester End", value: end.dueDateLabel)
                }
            }
        }
    }

    private var appearanceSection: some View {
        Section("Appearance") {
            Picker("Color Scheme", selection: $colorSchemeRaw) {
                Label("System", systemImage: "circle.lefthalf.filled").tag("system")
                Label("Light",  systemImage: "sun.max").tag("light")
                Label("Dark",   systemImage: "moon").tag("dark")
            }
        }
    }

    private var aboutSection: some View {
        Section("About") {
            LabeledContent("App", value: "Canopy")
            LabeledContent("Version", value: "1.0")
            LabeledContent("Backend", value: "vercel.apexengineeringak.com")
        }
    }

    private var actionsSection: some View {
        Section {
            Button(action: performLogout) {
                Label("Sign Out", systemImage: "rectangle.portrait.and.arrow.right")
                    .foregroundStyle(.primary)
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

    // MARK: - Computed
    private var preferredScheme: ColorScheme? {
        switch colorSchemeRaw {
        case "light": return .light
        case "dark":  return .dark
        default:      return nil
        }
    }
}
