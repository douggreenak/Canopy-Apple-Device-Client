import SwiftUI

// Port of web src/components/SyncReminderDialog.tsx — shown before every
// MANUAL "Sync Now" when a PowerSchool login is saved. Hosts the Scheduled
// Sync toggle (with the "Turn off?" confirmation) so the user can decide
// whether a manual sync is worth it at all.
struct SyncReminderSheet: View {
    @Environment(CanopyStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    let onSync: () -> Void

    @State private var autoSync = true
    @State private var showTurnOffConfirm = false
    @State private var saveError: String?

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 18) {
                Text("Canopy already syncs with PowerSchool automatically once a day, so this is really only worth doing if grades were just updated in PowerSchool and you don't want to wait for the next automatic sync.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)

                Divider()

                ScheduledSyncToggle(autoSync: $autoSync, showTurnOffConfirm: $showTurnOffConfirm, saveError: $saveError,
                                    caption: "Automatically sync PowerSchool once a day. Changes here save immediately.")

                if let saveError {
                    Text(saveError).font(.caption).foregroundStyle(.red)
                }

                Spacer()

                Button {
                    dismiss()
                    onSync()
                } label: {
                    Label("Sync Now", systemImage: "arrow.triangle.2.circlepath")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .keyboardShortcut(.defaultAction)
            }
            .padding(20)
            .navigationTitle("Heads up")
            .navigationBarTitleInline()
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
            }
        }
        .onAppear { autoSync = store.settings.autoSyncEnabled }
        .presentationDetents([.medium, .large])
    }
}

/// The Scheduled Sync switch with web's off-confirmation. Reused by Settings.
struct ScheduledSyncToggle: View {
    @Environment(CanopyStore.self) private var store
    @Binding var autoSync: Bool
    @Binding var showTurnOffConfirm: Bool
    @Binding var saveError: String?
    var caption: String
    var disabled = false

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Toggle(isOn: Binding(
                get: { autoSync },
                set: { newValue in
                    if newValue { Task { await save(true) } } else { showTurnOffConfirm = true }
                }
            )) {
                Label("Scheduled Sync", systemImage: "clock.arrow.2.circlepath")
            }
            .disabled(disabled)
            Text(caption).font(.caption).foregroundStyle(.secondary)
        }
        .alert("Turn off scheduled sync?", isPresented: $showTurnOffConfirm) {
            Button("Cancel", role: .cancel) {}
            Button("Turn Off", role: .destructive) { Task { await save(false) } }
        } message: {
            Text("Canopy will stop automatically checking PowerSchool for new grades and assignments once a day. You can still sync manually, and you can turn this back on anytime.")
        }
    }

    private func save(_ enabled: Bool) async {
        let prev = autoSync
        autoSync = enabled
        saveError = nil
        do { try await store.saveAutoSync(enabled) }
        catch { autoSync = prev; saveError = "Could not save scheduled sync settings." }
    }
}

// MARK: - PowerSchool login-failure banner (web PowerSchoolLoginWarning)
struct PowerSchoolLoginWarningBanner: View {
    var syncStore = PowerSchoolSyncStore.shared
    var onFix: () -> Void

    var body: some View {
        if syncStore.showsLoginWarning {
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.orange).font(.title3)
                VStack(alignment: .leading, spacing: 6) {
                    Text("PowerSchool sync failed — check your password").font(.subheadline.bold())
                    Text("PowerSchool rejected your saved username or password, so your grades and assignments aren't updating. Re-enter your PowerSchool password in Settings and run Sync Now.")
                        .font(.caption).foregroundStyle(.secondary)
                    Button("Fix in Settings", action: onFix).font(.caption.bold()).padding(.top, 2)
                }
                Spacer(minLength: 0)
                Button { syncStore.dismissLoginWarning() } label: {
                    Image(systemName: "xmark").font(.caption.bold()).foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Dismiss")
            }
            .padding(14)
            .background(Color.orange.opacity(0.12), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).strokeBorder(Color.orange.opacity(0.4), lineWidth: 1))
        }
    }
}
