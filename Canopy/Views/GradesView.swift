import SwiftUI

// MARK: - Main View

private enum GradeSection {
    case grades, transcript, syncLog
}

enum GradeSort: String, CaseIterable {
    case grade = "Grade"
    case name  = "Name"
}

struct GradesView: View {
    @Environment(CanopyStore.self) private var store
    @State private var selectedClass: SchoolClass?
    @State private var sort: GradeSort = .grade
    @State private var section: GradeSection = .grades

    private var gradedClasses: [SchoolClass] {
        let base = store.classes.filter { $0.grade != nil || $0.gradePercent != nil }
        switch sort {
        case .grade: return base.sorted { ($0.gradePercent ?? 0) > ($1.gradePercent ?? 0) }
        case .name:  return base.sorted { $0.name < $1.name }
        }
    }
    private var ungradedClasses: [SchoolClass] {
        store.classes
            .filter { $0.grade == nil && $0.gradePercent == nil }
            .sorted { $0.name < $1.name }
    }

    private var overallAverage: Double? {
        let pcts = gradedClasses.compactMap(\.gradePercent)
        guard !pcts.isEmpty else { return nil }
        return pcts.reduce(0, +) / Double(pcts.count)
    }

    private func psAssignments(for cls: SchoolClass) -> [Homework] {
        store.homework
            .filter { $0.classId == cls.id && $0.source == "powerschool" }
            .sorted { $0.dueDate > $1.dueDate }
    }

    // Cross-class missing work ranked by grade impact
    private var missingWorkItems: [(hw: Homework, cls: SchoolClass, impact: Double)] {
        var all: [(hw: Homework, cls: SchoolClass, impact: Double)] = []
        for cls in gradedClasses {
            guard let weights = cls.categoryWeights else { continue }
            let hw = psAssignments(for: cls)
            let impacts = missingWorkImpact(assignments: hw, weights: weights)
            for item in impacts.prefix(5) {
                all.append((hw: item.homework, cls: cls, impact: item.gradeImpactPercent))
            }
        }
        return all.sorted { $0.impact > $1.impact }.prefix(10).map { $0 }
    }

