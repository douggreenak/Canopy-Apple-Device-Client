import SwiftUI

// Shared calendar components used by both DashboardView and ScheduleView —
// ports of web DayView.tsx / WeekView.tsx / YearView.tsx, the dashboard
// Heatmap tab, and ClassDetailDialog.tsx. Every day computation goes
// through `CanopyStore.dayEntries(for:)` so A/B days, day swaps, assembly
// synthesis, cancellations and lunch suppression behave exactly as the web.

// MARK: - View mode (web Tabs: Day / Week / Year [/ Heatmap])

enum CalendarViewMode: String, CaseIterable, Identifiable {
    case day = "Day"
    case week = "Week"
    case year = "Year"
    case heatmap = "Heatmap"
    var id: String { rawValue }
}

/// A tapped class block — the entry plus the date it was tapped on, since a
/// class repeats and the detail sheet is date-specific.
struct ClassDaySelection: Identifiable {
    let entry: CanopyStore.DayEntry
    let date: Date
    var id: String { "\(entry.id)::\(DateFormatter.iso.string(from: date))" }
}

// MARK: - Metrics (web calendarMetrics.ts)

enum CalendarMetrics {
    static let pxPerHour: CGFloat = 64
    static let timeGutter: CGFloat = 64
    static let weekGutter: CGFloat = 44
    static let minBlockHeight: CGFloat = 28
    static let weekHeaderHeight: CGFloat = 48
    static let weekMinColumnWidth: CGFloat = 40

    static func totalHeight(_ b: ScheduleEngine.DayBounds) -> CGFloat {
        CGFloat(b.endMin - b.startMin) / 60 * pxPerHour
    }
    static func y(_ minutes: Int, _ b: ScheduleEngine.DayBounds) -> CGFloat {
        CGFloat(minutes - b.startMin) / 60 * pxPerHour
    }
    static func height(start: Int, end: Int, _ b: ScheduleEngine.DayBounds) -> CGFloat {
        max(y(end, b) - y(start, b), minBlockHeight)
    }
}

/// Grid range for Day/Week views, derived from every class (plus Lunch) so a
/// very early or late class is never clipped (web computeDayBounds).
func canopyCalendarBounds(_ store: CanopyStore) -> ScheduleEngine.DayBounds {
    ScheduleEngine.computeDayBounds(classes: store.classes, lunch: store.lunchClass.dayTimes)
}

/// Y offset to auto-scroll to: the earliest entry across `dates` minus 48 pt.
func canopyFirstEntryOffset(_ store: CanopyStore, dates: [Date], bounds: ScheduleEngine.DayBounds) -> CGFloat {
    let earliest = dates.flatMap { store.dayEntries(for: $0) }
        .map { CalendarMetrics.y(ScheduleEngine.timeToMinutes($0.startTime), bounds) }
        .min()
    guard let y = earliest else { return 0 }
    return max(0, y - 48)
}

// MARK: - Flow layout (web flex-wrap)

struct CalendarFlowLayout: Layout {
    var spacing: CGFloat = 6
    var rowSpacing: CGFloat = 6

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let maxW = proposal.width ?? .infinity
        var x: CGFloat = 0, y: CGFloat = 0, rowH: CGFloat = 0, maxX: CGFloat = 0
        for s in subviews {
            let sz = s.sizeThatFits(.unspecified)
            if x > 0 && x + sz.width > maxW { x = 0; y += rowH + rowSpacing; rowH = 0 }
            x += sz.width + spacing
            rowH = max(rowH, sz.height)
            maxX = max(maxX, x - spacing)
        }
        return CGSize(width: proposal.width ?? maxX, height: y + rowH)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var x = bounds.minX, y = bounds.minY, rowH: CGFloat = 0
        for s in subviews {
            let sz = s.sizeThatFits(.unspecified)
            if x > bounds.minX && x + sz.width > bounds.maxX { x = bounds.minX; y += rowH + rowSpacing; rowH = 0 }
            s.place(at: CGPoint(x: x, y: y), proposal: ProposedViewSize(sz))
            x += sz.width + spacing
            rowH = max(rowH, sz.height)
        }
    }
}

// MARK: - Hour grid (labels in the left gutter, solid hour + dashed half-hour lines)

private struct HourGridLines: View {
    let bounds: ScheduleEngine.DayBounds
    let gutter: CGFloat
    let width: CGFloat
    var labelSize: CGFloat = 11
    /// The week grid draws its labels in a dedicated column instead.
    var showLabels = true

