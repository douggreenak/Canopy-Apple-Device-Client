import SwiftUI

private let hourHeight: CGFloat = 64   // points per hour
private let dayStart = 7               // 7 AM
private let dayEnd   = 20              // 8 PM
private let totalHours = dayEnd - dayStart

private func minutesFrom7am(_ time: String) -> CGFloat {
    let parts = time.split(separator: ":").compactMap { Int($0) }
    guard parts.count == 2 else { return 0 }
    return CGFloat((parts[0] - dayStart) * 60 + parts[1])
}

// MARK: - View Mode

private enum ScheduleViewMode: String, CaseIterable {
    case day = "Day"
    case week = "Week"
    case year = "Year"
}

// MARK: - Main View

struct ScheduleView: View {
    @Environment(CanopyStore.self) private var store
    @State private var selectedDate = Date.now
    @State private var viewMode: ScheduleViewMode = .day
    @State private var tappedClass: SchoolClass?

    private var totalHeight: CGFloat { CGFloat(totalHours) * hourHeight }

    var body: some View {
        NavigationStack {
            ZStack { CanopyBackground()
                VStack(spacing: 0) {
                    controlBar
                        .padding(.horizontal, 16)
                        .padding(.top, 8)
                        .padding(.bottom, 4)

                    switch viewMode {
                    case .day:
                        if let dis = store.disruption(on: selectedDate) {
                            disruptionBanner(dis)
                        }
                        daySchedule
                    case .week:
                        weekSchedule
                    case .year:
                        yearSchedule
                    }
                }
            }
            .navigationTitle("")
            .navigationBarTitleInline()
            .iosHideNavigationBar()
            .refreshable { await store.loadAll() }
            .sheet(item: $tappedClass) { cls in
                ClassDetailSheet(
                    cls: cls,
                    assignments: store.homework
                        .filter { $0.classId == cls.id && $0.source == "powerschool" }
                        .sorted { $0.dueDate > $1.dueDate },
                    allHomework: store.homework
                        .filter { $0.classId == cls.id && $0.source != "powerschool" }
                )
            }
        }
    }

    // MARK: - Control Bar
    private var controlBar: some View {
        VStack(spacing: 8) {
            // Mode picker
            Picker("View", selection: $viewMode.animation(.spring(response: 0.3))) {
                ForEach(ScheduleViewMode.allCases, id: \.self) { mode in
                    Text(mode.rawValue).tag(mode)
                }
            }
            .pickerStyle(.segmented)

            // Day navigation — leading/trailing groups are each 88 pt wide so the
            // date label stays perfectly centred even with the extra "today" button.
            HStack(spacing: 0) {
                // Leading: back chevron + invisible balance spacer
                Button {
                    withAnimation(.spring(response: 0.3)) {
                        let step: Calendar.Component = viewMode == .week ? .weekOfYear : (viewMode == .year ? .year : .day)
                        selectedDate = Calendar.current.date(byAdding: step, value: -1, to: selectedDate)!
                    }
                } label: {
                    Image(systemName: "chevron.left")
                        .font(.body.weight(.semibold))
                        .frame(width: 44, height: 44)
                        .background(.regularMaterial, in: Circle())
                }
                .buttonStyle(.plain)
                Color.clear.frame(width: 44, height: 44) // balances the "today" button

                Spacer()

                VStack(spacing: 2) {
                    if viewMode == .day {
                        Text(selectedDate, format: .dateTime.weekday(.wide))
                            .font(.headline)
                        Text(selectedDate, format: .dateTime.month(.abbreviated).day())
                            .font(.subheadline).foregroundStyle(.secondary)
                    } else if viewMode == .week {
                        let weekStart = startOfWeek(for: selectedDate)
                        let weekEnd = Calendar.current.date(byAdding: .day, value: 4, to: weekStart)!
                        Text("Week of \(weekStart.formatted(.dateTime.month(.abbreviated).day()))")
                            .font(.headline)
                        Text("\(weekEnd.formatted(.dateTime.month(.abbreviated).day())), \(weekStart.formatted(.dateTime.year()))")
                            .font(.subheadline).foregroundStyle(.secondary)
                    } else {
                        Text(selectedDate, format: .dateTime.year())
                            .font(.headline)
                        Text("Year view").font(.subheadline).foregroundStyle(.secondary)
                    }
                }

                Spacer()

                // Trailing: forward chevron + today shortcut
                Button {
                    withAnimation(.spring(response: 0.3)) {
                        let step: Calendar.Component = viewMode == .week ? .weekOfYear : (viewMode == .year ? .year : .day)
                        selectedDate = Calendar.current.date(byAdding: step, value: 1, to: selectedDate)!
                    }
                } label: {
                    Image(systemName: "chevron.right")
                        .font(.body.weight(.semibold))
                        .frame(width: 44, height: 44)
                        .background(.regularMaterial, in: Circle())
                }
                .buttonStyle(.plain)

                Button {
                    withAnimation(.spring(response: 0.3)) { selectedDate = .now }
                } label: {
                    Image(systemName: "calendar.circle")
                        .font(.body.weight(.semibold))
                        .frame(width: 44, height: 44)
                        .background(.regularMaterial, in: Circle())
                }
                .buttonStyle(.plain)
                .disabled(Calendar.current.isDateInToday(selectedDate))
            }
            .foregroundStyle(.primary)
        }
    }

