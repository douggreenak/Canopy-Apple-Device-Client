import SwiftUI

// Port of web src/app/grades/page.tsx — overview of all PowerSchool classes.
// Hierarchy (top → bottom): header (title + last-synced + Sync Now) → tabs →
// stat strip → grade overview + coming up → missing-work triage → sort toggle
// → class cards with recent-assignment preview.

private enum GradeSection: Hashable {
    case grades, transcript, syncLog
}

private enum ClassSortMode: String, CaseIterable {
    case period = "By Period"
    case grade  = "By Grade"
}

struct GradesView: View {
    @Environment(CanopyStore.self) private var store
    @State private var selectedClass: SchoolClass?
    @State private var sortMode: ClassSortMode = .period
    @State private var section: GradeSection = .grades
    @State private var showSyncReminder = false
    @State private var toast: ToastMessage?

    // MARK: Data (PowerSchool only — that's where grades come from)

    private var psClasses: [SchoolClass] {
        let filtered = store.classes.filter(\.isPowerSchool)
        switch sortMode {
        case .period: return filtered.sorted { $0.period < $1.period }
        case .grade:  return filtered.sorted { ($0.gradePercent ?? -1) > ($1.gradePercent ?? -1) }
        }
    }

    private var allPsHomework: [Homework] { store.homework.filter { $0.source == "powerschool" } }

    private var overallStatus: StatusCounts { GradesUtil.counts(allPsHomework) }

    private var overallPercent: Double? {
        let pcts = psClasses.compactMap(\.gradePercent)
        guard !pcts.isEmpty else { return nil }
        return pcts.reduce(0, +) / Double(pcts.count)
    }

    /// Upcoming within 7 calendar days, soonest first, top 6.
    private var upcomingSoon: [Homework] {
        let today = Calendar.current.startOfDay(for: .now)
        return allPsHomework
            .filter(\.isUpcoming)
            .filter { h in
                guard let d = h.dueDate.asDate else { return false }
                let diff = Calendar.current.dateComponents([.day], from: today, to: Calendar.current.startOfDay(for: d)).day ?? 99
                return diff <= 7
            }
            .sorted { $0.dueDate < $1.dueDate }
            .prefix(6)
            .map { $0 }
    }

    /// Most recent / soonest first.
    private func classHomework(_ cls: SchoolClass) -> [Homework] {
        allPsHomework.filter { $0.classId == cls.id }.sorted { $0.dueDate > $1.dueDate }
    }

    /// Cross-class missing-work triage ranked by grade impact (top 8).
    private var missingWorkItems: [(hw: Homework, cls: SchoolClass, impact: Double)] {
        var all: [(hw: Homework, cls: SchoolClass, impact: Double)] = []
        for cls in psClasses {
            guard let weights = cls.categoryWeights, !weights.isEmpty else { continue }
            for item in missingWorkImpact(assignments: classHomework(cls), weights: weights) {
                all.append((hw: item.homework, cls: cls, impact: item.gradeImpactPercent))
            }
        }
        return Array(all.sorted { $0.impact > $1.impact }.prefix(8))
    }

    private var lastSyncedText: String? {
        guard let raw = store.settings.lastSyncAt?.nonEmpty else { return nil }
        guard let d = CanopyStore.parseISO(raw) else { return raw }
        let f = DateFormatter(); f.dateFormat = "MMM d, h:mm a"
        return f.string(from: d)
    }

    // MARK: Body

    var body: some View {
        NavigationStack {
            ZStack { CanopyBackground()
                Group {
                    switch section {
                    case .grades:     gradesContent
                    case .transcript: TranscriptView(top: AnyView(header))
                    case .syncLog:    SyncLogView(top: AnyView(header))
                    }
                }
                .id(section)
                .transition(.opacity.combined(with: .move(edge: .bottom)))
            }
            .animation(.easeOut(duration: 0.22), value: section)
            .navigationTitle("")
            .navigationBarTitleInline()
            .iosHideNavigationBar()
            .refreshable { await store.loadAll() }
            .sheet(item: $selectedClass) { cls in
                ClassDetailSheet(cls: cls)
            }
            .sheet(isPresented: $showSyncReminder) {
                SyncReminderSheet(onSync: syncNow)
            }
            .toast($toast)
            .onAppear {
                PowerSchoolSyncStore.shared.subscribe()
                resumeIfRunning()
                consumeNavigation()
            }
            .onDisappear { PowerSchoolSyncStore.shared.unsubscribe() }
            .onChange(of: AppNavigation.shared.gradesClassId) { _, _ in consumeNavigation() }
        }
    }