    var body: some View {
        let lineW = max(0, width - gutter)
        ZStack(alignment: .topLeading) {
            ForEach(ScheduleEngine.hours(in: bounds), id: \.self) { hour in
                let top = CalendarMetrics.y(hour * 60, bounds)
                if showLabels {
                    Text(ScheduleEngine.hourLabel(hour))
                        .font(.system(size: labelSize))
                        .foregroundStyle(Color.secondary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                        .frame(width: max(0, gutter - 8), alignment: .trailing)
                        .offset(y: top - labelSize * 0.7)
                }
                Rectangle()
                    .fill(Color.secondary.opacity(0.25))
                    .frame(width: lineW, height: 1)
                    .offset(x: gutter, y: top)
                if hour * 60 + 30 < bounds.endMin {
                    Path { p in
                        p.move(to: .zero)
                        p.addLine(to: CGPoint(x: lineW, y: 0))
                    }
                    .stroke(Color.secondary.opacity(0.25), style: StrokeStyle(lineWidth: 1, dash: [4, 3]))
                    .frame(width: lineW, height: 1)
                    .opacity(0.45)
                    .offset(x: gutter, y: CalendarMetrics.y(hour * 60 + 30, bounds))
                }
            }
        }
        .frame(width: width, height: CalendarMetrics.totalHeight(bounds), alignment: .topLeading)
        .allowsHitTesting(false)
    }
}

/// Hour labels in their own column (used by the week grid so the labels can
/// never be covered by the day columns laid over the grid lines).
private struct HourLabelsColumn: View {
    let bounds: ScheduleEngine.DayBounds
    let width: CGFloat
    var labelSize: CGFloat = 10

    var body: some View {
        ZStack(alignment: .topLeading) {
            ForEach(ScheduleEngine.hours(in: bounds), id: \.self) { hour in
                Text(ScheduleEngine.hourLabel(hour))
                    .font(.system(size: labelSize))
                    .foregroundStyle(Color.secondary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                    .frame(width: max(0, width - 6), alignment: .trailing)
                    .offset(y: CalendarMetrics.y(hour * 60, bounds) - labelSize * 0.7)
            }
        }
        .frame(width: width, height: CalendarMetrics.totalHeight(bounds), alignment: .topLeading)
        .allowsHitTesting(false)
    }
}

// MARK: - Now indicator (pulsing red dot + 2 pt line, refreshed every minute)

private struct NowIndicator: View {
    let bounds: ScheduleEngine.DayBounds
    let leading: CGFloat
    let width: CGFloat
    var dotSize: CGFloat = 10
    @State private var pulse = false

    var body: some View {
        TimelineView(.periodic(from: .now, by: 60)) { ctx in
            let cal = Calendar.current
            let nowMin = cal.component(.hour, from: ctx.date) * 60 + cal.component(.minute, from: ctx.date)
            if nowMin >= bounds.startMin && nowMin <= bounds.endMin {
                HStack(spacing: 0) {
                    Circle().fill(Color.red)
                        .frame(width: dotSize, height: dotSize)
                        .scaleEffect(pulse ? 1.25 : 1)
                        .opacity(pulse ? 0.7 : 1)
                    Rectangle().fill(Color.red).frame(height: 2)
                }
                .frame(width: width)
                .offset(x: leading, y: CalendarMetrics.y(nowMin, bounds) - dotSize / 2)
                .allowsHitTesting(false)
                .accessibilityHidden(true)
            }
        }
        .onAppear {
            withAnimation(.easeInOut(duration: 1).repeatForever(autoreverses: true)) { pulse = true }
        }
    }
}

// MARK: - Due-count badge (web dueCounts badge)

struct DueCountBadge: View {
    let count: Int
    var size: CGFloat = 16
    var body: some View {
        Text("\(count)")
            .font(.system(size: size * 0.62, weight: .bold))
            .foregroundStyle(.white)
            .padding(.horizontal, 3)
            .frame(minWidth: size, minHeight: size, maxHeight: size)
            .background(Color.red, in: Capsule())
            .accessibilityLabel("\(count) assignment\(count == 1 ? "" : "s") due")
    }
}

// MARK: - Staggered fade-in (web fadeInUp with index*45ms delay)

private struct FadeInUp: ViewModifier {
    let index: Int
    @State private var shown = false
    func body(content: Content) -> some View {
        content
            .opacity(shown ? 1 : 0)
            .offset(y: shown ? 0 : 6)
            .onAppear {
                withAnimation(.easeOut(duration: 0.22).delay(Double(index) * 0.045)) { shown = true }
            }
    }
}

// MARK: - Day view (web DayView.tsx)

struct ScheduleDayView: View {
    @Environment(CanopyStore.self) private var store
    let date: Date
    let hasClasses: Bool
    let dueCounts: [String: Int]
    let bounds: ScheduleEngine.DayBounds
    let width: CGFloat
    var onTap: ((CanopyStore.DayEntry) -> Void)? = nil