    // MARK: - Disruption banner
    private func disruptionBanner(_ dis: ScheduleDisruption) -> some View {
        HStack(spacing: 10) {
            Image(systemName: "calendar.badge.exclamationmark")
                .foregroundStyle(.orange)
            VStack(alignment: .leading, spacing: 2) {
                Text(dis.label.isEmpty ? dis.type.replacingOccurrences(of: "_", with: " ").capitalized : dis.label)
                    .font(.subheadline.bold())
                Text("Schedule modified for this day")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
        }
        .padding(12)
        .background(Color.orange.opacity(0.12), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .padding(.horizontal, 16)
        .padding(.bottom, 4)
    }

    // MARK: - Year Schedule
    private var yearSchedule: some View {
        let cal = Calendar.current
        let year = cal.component(.year, from: selectedDate)
        let months = (1...12).compactMap { m -> Date? in
            cal.date(from: DateComponents(year: year, month: m, day: 1))
        }
        let cols = [GridItem(.adaptive(minimum: 150, maximum: 240), spacing: 16)]
        return ScrollView {
            LazyVGrid(columns: cols, spacing: 16) {
                ForEach(months, id: \.self) { month in
                    MonthMiniCalendar(month: month, store: store) { tappedDate in
                        withAnimation(.spring(response: 0.3)) {
                            selectedDate = tappedDate
                            viewMode = .day
                        }
                    }
                }
            }
            .padding(16)
            .padding(.bottom, 32)
        }
    }

    // MARK: - Day Schedule
    private var daySchedule: some View {
        ScrollViewReader { proxy in
            ScrollView {
                ZStack(alignment: .topLeading) {
                    GeometryReader { geo in
                        timelineBody(for: selectedDate, containerWidth: geo.size.width)
                    }
                    // Real layout anchor at the first-event position.
                    // Color.clear spacer pushes the ID'd view to the exact Y we want
                    // so proxy.scrollTo can locate it without relying on .offset().
                    scrollAnchor(id: "dayAnchor", target: scrollTarget(for: [selectedDate]))
                }
                .frame(height: totalHeight + 32)
                .frame(maxWidth: .infinity)
                .padding(.horizontal, 16)
                .padding(.bottom, 32)
            }
            .onAppear {
                DispatchQueue.main.async {
                    proxy.scrollTo("dayAnchor", anchor: .top)
                }
            }
            .onChange(of: selectedDate) { _, _ in
                DispatchQueue.main.async {
                    withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) {
                        proxy.scrollTo("dayAnchor", anchor: .top)
                    }
                }
            }
        }
    }

    // MARK: - Week Schedule
    private var weekSchedule: some View {
        let weekStart = startOfWeek(for: selectedDate)
        let days = (0..<5).compactMap { Calendar.current.date(byAdding: .day, value: $0, to: weekStart) }

        return VStack(spacing: 0) {
            // Day header row — fixed, outside the ScrollView so it never scrolls
            HStack(spacing: 1) {
                ForEach(days, id: \.self) { date in
                    let isToday = Calendar.current.isDateInToday(date)
                    VStack(spacing: 2) {
                        Text(date.formatted(.dateTime.weekday(.abbreviated)))
                            .font(.caption2.weight(.medium))
                            .foregroundStyle(isToday ? Color.accentColor : .secondary)
                        Text(date.formatted(.dateTime.day()))
                            .font(.callout.weight(isToday ? .bold : .regular))
                            .foregroundStyle(isToday ? Color.accentColor : .primary)
                    }
                    .frame(maxWidth: .infinity)
                }
            }
            .frame(height: 36)
            .padding(.horizontal, 8)

            // Scrollable timeline
            ScrollViewReader { proxy in
                ScrollView {
                    ZStack(alignment: .topLeading) {
                        GeometryReader { geo in
                            weekTimelineBody(days: days, containerWidth: geo.size.width)
                        }
                        scrollAnchor(id: "weekAnchor", target: scrollTarget(for: days))
                    }
                    .frame(height: totalHeight + 32)
                    .frame(maxWidth: .infinity)
                    .padding(.horizontal, 8)
                    .padding(.bottom, 32)
                }
                .onAppear {
                    DispatchQueue.main.async {
                        proxy.scrollTo("weekAnchor", anchor: .top)
                    }
                }
                .onChange(of: selectedDate) { _, _ in
                    DispatchQueue.main.async {
                        withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) {
                            proxy.scrollTo("weekAnchor", anchor: .top)
                        }
                    }
                }
            }
        }
    }

