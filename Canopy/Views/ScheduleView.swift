import SwiftUI

// Port of web src/app/schedule/page.tsx: header + date nav, Day / Week /
// Year tabs over the shared calendar components, the zero-classes empty
// state, the day-view disruption banner, the date-specific class detail
// sheet, and the Disruptions section (month calendar + add) below the grid.
struct ScheduleView: View {
    @Environment(CanopyStore.self) private var store
    @State private var selectedDate = Date.now
    @State private var viewMode: CalendarViewMode = .day
    @State private var detail: ClassDaySelection?
    @State private var showAddDisruption = false

    private var nav: AppNavigation { AppNavigation.shared }
    private static let yearFmt: DateFormatter = { let f = DateFormatter(); f.dateFormat = "yyyy"; return f }()
    private static let dayYearFmt: DateFormatter = { let f = DateFormatter(); f.dateFormat = "d, yyyy"; return f }()

    var body: some View {
        NavigationStack {
            ZStack {
                CanopyBackground()
                GeometryReader { geo in
                    VStack(spacing: 0) {
                        headerBlock
                            .padding(.horizontal, 16)
                            .padding(.top, 8)
                            .padding(.bottom, 8)

                        // Kept outside the scroll view so the auto-scroll to
                        // the first class never hides them.
                        if viewMode == .day, let dis = store.disruption(on: selectedDate) {
                            disruptionBanner(dis)
                                .padding(.horizontal, 16)
                                .padding(.bottom, 8)
                        }

                        ScrollViewReader { proxy in
                            ScrollView {
                                VStack(alignment: .leading, spacing: 16) {
                                    Color.clear.frame(height: 0).id("scheduleTopAnchor")
                                    if store.classes.isEmpty && !store.isLoading {
                                        zeroClassesState
                                    }
                                    calendarContent(width: max(200, geo.size.width - 32))
                                    disruptionsSection
                                }
                                .padding(.horizontal, 16)
                                .padding(.bottom, 32)
                            }
                            .onAppear { scrollToFirstClass(proxy, animated: false) }
                            .onChange(of: selectedDate) { _, _ in scrollToFirstClass(proxy, animated: true) }
                            .onChange(of: viewMode) { _, _ in scrollToFirstClass(proxy, animated: false) }
                        }
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
            .sheet(isPresented: $showAddDisruption) {
                DisruptionEditorSheet(disruption: nil, prefillDate: .now).presentationDetents([.large])
            }
            .onAppear { consumeNavigation() }
            .onChange(of: nav.scheduleDate) { _, _ in consumeNavigation() }
        }
    }

    /// Cross-tab jump: open the requested date in Day view, then clear it.
    private func consumeNavigation() {
        guard let iso = nav.scheduleDate else { return }
        if let d = iso.asDate {
            selectedDate = d
            viewMode = .day
        }
        nav.scheduleDate = nil
    }

    /// Day view jumps to the first class; Week and Year (web: scrolled to top
    /// on change) go back to the top of the page so their headers stay visible.
    private func scrollToFirstClass(_ proxy: ScrollViewProxy, animated: Bool) {
        let target = viewMode == .day ? "scheduleGridAnchor" : "scheduleTopAnchor"
        DispatchQueue.main.async {
            if animated {
                withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) { proxy.scrollTo(target, anchor: .top) }
            } else {
                proxy.scrollTo(target, anchor: .top)
            }
        }
    }

    // MARK: - Header (title, subtitle, nav row, tabs)
    private var headerBlock: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Image(systemName: "calendar").font(.title2).foregroundStyle(Color.accentColor)
                Text("Schedule").font(.title.weight(.semibold)).fontDesign(.rounded)
            }
            Text("Your class calendar — tap a class for details, or add schedule disruptions (early-outs, no-school days).")
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            HStack(spacing: 6) {
                Button { navigate(-1) } label: {
                    Image(systemName: "chevron.left").font(.body.weight(.semibold))
                        .frame(width: 32, height: 32)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Previous")

                let isTodaySelected = Calendar.current.isDateInToday(selectedDate)
                if isTodaySelected {
                    Button { withAnimation(.spring(response: 0.3)) { selectedDate = .now } } label: {
                        Label("Today", systemImage: "calendar.circle")
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.small)
                } else {
                    Button { withAnimation(.spring(response: 0.3)) { selectedDate = .now } } label: {
                        Label("Today", systemImage: "calendar.circle")
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                }

                Button { navigate(1) } label: {
                    Image(systemName: "chevron.right").font(.body.weight(.semibold))
                        .frame(width: 32, height: 32)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Next")

                Spacer(minLength: 0)
            }
            Text(headerLabel)
                .font(.headline)
                .lineLimit(1)
                .minimumScaleFactor(0.7)

            Picker("View", selection: $viewMode.animation(.easeOut(duration: 0.2))) {
                ForEach([CalendarViewMode.day, .week, .year]) { mode in
                    Text(mode.rawValue).tag(mode)
                }
            }
            .pickerStyle(.segmented)
        }
    }

    private var headerLabel: String {
        switch viewMode {
        case .week:
            let start = ScheduleEngine.weekViewStart(for: selectedDate)
            let end = Calendar.current.date(byAdding: .day, value: 6, to: start) ?? start
            let sameMonth = Calendar.current.component(.month, from: start) == Calendar.current.component(.month, from: end)
            return sameMonth
                ? "\(DateFormatter.monthDay.string(from: start)) – \(Self.dayYearFmt.string(from: end))"
                : "\(DateFormatter.monthDay.string(from: start)) – \(DateFormatter.monthDayYear.string(from: end))"
        case .year:
            return Self.yearFmt.string(from: selectedDate)
        default:
            return DateFormatter.fullDate.string(from: selectedDate)
        }
    }

    private func navigate(_ dir: Int) {
        let step: Calendar.Component = viewMode == .week ? .weekOfYear : (viewMode == .year ? .year : .day)
        withAnimation(.spring(response: 0.3)) {
            selectedDate = Calendar.current.date(byAdding: step, value: dir, to: selectedDate) ?? selectedDate
        }
    }

    // MARK: - Disruption banner (day view)
    private func disruptionBanner(_ dis: ScheduleDisruption) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.orange)
            Text("\(Text(dis.displayLabel).bold()) — Schedule modified for this day.")
                .font(.subheadline)
            Spacer(minLength: 0)
        }
        .padding(12)
        .background(Color.orange.opacity(0.12), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
    }