    private static let emptyFmt: DateFormatter = {
        let f = DateFormatter(); f.dateFormat = "EEEE, MMMM d"; return f
    }()

    var body: some View {
        let entries = store.dayEntries(for: date)
        let iso = DateFormatter.iso.string(from: date)
        let cal = Calendar.current
        if entries.isEmpty {
            let dow = cal.component(.weekday, from: date) - 1
            let isWeekend = dow == 0 || dow == 6
            VStack(spacing: 8) {
                Text("No classes scheduled for \(Self.emptyFmt.string(from: date))")
                    .font(.body).foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                Text(hasClasses
                     ? (isWeekend ? "Enjoy your weekend!" : "None of your classes meet on this day.")
                     : "Set up your classes via PowerSchool sync or the Classes page.")
                    .font(.subheadline).foregroundStyle(.tertiary)
                    .multilineTextAlignment(.center)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 56)
        } else {
            let gutter = CalendarMetrics.timeGutter
            ZStack(alignment: .topLeading) {
                HourGridLines(bounds: bounds, gutter: gutter, width: width)
                ForEach(Array(entries.enumerated()), id: \.element.id) { i, entry in
                    DayClassBlock(
                        entry: entry,
                        index: i,
                        dueCount: entry.cancelled ? 0 : dueCountFor(dueCounts, classId: entry.cls.id, date: iso),
                        bounds: bounds,
                        x: gutter + 4,
                        width: max(40, width - gutter - 4 - 8)
                    )
                    .onTapGesture { onTap?(entry) }
                }
                if cal.isDateInToday(date) {
                    NowIndicator(bounds: bounds, leading: gutter - 4, width: width - gutter + 4)
                }
            }
            .frame(width: width, height: CalendarMetrics.totalHeight(bounds), alignment: .topLeading)
        }
    }
}

private struct DayClassBlock: View {
    let entry: CanopyStore.DayEntry
    let index: Int
    let dueCount: Int
    let bounds: ScheduleEngine.DayBounds
    let x: CGFloat
    let width: CGFloat