    // MARK: Header (title, last synced, Sync Now, tabs)

    private var header: some View {
        VStack(spacing: 0) {
            PowerSchoolLoginWarningBanner(onFix: { AppNavigation.shared.goToSettings(section: "powerschool") })
                .padding(.top, 8)
            ZeroGradeBanner().padding(.top, 8)

            HStack(alignment: .top, spacing: 12) {
                VStack(alignment: .leading, spacing: 3) {
                    HStack(spacing: 6) {
                        Image(systemName: "graduationcap.fill").foregroundStyle(Color.accentColor)
                        Text("Grades")
                    }
                    .font(.title2.bold())
                    .fontDesign(.rounded)
                    Text("Your PowerSchool grades, assignments, and status — tap Sync Now to update.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 8)
                VStack(alignment: .trailing, spacing: 4) {
                    syncButton
                    if let last = lastSyncedText {
                        Text("Last synced \(last)")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                }
            }
            .padding(.top, 10)

            Picker("", selection: $section) {
                Text("Grades").tag(GradeSection.grades)
                Text("Transcript").tag(GradeSection.transcript)
                Text("Sync Log").tag(GradeSection.syncLog)
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .padding(.vertical, 8)
        }
    }

    private var syncButton: some View {
        Button {
            if store.setupStatus?.hasPowerschool == true {
                showSyncReminder = true
            } else {
                syncNow()
            }
        } label: {
            HStack(spacing: 6) {
                if store.isSyncing {
                    ProgressView().controlSize(.small)
                } else {
                    Image(systemName: "arrow.triangle.2.circlepath")
                }
                Text(store.isSyncing ? "Syncing…" : "Sync Now")
            }
            .font(.subheadline.weight(.semibold))
        }
        .buttonStyle(.glassProminent)
        .disabled(store.isSyncing)
    }

    // MARK: Sync flow (web syncNow / handleSyncOutcome)

    private func syncNow() {
        Task {
            do {
                let status = try await store.syncPowerSchool()
                toast = .forSync(status, text: PowerSchoolSyncStore.gradesMessage(for: status))
            } catch {
                toast = ToastMessage(text: "Sync error: \(error.localizedDescription)", kind: .error)
            }
        }
    }

    /// A sync started elsewhere (Settings, class detail, the daily cron) should
    /// read as "in progress" here too, and report its outcome when it lands.
    private func resumeIfRunning() {
        Task {
            if let status = await store.resumeSyncIfRunning() {
                toast = .forSync(status, text: PowerSchoolSyncStore.gradesMessage(for: status))
            }
        }
    }

    private func consumeNavigation() {
        guard let id = AppNavigation.shared.gradesClassId else { return }
        AppNavigation.shared.gradesClassId = nil
        section = .grades
        if let cls = store.classes.first(where: { $0.id == id }) {
            selectedClass = cls
        }
    }

    // MARK: Grades tab content

    @ViewBuilder
    private var gradesContent: some View {
        if psClasses.isEmpty {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    header
                    emptyState
                }
                .padding(16)
            }
        } else {
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 20) {
                    header
                    if !allPsHomework.isEmpty { statStrip }
                    gradeOverviewPanel
                    if !upcomingSoon.isEmpty { comingUpPanel }
                    if !missingWorkItems.isEmpty { missingWorkSection }
                    if psClasses.count > 1 { classesHeader }
                    ForEach(psClasses) { cls in
                        Button { selectedClass = cls } label: {
                            GradeClassCard(cls: cls, homework: classHomework(cls), velocity: store.gradeVelocity(for: cls.id))
                        }
                        .buttonStyle(CardPressStyle())
                    }
                }
                .padding(16)
                .padding(.bottom, 24)
            }
        }
    }

    // MARK: Stat strip

