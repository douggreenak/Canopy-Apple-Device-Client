import SwiftUI

struct WhatIfSheet: View {
    @Environment(\.dismiss) private var dismiss
    let cls: SchoolClass
    let assignments: [Homework]

    @State private var selectedCategory: String = ""
    @State private var hypotheticalScore: Double = 85.0
    @State private var scoreText: String = "85"
    @FocusState private var scoreFocused: Bool

    private var weights: [String: Double] { cls.categoryWeights ?? [:] }
    private var categories: [String] { weights.keys.filter { (weights[$0] ?? 0) > 0 }.sorted() }

    private var currentGrade: Double? { overallGrade(assignments: assignments, weights: weights) }

    private var projectedGrade: Double? {
        guard !selectedCategory.isEmpty else { return nil }
        return simulateWhatIf(
            assignments: assignments,
            weights: weights,
            category: selectedCategory,
            percent: hypotheticalScore
        )
    }

    private var delta: Double? {
        guard let cur = currentGrade, let proj = projectedGrade else { return nil }
        return proj - cur
    }

    var body: some View {
        NavigationStack {
            ZStack { CanopyBackground()
                ScrollView {
                    VStack(spacing: 20) {
                        // Current grade hero
                        if let cur = currentGrade {
                            currentGradeCard(cur)
                        } else {
                            noGradeNotice
                        }

                        // Category picker
                        if categories.isEmpty {
                            noWeightsNotice
                        } else {
                            categoryCard
                            scoreCard
                            if let proj = projectedGrade {
                                resultCard(projected: proj)
                            }
                        }
                    }
                    .padding(16)
                    .padding(.bottom, 32)
                }
            }
            .navigationTitle("What If?")
            .navigationBarTitleInline()
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
                ToolbarItemGroup(placement: .keyboard) {
                    Spacer()
                    Button("Done") { scoreFocused = false }
                }
            }
        }
        .onAppear {
            selectedCategory = categories.first ?? ""
        }
    }

    // MARK: - Current grade card
    private func currentGradeCard(_ pct: Double) -> some View {
        HStack(spacing: 20) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Current grade").font(.caption).foregroundStyle(.secondary)
                Text(cls.name).font(.headline).lineLimit(1)
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 2) {
                Text(letterGrade(from: pct))
                    .font(.system(size: 44, weight: .bold, design: .rounded))
                    .foregroundStyle(gradeColor(letterGrade(from: pct)))
                Text(String(format: "%.1f%%", pct))
                    .font(.callout.monospacedDigit())
                    .foregroundStyle(.secondary)
            }
        }
        .padding(16)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
    }

    // MARK: - No grade notice
    private var noGradeNotice: some View {
        Label("No graded assignments yet — results will appear once PowerSchool is synced.", systemImage: "info.circle")
            .font(.subheadline)
            .foregroundStyle(.secondary)
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
    }

    // MARK: - No weights notice
    private var noWeightsNotice: some View {
        Label("No category weights configured for this class. Add weights in the class editor to use What If.", systemImage: "exclamationmark.triangle")
            .font(.subheadline)
            .foregroundStyle(.orange)
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(.orange.opacity(0.1), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
    }

    // MARK: - Category picker card
    private var categoryCard: some View {
        FormEditCard {
            HStack {
                Label("Category", systemImage: "tag").font(.body)
                Spacer()
                Picker("", selection: $selectedCategory) {
                    ForEach(categories, id: \.self) { cat in
                        Text(cat).tag(cat)
                    }
                }
                .labelsHidden()
            }
            .padding(.horizontal, 16).padding(.vertical, 13)
        }
    }

    // MARK: - Score input card
    private var scoreCard: some View {
        FormEditCard {
            VStack(spacing: 12) {
                HStack {
                    Label("Hypothetical Score", systemImage: "percent").font(.body)
                    Spacer()
                    TextField("", text: $scoreText)
                        .multilineTextAlignment(.trailing)
                        .foregroundStyle(.secondary)
                        .frame(width: 60)
                        .focused($scoreFocused)
                        #if !os(macOS)
                        .keyboardType(.decimalPad)
                        #endif
                        .onChange(of: scoreText) { _, v in
                            if let d = Double(v), d >= 0, d <= 100 {
                                hypotheticalScore = d
                            }
                        }
                    Text("%").foregroundStyle(.secondary)
                }
                .padding(.horizontal, 16).padding(.top, 13)

                Slider(value: $hypotheticalScore, in: 0...100, step: 1) {
                    EmptyView()
                } minimumValueLabel: {
                    Text("0").font(.caption2).foregroundStyle(.secondary)
                } maximumValueLabel: {
                    Text("100").font(.caption2).foregroundStyle(.secondary)
                }
                .onChange(of: hypotheticalScore) { _, v in
                    scoreText = String(Int(v))
                }
                .tint(.accentColor)
                .padding(.horizontal, 16).padding(.bottom, 14)
            }
        }
    }

    // MARK: - Result card
    private func resultCard(projected: Double) -> some View {
        let d = delta ?? 0
        let projLetter = letterGrade(from: projected)
        let curLetter = currentGrade.map { letterGrade(from: $0) } ?? "—"
        let deltaColor: Color = d >= 0.5 ? .green : d <= -0.5 ? .red : .secondary

        return VStack(spacing: 12) {
            Text("Projected Grade").font(.caption.bold()).foregroundStyle(.secondary)

            HStack(spacing: 0) {
                // Current
                VStack(spacing: 4) {
                    Text(curLetter)
                        .font(.system(size: 36, weight: .bold, design: .rounded))
                        .foregroundStyle(gradeColor(curLetter))
                    if let cur = currentGrade {
                        Text(String(format: "%.1f%%", cur))
                            .font(.caption.monospacedDigit())
                            .foregroundStyle(.secondary)
                    }
                    Text("Current").font(.caption2).foregroundStyle(.tertiary)
                }
                .frame(maxWidth: .infinity)

                // Arrow
                Image(systemName: d >= 0.5 ? "arrow.up.right" : d <= -0.5 ? "arrow.down.right" : "arrow.right")
                    .font(.title2)
                    .foregroundStyle(deltaColor)

                // Projected
                VStack(spacing: 4) {
                    Text(projLetter)
                        .font(.system(size: 36, weight: .bold, design: .rounded))
                        .foregroundStyle(gradeColor(projLetter))
                    Text(String(format: "%.1f%%", projected))
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(.secondary)
                    Text("Projected").font(.caption2).foregroundStyle(.tertiary)
                }
                .frame(maxWidth: .infinity)
            }

            // Delta chip — only show for meaningful changes (≥0.5pp)
            if abs(d) >= 0.5 {
                Text(String(format: "%+.1f%%", d))
                    .font(.subheadline.bold().monospacedDigit())
                    .foregroundStyle(deltaColor)
                    .padding(.horizontal, 14).padding(.vertical, 6)
                    .background(deltaColor.opacity(0.12), in: Capsule())
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
    }
}