    var body: some View {
        NavigationStack {
            ZStack { CanopyBackground()
                switch section {
                case .grades:
                    if store.classes.isEmpty {
                        ContentUnavailableView("No Classes",
                            systemImage: "books.vertical",
                            description: Text("Add classes in the web app to see grades here."))
                    } else {
                        ScrollView {
                            LazyVStack(alignment: .leading, spacing: 24) {
                                if let avg = overallAverage {
                                    statsStrip(avg: avg)
                                }
                                if !missingWorkItems.isEmpty {
                                    missingWorkSection
                                }
                                if !gradedClasses.isEmpty {
                                    gradeSection
                                }
                                if !ungradedClasses.isEmpty {
                                    ungradedSection
                                }
                            }
                            .padding(16)
                            .padding(.bottom, 24)
                        }
                    }
                case .transcript:
                    TranscriptView()
                case .syncLog:
                    SyncLogView()
                }
            }
            .navigationTitle("")
            .navigationBarTitleInline()
            .iosHideNavigationBar()
            .safeAreaInset(edge: .top, spacing: 0) {
                VStack(spacing: 0) {
                    Picker("", selection: $section) {
                        Text("Grades").tag(GradeSection.grades)
                        Text("Transcript").tag(GradeSection.transcript)
                        Text("Sync Log").tag(GradeSection.syncLog)
                    }
                    .pickerStyle(.segmented)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 8)
                    if section == .grades {
                        HStack {
                            Button {
                                Task { _ = try? await store.syncPowerSchool() }
                            } label: {
                                HStack(spacing: 5) {
                                    if store.isSyncing {
                                        ProgressView().controlSize(.small)
                                    } else {
                                        Image(systemName: "arrow.triangle.2.circlepath")
                                    }
                                    Text(store.isSyncing ? "Syncing…" : "Sync Now")
                                }
                                .font(.subheadline)
                            }
                            .disabled(store.isSyncing)
                            .padding(.horizontal, 16)
                            .padding(.vertical, 8)
                            Spacer()
                            Button {
                                withAnimation(.spring(response: 0.25, dampingFraction: 0.7)) {
                                    sort = sort == .grade ? .name : .grade
                                }
                            } label: {
                                Label(
                                    sort == .grade ? "Sort by Name" : "Sort by Grade",
                                    systemImage: sort == .grade ? "textformat.abc" : "percent"
                                )
                                .font(.subheadline)
                            }
                            .padding(.horizontal, 16)
                            .padding(.vertical, 8)
                        }
                    }
                }
                .background(.ultraThinMaterial)
            }
            .refreshable { await store.loadAll() }
            .sheet(item: $selectedClass) { cls in
                ClassDetailSheet(
                    cls: cls,
                    assignments: psAssignments(for: cls),
                    allHomework: store.homework.filter { $0.classId == cls.id && $0.source != "powerschool" }
                )
            }
        }
    }

    // MARK: Stats strip
    private func statsStrip(avg: Double) -> some View {
        let psHW = store.homework.filter { $0.source == "powerschool" }
        let c = GradesUtil.counts(psHW)

        return HStack(spacing: 0) {
            statCell(value: String(format: "%.1f%%", avg), label: "Average",
                     color: gradeColor(letterGrade(from: avg)))
            Divider().frame(height: 32)
            statCell(value: "\(c.missing)", label: "Missing", color: c.missing > 0 ? .red : .secondary)
            Divider().frame(height: 32)
            statCell(value: "\(c.late)", label: "Late", color: c.late > 0 ? .orange : .secondary)
            Divider().frame(height: 32)
            statCell(value: "\(c.ungraded)", label: "Ungraded", color: c.ungraded > 0 ? .yellow : .secondary)
            Divider().frame(height: 32)
            statCell(value: "\(c.upcomingThisWeek)", label: "This Week", color: .secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 12)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
    }

    private func statCell(value: String, label: String, color: Color) -> some View {
        VStack(spacing: 2) {
            Text(value).font(.headline).fontDesign(.rounded).foregroundStyle(color)
            Text(label).font(.caption2).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
    }

    // MARK: Missing work section
    private var missingWorkSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            SectionLabel(text: "Missing Work — Grade Impact")
            VStack(spacing: 0) {
                ForEach(Array(missingWorkItems.enumerated()), id: \.offset) { idx, item in
                    HStack(spacing: 12) {
                        Image(systemName: "exclamationmark.circle.fill")
                            .foregroundStyle(.red)
                            .font(.subheadline)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(item.hw.title)
                                .font(.subheadline)
                                .lineLimit(1)
                            Text(item.cls.name)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        Text(String(format: "−%.1f%%", item.impact))
                            .font(.subheadline.bold().monospacedDigit())
                            .foregroundStyle(.red)
                    }
                    .padding(.horizontal, 14).padding(.vertical, 10)
                    if idx < missingWorkItems.count - 1 {
                        Divider().padding(.leading, 14)
                    }
                }
            }
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        }
    }

    // MARK: Graded section
    private var gradeSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            SectionLabel(text: "Graded")
            AdaptiveGrid {
                ForEach(gradedClasses) { cls in
                    Button { selectedClass = cls } label: {
                        GradeCard(cls: cls, velocity: store.gradeVelocity(for: cls.id))
                    }
                    .buttonStyle(CardPressStyle())
                }
            }
        }
    }

    // MARK: Ungraded section
    private var ungradedSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            SectionLabel(text: "No Grade")
            AdaptiveGrid {
                ForEach(ungradedClasses) { cls in
                    Button { selectedClass = cls } label: {
                        UngradedCard(cls: cls)
                    }
                    .buttonStyle(CardPressStyle())
                }
            }
        }
    }
}

// MARK: - Adaptive Grid

struct AdaptiveGrid<Content: View>: View {
    let content: Content
    init(@ViewBuilder content: () -> Content) { self.content = content() }

    private let columns = [GridItem(.adaptive(minimum: 140, maximum: 240), spacing: 12)]