    // MARK: - Shared scroll helpers

    /// Y offset of the earliest class across the given days, minus 48 pt of breathing room.
    /// Falls back to 0 (7 AM) when there are no classes.
    private func scrollTarget(for days: [Date]) -> CGFloat {
        let earliest = days
            .flatMap { store.classes(for: $0) }
            .map { minutesFrom7am($0.startTime) * (hourHeight / 60) }
            .min()
        guard let y = earliest else { return 0 }
        return max(0, y - 48)
    }

    /// Zero-height anchor view placed at `target` using real layout height (not .offset),
    /// so ScrollViewReader.scrollTo can reliably locate it.
    @ViewBuilder
    private func scrollAnchor(id: String, target: CGFloat) -> some View {
        VStack(spacing: 0) {
            Color.clear.frame(height: target)
            Color.clear.frame(height: 1).id(id)
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity)
        .allowsHitTesting(false)
    }

    // Lays out hour grid + day columns given a known container width.
    private func weekTimelineBody(days: [Date], containerWidth: CGFloat) -> some View {
        let gaps = CGFloat(days.count - 1)   // 1-pt separators between columns
        let colW = max(1, (containerWidth - gaps) / CGFloat(days.count))

        return ZStack(alignment: .topLeading) {
            weekHourGrid(containerWidth: containerWidth)
            HStack(alignment: .top, spacing: 1) {
                ForEach(days, id: \.self) { date in
                    weekColumnBody(for: date, width: colW)
                }
            }
        }
        .frame(width: containerWidth, height: totalHeight + 32)
    }

    // Hour lines spanning the full content width — no time labels.
    private func weekHourGrid(containerWidth: CGFloat) -> some View {
        ZStack(alignment: .topLeading) {
            ForEach(dayStart...dayEnd, id: \.self) { hour in
                Rectangle()
                    .fill(Color.secondary.opacity(0.2))
                    .frame(width: containerWidth, height: 0.5)
                    .offset(y: CGFloat(hour - dayStart) * hourHeight)
            }
        }
        .frame(height: totalHeight + 32)
    }

    private func weekColumnBody(for date: Date, width: CGFloat) -> some View {
        ZStack(alignment: .topLeading) {
            ForEach(store.classes(for: date)) { cls in
                compactClassBlock(cls, width: width)
                    .onTapGesture { tappedClass = cls }
            }

            if let lunch = store.lunchTime(for: date) {
                compactLunchBlock(lunch, width: width)
            }

            nowIndicatorLine(date: date, width: width)
        }
        .frame(width: width, height: totalHeight + 32)
    }

    private func compactClassBlock(_ cls: SchoolClass, width: CGFloat) -> some View {
        let top = minutesFrom7am(cls.startTime) * (hourHeight / 60)
        let height = max(20, minutesFrom7am(cls.endTime) * (hourHeight / 60) - top)
        return VStack(alignment: .leading, spacing: 1) {
            Text(cls.name)
                .font(.caption2.bold())
                .lineLimit(2)
        }
        .padding(.horizontal, 4)
        .padding(.vertical, 3)
        .frame(width: width - 2, height: height, alignment: .topLeading)
        .background(Color(hex: cls.color).opacity(0.2), in: RoundedRectangle(cornerRadius: 4))
        .overlay(alignment: .leading) {
            RoundedRectangle(cornerRadius: 2).fill(Color(hex: cls.color)).frame(width: 3)
        }
        .clipShape(RoundedRectangle(cornerRadius: 4))
        .offset(x: 2, y: top)
    }

