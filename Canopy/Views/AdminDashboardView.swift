import SwiftUI

// Port of web src/app/admin/page.tsx — aggregate stats only, no private data.
struct AdminDashboardView: View {
    @Environment(AuthStore.self) private var authStore
    @State private var stats: SystemStats?
    @State private var error: String?
    @State private var loading = true
    @State private var userToDelete: SystemStats.UserRow?
    @State private var confirmText = ""
    @State private var deleting = false
    @State private var toast: ToastMessage?

    var body: some View {
        NavigationStack {
            ZStack {
                CanopyBackground()
                ScrollView {
                    VStack(alignment: .leading, spacing: 20) {
                        header
                        if loading {
                            ProgressView().frame(maxWidth: .infinity).padding(.top, 40)
                        } else if let error {
                            ContentUnavailableView("Couldn't load stats", systemImage: "exclamationmark.triangle", description: Text(error))
                        } else if let s = stats {
                            section("Users") {
                                statGrid([
                                    ("Registered users", s.totalUsers, nil),
                                    ("Active last 7 days", s.activeUsersLast7Days, "by session"),
                                    ("Active last 30 days", s.activeUsersLast30Days, "by session"),
                                ])
                            }
                            section("Content") {
                                statGrid([
                                    ("Classes", s.totalClasses, nil), ("Assignments", s.totalAssignments, nil),
                                    ("Exams", s.totalExams, nil), ("Tasks", s.totalTasks, nil),
                                ])
                            }
                            section("Registrations by Month") { registrations(s) }
                            section("Registered Users") { users(s) }
                        }
                    }
                    .padding()
                }
                .refreshable { await load() }
            }
            .navigationTitle("Admin")
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Button { Task { await authStore.logout() } } label: { Label("Sign Out", systemImage: "rectangle.portrait.and.arrow.right") }
                }
            }
        }
        .task { await load() }
        .toast($toast)
        .sheet(item: $userToDelete) { u in deleteSheet(u) }
    }

    private var header: some View {
        HStack(spacing: 12) {
            CanopyIconView(size: 44)
            VStack(alignment: .leading, spacing: 2) {
                Text("Admin Dashboard").font(.title2.bold())
                Text("Aggregate stats only — no private user data").font(.caption).foregroundStyle(.secondary)
            }
        }
    }

    @ViewBuilder
    private func section<C: View>(_ title: String, @ViewBuilder _ content: () -> C) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title).font(.headline)
            content()
        }
    }

    private func statGrid(_ items: [(String, Int, String?)]) -> some View {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 140), spacing: 10)], spacing: 10) {
            ForEach(items, id: \.0) { item in
                VStack(alignment: .leading, spacing: 4) {
                    Text("\(item.1)").font(.title.bold()).foregroundStyle(Color.accentColor)
                    Text(item.0).font(.caption).foregroundStyle(.secondary)
                    if let sub = item.2 { Text(sub).font(.caption2).foregroundStyle(.tertiary) }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(12)
                .glassCard(cornerRadius: 14)
            }
        }
    }

    private func registrations(_ s: SystemStats) -> some View {
        let maxCount = max(1, s.registrationsByMonth.map(\.count).max() ?? 1)
        return VStack(spacing: 8) {
            if s.registrationsByMonth.isEmpty {
                Text("No registrations yet.").font(.caption).foregroundStyle(.secondary)
            }
            ForEach(s.registrationsByMonth) { m in
                HStack(spacing: 10) {
                    Text(m.month).font(.caption.monospacedDigit()).frame(width: 64, alignment: .leading)
                    GeometryReader { geo in
                        RoundedRectangle(cornerRadius: 4)
                            .fill(Color.accentColor.opacity(0.8))
                            .frame(width: max(geo.size.width * 0.04, geo.size.width * CGFloat(m.count) / CGFloat(maxCount)))
                    }
                    .frame(height: 14)
                    Text("\(m.count)").font(.caption.bold().monospacedDigit()).frame(width: 30, alignment: .trailing)
                }
            }
        }
        .padding(12)
        .glassCard(cornerRadius: 14)
    }

    private func users(_ s: SystemStats) -> some View {
        VStack(spacing: 0) {
            if s.userList.isEmpty {
                Text("No users yet.").font(.caption).foregroundStyle(.secondary).padding()
            }
            ForEach(s.userList) { u in
                HStack(spacing: 12) {
                    Image(systemName: "person.crop.circle").font(.title2).foregroundStyle(.secondary)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(u.username).font(.subheadline.weight(.medium))
                        Text("Joined \(shortDate(u.registeredAt))").font(.caption).foregroundStyle(.secondary)
                    }
                    Spacer()
                    if let last = u.lastActiveAt, let d = CanopyStore.parseISO(last), d > Date.now.addingTimeInterval(-7 * 86400) {
                        TintedChip(text: "Active", color: .green)
                    } else if let last = u.lastActiveAt {
                        OutlinedChip(text: "Last seen \(shortDate(last))")
                    } else {
                        OutlinedChip(text: "Never active")
                    }
                    Button(role: .destructive) { confirmText = ""; userToDelete = u } label: {
                        Image(systemName: "trash").foregroundStyle(.red)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Delete \(u.username)")
                }
                .padding(.vertical, 10).padding(.horizontal, 12)
                if u.id != s.userList.last?.id { Divider().padding(.leading, 12) }
            }
        }
        .glassCard(cornerRadius: 14)
    }

    private func deleteSheet(_ u: SystemStats.UserRow) -> some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 16) {
                Text("This will permanently delete **\(u.username)** and all of their classes, assignments, grades, tasks, and settings. This cannot be undone.")
                    .font(.subheadline)
                TextField("Type \"\(u.username)\" to confirm", text: $confirmText)
                    .textFieldStyle(.roundedBorder)
                    .textAutocapNever()
                    .autocorrectionDisabled()
                Spacer()
                Button(role: .destructive) {
                    Task { await deleteUser(u) }
                } label: {
                    Text(deleting ? "Deleting…" : "Delete").frame(maxWidth: .infinity)
                }
                .buttonStyle(.glassProminent)
                .tint(.red)
                .controlSize(.large)
                .disabled(confirmText != u.username || deleting)
            }
            .padding(20)
            .navigationTitle("Delete user?")
            .navigationBarTitleInline()
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Cancel") { userToDelete = nil } } }
        }
        .presentationDetents([.medium])
    }

    private func load() async {
        loading = stats == nil
        error = nil
        do { stats = try await APIClient.shared.getAdminStats() }
        catch { self.error = error.localizedDescription }
        loading = false
    }

    private func deleteUser(_ u: SystemStats.UserRow) async {
        deleting = true
        defer { deleting = false }
        do {
            try await APIClient.shared.adminDeleteUser(username: u.username)
            userToDelete = nil
            toast = ToastMessage(text: "Deleted \(u.username).", kind: .success)
            await load()
        } catch {
            toast = ToastMessage(text: error.localizedDescription, kind: .error)
        }
    }

    private func shortDate(_ iso: String) -> String {
        guard let d = CanopyStore.parseISO(iso) else { return iso }
        return DateFormatter.monthDayYear.string(from: d)
    }
}
