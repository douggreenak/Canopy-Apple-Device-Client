import SwiftUI

// Port of web src/app/page.tsx (Dashboard): date navigation, tappable
// summary cards, the embedded Day / Week / Year / Heatmap calendar card, and
// the Upcoming Homework / Upcoming Exams / Pending Tasks cards.
struct DashboardView: View {
    @Environment(CanopyStore.self) private var store
    @State private var selectedDate = Date.now
    @State private var tab: CalendarViewMode = .day
    @State private var detail: ClassDaySelection?

    private var nav: AppNavigation { AppNavigation.shared }
    private var showSkeleton: Bool { store.isLoading && store.classes.isEmpty }

    var body: some View {
        NavigationStack {
            ZStack {
                CanopyBackground()
                GeometryReader { geo in
                    ScrollView {
                        LazyVStack(spacing: 16) {
                            if !store.askTasks.isEmpty { askBanner }
                            PowerSchoolLoginWarningBanner(onFix: { nav.goToSettings(section: "powerschool") })
                            ZeroGradeBanner()
                            header
                            if let loadError = store.loadError { loadErrorBanner(loadError) }
                            if let disruption = store.disruption(on: selectedDate) { disruptionBanner(disruption) }
                            summaryCards
                            if store.classes.isEmpty && !store.isLoading { onboardingBanner }
                            scheduleCard(width: max(200, geo.size.width - 32 - 28))
                            homeworkSection
                            examsSection
                            tasksSection
                        }
                        .padding(.horizontal, 16)
                        .padding(.bottom, 32)
                    }
                }
            }
            .navigationTitle("")
            .navigationBarTitleInline()
            .iosHideNavigationBar()
            .refreshable { await store.loadAll() }
            .sheet(item: $detail) { sel in
                ClassDayDetailSheet(entry: sel.entry, date: sel.date)
            }
            .onAppear { PowerSchoolSyncStore.shared.subscribe() }
            .onDisappear { PowerSchoolSyncStore.shared.unsubscribe() }
        }
    }

