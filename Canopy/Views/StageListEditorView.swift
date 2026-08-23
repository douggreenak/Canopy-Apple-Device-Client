import SwiftUI

/// Add/rename/reorder/delete a per-item completion-stage pipeline. Embedded in
/// HomeworkEditSheet and TaskEditSheet. Port of web's StageListEditor.
struct StageListEditorView: View {
    @Binding var stages: [TaskStage]

    var body: some View {
        FormEditCard {
            VStack(alignment: .leading, spacing: 0) {
                Label("Completion Stages", systemImage: "list.number")
                    .font(.body)
                    .padding(.horizontal, 16).padding(.top, 13).padding(.bottom, 8)

                if stages.isEmpty {
                    Text("This item uses a plain checkbox. Add stages for a multi-step pipeline — e.g. Draft → Turned In → Graded.")
                        .font(.caption).foregroundStyle(.secondary)
                        .padding(.horizontal, 16).padding(.bottom, 12)
                } else {
                    Divider().padding(.leading, 16)
                    ForEach(Array(stages.enumerated()), id: \.element.id) { i, _ in
                        stageRow(index: i)
                        if i < stages.count - 1 { Divider().padding(.leading, 16) }
                    }
                }

                Divider().padding(.leading, 16)
                Button { addStage() } label: {
                    Label("Add Stage", systemImage: "plus.circle")
                        .font(.subheadline)
                }
                .padding(16)
            }
        }
    }

    private func stageRow(index i: Int) -> some View {
        HStack(spacing: 8) {
            Text("\(i + 1)")
                .font(.caption.bold()).foregroundStyle(.secondary)
                .frame(width: 16)
            TextField("Stage name", text: Binding(
                get: { stages[i].label },
                set: { stages[i].label = $0 }
            ))
            .font(.subheadline)
            HStack(spacing: 14) {
                Button { moveUp(i) } label: { Image(systemName: "chevron.up") }
                    .disabled(i == 0)
                Button { moveDown(i) } label: { Image(systemName: "chevron.down") }
                    .disabled(i == stages.count - 1)
            }
            .font(.caption)
            .buttonStyle(.plain)
            .foregroundStyle(.secondary)
            Button(role: .destructive) { stages.remove(at: i) } label: {
                Image(systemName: "minus.circle.fill")
            }
            .buttonStyle(.plain)
            .foregroundStyle(.red)
        }
        .padding(.horizontal, 16).padding(.vertical, 8)
    }

    private func addStage() {
        stages.append(TaskStage(id: UUID().uuidString, label: "Stage \(stages.count + 1)"))
    }

    private func moveUp(_ i: Int) {
        guard i > 0 else { return }
        stages.swapAt(i, i - 1)
    }

    private func moveDown(_ i: Int) {
        guard i < stages.count - 1 else { return }
        stages.swapAt(i, i + 1)
    }
}
