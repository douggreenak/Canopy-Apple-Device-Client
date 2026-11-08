import SwiftUI

/// Package-tracking style progress indicator for a per-item completion
/// pipeline — port of web StageTracker.tsx.
///
/// Read-only when `onSelectStage` is nil (e.g. a preview). Otherwise every
/// stage node is tappable:
///   - Tap the current stage -> step back one (or to "not started" if it's
///     the first stage) — a mis-tap or "actually not done yet" is one tap to undo.
///   - Tap any other stage -> jump straight to it (every earlier stage is
///     implicitly reached, like a shipment tracker).
struct StageTrackerView: View {
    let stages: [TaskStage]
    let currentStageId: String?
    var onSelectStage: ((String?) -> Void)? = nil

    @Environment(\.colorScheme) private var scheme

    private var currentIndex: Int {
        guard let currentStageId else { return -1 }
        return stages.firstIndex { $0.id == currentStageId } ?? -1
    }

    private var activeColor: Color { CanopyPalette.success(scheme) }

    var body: some View {
        if stages.isEmpty {
            EmptyView()
        } else {
            VStack(alignment: .leading, spacing: 10) {
                // Header: current position in the pipeline (web shows it above the nodes).
                Text(currentIndex == -1 ? "Not started" : stages[currentIndex].label)
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(currentIndex == -1 ? Color.secondary : Color.primary)
                    .animation(.easeInOut(duration: 0.15), value: currentIndex)

                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(alignment: .top, spacing: 0) {
                        ForEach(Array(stages.enumerated()), id: \.element.id) { i, stage in
                            stageNode(stage, index: i)
                            if i < stages.count - 1 {
                                Rectangle()
                                    .fill(i < currentIndex ? activeColor : Color.secondary.opacity(0.25))
                                    .frame(width: 22, height: 2)
                                    .padding(.top, 13)
                                    .animation(.easeInOut(duration: 0.15), value: currentIndex)
                            }
                        }
                    }
                    .padding(.vertical, 4).padding(.horizontal, 2)
                }
            }
        }
    }

    private func stageNode(_ stage: TaskStage, index i: Int) -> some View {
        let reached = i <= currentIndex
        let isCurrent = i == currentIndex
        return Button {
            guard let onSelectStage else { return }
            onSelectStage(i == currentIndex ? (i == 0 ? nil : stages[i - 1].id) : stage.id)
        } label: {
            VStack(spacing: 5) {
                ZStack {
                    // Halo on the current node
                    Circle()
                        .fill(activeColor.opacity(0.2))
                        .frame(width: 34, height: 34)
                        .opacity(isCurrent ? 1 : 0)
                    Circle()
                        .fill(reached ? activeColor : Color.clear)
                        .frame(width: 28, height: 28)
                    Circle()
                        .strokeBorder(reached ? activeColor : Color.secondary.opacity(0.35), lineWidth: 2)
                        .frame(width: 28, height: 28)
                    if reached {
                        Image(systemName: "checkmark")
                            .font(.system(size: 12, weight: .bold))
                            .foregroundStyle(.white)
                    } else {
                        Circle()
                            .fill(Color.secondary.opacity(0.6))
                            .frame(width: 6, height: 6)
                    }
                }
                .frame(width: 34, height: 34)
                .animation(.easeInOut(duration: 0.15), value: currentIndex)

                Text(stage.label)
                    .font(.caption.weight(isCurrent ? .bold : .regular))
                    .foregroundStyle(reached ? Color.primary : Color.secondary)
                    .multilineTextAlignment(.center)
                    .lineLimit(2)
                    .frame(width: 76)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(onSelectStage == nil)
        .accessibilityLabel(isCurrent ? "Currently at \(stage.label) — tap to step back" : "Mark as \(stage.label)")
    }
}