    var body: some View {
        let cls = entry.cls
        let startMin = ScheduleEngine.timeToMinutes(entry.startTime)
        let endMin = ScheduleEngine.timeToMinutes(entry.endTime)
        let top = CalendarMetrics.y(startMin, bounds)
        let height = CalendarMetrics.height(start: startMin, end: endMin, bounds)
        let color = Color(hex: cls.color)
        let teacher = cls.displayTeacher

        VStack(alignment: .leading, spacing: 2) {
            HStack(spacing: 4) {
                Text(cls.name)
                    .font(.subheadline.bold())
                    .strikethrough(entry.cancelled)
                    .lineLimit(1)
                if dueCount > 0 { DueCountBadge(count: dueCount) }
            }
            if height >= 48 {
                Text("\(ScheduleEngine.formatTime12(entry.startTime)) – \(ScheduleEngine.formatTime12(entry.endTime))\(entry.cancelled ? " · Cancelled" : "")")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            if height >= 56, let teacher {
                Text(teacher + (cls.room.isEmpty ? "" : " · Rm \(cls.room)"))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .frame(width: width, height: height, alignment: .topLeading)
        .background(entry.cancelled ? Color.secondary.opacity(0.16) : color.opacity(0.16),
                    in: RoundedRectangle(cornerRadius: 8, style: .continuous))
        .overlay(alignment: .leading) {
            Rectangle().fill(entry.cancelled ? Color.secondary.opacity(0.5) : color).frame(width: 4)
        }
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        .opacity(entry.cancelled ? 0.65 : 1)
        .contentShape(Rectangle())
        .offset(x: x, y: top)
        .modifier(FadeInUp(index: index))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(cls.name), \(ScheduleEngine.formatTime12(entry.startTime)) to \(ScheduleEngine.formatTime12(entry.endTime))\(entry.cancelled ? ", cancelled" : "")\(dueCount > 0 ? ", \(dueCount) assignment\(dueCount == 1 ? "" : "s") due" : "")")
        .accessibilityAddTraits(.isButton)
    }
}

// MARK: - Week view (web WeekView.tsx)

struct ScheduleWeekView: View {
    @Environment(CanopyStore.self) private var store
    let weekStart: Date
    let dueCounts: [String: Int]
    let bounds: ScheduleEngine.DayBounds
    let width: CGFloat
    var onTap: ((CanopyStore.DayEntry, Date) -> Void)? = nil

    private static let dayLabels = ["Mon", "Tue", "Wed", "Thu", "Fri", "Sat", "Sun"]

    var body: some View {
        let cal = Calendar.current
        let days = (0..<7).compactMap { cal.date(byAdding: .day, value: $0, to: weekStart) }
        let gutter = CalendarMetrics.weekGutter
        // Seven equal columns that fit the available width (web WeekView);
        // only fall back to horizontal scrolling when columns would be unusably narrow.
        let contentW = max(width, gutter + 7 * CalendarMetrics.weekMinColumnWidth)
        let colW = (contentW - gutter) / 7
        let total = CalendarMetrics.totalHeight(bounds)
        let disrupted: [(label: String, text: String)] = days.enumerated().compactMap { i, d in
            store.disruption(on: d).map { (Self.dayLabels[i], "\(Self.dayLabels[i]): \($0.displayLabel)") }
        }

        VStack(alignment: .leading, spacing: 12) {
            if contentW <= width {
                // Fits: plain layout (no scroll container) — seven equal columns like the web.
                weekGrid(days: days, cal: cal, gutter: gutter, contentW: contentW, colW: colW, total: total)
            } else {
                ScrollView(.horizontal, showsIndicators: false) {
                    weekGrid(days: days, cal: cal, gutter: gutter, contentW: contentW, colW: colW, total: total)
                }
            }

            if !disrupted.isEmpty {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Schedule disruptions this week")
                        .font(.caption.weight(.medium))
                        .foregroundStyle(.secondary)
                    CalendarFlowLayout(spacing: 6, rowSpacing: 6) {
                        ForEach(disrupted, id: \.text) { item in
                            OutlinedChip(text: item.text, color: .orange)
                        }
                    }
                }
            }
        }
    }

    @ViewBuilder
    private func weekGrid(days: [Date], cal: Calendar, gutter: CGFloat, contentW: CGFloat, colW: CGFloat, total: CGFloat) -> some View {
        VStack(spacing: 0) {
            // Header row: weekday + day number (today = filled accent circle)
            HStack(spacing: 0) {
                Color.clear.frame(width: gutter, height: 1)
                ForEach(Array(days.enumerated()), id: \.offset) { i, d in
                    let isToday = cal.isDateInToday(d)
                    VStack(spacing: 2) {
                        Text(Self.dayLabels[i].uppercased())
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundStyle(Color.secondary)
                        Text("\(cal.component(.day, from: d))")
                            .font(.subheadline.weight(isToday ? .semibold : .regular))
                            .frame(width: 28, height: 28)
                            .background(isToday ? Color.accentColor : Color.clear, in: Circle())
                            .foregroundStyle(isToday ? Color.white : Color.primary)
                    }
                    .frame(width: colW)
                }
            }
            .frame(height: CalendarMetrics.weekHeaderHeight)
            .overlay(alignment: .bottom) { Divider() }

            ZStack(alignment: .topLeading) {
                HourGridLines(bounds: bounds, gutter: gutter, width: contentW, labelSize: 10, showLabels: false)
                HStack(spacing: 0) {
                    HourLabelsColumn(bounds: bounds, width: gutter, labelSize: 10)
                    ForEach(Array(days.enumerated()), id: \.offset) { _, d in
                        weekColumn(d, width: colW, total: total)
                    }
                }
            }
            .frame(width: contentW, height: total, alignment: .topLeading)
        }
        .frame(width: contentW)
    }

    private func weekColumn(_ date: Date, width: CGFloat, total: CGFloat) -> some View {
        let cal = Calendar.current
        let isToday = cal.isDateInToday(date)
        let iso = DateFormatter.iso.string(from: date)
        let entries = store.dayEntries(for: date)
        return ZStack(alignment: .topLeading) {
            Rectangle().fill(isToday ? Color.accentColor.opacity(0.04) : Color.clear)
            Rectangle().fill(Color.secondary.opacity(0.2)).frame(width: 1)
            ForEach(entries) { entry in
                WeekClassBlock(
                    entry: entry,
                    dueCount: entry.cancelled ? 0 : dueCountFor(dueCounts, classId: entry.cls.id, date: iso),
                    bounds: bounds,
                    width: width - 4
                )
                .onTapGesture { onTap?(entry, date) }
            }
            if isToday {
                NowIndicator(bounds: bounds, leading: -4, width: width + 4, dotSize: 8)
            }
        }
        .frame(width: width, height: total, alignment: .topLeading)
        .clipped()
    }
}

private struct WeekClassBlock: View {
    let entry: CanopyStore.DayEntry
    let dueCount: Int
    let bounds: ScheduleEngine.DayBounds
    let width: CGFloat

    private func shortTime(_ t: String) -> String {
        let m = ScheduleEngine.timeToMinutes(t)
        let h = m / 60, mm = m % 60
        let h12 = h % 12 == 0 ? 12 : h % 12
        return String(format: "%d:%02d", h12, mm)
    }

    var body: some View {
        let cls = entry.cls
        let startMin = ScheduleEngine.timeToMinutes(entry.startTime)
        let endMin = ScheduleEngine.timeToMinutes(entry.endTime)
        let top = CalendarMetrics.y(startMin, bounds)
        let height = CalendarMetrics.height(start: startMin, end: endMin, bounds)
        let color = Color(hex: cls.color)

        VStack(alignment: .leading, spacing: 1) {
            Text(cls.name)
                .font(.system(size: 12, weight: .bold))
                .strikethrough(entry.cancelled)
                .lineLimit(1)
                .padding(.trailing, dueCount > 0 ? 14 : 0)
            if height >= 36 {
                Text(shortTime(entry.startTime))
                    .font(.system(size: 9.5))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
        }
        .padding(.leading, 6)
        .padding(.trailing, 3)
        .padding(.vertical, 2)
        .frame(width: width, height: height, alignment: .topLeading)
        .background(entry.cancelled ? Color.secondary.opacity(0.16) : color.opacity(0.14),
                    in: RoundedRectangle(cornerRadius: 6, style: .continuous))
        .overlay(alignment: .leading) {
            Rectangle().fill(entry.cancelled ? Color.secondary.opacity(0.5) : color).frame(width: 3)
        }
        .overlay(alignment: .topTrailing) {
            if dueCount > 0 { DueCountBadge(count: dueCount, size: 14).padding(2) }
        }
        .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
        .opacity(entry.cancelled ? 0.5 : 1)
        .contentShape(Rectangle())
        .offset(x: 2, y: top)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(cls.name), \(ScheduleEngine.formatTime12(entry.startTime)) to \(ScheduleEngine.formatTime12(entry.endTime))\(entry.cancelled ? ", cancelled" : "")")
        .accessibilityAddTraits(.isButton)
    }
}

// MARK: - Year view (web YearView.tsx — 12 Monday-first month grids)

struct ScheduleYearView: View {
    @Environment(CanopyStore.self) private var store
    @Environment(\.colorScheme) private var scheme
    let year: Int
    let onDateTap: (Date) -> Void

    private static let monthFmt: DateFormatter = { let f = DateFormatter(); f.dateFormat = "MMM"; return f }()
    private static let a11yFmt: DateFormatter = { let f = DateFormatter(); f.dateFormat = "EEE, MMM d"; return f }()

    var body: some View {
        let cal = Calendar.current
        let months = (1...12).compactMap { cal.date(from: DateComponents(year: year, month: $0, day: 1)) }
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 150, maximum: 260), spacing: 16, alignment: .top)], alignment: .leading, spacing: 16) {
            ForEach(months, id: \.self) { month in
                monthGrid(month)
            }
        }
    }