    var body: some View {
        LazyVGrid(columns: columns, spacing: 12) {
            content
        }
    }
}

// MARK: - Grade Card

struct GradeCard: View {
    let cls: SchoolClass
    var velocity: Double? = nil

    var body: some View {
        let displayGrade = cls.grade ?? cls.gradePercent.map { letterGrade(from: $0) }

        VStack(spacing: 0) {
            // Color accent strip
            Color(hex: cls.color)
                .frame(height: 4)

            VStack(alignment: .leading, spacing: 6) {
                // Class name
                Text(cls.name)
                    .font(.caption.bold())
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)

                Spacer(minLength: 4)

                // Large grade
                HStack(alignment: .lastTextBaseline, spacing: 0) {
                    if let grade = displayGrade {
                        Text(grade)
                            .font(.system(size: 44, weight: .bold, design: .rounded))
                            .foregroundStyle(gradeColor(grade))
                    } else {
                        Text("—")
                            .font(.system(size: 44, weight: .light, design: .rounded))
                            .foregroundStyle(.tertiary)
                    }
                    Spacer()
                    Image(systemName: "chevron.right")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                        .padding(.bottom, 8)
                }

                // Percentage + velocity badge
                HStack(spacing: 6) {
                    if let pct = cls.gradePercent {
                        Text(String(format: "%.1f%%", pct))
                            .font(.callout.monospacedDigit())
                            .foregroundStyle(.secondary)
                    } else {
                        Text("No grade")
                            .font(.callout)
                            .foregroundStyle(.tertiary)
                    }
                    if let v = velocity, abs(v) >= 0.1 {
                        velocityBadge(v)
                    }
                }
            }
            .padding(.horizontal, 14)
            .padding(.top, 12)
            .padding(.bottom, 14)
        }
        .frame(minHeight: 140)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .shadow(color: .black.opacity(0.06), radius: 8, y: 2)
    }

    private func velocityBadge(_ delta: Double) -> some View {
        let up = delta > 0
        let color: Color = up ? .green : .red
        return HStack(spacing: 2) {
            Image(systemName: up ? "arrow.up" : "arrow.down")
                .font(.system(size: 8, weight: .bold))
            Text(String(format: "%.1f%%", abs(delta)))
                .font(.system(size: 9, weight: .bold).monospacedDigit())
        }
        .foregroundStyle(color)
        .padding(.horizontal, 5).padding(.vertical, 2)
        .background(color.opacity(0.12), in: Capsule())
    }
}

// MARK: - Ungraded Card

struct UngradedCard: View {
    let cls: SchoolClass

    var body: some View {
        VStack(spacing: 0) {
            Color(hex: cls.color).frame(height: 4)
            VStack(alignment: .leading, spacing: 6) {
                Text(cls.name)
                    .font(.caption.bold())
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)
                Spacer(minLength: 4)
                Text("—")
                    .font(.system(size: 44, weight: .light, design: .rounded))
                    .foregroundStyle(.tertiary)
                Text("No grade")
                    .font(.callout)
                    .foregroundStyle(.tertiary)
            }
            .padding(.horizontal, 14)
            .padding(.top, 12)
            .padding(.bottom, 14)
        }
        .frame(minHeight: 120)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .shadow(color: .black.opacity(0.06), radius: 8, y: 2)
    }
}

// MARK: - Section Label

struct SectionLabel: View {
    let text: String
    var body: some View {
        Text(text.uppercased())
            .font(.caption.bold())
            .foregroundStyle(.secondary)
            .tracking(1)
    }
}

// MARK: - Class Detail Sheet

