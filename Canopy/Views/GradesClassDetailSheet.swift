import SwiftUI

// Port of web src/app/grades/[classId]/page.tsx — a single class's gradebook.
// Layout (top → bottom): actions (What if? / Final Calc / Sync) → weights
// caption → header card with grade + progress bar → stat strip → category
// breakdown (tap to filter) → Grade Change Driver → quick-filter chips →
// search + sort → assignments (time-bucketed when sorted by Recent) → the
// Apple-only manual Homework list.

struct ClassDetailSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(CanopyStore.self) private var store
    @Environment(\.colorScheme) private var colorScheme
    let cls: SchoolClass

    /// Assignment lists are derived live from the store (they refresh after a
    /// sync); the extra parameters are accepted for source compatibility with
    /// older call sites and ignored.
    init(cls: SchoolClass, assignments: [Homework]? = nil, allHomework: [Homework]? = nil) {
        self.cls = cls
    }

    @State private var showWhatIf = false
    @State private var showFinalGrade = false
    @State private var showSyncReminder = false
    @State private var simAssignment: Homework?
    @State private var toast: ToastMessage?
    @State private var query = ""
    @State private var filterMode: FilterMode = .all
    @State private var categoryFilter: String?
    @State private var sortMode: SortMode = .dueDesc
    @State private var classSyncLog: [SyncLogEntry] = []
    @State private var classHistory: [GradeHistoryEntry] = []

    enum FilterMode: String, CaseIterable {
        case all = "All", missing = "Missing", late = "Late", ungraded = "Ungraded", upcoming = "Upcoming", graded = "Graded"
    }
    enum SortMode: String, CaseIterable {
        case dueDesc = "Recent", dueAsc = "Oldest", category = "Category"
    }

    private struct CategoryStat: Identifiable {
        let name: String
        let count: Int
        let graded: Int
        let avg: Double?
        var id: String { name }
    }

    // MARK: Derived data

    /// Latest copy of the class from the store (grades change after a sync).
    private var live: SchoolClass { store.schoolClass(cls.id) ?? cls }
    private var classHomework: [Homework] {
        store.homework.filter { $0.classId == cls.id && $0.source == "powerschool" }
    }
    private var manualHomework: [Homework] {
        store.homework.filter { $0.classId == cls.id && $0.source != "powerschool" }.sorted { $0.dueDate < $1.dueDate }
    }
    private var weights: [String: Double] { live.categoryWeights ?? [:] }
    private var hasWeights: Bool { !weights.isEmpty }
    private var stats: StatusCounts { GradesUtil.counts(classHomework) }
    private var color: Color { GradesDisplay.classColor(live) }
    private var velocity: Double? {
        classHistory.isEmpty ? store.gradeVelocity(for: cls.id) : GradesDisplay.velocity(from: classHistory)
    }
    private var infoColor: Color { CanopyPalette.info(colorScheme) }

    /// Derived from the ASSIGNMENTS (not the weight table); "Other" when unset.
    private var categoryStats: [CategoryStat] {
        var order: [String] = []
        var items: [String: [Homework]] = [:]
        for h in classHomework {
            let cat = h.category?.nonEmpty ?? "Other"
            if items[cat] == nil { order.append(cat) }
            items[cat, default: []].append(h)
        }
        return order.map { name -> CategoryStat in
            let list = items[name] ?? []
            let pcts = list.compactMap(\.percentValue)
            return CategoryStat(name: name, count: list.count, graded: pcts.count,
                                avg: pcts.isEmpty ? nil : pcts.reduce(0, +) / Double(pcts.count))
        }
        .sorted { $0.count != $1.count ? $0.count > $1.count : $0.name < $1.name }
    }

    private func weight(forCategory name: String) -> Double? {
        weights.first { categoriesMatch($0.key, name) }?.value
    }

    /// Order of operations mirrors the web: query → status → category → sort.
    private var filteredSorted: [Homework] {
        let q = query.trimmingCharacters(in: .whitespaces).lowercased()
        var list = classHomework.filter { h in
            q.isEmpty || h.title.lowercased().contains(q) || (h.category ?? "").lowercased().contains(q)
        }
        switch filterMode {
        case .all:      break
        case .missing:  list = list.filter(\.isMissing)
        case .late:     list = list.filter(\.isLate)
        case .ungraded: list = list.filter(\.isUngraded)
        case .upcoming: list = list.filter(\.isUpcoming)
        case .graded:   list = list.filter(\.isGraded)
        }
        if let cf = categoryFilter {
            list = list.filter { ($0.category?.nonEmpty ?? "Other") == cf }
        }
        list.sort { a, b in
            if sortMode == .category {
                let ca = (a.category?.nonEmpty ?? "zzz").lowercased()
                let cb = (b.category?.nonEmpty ?? "zzz").lowercased()
                if ca != cb { return ca < cb }
            }
            return sortMode == .dueAsc ? a.dueDate < b.dueDate : a.dueDate > b.dueDate
        }
        return list
    }

    /// Time buckets only when sorted by Recent; otherwise one flat group.
    private var groupedRows: [(bucket: TimeBucket?, items: [Homework])] {
        let list = filteredSorted
        guard sortMode == .dueDesc else { return [(nil, list)] }
        return TimeBucket.allCases.compactMap { b in
            let items = list.filter { GradesUtil.timeBucket($0.dueDate) == b }
            return items.isEmpty ? nil : (b, items)
        }
    }

    private var hasActiveFilter: Bool {
        filterMode != .all || categoryFilter != nil || !query.trimmingCharacters(in: .whitespaces).isEmpty
    }

    /// Which assignment moved the grade most since the last sync. The "before"
    /// snapshot is rebuilt from this class's `score_changed` sync-log entries
    /// (keyed by homework id — that's what the server writes to `entityId`);
    /// a detail without a leading "NN%" means it was ungraded last sync.
    private var impactfulChange: (homework: Homework, delta: Double)? {
        guard !classHomework.isEmpty, !classSyncLog.isEmpty else { return nil }
        let before: [Homework] = classHomework.map { hw in
            guard let change = classSyncLog.first(where: { $0.entityId == hw.id && $0.changeType == "score_changed" }) else {
                return hw
            }
            var m = hw
            if let r = change.detail.range(of: #"^([\d.]+)%"#, options: .regularExpression) {
                m.scorePercent = Double(change.detail[r].dropLast())
            } else {
                m.scorePercent = nil
            }
            return m
        }
        guard let result = mostImpactfulAssignment(after: classHomework, before: before, weights: weights),
              abs(result.delta) >= 0.1 else { return nil }
        return result
    }

    // MARK: Body

    var body: some View {
        NavigationStack {
            ZStack { CanopyBackground()
                ScrollView {
                    VStack(alignment: .leading, spacing: 20) {
                        actionRow
                        weightsCaption
                        headerCard
                        statStrip
                        if !categoryStats.isEmpty { categoryBreakdown }
                        if let change = impactfulChange { changeDriver(change) }
                        if !classHomework.isEmpty { filterChips }
                        assignmentsBrowser
                        if !manualHomework.isEmpty { homeworkSection }
                    }
                    .padding(16)
                    .padding(.bottom, 32)
                }
            }
            .navigationTitle(live.name)
            .navigationBarTitleInline()
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
            .sheet(isPresented: $showWhatIf) {
                WhatIfSheet(cls: live, assignments: classHomework)
                    .presentationDetents([.medium, .large])
            }
            .sheet(isPresented: $showFinalGrade) {
                FinalGradeSheet(currentGrade: live.gradePercent, className: live.name)
                    .presentationDetents([.medium, .large])
            }
            .sheet(item: $simAssignment) { hw in
                AssignmentSimulatorSheet(cls: live, homework: classHomework, assignment: hw)
                    .presentationDetents([.medium, .large])
            }
            .sheet(isPresented: $showSyncReminder) {
                SyncReminderSheet(onSync: syncNow)
            }
            .toast($toast)
            .task { await loadDetail() }
            .onAppear {
                PowerSchoolSyncStore.shared.subscribe()
                resumeIfRunning()
            }
            .onDisappear { PowerSchoolSyncStore.shared.unsubscribe() }
        }
    }

    // MARK: Actions

    private var actionRow: some View {
        GradesFlowLayout(spacing: 8) {
            Button { showWhatIf = true } label: {
                Label("What if?", systemImage: "function")
            }
            Button { showFinalGrade = true } label: {
                Label("Final Calc", systemImage: "checklist")
            }
            Button {
                if store.setupStatus?.hasPowerschool == true {
                    showSyncReminder = true
                } else {
                    syncNow()
                }
            } label: {
                HStack(spacing: 5) {
                    if store.isSyncing {
                        ProgressView().controlSize(.small)
                    } else {
                        Image(systemName: "arrow.triangle.2.circlepath")
                    }
                    Text(store.isSyncing ? "Syncing…" : "Sync")
                }
            }
            .disabled(store.isSyncing)
        }
        .buttonStyle(.glass)
        .controlSize(.small)
    }

    private var weightsCaption: some View {
        Text(hasWeights
             ? "Grade weights: \(GradesDisplay.weightsText(weights, separator: " · "))"
             : "No category weights for this class (graded on total points, or not synced yet — run Sync to check).")
            .font(.caption)
            .foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)
    }

    // MARK: Header card

    private var headerCard: some View {
        VStack(spacing: 0) {
            Color(hex: live.color).frame(height: 6)
            VStack(alignment: .leading, spacing: 12) {
                HStack(alignment: .top, spacing: 12) {
                    VStack(alignment: .leading, spacing: 8) {
                        Text(live.name)
                            .font(.title2.weight(.semibold))
                            .fontDesign(.rounded)
                            .fixedSize(horizontal: false, vertical: true)
                        GradesFlowLayout(spacing: 6) {
                            if let teacher = live.displayTeacher {
                                OutlinedChip(text: teacher, systemImage: "envelope")
                            }
                            if !live.room.isEmpty {
                                OutlinedChip(text: "Rm \(live.room)", systemImage: "mappin.and.ellipse")
                            }
                            OutlinedChip(text: "Period \(live.period)", systemImage: "clock")
                            if live.isPowerSchool {
                                OutlinedChip(text: "PowerSchool", color: .accentColor)
                            }
                        }
                    }
                    Spacer(minLength: 8)
                    VStack(alignment: .trailing, spacing: 2) {
                        if let p = live.gradePercent {
                            Text(GradesDisplay.pct1(p))
                                .font(.system(size: 40, weight: .semibold, design: .rounded))
                                .monospacedDigit()
                                .foregroundStyle(color)
                                .lineLimit(1)
                                .minimumScaleFactor(0.6)
                            Text(live.grade?.nonEmpty ?? GradesUtil.letterFromPercent(p))
                                .font(.title3.weight(.medium))
                                .foregroundStyle(color)
                        } else if let g = live.grade?.nonEmpty {
                            Text(g)
                                .font(.system(size: 40, weight: .semibold, design: .rounded))
                                .foregroundStyle(color)
                        } else {
                            OutlinedChip(text: "No grade yet")
                        }
                    }
                }
                if let v = velocity {
                    OutlinedChip(text: "\(GradesDisplay.signed1(v)) this week",
                                 systemImage: v > 0 ? "chart.line.uptrend.xyaxis" : "chart.line.downtrend.xyaxis",
                                 color: v > 0 ? .green : .red)
                }
                if let p = live.gradePercent {
                    GradeProgressBar(value: p / 100, color: color, height: 10)
                }
            }
            .padding(16)
        }
        .glassEffect(.regular, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .shadow(color: .black.opacity(0.06), radius: 8, y: 2)
    }

    // MARK: Stat strip

    private var statStrip: some View {
        let s = stats
        return LazyVGrid(columns: [GridItem(.adaptive(minimum: 150), spacing: 10)], spacing: 10) {
            GradeStatTile(label: "Graded", value: "\(s.graded) / \(s.total)", systemImage: "checkmark.circle",
                          color: .green, valueColor: .primary)
            GradeStatTile(label: "Missing", value: "\(s.missing)", systemImage: "exclamationmark.circle",
                          color: .red, valueColor: s.missing > 0 ? .red : .primary, emphasize: s.missing > 0)
            GradeStatTile(label: "Late", value: "\(s.late)", systemImage: "exclamationmark.triangle",
                          color: .orange, valueColor: s.late > 0 ? .orange : .primary, emphasize: s.late > 0)
            GradeStatTile(label: "Ungraded", value: "\(s.ungraded)", systemImage: "questionmark.circle",
                          color: .secondary, valueColor: .primary)
            GradeStatTile(label: "Upcoming", value: "\(s.upcoming)", systemImage: "calendar",
                          color: .accentColor, valueColor: s.upcoming > 0 ? .accentColor : .primary, emphasize: s.upcoming > 0)
        }
    }

    // MARK: Category breakdown

    private var categoryBreakdown: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                SectionLabel(text: "Category Breakdown")
                if let cf = categoryFilter {
                    Button {
                        withAnimation(.spring(response: 0.25)) { categoryFilter = nil }
                    } label: {
                        HStack(spacing: 4) {
                            Text("Filtered: \(cf)")
                            Image(systemName: "xmark.circle.fill")
                        }
                        .font(.caption2.weight(.semibold))
                        .padding(.horizontal, 8).padding(.vertical, 3)
                        .background(Color.accentColor, in: Capsule())
                        .foregroundStyle(.white)
                    }
                    .buttonStyle(.plain)
                }
            }
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 150), spacing: 10)], spacing: 10) {
                ForEach(categoryStats) { cat in
                    categoryCard(cat)
                }
            }
        }
    }

    private func categoryCard(_ cat: CategoryStat) -> some View {
        let catColor = GradesUtil.gradeColor(cat.avg)
        let active = categoryFilter == cat.name
        let shape = RoundedRectangle(cornerRadius: 14, style: .continuous)
        return Button {
            withAnimation(.spring(response: 0.25)) { categoryFilter = active ? nil : cat.name }
        } label: {
            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Text(cat.name.uppercased())
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(.secondary)
                        .tracking(0.5)
                        .lineLimit(1)
                    Spacer()
                    if active { TintedChip(text: "Active", color: .accentColor) }
                }
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    Text(cat.avg.map { GradesDisplay.pct1($0) } ?? "—")
                        .font(.title2.weight(.semibold))
                        .fontDesign(.rounded)
                        .monospacedDigit()
                        .foregroundStyle(cat.avg != nil ? catColor : Color.secondary.opacity(0.6))
                    Text("\(cat.graded)/\(cat.count) graded")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
                if let w = weight(forCategory: cat.name) {
                    Text("Weight \(GradesDisplay.num(w))%").font(.caption2).foregroundStyle(.tertiary)
                }
                if let avg = cat.avg {
                    GradeProgressBar(value: avg / 100, color: catColor, height: 4)
                }
            }
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background {
                ZStack {
                    shape.fill(.regularMaterial)
                    if active { shape.fill(catColor.opacity(0.06)) }
                }
            }
            .overlay(shape.strokeBorder(active ? catColor : Color.secondary.opacity(0.12), lineWidth: active ? 2 : 1))
        }
        .buttonStyle(.plain)
        .accessibilityLabel(active ? "Clear \(cat.name) filter" : "Filter by \(cat.name)")
    }

    // MARK: Grade Change Driver

    private func categorySuffix(_ hw: Homework) -> String {
        hw.category?.nonEmpty.map { " · \($0)" } ?? ""
    }

    private func changeDriver(_ change: (homework: Homework, delta: Double)) -> some View {
        let up = change.delta > 0
        let tint: Color = up ? .green : .red
        return VStack(alignment: .leading, spacing: 10) {
            SectionLabel(text: "Grade Change Driver")
            HStack(spacing: 10) {
                Image(systemName: up ? "chart.line.uptrend.xyaxis" : "chart.line.downtrend.xyaxis")
                    .font(.title3)
                    .foregroundStyle(tint)
                VStack(alignment: .leading, spacing: 2) {
                    Text("\(Text(change.homework.title).bold())\(Text(categorySuffix(change.homework)).foregroundStyle(.secondary))")
                        .font(.subheadline)
                        .lineLimit(2)
                    Text("Moved overall grade by \(Text(GradesDisplay.signed2(change.delta)).bold().foregroundStyle(tint)) since last sync")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer(minLength: 0)
            }
            .padding(14)
            .glassEffect(.regular, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        }
    }

    // MARK: Quick-filter chips

    private func count(for f: FilterMode) -> Int {
        switch f {
        case .all: return stats.total
        case .missing: return stats.missing
        case .late: return stats.late
        case .ungraded: return stats.ungraded
        case .upcoming: return stats.upcoming
        case .graded: return stats.graded
        }
    }

    private func chipColor(_ f: FilterMode) -> Color {
        switch f {
        case .all, .upcoming: return .accentColor
        case .missing: return .red
        case .late: return .orange
        case .ungraded: return .secondary
        case .graded: return .green
        }
    }

    private func chipIcon(_ f: FilterMode) -> String? {
        switch f {
        case .all: return nil
        case .missing: return "exclamationmark.circle"
        case .late: return "exclamationmark.triangle"
        case .ungraded: return "questionmark.circle"
        case .upcoming: return "calendar"
        case .graded: return "checkmark.circle"
        }
    }

    private var filterChips: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 6) {
                ForEach(FilterMode.allCases, id: \.self) { f in
                    let n = count(for: f)
                    let on = filterMode == f
                    let tint = chipColor(f)
                    let disabled = f != .all && n == 0
                    Button {
                        withAnimation(.spring(response: 0.2)) {
                            filterMode = (on && f != .all) ? .all : f
                        }
                    } label: {
                        HStack(spacing: 4) {
                            if let icon = chipIcon(f) {
                                Image(systemName: icon).font(.system(size: 10, weight: .semibold))
                            }
                            Text("\(f.rawValue) · \(n)")
                        }
                        .font(.caption.weight(on ? .semibold : .regular))
                        .padding(.horizontal, 10).padding(.vertical, 5)
                        .background(on ? tint : Color.clear, in: Capsule())
                        .overlay(Capsule().strokeBorder(on ? Color.clear : Color.secondary.opacity(0.35), lineWidth: 1))
                        .foregroundStyle(on ? Color.white : Color.primary)
                    }
                    .buttonStyle(.plain)
                    .disabled(disabled)
                    .opacity(disabled ? 0.4 : 1)
                }
            }
            .padding(.vertical, 2)
        }
    }

    // MARK: Assignments (header, search, sort, list)

    private func clearFilters() {
        withAnimation(.spring(response: 0.2)) {
            filterMode = .all
            categoryFilter = nil
            query = ""
        }
    }

    private var assignmentsBrowser: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                SectionLabel(text: filteredSorted.count == classHomework.count
                             ? "All Assignments · \(classHomework.count)"
                             : "Showing \(filteredSorted.count) of \(classHomework.count)")
                Spacer()
                if hasActiveFilter {
                    Button("Clear filters") { clearFilters() }
                        .font(.caption.weight(.semibold))
                }
            }

            HStack {
                Image(systemName: "magnifyingglass").foregroundStyle(.secondary).font(.caption)
                TextField("Search assignments…", text: $query)
                    .textFieldStyle(.plain)
                    .font(.subheadline)
                    .textAutocapNever()
                if !query.isEmpty {
                    Button { query = "" } label: {
                        Image(systemName: "xmark.circle.fill").foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(8)
            .background(Color.secondary.opacity(0.1), in: RoundedRectangle(cornerRadius: 10, style: .continuous))

            Picker("Sort", selection: $sortMode) {
                ForEach(SortMode.allCases, id: \.self) { Text($0.rawValue).tag($0) }
            }
            .pickerStyle(.segmented)
            .labelsHidden()

            assignmentList
        }
    }

    @ViewBuilder
    private var assignmentList: some View {
        if classHomework.isEmpty {
            GradeInfoBox {
                Text("No assignments yet for this class. Tap \(Text("Sync").bold()) to pull the latest from PowerSchool.")
            }
        } else if filteredSorted.isEmpty {
            GradeInfoBox {
                VStack(alignment: .leading, spacing: 6) {
                    Text("No assignments match the current filters.")
                    Button("Clear filters") { clearFilters() }
                        .font(.subheadline.weight(.semibold))
                }
            }
        } else {
            Text("Tip: tap any assignment to see how a different score would change your grade.")
                .font(.caption)
                .foregroundStyle(.secondary)
            VStack(spacing: 0) {
                ForEach(Array(groupedRows.enumerated()), id: \.offset) { _, group in
                    if let bucket = group.bucket {
                        HStack(spacing: 10) {
                            Text(bucket.rawValue.uppercased())
                                .font(.system(size: 10, weight: .bold))
                                .tracking(1.2)
                                .foregroundStyle(.tertiary)
                            Rectangle().fill(Color.secondary.opacity(0.2)).frame(height: 1)
                            Text("\(group.items.count)")
                                .font(.system(size: 10))
                                .foregroundStyle(.tertiary)
                        }
                        .padding(.horizontal, 14)
                        .padding(.top, 14)
                        .padding(.bottom, 6)
                    }
                    ForEach(Array(group.items.enumerated()), id: \.element.id) { idx, hw in
                        AssignmentDetailRow(hw: hw)
                            .onTapGesture { simAssignment = hw }
                        if idx < group.items.count - 1 { Divider().padding(.leading, 14) }
                    }
                }
            }
            .padding(.bottom, 4)
            .glassEffect(.regular, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        }
    }

    // MARK: Manual homework (Apple-only)

    private var homeworkSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            SectionLabel(text: "Homework")
            VStack(spacing: 0) {
                ForEach(Array(manualHomework.enumerated()), id: \.element.id) { idx, hw in
                    HomeworkDetailRow(hw: hw)
                    if idx < manualHomework.count - 1 {
                        Divider().padding(.leading, 16)
                    }
                }
            }
            .glassEffect(.regular, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        }
    }

    // MARK: Sync + data loading

    private func syncNow() {
        Task {
            do {
                let status = try await store.syncPowerSchool()
                toast = .forSync(status, text: detailMessage(for: status))
            } catch {
                toast = ToastMessage(text: "Sync error: \(error.localizedDescription)", kind: .error)
            }
            await loadDetail()
        }
    }

    private func resumeIfRunning() {
        Task {
            if let status = await store.resumeSyncIfRunning() {
                toast = .forSync(status, text: detailMessage(for: status))
                await loadDetail()
            }
        }
    }

    /// Web Grade Detail snackbar copy (differs slightly from the Grades page).
    private func detailMessage(for s: PowerSchoolStatus) -> String {
        switch s.status {
        case "success": return "Grades synced."
        case "error":
            if (s.error ?? "").contains("Missing PowerSchool credentials") {
                return "Save your PowerSchool login in Settings first."
            }
            return s.error ?? "Sync failed."
        default: return "Still syncing in the background — check back in a bit."
        }
    }

    private func loadDetail() async {
        async let log = APIClient.shared.getSyncLog(classId: cls.id, limit: 50)
        async let history = APIClient.shared.getGradeHistory(classId: cls.id)
        if let l = try? await log { classSyncLog = l }
        if let h = try? await history { classHistory = h }
    }
}

