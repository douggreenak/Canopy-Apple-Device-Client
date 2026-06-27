import SwiftUI

// Port of web src/components/FinalGradeDialog.tsx — "what score do I need on the final?"

struct FinalGradeSheet: View {
    @Environment(\.dismiss) private var dismiss
    let currentGrade: Double?
    let className: String

    @State private var finalWeight = "20"

    private struct Target: Identifiable { let label: String; let min: Double; var id: String { label } }
    private let targets: [Target] = [
        .init(label: "A",  min: 93), .init(label: "A-", min: 90),
        .init(label: "B+", min: 87), .init(label: "B",  min: 83), .init(label: "B-", min: 80),
        .init(label: "C+", min: 77), .init(label: "C",  min: 73), .init(label: "C-", min: 70),
        .init(label: "D",  min: 60),
    ]

    private var weight: Double? {
        guard let w = Double(finalWeight), w > 0, w <= 100 else { return nil }
        return w
    }

    private func neededScore(target: Double) -> Double {
        let w = weight ?? 20
        let courseworkWeight = 1 - w / 100
        return (target - courseworkWeight * (currentGrade ?? 0)) / (w / 100)
    }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    Text("Enter your final exam's weight to see the score you need for each letter grade.")
                        .font(.footnote).foregroundStyle(.secondary)
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("CURRENT GRADE").font(.caption2.bold()).foregroundStyle(.secondary)
                            Text(currentGrade != nil ? String(format: "%.1f%%", currentGrade!) : "—")
                                .font(.title2.bold().monospacedDigit())
                        }
                        Spacer()
                        VStack(alignment: .trailing, spacing: 2) {
                            Text("FINAL WEIGHT").font(.caption2.bold()).foregroundStyle(.secondary)
                            HStack(spacing: 2) {
                                TextField("20", text: $finalWeight)
                                    .frame(width: 50)
                                    .multilineTextAlignment(.trailing)
                                    #if os(iOS)
                                    .keyboardType(.numberPad)
                                    #endif
                                Text("%").foregroundStyle(.secondary)
                            }
                        }
                    }
                }

                if currentGrade == nil {
                    Section {
                        Label("No current grade recorded for this class.", systemImage: "info.circle")
                            .font(.footnote).foregroundStyle(.secondary)
                    }
                }

                if let w = weight, currentGrade != nil {
                    Section {
                        ForEach(targets) { t in
                            let needed = neededScore(target: t.min)
                            HStack {
                                Text(t.label).font(.subheadline.bold()).frame(width: 36, alignment: .leading)
                                Text("\(Int(t.min))%").font(.caption).foregroundStyle(.secondary)
                                Spacer()
                                if needed <= 0 {
                                    Text("Already secured").font(.subheadline.bold()).foregroundStyle(.green)
                                } else if needed <= 100 {
                                    Text(String(format: "%.1f%%", needed)).font(.subheadline.bold().monospacedDigit())
                                } else {
                                    Text("Not possible").font(.subheadline.bold()).foregroundStyle(.red)
                                }
                            }
                        }
                    } header: {
                        Text("Scores Needed on Final")
                    } footer: {
                        Text("Assumes the final is worth \(Int(w))% and the remaining \(Int(100 - w))% is locked in at \(String(format: "%.1f%%", currentGrade!)).")
                    }
                }
            }
            .insetGroupedListStyle()
            .background(CanopyBackground())
            .scrollContentBackground(.hidden)
            .navigationTitle("Final Grade Calculator")
            .navigationBarTitleInline()
            .toolbar {
                ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } }
            }
        }
    }
}