    // MARK: - Zero-classes empty state
    private var zeroClassesState: some View {
        VStack(spacing: 10) {
            Text("No classes imported — only Lunch is shown on the schedule")
                .font(.headline).foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
            Text("Add classes from the Classes page or import them from PowerSchool to populate your full schedule.")
                .font(.subheadline).foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
            HStack(spacing: 10) {
                Button("Add classes") { nav.go(.classes) }
                    .buttonStyle(.bordered)
                Button("Connect PowerSchool") { nav.goToSettings(section: "powerschool") }
                    .buttonStyle(.borderedProminent)
            }
            .padding(.top, 4)
        }
        .frame(maxWidth: .infinity)
        .padding(16)
        .glassCard(cornerRadius: 14)
    }

    // MARK: - Calendar content
    @ViewBuilder
    private func calendarContent(width: CGFloat) -> some View {
        let innerWidth = max(120, width - 28)
        let bounds = canopyCalendarBounds(store)
        let dueCounts = buildDueCountMap(homework: store.homework, tasks: store.tasks)
        Group {
            switch viewMode {
            case .day:
                ScheduleDayView(date: selectedDate, hasClasses: !store.classes.isEmpty,
                                dueCounts: dueCounts, bounds: bounds, width: innerWidth) { entry in
                    detail = ClassDaySelection(entry: entry, date: selectedDate)
                }
                .overlay(alignment: .top) {
                    scrollAnchor(target: canopyFirstEntryOffset(store, dates: [selectedDate], bounds: bounds))
                }
            case .week:
                let weekStart = ScheduleEngine.weekViewStart(for: selectedDate)
                let days = (0..<7).compactMap { Calendar.current.date(byAdding: .day, value: $0, to: weekStart) }
                ScheduleWeekView(weekStart: weekStart, dueCounts: dueCounts, bounds: bounds, width: innerWidth) { entry, date in
                    detail = ClassDaySelection(entry: entry, date: date)
                }
                .overlay(alignment: .top) {
                    scrollAnchor(target: CalendarMetrics.weekHeaderHeight + canopyFirstEntryOffset(store, dates: days, bounds: bounds))
                }
            default:
                ScheduleYearView(year: Calendar.current.component(.year, from: selectedDate)) { date in
                    withAnimation(.easeOut(duration: 0.2)) { selectedDate = date; viewMode = .day }
                }
            }
        }
        .padding(14)
        .glassCard()
        .id(viewMode)
    }

    /// Zero-height anchor placed with real layout height (not .offset) so
    /// ScrollViewProxy.scrollTo can locate it; `.top` alignment on the overlay
    /// puts the spacer's origin at the grid's top edge.
    private func scrollAnchor(target: CGFloat) -> some View {
        VStack(spacing: 0) {
            Color.clear.frame(height: max(0, target - 14))
            Color.clear.frame(height: 1).id("scheduleGridAnchor")
            Spacer(minLength: 0)
        }
        .allowsHitTesting(false)
    }

    // MARK: - Disruptions section (web: header + count + Add, caption, month calendar)
    private var disruptionsSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.orange)
                Text("Disruptions").font(.headline)
                if !store.disruptions.isEmpty {
                    Text("\(store.disruptions.count)")
                        .font(.caption.weight(.semibold))
                        .padding(.horizontal, 7).padding(.vertical, 2)
                        .background(Color.secondary.opacity(0.15), in: Capsule())
                }
                Spacer()
                Button { showAddDisruption = true } label: {
                    Label("Add", systemImage: "plus")
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
            }
            Text("School is treated as in session every day by default — add a \"No School\" entry with an end date to mark a break (summer, winter, etc.) or any other day off.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            DisruptionCalendarView()
        }
        .padding(14)
        .glassCard()
        .id("scheduleDisruptions")
    }
}