struct ClassDetailSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(CanopyStore.self) private var store
    let cls: SchoolClass
    let assignments: [Homework]   // PowerSchool
    let allHomework: [Homework]   // Manual

    @State private var showWhatIf = false
    @State private var showFinalGrade = false
    @State private var searchText = ""
    @State private var filter: AssignFilter = .all
    @State private var categoryFilter: String? = nil
    @State private var sortMode: AssignSort = .dueDesc

    enum AssignFilter: String, CaseIterable {
        case all = "All", missing = "Missing", late = "Late", ungraded = "Ungraded", upcoming = "Upcoming", graded = "Graded"
    }
    enum AssignSort: String, CaseIterable {
        case dueDesc = "Newest", dueAsc = "Oldest", category = "Category"
    }

    private var filteredAssignments: [Homework] {
        var list = assignments
        if let cat = categoryFilter { list = list.filter { $0.category == cat } }
        switch filter {
        case .all: break
        case .missing:  list = list.filter { $0.isMissing }
        case .late:     list = list.filter { $0.isLate }
        case .ungraded: list = list.filter { $0.isUngraded }
        case .upcoming: list = list.filter { $0.isUpcoming }
        case .graded:   list = list.filter { $0.isGraded }
        }
        if !searchText.isEmpty {
            list = list.filter { $0.title.localizedCaseInsensitiveContains(searchText) }
        }
        switch sortMode {
        case .dueDesc:   list.sort { $0.dueDate > $1.dueDate }
        case .dueAsc:    list.sort { $0.dueDate < $1.dueDate }
        case .category:  list.sort { ($0.category ?? "") < ($1.category ?? "") }
        }
        return list
    }

    // Reconstruct "before" homework from sync_log score_changed entries
    private var impactfulChange: (homework: Homework, delta: Double)? {
        guard let weights = cls.categoryWeights, !weights.isEmpty else { return nil }
        let scoreChanges = store.syncLog.filter {
            $0.classId == cls.id && $0.changeType == "score_changed"
        }
        guard !scoreChanges.isEmpty else { return nil }

        let before: [Homework] = assignments.map { hw in
            guard let entry = scoreChanges.first(where: {
                $0.entityId == (hw.sourceId ?? hw.id)
            }) else { return hw }
            // Parse "X% → Y%" from detail
            let parts = entry.detail.components(separatedBy: "→")
            guard let beforePart = parts.first else { return hw }
            let beforePct = Double(beforePart
                .trimmingCharacters(in: .whitespacesAndNewlines)
                .replacingOccurrences(of: "%", with: ""))
            var modified = hw
            modified.scorePercent = beforePct
            return modified
        }

        return mostImpactfulAssignment(after: assignments, before: before, weights: weights)
    }

    var body: some View {
        NavigationStack {
            ZStack { CanopyBackground()
                ScrollView {
                    VStack(spacing: 20) {
                        gradeHero
                        if !assignments.isEmpty {
                            detailStatStrip
                        }
                        if let change = impactfulChange {
                            changeDriverCard(change)
                        }
                        if let weights = cls.categoryWeights, !weights.isEmpty {
                            categoryBreakdown(weights)
                        }
                        if !assignments.isEmpty {
                            assignmentBrowser
                        }
                        if !allHomework.isEmpty {
                            homeworkSection
                        }
                        if assignments.isEmpty && allHomework.isEmpty {
                            ContentUnavailableView(
                                "No Assignments",
                                systemImage: "tray",
                                description: Text("Synced assignments will appear here.")
                            )
                            .padding(.top, 40)
                        }
                    }
                    .padding(16)
                    .padding(.bottom, 32)
                }
            }
            .navigationTitle(cls.name)
            .navigationBarTitleInline()
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
                ToolbarItem(placement: .cancellationAction) {
                    Menu {
                        if cls.categoryWeights != nil {
                            Button { showWhatIf = true } label: { Label("What If?", systemImage: "wand.and.stars") }
                        }
                        Button { showFinalGrade = true } label: { Label("Final Grade Calculator", systemImage: "function") }
                    } label: {
                        Image(systemName: "ellipsis.circle")
                    }
                }
            }
            .sheet(isPresented: $showWhatIf) {
                WhatIfSheet(cls: cls, assignments: assignments)
                    .presentationDetents([.medium, .large])
            }
            .sheet(isPresented: $showFinalGrade) {
                FinalGradeSheet(currentGrade: cls.gradePercent, className: cls.name)
                    .presentationDetents([.medium, .large])
            }
        }
    }

    // MARK: Grade Hero
    private var gradeHero: some View {
        HStack(spacing: 0) {
            Color(hex: cls.color)
                .frame(width: 5)
                .clipShape(UnevenRoundedRectangle(
                    topLeadingRadius: 14, bottomLeadingRadius: 14,
                    bottomTrailingRadius: 0, topTrailingRadius: 0
                ))

            HStack(spacing: 20) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(cls.name)
                        .font(.title3.bold())
                    if !cls.teacher.isEmpty {
                        Text(cls.teacher)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                    if !cls.room.isEmpty {
                        Label("Room \(cls.room)", systemImage: "door.right.hand.open")
                            .font(.caption)
                            .foregroundStyle(.tertiary)
                    }
                }
                Spacer()
                VStack(alignment: .trailing, spacing: 2) {
                    let displayGrade = cls.grade ?? cls.gradePercent.map { letterGrade(from: $0) }
                    if let grade = displayGrade {
                        Text(grade)
                            .font(.system(size: 52, weight: .bold, design: .rounded))
                            .foregroundStyle(gradeColor(grade))
                    }
                    if let pct = cls.gradePercent {
                        Text(String(format: "%.1f%%", pct))
                            .font(.callout.monospacedDigit())
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 18)
        }
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .shadow(color: .black.opacity(0.06), radius: 8, y: 2)
    }

    // MARK: Grade Change Driver
    private func changeDriverCard(_ change: (homework: Homework, delta: Double)) -> some View {
        let up = change.delta > 0
        let color: Color = up ? .green : .red

        return HStack(spacing: 12) {
            Image(systemName: up ? "arrow.up.circle.fill" : "arrow.down.circle.fill")
                .font(.title2)
                .foregroundStyle(color)
            VStack(alignment: .leading, spacing: 3) {
                Text("Grade Change Driver")
                    .font(.caption.bold())
                    .foregroundStyle(.secondary)
                Text(change.homework.title)
                    .font(.subheadline)
                    .lineLimit(1)
                if let cat = change.homework.category {
                    Text(cat).font(.caption2).foregroundStyle(.tertiary)
                }
            }
            Spacer()
            Text(String(format: "%+.1f%%", change.delta))
                .font(.subheadline.bold().monospacedDigit())
                .foregroundStyle(color)
        }
        .padding(14)
        .background(color.opacity(0.08), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous)
            .strokeBorder(color.opacity(0.25), lineWidth: 0.5))
    }

    // MARK: Detail stat strip
    private var detailStatStrip: some View {
        let c = GradesUtil.counts(assignments)
        return HStack(spacing: 0) {
            miniStat("\(c.graded)", "Graded", .secondary)
            Divider().frame(height: 28)
            miniStat("\(c.missing)", "Missing", c.missing > 0 ? .red : .secondary)
            Divider().frame(height: 28)
            miniStat("\(c.late)", "Late", c.late > 0 ? .orange : .secondary)
            Divider().frame(height: 28)
            miniStat("\(c.ungraded)", "Ungraded", c.ungraded > 0 ? .yellow : .secondary)
            Divider().frame(height: 28)
            miniStat("\(c.upcoming)", "Upcoming", .secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 10)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
    }

    private func miniStat(_ value: String, _ label: String, _ color: Color) -> some View {
        VStack(spacing: 2) {
            Text(value).font(.subheadline.bold()).fontDesign(.rounded).foregroundStyle(color)
            Text(label).font(.caption2).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
    }

    // MARK: Category breakdown
    private func categoryBreakdown(_ weights: [String: Double]) -> some View {
        let cats = weights.keys.sorted()
        return VStack(alignment: .leading, spacing: 8) {
            SectionLabel(text: "Categories")
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 10) {
                    ForEach(cats, id: \.self) { cat in
                        let avg = categoryAverage(assignments: assignments, category: cat)
                        let count = assignments.filter { $0.category == cat }.count
                        let selected = categoryFilter == cat
                        Button {
                            withAnimation(.spring(response: 0.25)) {
                                categoryFilter = selected ? nil : cat
                            }
                        } label: {
                            VStack(alignment: .leading, spacing: 4) {
                                Text(cat).font(.caption.bold()).lineLimit(1)
                                Text(avg != nil ? String(format: "%.0f%%", avg!) : "—")
                                    .font(.title3.bold().monospacedDigit())
                                    .foregroundStyle(avg != nil ? gradeColor(letterGrade(from: avg!)) : .secondary)
                                Text("\(count) items · \(Int(weights[cat] ?? 0))%")
                                    .font(.caption2).foregroundStyle(.secondary)
                            }
                            .padding(10)
                            .frame(width: 120, alignment: .leading)
                            .background(selected ? Color.accentColor.opacity(0.15) : Color.secondary.opacity(0.08),
                                        in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                            .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous)
                                .strokeBorder(selected ? Color.accentColor : .clear, lineWidth: 1.5))
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
    }

    // MARK: Assignment browser (filters + search + sort + list)
    private var assignmentBrowser: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                SectionLabel(text: "Assignments")
                Spacer()
                Menu {
                    Picker("Sort", selection: $sortMode) {
                        ForEach(AssignSort.allCases, id: \.self) { Text($0.rawValue).tag($0) }
                    }
                } label: {
                    Label(sortMode.rawValue, systemImage: "arrow.up.arrow.down").font(.caption)
                }
            }

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 6) {
                    ForEach(AssignFilter.allCases, id: \.self) { f in
                        let on = filter == f
                        Button {
                            withAnimation(.spring(response: 0.2)) { filter = f }
                        } label: {
                            Text(f.rawValue)
                                .font(.caption.weight(on ? .semibold : .regular))
                                .padding(.horizontal, 10).padding(.vertical, 5)
                                .background(on ? Color.accentColor : Color.secondary.opacity(0.12), in: Capsule())
                                .foregroundStyle(on ? .white : .primary)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }

            HStack {
                Image(systemName: "magnifyingglass").foregroundStyle(.secondary).font(.caption)
                TextField("Search assignments", text: $searchText)
                    .textFieldStyle(.plain)
                    .font(.subheadline)
                if !searchText.isEmpty {
                    Button { searchText = "" } label: { Image(systemName: "xmark.circle.fill").foregroundStyle(.secondary) }
                        .buttonStyle(.plain)
                }
            }
            .padding(8)
            .background(Color.secondary.opacity(0.1), in: RoundedRectangle(cornerRadius: 10, style: .continuous))

            assignmentList
        }
    }

    @ViewBuilder
    private var assignmentList: some View {
        let list = filteredAssignments
        if list.isEmpty {
            Text("No matching assignments")
                .font(.subheadline).foregroundStyle(.secondary)
                .frame(maxWidth: .infinity).padding(.vertical, 24)
        } else if sortMode == .dueDesc {
            // Grouped by time bucket
            ForEach(TimeBucket.allCases, id: \.self) { bucket in
                let inBucket = list.filter { GradesUtil.timeBucket($0.dueDate) == bucket }
                if !inBucket.isEmpty {
                    VStack(alignment: .leading, spacing: 0) {
                        Text(bucket.rawValue)
                            .font(.caption2.bold()).foregroundStyle(.secondary)
                            .padding(.horizontal, 4).padding(.bottom, 4).padding(.top, 6)
                        VStack(spacing: 0) {
                            ForEach(Array(inBucket.enumerated()), id: \.element.id) { idx, hw in
                                AssignmentDetailRow(hw: hw)
                                if idx < inBucket.count - 1 { Divider().padding(.leading, 16) }
                            }
                        }
                        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                    }
                }
            }
        } else {
            VStack(spacing: 0) {
                ForEach(Array(list.enumerated()), id: \.element.id) { idx, hw in
                    AssignmentDetailRow(hw: hw)
                    if idx < list.count - 1 { Divider().padding(.leading, 16) }
                }
            }
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        }
    }

    // MARK: Homework
    private var homeworkSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            SectionLabel(text: "Homework")
            VStack(spacing: 0) {
                ForEach(Array(allHomework.enumerated()), id: \.element.id) { idx, hw in
                    HomeworkDetailRow(hw: hw)
                    if idx < allHomework.count - 1 {
                        Divider().padding(.leading, 16)
                    }
                }
            }
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        }
    }
}