    private func monthGrid(_ month: Date) -> some View {
        let cal = Calendar.current
        let range = cal.range(of: .day, in: .month, for: month) ?? 1..<2
        let startDow = (cal.component(.weekday, from: month) - 1 + 6) % 7 // Monday = 0
        var cells: [Date?] = Array(repeating: nil, count: startDow)
        for d in range { cells.append(cal.date(byAdding: .day, value: d - 1, to: month)) }
        return VStack(alignment: .leading, spacing: 4) {
            Text(Self.monthFmt.string(from: month)).font(.subheadline.weight(.semibold))
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 2), count: 7), spacing: 2) {
                ForEach(Array(["M", "T", "W", "T", "F", "S", "S"].enumerated()), id: \.offset) { _, s in
                    Text(s).font(.system(size: 9)).foregroundStyle(.secondary).frame(maxWidth: .infinity)
                }
                ForEach(Array(cells.enumerated()), id: \.offset) { _, day in
                    if let day { dayCell(day) } else { Color.clear.frame(height: 28) }
                }
            }
        }
    }

    private func dayCell(_ date: Date) -> some View {
        let cal = Calendar.current
        let iso = DateFormatter.iso.string(from: date)
        let dow = cal.component(.weekday, from: date) - 1
        let isToday = cal.isDateInToday(date)
        let disruption = store.disruption(onISO: iso)
        let hasClasses = (store.classes + [store.lunchClass]).contains { $0.days.contains(dow) }
        let errorC = CanopyPalette.error(scheme), warnC = CanopyPalette.warning(scheme)

        var bg = Color.clear
        var fg = Color.primary
        var underline: Color? = nil
        if isToday { bg = .accentColor; fg = .white }
        else if disruption?.type == "no_school" { bg = errorC.opacity(0.14); underline = errorC }
        else if disruption != nil { bg = warnC.opacity(0.16); underline = warnC }
        else if hasClasses { bg = Color.accentColor.opacity(0.1) }
        else { fg = Color.tertiaryLabel }

        let label = disruption.map { "\(DateFormatter.monthDay.string(from: date)): \($0.displayLabel)" }
            ?? Self.a11yFmt.string(from: date)

        return Button { onDateTap(date) } label: {
            Text("\(cal.component(.day, from: date))")
                .font(.system(size: 10.5, weight: isToday ? .semibold : .regular))
                .foregroundStyle(fg)
                .frame(width: 28, height: 28)
                .background(bg, in: Circle())
                .overlay(alignment: .bottom) {
                    if let underline {
                        Capsule().fill(underline).frame(width: 14, height: 2).offset(y: -3)
                    }
                }
                .frame(maxWidth: .infinity)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label)
        .help(label)
    }
}