    private func compactLunchBlock(_ dt: DayTime, width: CGFloat) -> some View {
        let top = minutesFrom7am(dt.startTime) * (hourHeight / 60)
        let height = max(16, minutesFrom7am(dt.endTime) * (hourHeight / 60) - top)
        return Text("Lunch")
            .font(.caption2.bold())
            .padding(.horizontal, 4).padding(.vertical, 2)
            .frame(width: width - 2, height: height, alignment: .topLeading)
            .background(Color.accentColor.opacity(0.10), in: RoundedRectangle(cornerRadius: 4))
            .clipShape(RoundedRectangle(cornerRadius: 4))
            .offset(x: 2, y: top)
    }

    @ViewBuilder
    private func nowIndicatorLine(date: Date, width: CGFloat) -> some View {
        let now = Date.now
        let cal = Calendar.current
        let h = cal.component(.hour, from: now)
        let m = cal.component(.minute, from: now)
        if Calendar.current.isDate(now, inSameDayAs: date) && h >= dayStart && h < dayEnd {
            let y = CGFloat((h - dayStart) * 60 + m) * (hourHeight / 60)
            Rectangle().fill(Color.red).frame(height: 1.5)
                .overlay(alignment: .leading) {
                    Circle().fill(.red).frame(width: 6, height: 6).offset(x: -3)
                }
                .offset(y: y)
        }
    }

    // MARK: - Day Timeline
    private func timelineBody(for date: Date, containerWidth: CGFloat) -> some View {
        let blockAreaOffset: CGFloat = 8   // no label column; just a small left margin
        let blockWidth = containerWidth - blockAreaOffset
        return ZStack(alignment: .topLeading) {
            hourGrid(containerWidth: containerWidth)

            ForEach(store.dayEntries(for: date)) { entry in
                classBlock(entry, offset: blockAreaOffset, width: blockWidth)
                    .onTapGesture { tappedClass = entry.cls }
            }

            if store.disruption(on: date)?.type != "no_school", let lunch = store.lunchTime(for: date) {
                lunchBlock(lunch, offset: blockAreaOffset, width: blockWidth)
            }

            nowIndicator(for: date, offset: blockAreaOffset, containerWidth: containerWidth)
        }
        .frame(width: containerWidth, height: totalHeight + 32)
    }

    // MARK: - Hour grid — lines only, no time labels
    private func hourGrid(containerWidth: CGFloat) -> some View {
        ZStack(alignment: .topLeading) {
            ForEach(dayStart...dayEnd, id: \.self) { hour in
                Rectangle()
                    .fill(Color.secondary.opacity(0.2))
                    .frame(width: containerWidth, height: 0.5)
                    .offset(y: CGFloat(hour - dayStart) * hourHeight)
            }
        }
        .frame(height: totalHeight + 32)
    }