// MARK: - Assignment Detail Row

struct AssignmentDetailRow: View {
    let hw: Homework

    private var flagInfo: (label: String, color: Color)? {
        guard let f = hw.flags, !f.isEmpty else { return nil }
        let lower = f.lowercased()
        if lower.contains("missing")   { return ("Missing", .red) }
        if lower.contains("late")      { return ("Late", .orange) }
        if lower.contains("collected") { return ("Collected", .blue) }
        return (f, .secondary)
    }

    var body: some View {
        HStack(spacing: 12) {
            Circle()
                .fill(hw.completed ? Color.accentColor : Color.systemFill)
                .frame(width: 8, height: 8)
                .padding(.leading, 16)
            VStack(alignment: .leading, spacing: 3) {
                Text(hw.title)
                    .font(.subheadline)
                    .lineLimit(2)
                HStack(spacing: 6) {
                    if let cat = hw.category, !cat.isEmpty {
                        Text(cat)
                            .font(.caption2)
                            .foregroundStyle(.tertiary)
                    }
                    if let flag = flagInfo {
                        Text(flag.label)
                            .font(.caption2.bold())
                            .padding(.horizontal, 5).padding(.vertical, 1)
                            .background(flag.color.opacity(0.12), in: Capsule())
                            .foregroundStyle(flag.color)
                    }
                }
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 2) {
                if let score = hw.score {
                    Text(score)
                        .font(.subheadline.bold().monospacedDigit())
                }
                if let pct = hw.scorePercent {
                    Text(String(format: "%.0f%%", pct))
                        .font(.caption2)
                        .foregroundStyle(scoreColor(pct))
                }
            }
            .padding(.trailing, 16)
        }
        .padding(.vertical, 12)
    }