// MARK: - Heatmap (web dashboard Heatmap tab)

struct WorkloadHeatmapView: View {
    @Environment(CanopyStore.self) private var store
    @Environment(\.colorScheme) private var scheme
    let onDateTap: (Date) -> Void

    private static let a11yFmt: DateFormatter = { let f = DateFormatter(); f.dateFormat = "EEEE, MMM d"; return f }()
    private static let weekdayFmt: DateFormatter = { let f = DateFormatter(); f.dateFormat = "EEE"; return f }()

    private func fill(_ intensity: Int, weekend: Bool) -> Color {
        switch intensity {
        case 1: return CanopyPalette.info(scheme).opacity(0.30)
        case 2: return CanopyPalette.warning(scheme).opacity(0.40)
        case 3: return CanopyPalette.error(scheme).opacity(0.42)
        default: return weekend ? Color.secondary.opacity(0.10) : Color.secondary.opacity(0.06)
        }
    }

    private func countColor(_ intensity: Int) -> Color {
        switch intensity {
        case 1: return CanopyPalette.info(scheme)
        case 2: return Color(hex: scheme == .dark ? "#f9ab00" : "#b06000")
        case 3: return CanopyPalette.error(scheme)
        default: return .secondary
        }
    }

    var body: some View {
        let days = buildHeatmap(homework: store.homework, tasks: store.tasks, disruptions: store.disruptions, days: 14)
        let hasLoad = days.contains { $0.total > 0 }
        let todayIso = DateFormatter.iso.string(from: .now)

        VStack(alignment: .leading, spacing: 14) {
            Text("14-day workload — assignments + tasks due each day.")
                .font(.subheadline).foregroundStyle(.secondary)

            CalendarFlowLayout(spacing: 6, rowSpacing: 6) {
                ForEach(days) { day in
                    heatmapCell(day, isToday: day.date == todayIso)
                }
            }

            if !hasLoad {
                Text("No upcoming homework or tasks.").font(.caption).foregroundStyle(.secondary)
            }

            CalendarFlowLayout(spacing: 12, rowSpacing: 6) {
                Text("Workload:").font(.caption).foregroundStyle(.secondary)
                ForEach(0..<4, id: \.self) { i in
                    HStack(spacing: 4) {
                        RoundedRectangle(cornerRadius: 2)
                            .fill(fill(i, weekend: false))
                            .frame(width: 12, height: 12)
                            .overlay(RoundedRectangle(cornerRadius: 2).strokeBorder(Color.secondary.opacity(0.3), lineWidth: 1))
                        Text(["None", "Light", "Moderate", "Heavy"][i]).font(.caption).foregroundStyle(.secondary)
                    }
                }
                HStack(spacing: 4) {
                    RoundedRectangle(cornerRadius: 2)
                        .strokeBorder(Color.secondary.opacity(0.4), style: StrokeStyle(lineWidth: 1, dash: [2, 2]))
                        .frame(width: 12, height: 12)
                    Text("Weekend").font(.caption).foregroundStyle(.secondary)
                }
            }
        }
    }

