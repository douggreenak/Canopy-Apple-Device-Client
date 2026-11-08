import SwiftUI

// Port of web src/components/FinalGradeDialog.tsx — "what score do I need on the final?"

struct FinalGradeSheet: View {
    @Environment(\.dismiss) private var dismiss
    let currentGrade: Double?
    var className: String? = nil

    @State private var finalWeight = "20"

    private struct Target: Identifiable { let label: String; let min: Double; var id: String { label } }
    private let targets: [Target] = [
        .init(label: "A",  min: 93), .init(label: "A-", min: 90),
        .init(label: "B+", min: 87), .init(label: "B",  min: 83), .init(label: "B-", min: 80),
        .init(label: "C+", min: 77), .init(label: "C",  min: 73), .init(label: "C-", min: 70),
        .init(label: "D",  min: 60),
    ]

    /// Decimal weights allowed (web `parseFloat`), valid in (0, 100].
    private var weight: Double? {
        guard let w = Double(finalWeight.trimmingCharacters(in: .whitespaces)), w > 0, w <= 100 else { return nil }
        return w
    }

    private func neededScore(current: Double, weight w: Double, target: Double) -> Double {
        let courseworkWeight = 1 - w / 100
        return (target - courseworkWeight * current) / (w / 100)
    }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    Text("Enter the weight of your final exam to see what score you need to reach each letter grade.")
                        .font(.footnote).foregroundStyle(.secondary)
                    HStack(alignment: .top) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("CURRENT GRADE").font(.caption2.bold()).foregroundStyle(.secondary).tracking(0.5)
                            Text(currentGrade.map { GradesDisplay.pct1($0) } ?? "—")
                                .font(.title2.weight(.medium).monospacedDigit())
                                .foregroundStyle(GradesUtil.gradeColor(currentGrade))
                        }
                        Spacer()
                        VStack(alignment: .trailing, spacing: 2) {
                            Text("FINAL EXAM WEIGHT").font(.caption2.bold()).foregroundStyle(.secondary).tracking(0.5)
                            HStack(spacing: 2) {
                                TextField("20", text: $finalWeight)
                                    .frame(width: 56)
                                    .multilineTextAlignment(.trailing)
                                    #if os(iOS)
                                    .keyboardType(.decimalPad)
                                    #endif
                                Text("%").foregroundStyle(.secondary)
                            }
                            Text("Percent of total grade").font(.caption2).foregroundStyle(.tertiary)
                        }
                    }
                }

                if currentGrade == nil {
                    Section {
                        Label("No current grade recorded for this class.", systemImage: "info.circle")
                            .font(.footnote).foregroundStyle(.secondary)
                    }
                }

                if let w = weight, let current = currentGrade {
                    Section {
                        HStack {
                            Text("Grade").frame(width: 40, alignment: .leading)
                            Text("Threshold")
                            Spacer()
                            Text("Need")
                        }
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                        ForEach(targets) { t in
                            let needed = neededScore(current: current, weight: w, target: t.min)
                            HStack {
                                Text(t.label).font(.subheadline.bold()).frame(width: 40, alignment: .leading)
                                Text("\(Int(t.min))%").font(.subheadline).foregroundStyle(.secondary)
                                Spacer()
                                if needed <= 0 {
                                    Text("Already secured").font(.subheadline.bold()).foregroundStyle(.green)
                                } else if needed <= 100 {
                                    Text(GradesDisplay.pct1(needed)).font(.subheadline.bold().monospacedDigit())
                                } else {
                                    Text("Not possible").font(.subheadline.bold()).foregroundStyle(.red)
                                }
                            }
                        }
                    } header: {
                        Text("Scores Needed on Final")
                    } footer: {
                        Text("Assumes the final is worth \(GradesDisplay.num(w))% and the remaining \(Int((100 - w).rounded()))% is already locked in at \(GradesDisplay.pct1(current)).")
                    }
                }
            }
            .insetGroupedListStyle()
            .background(CanopyBackground())
            .scrollContentBackground(.hidden)
            .navigationTitle(className.map { "Final Grade Calculator — \($0)" } ?? "Final Grade Calculator")
            .navigationBarTitleInline()
            .toolbar {
                ToolbarItem(placement: .confirmationAction) { Button("Close") { dismiss() } }
            }
        }
    }
}