    // MARK: - Header + date navigation (web h1 + ◀ today ▶)
    private var header: some View {
        HStack(alignment: .top, spacing: 8) {
            VStack(alignment: .leading, spacing: 4) {
                Text(DateFormatter.fullDate.string(from: selectedDate))
                    .font(.title2.weight(.semibold))
                    .fontDesign(.rounded)
                    .lineLimit(2)
                    .minimumScaleFactor(0.8)
                Text(store.classes.isEmpty ? "Add your classes to see your schedule here." : "Here's your schedule overview.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 0)
            HStack(spacing: 4) {
                navButton("chevron.left", label: "Previous") { navigate(-1) }
                navButton("calendar.circle", label: "Today") {
                    withAnimation(.spring(response: 0.3)) { selectedDate = .now }
                }
                navButton("chevron.right", label: "Next") { navigate(1) }
            }
        }
        .padding(.top, 8)
    }

    private func navButton(_ icon: String, label: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.body.weight(.semibold))
                .frame(width: 36, height: 36)
                .background(.regularMaterial, in: Circle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label)
    }

    /// Step size follows the active calendar tab (web navigateDate).
    private func navigate(_ dir: Int) {
        let step: Calendar.Component
        switch tab {
        case .day, .heatmap: step = .day
        case .week: step = .weekOfYear
        case .year: step = .year
        }
        withAnimation(.spring(response: 0.3)) {
            selectedDate = Calendar.current.date(byAdding: step, value: dir, to: selectedDate) ?? selectedDate
        }
    }

    // MARK: - Summary cards (4, each tappable)
    private var summaryCards: some View {
        let classCount = store.activeClassCount(for: selectedDate)
        let hwCount = store.upcomingHomework(limit: 5).count
        let examCount = store.upcomingExams(limit: 3).count
        let due = store.dueToday()

        return HStack(spacing: 10) {
            SummaryCard(value: "\(classCount)", label: "Classes Today", icon: "calendar", color: .accentColor) {
                nav.goToSchedule(date: DateFormatter.iso.string(from: selectedDate))
            }
            SummaryCard(value: "\(hwCount)", label: "Upcoming Homework", icon: "doc.text", color: .red) {
                nav.go(.homework)
            }
            SummaryCard(value: "\(examCount)", label: "Upcoming Exams", icon: "pencil.and.list.clipboard", color: .orange) {
                nav.go(.exams)
            }
            SummaryCard(value: due.total > 0 ? "\(due.done)" : "—",
                        suffix: due.total > 0 ? "/\(due.total)" : "",
                        label: "Due Today", icon: "checkmark.circle", color: .green,
                        dimmed: due.total == 0) {
                nav.go(.homework)
            }
        }
        .redacted(reason: showSkeleton ? .placeholder : [])
        .disabled(showSkeleton)
    }

    // MARK: - Schedule tabs card (Day / Week / Year / Heatmap)
    private func scheduleCard(width: CGFloat) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Picker("View", selection: $tab.animation(.easeOut(duration: 0.2))) {
                ForEach(CalendarViewMode.allCases) { mode in
                    Text(mode.rawValue).tag(mode)
                }
            }
            .pickerStyle(.segmented)

            Group {
                if showSkeleton {
                    VStack(spacing: 8) {
                        RoundedRectangle(cornerRadius: 10).fill(Color.secondary.opacity(0.12)).frame(height: 200)
                        Text(tab == .week
                             ? "No schedule to display. Add classes in Settings to see your week view."
                             : "No classes scheduled — add classes in Settings to see your day view.")
                            .font(.subheadline).foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 8)
                } else {
                    let bounds = canopyCalendarBounds(store)
                    let dueCounts = buildDueCountMap(homework: store.homework, tasks: store.tasks)
                    switch tab {
                    case .day:
                        ScheduleDayView(date: selectedDate, hasClasses: !store.classes.isEmpty,
                                        dueCounts: dueCounts, bounds: bounds, width: width) { entry in
                            detail = ClassDaySelection(entry: entry, date: selectedDate)
                        }
                    case .week:
                        ScheduleWeekView(weekStart: ScheduleEngine.weekViewStart(for: selectedDate),
                                         dueCounts: dueCounts, bounds: bounds, width: width) { entry, date in
                            detail = ClassDaySelection(entry: entry, date: date)
                        }
                    case .year:
                        ScheduleYearView(year: Calendar.current.component(.year, from: selectedDate)) { date in
                            withAnimation(.easeOut(duration: 0.2)) { selectedDate = date; tab = .day }
                        }
                    case .heatmap:
                        WorkloadHeatmapView { date in
                            withAnimation(.easeOut(duration: 0.2)) { selectedDate = date; tab = .day }
                        }
                    }
                }
            }
            .id(tab)
        }
        .padding(14)
        .glassCard()
    }

    // MARK: - Onboarding banner (zero classes configured at all, not just none today)
    private var onboardingBanner: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 10) {
                Image(systemName: "sparkles").font(.title2).foregroundStyle(Color.accentColor)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Welcome to Canopy!").font(.subheadline.bold())
                    Text("Add your classes to see your schedule, grades, and homework here.")
                        .font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
            }
            Button {
                NotificationCenter.default.post(name: .openSetupWizard, object: nil)
            } label: {
                Text("Get Started").font(.subheadline.bold())
                    .frame(maxWidth: .infinity).padding(.vertical, 10)
            }
            .buttonStyle(.glassProminent)
            .buttonBorderShape(.roundedRectangle(radius: 10))
        }
        .padding(14)
        .background(Color.accentColor.opacity(0.10), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous)
            .strokeBorder(Color.accentColor.opacity(0.3), lineWidth: 0.5))
    }

    // MARK: - Load error banner
    private func loadErrorBanner(_ message: String) -> some View {
        HStack(spacing: 10) {
            Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.red)
            Text(message).font(.caption).foregroundStyle(.secondary)
            Spacer()
            Button("Retry") { Task { await store.loadAll() } }.font(.caption.bold())
        }
        .padding(12)
        .background(Color.red.opacity(0.08), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
    }

    // MARK: - Ask Banner
    private var askBanner: some View {
        HStack(spacing: 12) {
            Image(systemName: "questionmark.circle.fill")
                .font(.title2)
                .foregroundStyle(.orange)
            VStack(alignment: .leading, spacing: 2) {
                Text(store.askTasks.count == 1 ? "You have something to ask" : "You have \(store.askTasks.count) things to ask")
                    .font(.subheadline.bold())
                Text(store.askTasks.map(\.title).joined(separator: " · "))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }
            Spacer()
        }
        .padding(14)
        .background(.orange.opacity(0.12), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous)
            .strokeBorder(.orange.opacity(0.3), lineWidth: 0.5))
    }

    // MARK: - Disruption alert for the selected date
    private func disruptionBanner(_ d: ScheduleDisruption) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.title3)
                .foregroundStyle(.orange)
            Text("\(Text(d.displayLabel).bold()) — Schedule has been modified for today.")
                .font(.subheadline)
            Spacer(minLength: 0)
        }
        .padding(14)
        .background(.orange.opacity(0.10), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous)
            .strokeBorder(.orange.opacity(0.3), lineWidth: 0.5))
    }

    // MARK: - Upcoming Homework
    private var homeworkSection: some View {
        let items = store.upcomingHomework(limit: 5)
        return VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline) {
                SectionHeader(title: "Upcoming Homework", icon: "doc.text.fill", color: .red)
                Spacer()
                if !items.isEmpty {
                    Text("\(items.count) item\(items.count == 1 ? "" : "s")")
                        .font(.caption).foregroundStyle(.tertiary)
                }
            }
            if items.isEmpty {
                emptyState("No homework due soon.")
            } else {
                VStack(spacing: 8) {
                    ForEach(items) { hw in
                        HomeworkRow(hw: hw, store: store)
                    }
                }
            }
        }
    }

    // MARK: - Upcoming Exams
    private var examsSection: some View {
        let items = store.upcomingExams(limit: 3)
        return VStack(alignment: .leading, spacing: 10) {
            SectionHeader(title: "Upcoming Exams", icon: "pencil.and.list.clipboard", color: .orange)
            if items.isEmpty {
                emptyState("No exams scheduled. Add them on the Exams page.")
            } else {
                VStack(spacing: 8) {
                    ForEach(items) { exam in
                        DashboardExamRow(exam: exam)
                    }
                }
            }
        }
    }

    // MARK: - Pending Tasks
    private var tasksSection: some View {
        let items = store.pendingTasks(limit: 5)
        return VStack(alignment: .leading, spacing: 10) {
            SectionHeader(title: "Pending Tasks", icon: "checkmark.circle.fill", color: .green)
            if items.isEmpty {
                emptyState("No pending tasks — you're all caught up!")
            } else {
                VStack(spacing: 8) {
                    ForEach(items) { task in
                        TaskRow(task: task, store: store)
                    }
                }
            }
        }
    }

    private func emptyState(_ message: String) -> some View {
        Text(message)
            .font(.subheadline).foregroundStyle(.secondary)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(14)
            .glassCard(cornerRadius: 14)
    }
}