    // MARK: - Class block
    private func classBlock(_ entry: CanopyStore.DayEntry, offset: CGFloat, width: CGFloat) -> some View {
        let cls = entry.cls
        let top = minutesFrom7am(entry.startTime) * (hourHeight / 60)
        let height = max(24, minutesFrom7am(entry.endTime) * (hourHeight / 60) - top)

        return VStack(alignment: .leading, spacing: 2) {
            HStack(spacing: 4) {
                Text(cls.name).font(.caption.bold()).lineLimit(1)
                    .strikethrough(entry.cancelled)
                if entry.cancelled {
                    Text("Cancelled").font(.system(size: 8, weight: .bold))
                        .padding(.horizontal, 4).padding(.vertical, 1)
                        .background(Color.red.opacity(0.15), in: Capsule())
                        .foregroundStyle(.red)
                }
            }
            if height > 36 {
                Text("\(entry.startTime) – \(entry.endTime)")
                    .font(.caption2).foregroundStyle(.secondary)
            }
            if height > 52, !cls.room.isEmpty {
                Text("Rm \(cls.room)").font(.caption2).foregroundStyle(.secondary)
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 5)
        .frame(width: width, height: height, alignment: .topLeading)
        .background(Color(hex: cls.color).opacity(entry.cancelled ? 0.08 : 0.22), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
        .overlay(alignment: .leading) {
            RoundedRectangle(cornerRadius: 3).fill(Color(hex: cls.color)).frame(width: 4)
        }
        .overlay(RoundedRectangle(cornerRadius: 8, style: .continuous)
            .strokeBorder(Color(hex: cls.color).opacity(0.3), lineWidth: 0.5))
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        .opacity(entry.cancelled ? 0.6 : 1)
        .offset(x: offset, y: top)
    }

    // MARK: - Lunch block
    private func lunchBlock(_ dt: DayTime, offset: CGFloat, width: CGFloat) -> some View {
        let top = minutesFrom7am(dt.startTime) * (hourHeight / 60)
        let height = max(20, minutesFrom7am(dt.endTime) * (hourHeight / 60) - top)

        return HStack(spacing: 6) {
            Image(systemName: "fork.knife").font(.caption2)
            Text("Lunch").font(.caption.bold())
            if height > 32 {
                Text("\(dt.startTime) – \(dt.endTime)").font(.caption2).foregroundStyle(.secondary)
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .frame(width: width, height: height, alignment: .leading)
        .background(Color.accentColor.opacity(0.10), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
        .overlay(alignment: .leading) {
            RoundedRectangle(cornerRadius: 3).fill(Color.accentColor.opacity(0.5)).frame(width: 3)
        }
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        .offset(x: offset, y: top)
    }

    // MARK: - Now indicator
    @ViewBuilder
    private func nowIndicator(for date: Date, offset: CGFloat, containerWidth: CGFloat) -> some View {
        let now = Date.now
        let cal = Calendar.current
        let h = cal.component(.hour, from: now)
        let m = cal.component(.minute, from: now)
        if Calendar.current.isDate(now, inSameDayAs: date) && h >= dayStart && h < dayEnd {
            let y = CGFloat((h - dayStart) * 60 + m) * (hourHeight / 60)
            let lineWidth = containerWidth - offset + 4  // dot overhangs 4 pts into label area
            HStack(spacing: 0) {
                Circle().fill(.red).frame(width: 8, height: 8)
                Rectangle().fill(.red).frame(width: lineWidth, height: 1.5)
            }
            .shadow(color: .red.opacity(0.4), radius: 3)
            .offset(x: offset - 4, y: y)
        }
    }

    // MARK: - Helpers
    private func startOfWeek(for date: Date) -> Date {
        let cal = Calendar.current
        var comps = cal.dateComponents([.weekOfYear, .yearForWeekOfYear], from: date)
        comps.weekday = 2 // Monday
        return cal.date(from: comps) ?? date
    }
}

// MARK: - Month mini calendar (Year view)

struct MonthMiniCalendar: View {
    let month: Date
    let store: CanopyStore
    let onTap: (Date) -> Void

    private let cal = Calendar.current
    private let weekdaySymbols = ["S", "M", "T", "W", "T", "F", "S"]

    var body: some View {
        let days = monthDays()
        VStack(alignment: .leading, spacing: 6) {
            Text(month, format: .dateTime.month(.wide))
                .font(.subheadline.bold())
            HStack(spacing: 0) {
                ForEach(Array(weekdaySymbols.enumerated()), id: \.offset) { _, s in
                    Text(s).font(.system(size: 9)).foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity)
                }
            }
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 1), count: 7), spacing: 3) {
                ForEach(Array(days.enumerated()), id: \.offset) { _, day in
                    if let day {
                        dayCell(day)
                    } else {
                        Color.clear.frame(height: 22)
                    }
                }
            }
        }
        .padding(12)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
    }

    private func dayCell(_ date: Date) -> some View {
        let hasClasses = !store.classes(for: date).isEmpty
        let hasDisruption = store.disruption(on: date) != nil
        let isToday = cal.isDateInToday(date)
        return Button { onTap(date) } label: {
            Text("\(cal.component(.day, from: date))")
                .font(.system(size: 10, weight: isToday ? .bold : .regular))
                .frame(maxWidth: .infinity)
                .frame(height: 22)
                .background(
                    Circle()
                        .fill(isToday ? Color.accentColor
                              : hasClasses ? Color.accentColor.opacity(0.14) : Color.clear)
                        .frame(width: 22, height: 22)
                )
                .foregroundStyle(isToday ? .white : .primary)
                .overlay(alignment: .topTrailing) {
                    if hasDisruption {
                        Circle().fill(.orange).frame(width: 4, height: 4).offset(x: -2, y: 2)
                    }
                }
        }
        .buttonStyle(.plain)
    }

    private func monthDays() -> [Date?] {
        guard let range = cal.range(of: .day, in: .month, for: month),
              let first = cal.date(from: cal.dateComponents([.year, .month], from: month)) else { return [] }
        let leading = cal.component(.weekday, from: first) - 1 // 0=Sun
        var cells: [Date?] = Array(repeating: nil, count: leading)
        for d in range {
            if let date = cal.date(byAdding: .day, value: d - 1, to: first) { cells.append(date) }
        }
        return cells
    }
}