    private func heatmapCell(_ day: HeatmapDay, isToday: Bool) -> some View {
        let date = day.date.asDate ?? .now
        let dow = Calendar.current.component(.weekday, from: date) - 1
        let isWeekend = dow == 0 || dow == 6
        let dashed = isWeekend || day.disruption != nil
        var a11y = Self.a11yFmt.string(from: date)
        if day.total > 0 { a11y += ", \(day.total) due" }
        if let d = day.disruption { a11y += ", \(d.label)" }

        return Button { onDateTap(date) } label: {
            VStack(spacing: 1) {
                Text(Self.weekdayFmt.string(from: date))
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundStyle(.secondary)
                Text("\(Calendar.current.component(.day, from: date))")
                    .font(.subheadline.weight(.semibold))
                if day.total > 0 {
                    Text("\(day.total)")
                        .font(.system(size: 9, weight: .bold))
                        .foregroundStyle(countColor(day.intensity))
                }
            }
            .frame(width: 52, height: 52)
            .background(fill(day.intensity, weekend: isWeekend), in: RoundedRectangle(cornerRadius: 6, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .strokeBorder(isToday ? Color.accentColor : Color.secondary.opacity(0.3),
                                  style: StrokeStyle(lineWidth: 1, dash: dashed ? [3, 2] : []))
            )
            .overlay(alignment: .topTrailing) {
                if let d = day.disruption {
                    Circle()
                        .fill(Color(hex: ScheduleEngine.disruptionColorHex(for: d.type)))
                        .frame(width: 7, height: 7)
                        .overlay(Circle().strokeBorder(Color.systemBackground, lineWidth: 1))
                        .padding(3)
                }
            }
        }
        .buttonStyle(.plain)
        .accessibilityLabel(a11y)
        .help(day.disruption?.label ?? a11y)
    }
}

// MARK: - Date-specific class detail (web ClassDetailDialog.tsx)

struct ClassDayDetailSheet: View {
    @Environment(CanopyStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var scheme
    let entry: CanopyStore.DayEntry
    let date: Date
    @State private var showEditor = false

    private static let overlineFmt: DateFormatter = { let f = DateFormatter(); f.dateFormat = "EEEE, MMM d"; return f }()
    private static let dayLabels = ["Sun", "Mon", "Tue", "Wed", "Thu", "Fri", "Sat"]

    var body: some View {
        let cls = entry.cls
        let cal = Calendar.current
        let iso = DateFormatter.iso.string(from: date)
        let disruption = store.disruption(onISO: iso)
        let isToday = cal.isDateInToday(date)
        let isPast = !isToday && date < cal.startOfDay(for: .now)
        let weekday = cal.component(.weekday, from: date) - 1
        let normalStart = cls.dayTimes?[String(weekday)]?.startTime.nonEmpty ?? cls.startTime
        let normalEnd = cls.dayTimes?[String(weekday)]?.endTime.nonEmpty ?? cls.endTime
        let shifted = entry.isShifted(weekday: weekday)
        let dur = ScheduleEngine.timeToMinutes(entry.endTime) - ScheduleEngine.timeToMinutes(entry.startTime)
        let warn = CanopyPalette.warning(scheme)

        VStack(spacing: 0) {
            Color(hex: cls.color).frame(height: 6)

            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    HStack(alignment: .top, spacing: 8) {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(Self.overlineFmt.string(from: date).uppercased() + (isToday ? " · TODAY" : "") + (isPast ? " · PAST" : ""))
                                .font(.caption2.weight(.semibold))
                                .tracking(0.5)
                                .foregroundStyle(.secondary)
                            HStack(spacing: 8) {
                                Text(cls.name)
                                    .font(.title2.weight(.medium))
                                    .fontDesign(.rounded)
                                    .strikethrough(entry.cancelled)
                                    .foregroundStyle(entry.cancelled ? Color.secondary : Color.primary)
                                if cls.isAp == true {
                                    Text("AP")
                                        .font(.system(size: 10, weight: .bold))
                                        .padding(.horizontal, 6).padding(.vertical, 2)
                                        .background(Color.purple.opacity(0.18), in: Capsule())
                                        .foregroundStyle(.purple)
                                }
                            }
                        }
                        Spacer(minLength: 0)
                        Button { dismiss() } label: {
                            Image(systemName: "xmark.circle.fill")
                                .font(.title3)
                                .foregroundStyle(.secondary)
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("Close")
                    }

                    if entry.cancelled {
                        HStack(spacing: 8) {
                            Image(systemName: "nosign")
                            Text("Class cancelled for this day").font(.subheadline.weight(.medium))
                        }
                        .foregroundStyle(.red)
                        .padding(.horizontal, 12).padding(.vertical, 8)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(Color.red.opacity(0.08), in: RoundedRectangle(cornerRadius: 8))
                    } else if let disruption {
                        HStack(spacing: 8) {
                            Image(systemName: "exclamationmark.triangle.fill")
                            Text(disruption.label.nonEmpty ?? "Schedule modified for this day").font(.subheadline.weight(.medium))
                        }
                        .foregroundStyle(warn)
                        .padding(.horizontal, 12).padding(.vertical, 8)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(warn.opacity(0.10), in: RoundedRectangle(cornerRadius: 8))
                    }

                    HStack(alignment: .center, spacing: 12) {
                        Image(systemName: "clock").foregroundStyle(.secondary)
                        VStack(alignment: .leading, spacing: 2) {
                            Text("\(ScheduleEngine.formatTime12(entry.startTime)) – \(ScheduleEngine.formatTime12(entry.endTime))")
                                .font(.headline.weight(.medium))
                                .strikethrough(entry.cancelled)
                                .foregroundStyle(entry.cancelled ? Color.secondary : Color.primary)
                            Text((dur > 0 ? "\(dur) minute\(dur == 1 ? "" : "s")" : "—") + (shifted ? " · adjusted" : ""))
                                .font(.caption).foregroundStyle(.secondary)
                        }
                    }
                    if shifted {
                        Text("Normally: \(ScheduleEngine.formatTime12(normalStart)) – \(ScheduleEngine.formatTime12(normalEnd))")
                            .font(.caption).foregroundStyle(.tertiary)
                            .padding(.leading, 36)
                    }

                    Divider()

                    VStack(alignment: .leading, spacing: 10) {
                        if let teacher = cls.displayTeacher {
                            Label(teacher, systemImage: "person").font(.subheadline)
                        }
                        if !cls.room.isEmpty {
                            Label("Room \(cls.room)", systemImage: "mappin.and.ellipse").font(.subheadline)
                        }
                        HStack(alignment: .firstTextBaseline, spacing: 8) {
                            Image(systemName: "calendar").foregroundStyle(.secondary)
                            Text("Period \(cls.period)").font(.subheadline)
                            Text("·").foregroundStyle(.tertiary)
                            CalendarFlowLayout(spacing: 4, rowSpacing: 4) {
                                ForEach(cls.days.sorted(), id: \.self) { d in
                                    let label = Self.dayLabels.indices.contains(d) ? Self.dayLabels[d] : "?"
                                    if d == weekday {
                                        Text(label)
                                            .font(.caption2.weight(.semibold))
                                            .padding(.horizontal, 7).padding(.vertical, 2)
                                            .background(Color.accentColor, in: Capsule())
                                            .foregroundStyle(.white)
                                    } else {
                                        OutlinedChip(text: label)
                                    }
                                }
                            }
                        }
                        if !cls.semester.isEmpty {
                            Text(cls.semester).font(.caption).foregroundStyle(.secondary).padding(.leading, 28)
                        }
                        if cls.isPowerSchool {
                            HStack(spacing: 8) {
                                OutlinedChip(text: "PowerSchool", color: .accentColor)
                                if let gp = cls.gradePercent {
                                    Text(String(format: "%.1f%%", gp) + ((cls.grade?.nonEmpty).map { " · \($0)" } ?? ""))
                                        .font(.subheadline.weight(.medium))
                                }
                            }
                            .padding(.leading, 28)
                        }
                    }
                }
                .padding(20)
            }

            Divider()
            HStack(spacing: 10) {
                Button("Close") { dismiss() }
                Spacer()
                if !entry.isSynthetic {
                    Button {
                        showEditor = true
                    } label: { Label("Edit class", systemImage: "pencil") }
                    .buttonStyle(.bordered)
                }
                if cls.isPowerSchool {
                    Button {
                        dismiss()
                        AppNavigation.shared.goToGrades(classId: cls.id)
                    } label: { Label("View grades", systemImage: "checklist") }
                    .buttonStyle(.borderedProminent)
                }
            }
            .padding(.horizontal, 20).padding(.vertical, 14)
        }
        .background(CanopyBackground())
        .sheet(isPresented: $showEditor) {
            ClassEditorSheet(cls: cls).presentationDetents([.large])
        }
        .presentationDetents([.medium, .large])
    }
}