// MARK: - Assignment row (tap → score simulator)

struct AssignmentDetailRow: View {
    @Environment(\.colorScheme) private var colorScheme
    let hw: Homework

    var body: some View {
        let pct = hw.percentValue
        let rowColor = GradesUtil.gradeColor(pct)
        let stripe: Color? = hw.isMissing ? .red : hw.isLate ? .orange : nil
        let info = CanopyPalette.info(colorScheme)

        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text(hw.title)
                    .font(.subheadline.weight(.medium))
                    .lineLimit(2)
                GradesFlowLayout(spacing: 6) {
                    if let cat = hw.category?.nonEmpty { GradeCategoryPill(text: cat) }
                    Text(GradesUtil.relativeDueLabel(hw.dueDate)).font(.caption2).foregroundStyle(.tertiary)
                    if let flag = hw.flags?.nonEmpty {
                        TintedChip(text: flag, color: GradesUtil.flagSeverity(flag).color)
                    }
                }
                if let note = hw.teacherNote?.nonEmpty {
                    HStack(alignment: .top, spacing: 4) {
                        Image(systemName: "bubble.left")
                            .font(.system(size: 10))
                            .foregroundStyle(info)
                            .padding(.top, 2)
                        Text(note)
                            .font(.caption)
                            .italic()
                            .foregroundStyle(info)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
            Spacer(minLength: 8)
            VStack(alignment: .trailing, spacing: 3) {
                if let score = hw.score?.nonEmpty {
                    Text(score)
                        .font(.subheadline.weight(.semibold))
                        .monospacedDigit()
                        .foregroundStyle(pct != nil ? rowColor : .primary)
                }
                if let pct {
                    Text(GradesDisplay.pct1(pct))
                        .font(.caption2.weight(.bold))
                        .monospacedDigit()
                        .padding(.horizontal, 7).padding(.vertical, 2)
                        .background(rowColor.opacity(0.12), in: Capsule())
                        .foregroundStyle(rowColor)
                } else if hw.score?.nonEmpty == nil && hw.flags?.nonEmpty == nil {
                    Text("—").font(.subheadline).foregroundStyle(.tertiary)
                }
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(stripe.map { $0.opacity(0.04) } ?? Color.clear)
        .overlay(alignment: .leading) {
            if let stripe { Rectangle().fill(stripe).frame(width: 3) }
        }
        .contentShape(Rectangle())
    }
}

// MARK: - Manual homework row

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
