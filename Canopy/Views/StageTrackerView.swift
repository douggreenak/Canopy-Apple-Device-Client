import SwiftUI

/// Interactive completion-stage tracker — port of web StageTracker.tsx.
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

    private var currentIndex: Int {
        guard let currentStageId else { return -1 }
        return stages.firstIndex { $0.id == currentStageId } ?? -1
    }

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 0) {
                ForEach(Array(stages.enumerated()), id: \.element.id) { i, stage in
                    stageNode(stage, index: i)
                    if i < stages.count - 1 {
                        Rectangle()
                            .fill(i < currentIndex ? Color.accentColor : Color.secondary.opacity(0.25))
                            .frame(width: 20, height: 2)
                    }
                }
            }
            .padding(.vertical, 6).padding(.horizontal, 2)
        }
    }

    private func stageNode(_ stage: TaskStage, index i: Int) -> some View {
        let reached = i <= currentIndex
        let isCurrent = i == currentIndex
        return Button {
            guard let onSelectStage else { return }
            onSelectStage(i == currentIndex ? (i == 0 ? nil : stages[i - 1].id) : stage.id)
        } label: {
            VStack(spacing: 6) {
                ZStack {
                    Circle()
                        .fill(reached ? Color.accentColor : Color.secondary.opacity(0.15))
                        .frame(width: isCurrent ? 28 : 22, height: isCurrent ? 28 : 22)
                    if reached && !isCurrent {
                        Image(systemName: "checkmark")
                            .font(.system(size: 10, weight: .bold))
                            .foregroundStyle(.white)
                    } else if isCurrent {
                        Circle().fill(.white).frame(width: 9, height: 9)
                    }
                }
                Text(stage.label)
                    .font(.system(size: 10, weight: isCurrent ? .bold : .regular))
                    .foregroundStyle(reached ? .primary : .secondary)
                    .lineLimit(1)
                    .frame(maxWidth: 70)
            }
        }
        .buttonStyle(.plain)
        .disabled(onSelectStage == nil)
    }
}