    private func scoreColor(_ pct: Double) -> Color {
        switch pct {
        case 90...: return .accentColor
        case 80..<90: return .blue
        case 70..<80: return .orange
        default: return .red
        }
    }
}

// MARK: - Homework Detail Row

struct HomeworkDetailRow: View {
    let hw: Homework
    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: hw.completed ? "checkmark.circle.fill" : "circle")
                .foregroundStyle(hw.completed ? Color.accentColor : .secondary)
                .padding(.leading, 16)
            VStack(alignment: .leading, spacing: 2) {
                Text(hw.title)
                    .font(.subheadline)
                    .strikethrough(hw.completed)
                    .foregroundStyle(hw.completed ? .secondary : .primary)
                    .lineLimit(2)
                Text(hw.dueDate.dueDateLabel)
                    .font(.caption2)
                    .foregroundStyle(hw.dueDate.isOverdue && !hw.completed ? Color.red : Color.secondary.opacity(0.6))
            }
            Spacer()
            PriorityDot(priority: hw.priority)
                .padding(.trailing, 16)
        }
        .padding(.vertical, 12)
    }
}

// MARK: - Card Press Style

struct CardPressStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.96 : 1.0)
            .animation(.spring(response: 0.2, dampingFraction: 0.7), value: configuration.isPressed)
    }
}

// MARK: - Grade letter fallback

func letterGrade(from pct: Double) -> String {
    switch pct {
    case 97...: return "A+"
    case 93...: return "A"
    case 90...: return "A-"
    case 87...: return "B+"
    case 83...: return "B"
    case 80...: return "B-"
    case 77...: return "C+"
    case 73...: return "C"
    case 70...: return "C-"
    case 67...: return "D+"
    case 63...: return "D"
    case 60...: return "D-"
    default:    return "F"
    }
}

// MARK: - Grade color helper

func gradeColor(_ grade: String) -> Color {
    switch grade.prefix(1) {
    case "A": return .accentColor
    case "B": return .blue
    case "C": return .orange
    case "D": return .red
    default:  return .secondary
    }
}
