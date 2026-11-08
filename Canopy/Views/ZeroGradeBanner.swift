import SwiftUI

// Zero-grade warnings (web ZeroGradeBanner). A synced PowerSchool assignment
// that scored 0 raises a dismissible banner. Dismissing is permanent for that
// assignment and saved in the `dismissedZeroAssignments` server setting so it
// stays dismissed on web, iPhone, iPad, Mac, and Watch.

extension Homework {
    /// Identity that survives re-syncs: PowerSchool's own id when present.
    var zeroKey: String { sourceId?.nonEmpty ?? id }

    var isZeroGrade: Bool {
        guard source == "powerschool" else { return false }
        if let f = flags, f.range(of: "exempt|collected", options: [.regularExpression, .caseInsensitive]) != nil { return false }
        guard let pct = percentValue else { return false }
        return pct == 0
    }
}

extension AppSettings {
    var dismissedZeroKeys: Set<String> {
        guard let raw = dismissedZeroAssignments, let data = raw.data(using: .utf8),
              let arr = try? JSONDecoder().decode([String].self, from: data) else { return [] }
        return Set(arr)
    }
}

extension CanopyStore {
    /// Zero-scored assignments not yet dismissed, newest due date first.
    var activeZeroAssignments: [Homework] {
        let hidden = settings.dismissedZeroKeys
        return homework
            .filter { $0.isZeroGrade && !hidden.contains($0.zeroKey) }
            .sorted { $0.dueDate > $1.dueDate }
    }

    /// Optimistically hides the banner, then saves; rolls back if the save fails.
    func dismissZeroAssignments(_ keys: [String]) async {
        let previous = settings.dismissedZeroAssignments
        var all = (try? JSONDecoder().decode([String].self, from: Data((previous ?? "[]").utf8))) ?? []
        for k in keys where !all.contains(k) { all.append(k) }
        all = Array(all.suffix(150))   // server caps a setting at 10,000 chars
        guard let data = try? JSONEncoder().encode(all), let json = String(data: data, encoding: .utf8) else { return }
        settings.dismissedZeroAssignments = json
        do {
            try await APIClient.shared.saveSetting(key: "dismissedZeroAssignments", value: json)
        } catch {
            settings.dismissedZeroAssignments = previous
            lastMutationError = "Couldn't save that dismissal: \(error.localizedDescription)"
        }
    }
}

struct ZeroGradeBanner: View {
    @Environment(CanopyStore.self) private var store

    var body: some View {
        let zeros = store.activeZeroAssignments
        Group {
            if let first = zeros.first {
            let cls = store.schoolClass(first.classId)
            HStack(alignment: .top, spacing: 10) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.title3)
                    .foregroundStyle(.orange)
                VStack(alignment: .leading, spacing: 3) {
                    Text(zeros.count == 1 ? "You got a 0 on \(first.title)" : "You have \(zeros.count) assignments with a 0")
                        .font(.subheadline.weight(.semibold))
                    Group {
                        if zeros.count == 1 {
                            Text((cls.map { "\($0.name) — " } ?? "") + "talk to your teacher about making it up.")
                        } else {
                            Text(zeros.prefix(4).map { h in
                                store.schoolClass(h.classId).map { "\(h.title) (\($0.name))" } ?? h.title
                            }.joined(separator: " · "))
                        }
                    }
                    .font(.caption).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                    if let cls {
                        Button("View grades") {
                            AppNavigation.shared.goToGrades(classId: cls.id)
                        }
                        .font(.caption.weight(.semibold))
                        .padding(.top, 2)
                    }
                }
                Spacer(minLength: 0)
                Button {
                    Task { await store.dismissZeroAssignments(zeros.map(\.zeroKey)) }
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.title3)
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Dismiss zero-grade warning")
            }
            .padding(12)
            .background(.orange.opacity(0.12), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            .glassEffect(.regular.tint(.orange.opacity(0.18)), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            .transition(.move(edge: .top).combined(with: .opacity))
            }
        }
        .animation(.spring(duration: 0.3), value: zeros.count)
    }
}
