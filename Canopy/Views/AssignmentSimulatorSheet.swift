import SwiftUI

// Port of web src/components/AssignmentGradeSimulatorDialog.tsx — opens from
// tapping an assignment on the class detail: drag the slider to "what if I
// scored X% on this?" and see the class grade before vs. after.

struct AssignmentSimulatorSheet: View {
    @Environment(\.dismiss) private var dismiss
    let cls: SchoolClass
    /// Every PowerSchool assignment in this class — needed to recompute the grade.
    let homework: [Homework]
    let assignment: Homework

    @State private var percent: Double = 85

    private var weights: [String: Double] { cls.categoryWeights ?? [:] }
    private var currentPct: Double? { assignment.percentValue }

    private var prediction: GradePrediction {
        predictGradeChange(assignments: homework, weights: weights, assignmentId: assignment.id,
                           percent: percent, officialGrade: cls.gradePercent)
    }

    private var delta: Double? {
        guard let old = prediction.oldGrade, let new = prediction.newGrade else { return nil }
        return new - old
    }

    private var subtitle: String {
        assignment.title + (assignment.category?.nonEmpty.map { " · \($0)" } ?? "")
    }

    private var intro: String {
        if let p = currentPct {
            return "You currently have \(GradesDisplay.pct1(p)) on this assignment. Drag the slider to try a different score and see what it would do to your \(cls.name) grade."
        }
        return "This assignment isn't graded yet. Drag the slider to guess your score and see what it would do to your \(cls.name) grade."
    }

    private var methodNote: String {
        if prediction.method == .weighted {
            return "Estimated using your class's grade categories and weights (\(GradesDisplay.weightsText(weights, separator: ", "))). \"Grade now\" is your PowerSchool grade."
        }
        return "This class doesn't use category weights, so it's graded on total points — a 100-point test moves your grade more than a 5-point worksheet. This is an estimate of that calculation; 'Grade now' is your PowerSchool grade."
    }

    var body: some View {
        NavigationStack {
            ZStack { CanopyBackground()
                ScrollView {
                    VStack(alignment: .leading, spacing: 18) {
                        Text(subtitle)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)

                        Text(intro)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)

                        VStack(spacing: 2) {
                            Text("Score on this assignment").font(.caption).foregroundStyle(.secondary)
                            Text("\(Int(percent))%")
                                .font(.system(size: 40, weight: .semibold, design: .rounded))
                                .monospacedDigit()
                                .contentTransition(.numericText())
                        }
                        .frame(maxWidth: .infinity)

                        VStack(spacing: 2) {
                            Slider(value: $percent, in: 0...100, step: 1)
                                .tint(.accentColor)
                                .accessibilityLabel("Simulated score on this assignment")
                            HStack {
                                Text("0%"); Spacer(); Text("50%"); Spacer(); Text("100%")
                            }
                            .font(.caption2)
                            .foregroundStyle(.tertiary)
                        }
                        .padding(.horizontal, 4)

                        HStack(spacing: 8) {
                            gradeBox(label: "Grade now", value: prediction.oldGrade, emphasized: false)
                            Image(systemName: "arrow.right").font(.title3).foregroundStyle(.tertiary)
                            gradeBox(label: "Predicted", value: prediction.newGrade, emphasized: true)
                        }

                        if let d = delta {
                            deltaChip(d).frame(maxWidth: .infinity)
                        }

                        GradeInfoBox { Text(methodNote).font(.caption) }
                    }
                    .padding(16)
                    .padding(.bottom, 24)
                }
            }
            .navigationTitle("What if I score…?")
            .navigationBarTitleInline()
            .toolbar {
                ToolbarItem(placement: .confirmationAction) { Button("Close") { dismiss() } }
            }
        }
        .onAppear { percent = (currentPct ?? 85).rounded() }
        .animation(.easeOut(duration: 0.15), value: percent)
    }

    // MARK: Pieces

    private func gradeBox(label: String, value: Double?, emphasized: Bool) -> some View {
        let color = GradesUtil.gradeColor(value)
        let shape = RoundedRectangle(cornerRadius: 12, style: .continuous)
        return VStack(spacing: 2) {
            Text(label.uppercased())
                .font(.caption2.weight(.semibold))
                .tracking(0.5)
                .foregroundStyle(.secondary)
            if let v = value {
                Text(GradesDisplay.pct1(v))
                    .font(.system(size: 26, weight: .semibold, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(color)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                    .contentTransition(.numericText())
                Text(GradesUtil.letterFromPercent(v))
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(color)
            } else {
                Text("—").font(.system(size: 26)).foregroundStyle(.tertiary)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 12)
        .padding(.horizontal, 8)
        .background(emphasized ? color.opacity(0.08) : Color.clear, in: shape)
        .overlay(shape.strokeBorder(emphasized ? color : Color.secondary.opacity(0.25), lineWidth: 1))
    }

    private func deltaChip(_ d: Double) -> some View {
        let noChange = abs(d) < 0.05
        let text = noChange
            ? "No change to your grade"
            : "\(d > 0 ? "+" : "")\(String(format: "%.1f", d)) points \(d > 0 ? "higher" : "lower")"
        let color: Color = d > 0.05 ? .green : d < -0.05 ? .red : .secondary
        return Text(text)
            .font(.caption.weight(.semibold))
            .monospacedDigit()
            .padding(.horizontal, 12).padding(.vertical, 5)
            .background(color.opacity(0.14), in: Capsule())
            .foregroundStyle(color)
    }
}
