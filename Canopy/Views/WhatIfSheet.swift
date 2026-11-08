import SwiftUI

// Port of web src/components/WhatIfDialog.tsx — pick a category and a
// hypothetical score, see how it would move the overall grade.

struct WhatIfSheet: View {
    @Environment(\.dismiss) private var dismiss
    let cls: SchoolClass
    let assignments: [Homework]

    private static let customKey = "__custom__"

    @State private var category: String = ""
    @State private var customCategory = ""
    @State private var percent: Double = 85
    @State private var scoreText = "85"
    @FocusState private var scoreFocused: Bool

    private var weights: [String: Double] { cls.categoryWeights ?? [:] }
    private var categories: [String] { GradesDisplay.orderedWeightKeys(weights) }
    private var hasWeights: Bool { !categories.isEmpty }

    private var effectiveCategory: String {
        if !hasWeights { return customCategory.trimmingCharacters(in: .whitespaces) }
        return category == Self.customKey ? customCategory.trimmingCharacters(in: .whitespaces) : category
    }

    /// Without a weight table the typed category stands in as the whole grade.
    private var simWeights: [String: Double] {
        if hasWeights { return weights }
        return effectiveCategory.isEmpty ? [:] : [effectiveCategory: 100]
    }

    private var currentGrade: Double? { overallGrade(assignments: assignments, weights: simWeights) }

    private var projectedGrade: Double? {
        guard !effectiveCategory.isEmpty else { return nil }
        return simulateWhatIf(assignments: assignments, weights: simWeights, category: effectiveCategory, percent: percent)
    }

    private var delta: Double? {
        guard let cur = currentGrade, let proj = projectedGrade else { return nil }
        return proj - cur
    }

    var body: some View {
        NavigationStack {
            ZStack { CanopyBackground()
                ScrollView {
                    VStack(alignment: .leading, spacing: 16) {
                        if !hasWeights {
                            GradeInfoBox {
                                Text("Set up grade weights for \(cls.name) in the class editor to unlock the full simulator. For now, you can try any category name below.")
                            }
                        }

                        VStack(alignment: .leading, spacing: 4) {
                            Text("Pick a category and hypothetical score — see how it would move your overall grade.")
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                            Text("Estimated using equal weight per assignment within each category.")
                                .font(.caption2)
                                .foregroundStyle(.tertiary)
                        }
                        .fixedSize(horizontal: false, vertical: true)

                        categoryCard
                        scoreCard

                        Divider()

                        resultRow

                        if let d = delta {
                            Text(GradesDisplay.signed2(d))
                                .font(.caption.weight(.semibold))
                                .monospacedDigit()
                                .padding(.horizontal, 12).padding(.vertical, 5)
                                .background(deltaColor(d).opacity(0.14), in: Capsule())
                                .foregroundStyle(deltaColor(d))
                                .frame(maxWidth: .infinity)
                        }
                    }
                    .padding(16)
                    .padding(.bottom, 32)
                }
            }
            .navigationTitle("What-if Grade Calculator")
            .navigationBarTitleInline()
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Close") { dismiss() }
                }
                #if os(iOS)
                ToolbarItemGroup(placement: .keyboard) {
                    Spacer()
                    Button("Done") { scoreFocused = false }
                }
                #endif
            }
        }
        .onAppear { category = categories.first ?? "" }
    }

    private func deltaColor(_ d: Double) -> Color {
        d > 0.05 ? .green : d < -0.05 ? .red : .secondary
    }

    // MARK: Category

    private var categoryCard: some View {
        FormEditCard {
            VStack(spacing: 0) {
                if hasWeights {
                    HStack {
                        Label("Category", systemImage: "tag").font(.body)
                        Spacer()
                        Picker("", selection: $category) {
                            ForEach(categories, id: \.self) { cat in
                                Text("\(cat) (\(GradesDisplay.num(weights[cat] ?? 0))%)").tag(cat)
                            }
                            Text("Other (type below)").tag(Self.customKey)
                        }
                        .labelsHidden()
                    }
                    .padding(.horizontal, 16).padding(.vertical, 12)

                    if category == Self.customKey {
                        Divider().padding(.leading, 16)
                        HStack {
                            Text("Category name").font(.body)
                            Spacer()
                            TextField("e.g. Tests", text: $customCategory)
                                .multilineTextAlignment(.trailing)
                                .textFieldStyle(.plain)
                        }
                        .padding(.horizontal, 16).padding(.vertical, 12)
                    }
                } else {
                    HStack {
                        Label("Category", systemImage: "tag").font(.body)
                        Spacer()
                        TextField("e.g. Tests", text: $customCategory)
                            .multilineTextAlignment(.trailing)
                            .textFieldStyle(.plain)
                    }
                    .padding(.horizontal, 16).padding(.vertical, 12)
                }
            }
        }
    }

    // MARK: Score

    private var scoreCard: some View {
        FormEditCard {
            VStack(spacing: 12) {
                HStack {
                    Text("Hypothetical score: \(Text("\(Int(percent))%").bold())")
                        .font(.body)
                    Spacer()
                    TextField("Score %", text: $scoreText)
                        .multilineTextAlignment(.trailing)
                        .foregroundStyle(.secondary)
                        .frame(width: 60)
                        .focused($scoreFocused)
                        .textFieldStyle(.plain)
                        #if os(iOS)
                        .keyboardType(.numberPad)
                        #endif
                        .onChange(of: scoreText) { _, v in
                            // Web: parseInt, clamped to 0…100 (blank → 0).
                            let digits = v.filter(\.isNumber)
                            let parsed = Int(digits) ?? 0
                            let clamped = min(100, max(0, parsed))
                            if Double(clamped) != percent { percent = Double(clamped) }
                        }
                    Text("%").foregroundStyle(.secondary)
                }
                .padding(.horizontal, 16).padding(.top, 13)

                VStack(spacing: 2) {
                    Slider(value: $percent, in: 0...100, step: 1)
                        .tint(.accentColor)
                        .onChange(of: percent) { _, v in
                            let s = String(Int(v))
                            if s != scoreText { scoreText = s }
                        }
                    HStack {
                        Text("0"); Spacer(); Text("50"); Spacer(); Text("100")
                    }
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
                }
                .padding(.horizontal, 16).padding(.bottom, 14)
            }
        }
    }

    // MARK: Result

    private var resultRow: some View {
        HStack(spacing: 12) {
            gradeColumn(label: "Current", value: currentGrade)
            Image(systemName: "arrow.right").font(.title3).foregroundStyle(.tertiary)
            gradeColumn(label: "Projected", value: projectedGrade)
        }
        .frame(maxWidth: .infinity)
    }

    private func gradeColumn(label: String, value: Double?) -> some View {
        let color = GradesUtil.gradeColor(value)
        return VStack(spacing: 2) {
            Text(label).font(.caption).foregroundStyle(.secondary)
            if let v = value {
                Text(GradesDisplay.pct1(v))
                    .font(.system(size: 30, weight: .medium, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(color)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                Text(GradesUtil.letterFromPercent(v))
                    .font(.subheadline)
                    .foregroundStyle(color)
            } else {
                Text("—").font(.system(size: 30)).foregroundStyle(.tertiary)
            }
        }
        .frame(maxWidth: .infinity)
    }
}
