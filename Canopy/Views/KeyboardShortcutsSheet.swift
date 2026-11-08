import SwiftUI

// Port of web src/components/KeyboardShortcutsModal.tsx + lib/keyboardShortcuts.ts.
// The web uses "G then <key>" sequences (no modifier); on Apple platforms the
// natural equivalent is ⌘1…⌘7 for tabs and ⌘/ for this panel, so the panel
// documents exactly what MainTabView actually binds.

struct ShortcutItem: Identifiable {
    let id = UUID()
    /// Rendered as separate key caps; "then" renders as an italic connector.
    let keys: [String]
    let description: String
}

struct ShortcutGroup: Identifiable {
    let title: String
    let items: [ShortcutItem]
    var id: String { title }
}

enum KeyboardShortcuts {
    /// Tab order shared with MainTabView's hidden ⌘-number buttons.
    static let navTabs: [(label: String, tab: AppTab)] = [
        ("Dashboard", .dashboard),
        ("Classes",   .classes),
        ("Schedule",  .schedule),
        ("Grades",    .grades),
        ("Exams",     .exams),
        ("Tasks",     .homework),
        ("Settings",  .settings),
    ]

    static let groups: [ShortcutGroup] = [
        ShortcutGroup(title: "Navigation", items: navTabs.enumerated().map { i, t in
            ShortcutItem(keys: ["⌘", "\(i + 1)"], description: "Go to \(t.label)")
        }),
        ShortcutGroup(title: "General", items: [
            ShortcutItem(keys: ["⌘", "/"], description: "Show this keyboard shortcuts panel"),
            ShortcutItem(keys: ["Esc"], description: "Close the open dialog or menu"),
            ShortcutItem(keys: ["Tab"], description: "Move focus to the next control"),
            ShortcutItem(keys: ["Shift", "Tab"], description: "Move focus to the previous control"),
            ShortcutItem(keys: ["Return"], description: "Activate the focused button, link, or card"),
            ShortcutItem(keys: ["Space"], description: "Activate the focused button or toggle a checkbox"),
        ]),
    ]
}

struct KeyboardShortcutsSheet: View {
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 22) {
                    ForEach(KeyboardShortcuts.groups) { group in
                        VStack(alignment: .leading, spacing: 10) {
                            Text(group.title.uppercased())
                                .font(.caption.weight(.bold))
                                .tracking(0.5)
                                .foregroundStyle(.secondary)
                            ForEach(group.items) { item in
                                HStack(alignment: .center, spacing: 16) {
                                    Text(item.description).font(.subheadline)
                                    Spacer(minLength: 8)
                                    HStack(spacing: 4) {
                                        ForEach(Array(item.keys.enumerated()), id: \.offset) { i, k in
                                            if k == "then" {
                                                Text("then").font(.caption).italic().foregroundStyle(.tertiary)
                                            } else {
                                                if i > 0 && item.keys[i - 1] != "then" {
                                                    Text("+").font(.caption).foregroundStyle(.tertiary)
                                                }
                                                KeyCap(label: k)
                                            }
                                        }
                                    }
                                }
                            }
                            Divider()
                        }
                    }
                    Text("These are additive — every action in Canopy still works with a mouse or touch.")
                        .font(.caption).foregroundStyle(.secondary)
                }
                .padding(20)
            }
            .background(CanopyBackground())
            .navigationTitle("Keyboard Shortcuts")
            .navigationBarTitleInline()
            .toolbar {
                ToolbarItem(placement: .confirmationAction) { Button("Close") { dismiss() } }
            }
        }
        .presentationDetents([.medium, .large])
        #if os(macOS)
        .frame(minWidth: 420, minHeight: 480)
        #endif
    }
}

private struct KeyCap: View {
    let label: String
    var body: some View {
        Text(label)
            .font(.caption.weight(.semibold).monospaced())
            .frame(minWidth: 24, minHeight: 24)
            .padding(.horizontal, 6)
            .background(Color.secondary.opacity(0.12), in: RoundedRectangle(cornerRadius: 6, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 6, style: .continuous).strokeBorder(Color.secondary.opacity(0.3), lineWidth: 1))
    }
}