// MARK: - Summary Card

struct SummaryCard: View {
    let value: String
    var suffix: String = ""
    let label: String
    let icon: String
    let color: Color
    var dimmed = false
    var action: () -> Void = {}

    var body: some View {
        Button(action: action) {
            VStack(spacing: 4) {
                Image(systemName: icon)
                    .font(.body)
                    .foregroundStyle(color)
                HStack(alignment: .lastTextBaseline, spacing: 0) {
                    Text(value)
                        .font(.title2.bold())
                        .fontDesign(.rounded)
                        .foregroundStyle(dimmed ? Color.tertiaryLabel : Color.primary)
                    if !suffix.isEmpty {
                        Text(suffix)
                            .font(.caption.weight(.medium))
                            .fontDesign(.rounded)
                            .foregroundStyle(.secondary)
                    }
                }
                Text(label)
                    .font(.system(size: 9, weight: .medium))
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
                    .multilineTextAlignment(.center)
                    .minimumScaleFactor(0.8)
            }
            .frame(maxWidth: .infinity, minHeight: 84)
            .padding(.vertical, 12)
            .padding(.horizontal, 4)
            .glassEffect(.regular, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            .contentShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(label): \(value)\(suffix)")
    }
}

// MARK: - Sub-views

struct SectionHeader: View {
    let title: String
    let icon: String
    var color: Color = .primary
    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: icon).foregroundStyle(color)
            Text(title)
        }
        .font(.headline)
        .foregroundStyle(.primary)
    }
}

struct HomeworkRow: View {
    let hw: Homework
    let store: CanopyStore

    var body: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 3) {
                Text(hw.title).font(.subheadline.weight(.medium)).lineLimit(1)
                HStack(spacing: 6) {
                    if let cls = store.schoolClass(hw.classId) {
                        Text(cls.name)
                            .font(.caption.weight(.medium))
                            .foregroundStyle(Color(hex: cls.color))
                            .lineLimit(1)
                    }
                    if let d = hw.dueDate.asDate {
                        Text("Due \(DateFormatter.monthDay.string(from: d))")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                }
            }
            Spacer()
            priorityChip
        }
        .padding(14)
        .glassCard(cornerRadius: 14)
    }

    @ViewBuilder
    private var priorityChip: some View {
        switch hw.priority {
        case "high": TintedChip(text: hw.priority, color: .red)
        case "medium": TintedChip(text: hw.priority, color: .orange)
        default: OutlinedChip(text: hw.priority)
        }
    }
}

/// Web dashboard exam row: title + "MMM D at startTime[ — location]".
struct DashboardExamRow: View {
    let exam: Exam
    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(exam.title).font(.subheadline.weight(.medium)).lineLimit(1)
            let dateText = exam.date.asDate.map { DateFormatter.monthDay.string(from: $0) } ?? exam.date
            let timeText = exam.startTime.isEmpty ? "" : " at \(ScheduleEngine.formatTime12(exam.startTime))"
            Text("\(dateText)\(timeText)" + (exam.location.isEmpty ? "" : " — \(exam.location)"))
                .font(.caption).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .glassCard(cornerRadius: 14)
    }
}

struct TaskRow: View {
    let task: SchoolTask; let store: CanopyStore
    var body: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 3) {
                Text(task.title).font(.subheadline.weight(.medium)).lineLimit(1)
                if let d = task.dueDate.asDate {
                    Text("Due \(DateFormatter.monthDay.string(from: d))")
                        .font(.caption).foregroundStyle(.secondary)
                }
            }
            Spacer()
            OutlinedChip(text: task.category)
        }
        .padding(14)
        .glassCard(cornerRadius: 14)
    }
}