    private var statStrip: some View {
        let c = overallStatus
        return LazyVGrid(columns: [GridItem(.adaptive(minimum: 150), spacing: 10)], spacing: 10) {
            GradeStatTile(label: "Overall",
                          value: overallPercent.map { GradesDisplay.pct1($0) } ?? "—",
                          sub: overallPercent.map { GradesUtil.letterFromPercent($0) } ?? "No grades yet",
                          systemImage: "chart.line.uptrend.xyaxis",
                          color: GradesUtil.gradeColor(overallPercent))
            GradeStatTile(label: "Missing", value: "\(c.missing)",
                          sub: c.missing == 1 ? "assignment" : "assignments",
                          systemImage: "exclamationmark.circle", color: .red, emphasize: c.missing > 0)
            GradeStatTile(label: "Late", value: "\(c.late)",
                          sub: c.late == 1 ? "assignment" : "assignments",
                          systemImage: "exclamationmark.triangle", color: .orange, emphasize: c.late > 0)
            GradeStatTile(label: "Ungraded", value: "\(c.ungraded)", sub: "past-due, no score",
                          systemImage: "questionmark.circle", color: .secondary)
            GradeStatTile(label: "Due this week", value: "\(c.upcomingThisWeek)", sub: "upcoming assignments",
                          systemImage: "calendar", color: .accentColor, emphasize: c.upcomingThisWeek > 0)
        }
    }

    // MARK: Grade overview panel

