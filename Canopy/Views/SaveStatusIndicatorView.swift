import SwiftUI

// Port of web src/components/SaveStatusIndicator.tsx — a small, non-blocking
// status pill driven by NetworkActivity (generic save tracking) and
// PowerSchoolSyncStore (a sync can keep running for minutes after the user
// has navigated elsewhere). Renders nothing when there's nothing to say.
struct SaveStatusIndicatorView: View {
    @Environment(\.colorScheme) private var scheme
    var activity = NetworkActivity.shared
    var syncStore = PowerSchoolSyncStore.shared
    /// Collapses to the icon only (web `dense`).
    var dense = false

    /// "Saved" lingers for 2 s after the last successful mutation.
    @State private var showSaved = false

    private enum EffectiveState { case offline, syncing, saving, error, saved, none }

    private var state: EffectiveState {
        if activity.isOffline { return .offline }
        if syncStore.isRunning { return .syncing }
        if activity.inFlightMutations > 0 { return .saving }
        if activity.lastMutationFailed { return .error }
        if showSaved { return .saved }
        return .none
    }

    private var label: String {
        switch state {
        case .offline: return "No internet connection"
        case .syncing: return "Syncing PowerSchool…"
        case .saving:  return "Saving…"
        case .saved:   return "Saved"
        case .error:   return "Couldn't save"
        case .none:    return ""
        }
    }

    private var color: Color {
        switch state {
        case .offline, .error:   return CanopyPalette.error(scheme)
        case .saving, .syncing:  return .secondary
        case .saved:             return CanopyPalette.success(scheme)
        case .none:              return .clear
        }
    }

    var body: some View {
        Group {
            if state != .none {
                HStack(spacing: 6) {
                    icon
                    if !dense {
                        Text(label).font(.caption.weight(.medium))
                    }
                }
                .foregroundStyle(color)
                .padding(.horizontal, dense ? 6 : 10).padding(.vertical, 5)
                .background(.regularMaterial, in: Capsule())
                .shadow(color: .black.opacity(0.08), radius: 6, y: 2)
                .accessibilityLabel(label)
                .transition(.move(edge: .top).combined(with: .opacity))
            }
        }
        .animation(.easeInOut(duration: 0.2), value: state == .none)
        .task(id: activity.lastSavedAt) {
            guard activity.lastSavedAt != nil else { return }
            showSaved = true
            try? await Task.sleep(nanoseconds: 2_000_000_000)
            if !Task.isCancelled { showSaved = false }
        }
    }

    @ViewBuilder
    private var icon: some View {
        switch state {
        case .syncing:
            Image(systemName: "arrow.triangle.2.circlepath")
                .font(.caption.weight(.semibold))
                .symbolEffect(.rotate, options: .repeating)
        case .saving:
            ProgressView().controlSize(.mini)
        case .offline:
            Image(systemName: "icloud.slash").font(.caption.weight(.semibold))
        case .error:
            Image(systemName: "exclamationmark.circle").font(.caption.weight(.semibold))
        case .saved:
            Image(systemName: "checkmark.icloud").font(.caption.weight(.semibold))
        case .none:
            EmptyView()
        }
    }
}
