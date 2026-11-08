import SwiftUI

/// Lets a single Task/Homework define its own completion pipeline (e.g.
/// Done → Turned In). Embedded in HomeworkEditSheet and TaskEditSheet — port
/// of web StageListEditor plus the dialog's "Completion Stages (optional)"
/// heading and caption. Labels are trimmed and blanks are never added; the
/// sheets additionally drop blank labels on save.
struct StageListEditorView: View {
    @Binding var stages: [TaskStage]
    @State private var newLabel = ""

    private var canAdd: Bool { !newLabel.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }

    var body: some View {
        FormEditCard {
            VStack(alignment: .leading, spacing: 0) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Completion Stages (optional)")
                        .font(.subheadline.weight(.semibold))
                    Text("Track this item's own progress — e.g. **Done** then **Turned In** — instead of a plain checkbox. Applies only to this item.")
                        .font(.caption).foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(.horizontal, 16).padding(.top, 13).padding(.bottom, 12)

                if !stages.isEmpty {
                    Divider().padding(.leading, 16)
                    ForEach(Array(stages.enumerated()), id: \.element.id) { i, _ in
                        stageRow(index: i)
                        if i < stages.count - 1 { Divider().padding(.leading, 16) }
                    }
                }

                Divider().padding(.leading, 16)
                HStack(spacing: 10) {
                    TextField("e.g. Turned In", text: $newLabel)
                        .font(.subheadline)
                        .textFieldStyle(.plain)
                        .onSubmit { addStage() }
                        .submitLabel(.done)
                    Button { addStage() } label: {
                        Label("Add Stage", systemImage: "plus")
                            .font(.subheadline.weight(.medium))
                    }
                    .buttonStyle(.glass)
                    .buttonBorderShape(.capsule)
                    .controlSize(.small)
                    .disabled(!canAdd)
                }
                .padding(.horizontal, 16).padding(.vertical, 10)
            }
        }
    }

    private func stageRow(index i: Int) -> some View {
        HStack(spacing: 8) {
            Text("\(i + 1)")
                .font(.caption.bold()).foregroundStyle(.secondary)
                .frame(width: 16, alignment: .trailing)
            TextField("Stage name", text: Binding(
                get: { i < stages.count ? stages[i].label : "" },
                set: { if i < stages.count { stages[i].label = $0 } }
            ))
            .font(.subheadline)
            .textFieldStyle(.plain)
            HStack(spacing: 14) {
                Button { moveStage(i, -1) } label: { Image(systemName: "arrow.up") }
                    .disabled(i == 0)
                    .accessibilityLabel("Move stage up")
                Button { moveStage(i, 1) } label: { Image(systemName: "arrow.down") }
                    .disabled(i == stages.count - 1)
                    .accessibilityLabel("Move stage down")
            }
            .font(.caption.weight(.semibold))
            .buttonStyle(.plain)
            .foregroundStyle(.secondary)
            Button(role: .destructive) {
                withAnimation(.spring(response: 0.25)) { _ = stages.remove(at: i) }
            } label: {
                Image(systemName: "trash")
            }
            .font(.caption.weight(.semibold))
            .buttonStyle(.plain)
            .foregroundStyle(.red)
            .accessibilityLabel("Remove stage")
        }
        .padding(.horizontal, 16).padding(.vertical, 8)
    }

    private func addStage() {
        let label = newLabel.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !label.isEmpty else { return }
        withAnimation(.spring(response: 0.25)) {
            stages.append(TaskStage(id: UUID().uuidString, label: label))
        }
        newLabel = ""
    }

    private func moveStage(_ i: Int, _ dir: Int) {
        let target = i + dir
        guard target >= 0, target < stages.count else { return }
        withAnimation(.spring(response: 0.25)) { stages.swapAt(i, target) }
    }
}