    private var gradeOverviewPanel: some View {
        VStack(alignment: .leading, spacing: 10) {
            SectionLabel(text: "Grade overview")
            VStack(spacing: 10) {
                ForEach(psClasses) { c in
                    HStack(spacing: 10) {
                        ClassColorDot(hex: c.color)
                        Text(c.name)
                            .font(.subheadline)
                            .lineLimit(1)
                            .frame(width: 120, alignment: .leading)
                        if let p = c.gradePercent {
                            GradeProgressBar(value: p / 100, color: GradesUtil.gradeColor(p))
                            Text(GradesDisplay.pct1(p))
                                .font(.subheadline.weight(.semibold))
                                .monospacedDigit()
                                .foregroundStyle(GradesUtil.gradeColor(p))
                                .frame(width: 58, alignment: .trailing)
                        } else {
                            Capsule().fill(Color.secondary.opacity(0.12)).frame(height: 8)
                            Text("No grade")
                                .font(.caption)
                                .foregroundStyle(.tertiary)
                                .frame(width: 58, alignment: .trailing)
                        }
                    }
                    .contentShape(Rectangle())
                    .onTapGesture { selectedClass = c }
                }
            }
            .padding(14)
            .glassEffect(.regular, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        }
    }

    // MARK: Coming up panel

    private var comingUpPanel: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 6) {
                Image(systemName: "calendar").font(.caption).foregroundStyle(Color.accentColor)
                SectionLabel(text: "Coming up")
            }
            VStack(spacing: 0) {
                ForEach(Array(upcomingSoon.enumerated()), id: \.element.id) { idx, h in
                    let c = store.schoolClass(h.classId)
                    HStack(spacing: 10) {
                        RoundedRectangle(cornerRadius: 2)
                            .fill(c.map { Color(hex: $0.color) } ?? Color.secondary.opacity(0.3))
                            .frame(width: 3)
                            .frame(minHeight: 32)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(h.title).font(.subheadline.weight(.medium)).lineLimit(1)
                            Text("\(c?.name ?? "Class")\(h.category?.nonEmpty.map { " · \($0)" } ?? "")")
                                .font(.caption).foregroundStyle(.secondary).lineLimit(1)
                        }
                        Spacer(minLength: 8)
                        Text(GradesUtil.relativeDueLabel(h.dueDate))
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(Color.accentColor)
                            .lineLimit(1)
                    }
                    .padding(.vertical, 8)
                    .contentShape(Rectangle())
                    .onTapGesture { if let c { selectedClass = c } }
                    if idx < upcomingSoon.count - 1 { Divider() }
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 6)
            .glassEffect(.regular, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        }
    }

    // MARK: Missing work triage

    private var missingWorkSection: some View {
        let items = missingWorkItems
        return VStack(alignment: .leading, spacing: 10) {
            SectionLabel(text: "Missing Work — Grade Impact")
            VStack(spacing: 0) {
                HStack {
                    Text("Assignment").font(.caption2.weight(.semibold)).foregroundStyle(.secondary)
                    Spacer()
                    Text("Grade impact").font(.caption2.weight(.semibold)).foregroundStyle(.secondary)
                }
                .padding(.horizontal, 14).padding(.vertical, 8)
                Divider()
                ForEach(Array(items.enumerated()), id: \.offset) { idx, item in
                    HStack(spacing: 12) {
                        VStack(alignment: .leading, spacing: 3) {
                            HStack(spacing: 4) {
                                Image(systemName: "exclamationmark.circle").font(.caption2).foregroundStyle(.red)
                                Text(item.hw.title).font(.subheadline.weight(.medium)).lineLimit(1)
                            }
                            HStack(spacing: 6) {
                                ClassColorDot(hex: item.cls.color, size: 8)
                                Text(item.cls.name).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                                Text("·").font(.caption).foregroundStyle(.tertiary)
                                Text(item.hw.category?.nonEmpty ?? "—").font(.caption).foregroundStyle(.secondary).lineLimit(1)
                            }
                        }
                        Spacer(minLength: 8)
                        Text(String(format: "−%.1f%%", item.impact))
                            .font(.subheadline.weight(.semibold))
                            .monospacedDigit()
                            .foregroundStyle(.red)
                    }
                    .padding(.horizontal, 14).padding(.vertical, 10)
                    .contentShape(Rectangle())
                    .onTapGesture { selectedClass = item.cls }
                    if idx < items.count - 1 { Divider().padding(.leading, 14) }
                }
            }
            .glassEffect(.regular, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        }
    }

    // MARK: Sort toggle

    private var classesHeader: some View {
        HStack {
            SectionLabel(text: "\(psClasses.count) \(psClasses.count == 1 ? "Class" : "Classes")")
            Spacer()
            Picker("", selection: $sortMode) {
                ForEach(ClassSortMode.allCases, id: \.self) { Text($0.rawValue).tag($0) }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .frame(width: 200)
        }
    }

    // MARK: Empty state

    private var emptyState: some View {
        VStack(spacing: 14) {
            Image(systemName: "graduationcap")
                .font(.system(size: 56))
                .foregroundStyle(.tertiary)
            Text("No grades imported yet").font(.title3.weight(.semibold))
            Text("Connect your PowerSchool account in Settings to automatically import your classes, grades, and assignments.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
            Button {
                AppNavigation.shared.goToSettings(section: "powerschool")
            } label: {
                Label("Set Up PowerSchool", systemImage: "graduationcap")
            }
            .buttonStyle(.glassProminent)
            .padding(.top, 6)
        }
        .padding(.vertical, 40)
        .padding(.horizontal, 24)
        .frame(maxWidth: .infinity)
        .glassEffect(.regular, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
    }
}

// MARK: - Class card (web class card with recent-assignment preview)

struct GradeClassCard: View {
    let cls: SchoolClass
    /// PowerSchool assignments for this class, most recent first.
    let homework: [Homework]
    var velocity: Double? = nil

    var body: some View {
        let recent = Array(homework.prefix(4))
        let letter = cls.grade?.nonEmpty ?? cls.gradePercent.map { GradesUtil.letterFromPercent($0) }
        let color = GradesDisplay.classColor(cls)
        let stats = GradesUtil.counts(homework)

        VStack(spacing: 0) {
            Color(hex: cls.color).frame(height: 4)

            VStack(alignment: .leading, spacing: 12) {
                HStack(alignment: .top, spacing: 12) {
                    VStack(alignment: .leading, spacing: 6) {
                        Text(cls.name)
                            .font(.title3.weight(.semibold))
                            .multilineTextAlignment(.leading)
                            .lineLimit(2)
                            .fixedSize(horizontal: false, vertical: true)
                        if let teacher = cls.displayTeacher {
                            Text(teacher).font(.subheadline).foregroundStyle(.secondary).lineLimit(1)
                        }
                        GradesFlowLayout(spacing: 6) {
                            if !cls.room.isEmpty { OutlinedChip(text: "Rm \(cls.room)") }
                            OutlinedChip(text: "Period \(cls.period)")
                        }
                        if stats.missing > 0 || stats.late > 0 || stats.ungraded > 0 {
                            GradesFlowLayout(spacing: 6) {
                                if stats.missing > 0 {
                                    OutlinedChip(text: "\(stats.missing) missing", systemImage: "exclamationmark.circle", color: .red)
                                }
                                if stats.late > 0 {
                                    OutlinedChip(text: "\(stats.late) late", systemImage: "exclamationmark.triangle", color: .orange)
                                }
                                if stats.ungraded > 0 {
                                    OutlinedChip(text: "\(stats.ungraded) ungraded", systemImage: "questionmark.circle", color: .secondary)
                                }
                            }
                        }
                    }
                    Spacer(minLength: 8)
                    HStack(spacing: 6) {
                        VStack(alignment: .trailing, spacing: 2) {
                            if let p = cls.gradePercent {
                                Text(GradesDisplay.pct1(p))
                                    .font(.system(size: 34, weight: .semibold, design: .rounded))
                                    .monospacedDigit()
                                    .foregroundStyle(color)
                                    .lineLimit(1)
                                    .minimumScaleFactor(0.6)
                                if let letter {
                                    Text(letter).font(.headline).foregroundStyle(color)
                                }
                                if let v = velocity {
                                    OutlinedChip(text: GradesDisplay.signed1(v),
                                                 systemImage: v > 0 ? "chart.line.uptrend.xyaxis" : "chart.line.downtrend.xyaxis",
                                                 color: v > 0 ? .green : .red)
                                }
                            } else if let letter {
                                Text(letter)
                                    .font(.system(size: 34, weight: .semibold, design: .rounded))
                                    .foregroundStyle(color)
                            } else {
                                OutlinedChip(text: "No grade yet")
                            }
                        }
                        Image(systemName: "chevron.right")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.tertiary)
                    }
                }

                if homework.isEmpty {
                    GradeInfoBox { Text("No assignments yet for this class.") }
                } else {
                    Divider()
                    HStack {
                        Text("Recent · \(recent.count) of \(homework.count)".uppercased())
                            .font(.caption2.weight(.semibold))
                            .foregroundStyle(.secondary)
                            .tracking(0.5)
                        Spacer()
                        Text("View all →")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(Color.accentColor)
                    }
                    VStack(spacing: 0) {
                        ForEach(Array(recent.enumerated()), id: \.element.id) { idx, h in
                            RecentAssignmentRow(hw: h)
                            if idx < recent.count - 1 { Divider() }
                        }
                    }
                }
            }
            .padding(14)
        }
        .glassEffect(.regular, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .shadow(color: .black.opacity(0.06), radius: 8, y: 2)
    }
}

// MARK: - Recent assignment preview row

private struct RecentAssignmentRow: View {
    let hw: Homework

    var body: some View {
        let pct = hw.percentValue
        let stripe: Color? = hw.isMissing ? .red : hw.isLate ? .orange : nil

        HStack(spacing: 10) {
            VStack(alignment: .leading, spacing: 3) {
                Text(hw.title).font(.subheadline.weight(.medium)).lineLimit(1)
                GradesFlowLayout(spacing: 6) {
                    if let cat = hw.category?.nonEmpty { GradeCategoryPill(text: cat) }
                    Text(GradesUtil.relativeDueLabel(hw.dueDate)).font(.caption2).foregroundStyle(.tertiary)
                    if let flag = hw.flags?.nonEmpty {
                        TintedChip(text: flag, color: GradesUtil.flagSeverity(flag).color)
                    }
                }
            }
            Spacer(minLength: 8)
            if let score = hw.score?.nonEmpty {
                Text(score)
                    .font(.subheadline.weight(.semibold))
                    .monospacedDigit()
                    .foregroundStyle(pct != nil ? GradesUtil.gradeColor(pct) : .secondary)
            } else if hw.flags?.nonEmpty == nil {
                Text("—").font(.subheadline).foregroundStyle(.tertiary)
            }
        }
        .padding(.vertical, 8)
        .padding(.horizontal, 8)
        .background(stripe.map { $0.opacity(0.05) } ?? Color.clear)
        .overlay(alignment: .leading) {
            if let stripe { Rectangle().fill(stripe).frame(width: 3) }
        }
    }
}
