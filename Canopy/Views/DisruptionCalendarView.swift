import SwiftUI

/// Month-grid view of schedule disruptions — port of web
/// src/components/DisruptionCalendar.tsx. Tap an empty day to add, tap a chip
/// to edit, long-press-and-drag a chip onto another day to move it (the whole
/// span moves by the same number of days). The drag is tracked in the grid's
/// own coordinate space and hit-tested against cell frames collected through a
/// PreferenceKey, so the drop target is the cell under the finger — not the
/// cell the chip started in.
struct DisruptionCalendarView: View {
    @Environment(CanopyStore.self) private var store
    @Environment(\.colorScheme) private var scheme
    @State private var month: Date = Calendar.current.date(from: Calendar.current.dateComponents([.year, .month], from: .now)) ?? .now
    @State private var addDate: Date?
    @State private var editingDisruption: ScheduleDisruption?
    @State private var drag: DragState?
    @State private var cellFrames: [String: CGRect] = [:]

    private struct DragState: Equatable {
        let id: String
        /// ISO date of the cell the chip was picked up from.
        let anchor: String
        var location: CGPoint? = nil
        var over: String? = nil
    }

    private struct CellFramesKey: PreferenceKey {
        static var defaultValue: [String: CGRect] { [:] }
        static func reduce(value: inout [String: CGRect], nextValue: () -> [String: CGRect]) {
            value.merge(nextValue()) { _, new in new }
        }
    }

    private let cal = Calendar.current
    private static let dayHeaders = ["Sun", "Mon", "Tue", "Wed", "Thu", "Fri", "Sat"]
    private static let monthFmt: DateFormatter = { let f = DateFormatter(); f.dateFormat = "MMMM yyyy"; return f }()
    private static let longDayFmt: DateFormatter = { let f = DateFormatter(); f.dateFormat = "MMMM d"; return f }()
    private let gridSpace = "disruptionGrid"

    var body: some View {
        VStack(spacing: 10) {
            monthHeader
            weekdayRow
            monthGrid
            footer
        }
        .sheet(item: $editingDisruption) { d in
            DisruptionEditorSheet(disruption: d).presentationDetents([.large])
        }
        .sheet(isPresented: Binding(
            get: { addDate != nil },
            set: { if !$0 { addDate = nil } }
        )) {
            DisruptionEditorSheet(disruption: nil, prefillDate: addDate ?? .now)
                .presentationDetents([.large])
        }
        .sensoryFeedback(.impact(weight: .light), trigger: drag?.id)
    }

    // MARK: - Month header (◀ "MMMM yyyy" [today] ▶)
    private var isCurrentMonth: Bool { cal.isDate(month, equalTo: .now, toGranularity: .month) }

    private var monthHeader: some View {
        HStack(spacing: 6) {
            Button { changeMonth(-1) } label: {
                Image(systemName: "chevron.left").font(.body.weight(.semibold))
                    .frame(width: 32, height: 32)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Previous month")

            Text(Self.monthFmt.string(from: month))
                .font(.headline)
                .frame(maxWidth: .infinity)

            Button {
                withAnimation(.spring(response: 0.3)) {
                    month = cal.date(from: cal.dateComponents([.year, .month], from: .now)) ?? .now
                }
            } label: {
                Image(systemName: "calendar.circle")
                    .font(.body.weight(.semibold))
                    .frame(width: 32, height: 32)
                    .background(isCurrentMonth ? Color.clear : Color.accentColor, in: Circle())
                    .overlay(Circle().strokeBorder(isCurrentMonth ? Color.secondary.opacity(0.35) : Color.accentColor, lineWidth: 1))
                    .foregroundStyle(isCurrentMonth ? Color.secondary : Color.white)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Jump to today's month")
            .help("Jump to today's month")

            Button { changeMonth(1) } label: {
                Image(systemName: "chevron.right").font(.body.weight(.semibold))
                    .frame(width: 32, height: 32)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Next month")
        }
    }

    private var weekdayRow: some View {
        HStack(spacing: 4) {
            ForEach(Self.dayHeaders, id: \.self) { s in
                Text(s).font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity)
            }
        }
    }

    // MARK: - Grid (full weeks, Sunday first; out-of-month cells faded)
    private var monthGrid: some View {
        let days = gridDays()
        return LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 4), count: 7), spacing: 4) {
            ForEach(days, id: \.self) { day in
                dayCell(day)
            }
        }
        .coordinateSpace(name: gridSpace)
        .onPreferenceChange(CellFramesKey.self) { cellFrames = $0 }
        .overlay {
            if let drag, let loc = drag.location,
               let d = store.disruptions.first(where: { $0.id == drag.id }) {
                let w = (cellFrames[drag.anchor]?.width ?? 60) - 8
                chipLabel(d)
                    .frame(width: max(30, w))
                    .shadow(color: .black.opacity(0.25), radius: 6, y: 3)
                    .scaleEffect(1.08)
                    .position(loc)
                    .allowsHitTesting(false)
            }
        }
    }

    private func dayCell(_ date: Date) -> some View {
        let iso = DateFormatter.iso.string(from: date)
        let inMonth = cal.isDate(date, equalTo: month, toGranularity: .month)
        let isToday = cal.isDateInToday(date)
        let dow = cal.component(.weekday, from: date) - 1
        let isWeekend = dow == 0 || dow == 6
        let isDragTarget = drag?.over == iso
        let dayDisruptions = store.disruptions.filter { $0.covers(iso) }

        let bg: Color = isDragTarget ? Color.accentColor.opacity(0.1)
            : isToday ? Color.accentColor.opacity(0.05)
            : (isWeekend && inMonth) ? (scheme == .dark ? Color.white.opacity(0.05) : Color.black.opacity(0.035))
            : Color.clear
        let border: Color = isDragTarget ? Color.accentColor
            : isToday ? Color.accentColor.opacity(0.7)
            : Color.secondary.opacity(0.25)

        return VStack(alignment: .leading, spacing: 3) {
            Text("\(cal.component(.day, from: date))")
                .font(.system(size: 12, weight: isToday ? .bold : .regular))
                .foregroundStyle(isToday ? Color.accentColor : Color.primary)
            ForEach(dayDisruptions) { d in
                chip(d, cellISO: iso)
            }
            if isDragTarget && dayDisruptions.isEmpty {
                Text("Drop here")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(Color.accentColor)
                    .frame(maxWidth: .infinity)
                    .padding(.top, 6)
            }
            Spacer(minLength: 0)
        }
        .padding(6)
        .frame(maxWidth: .infinity, minHeight: 76, alignment: .topLeading)
        .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(bg))
        .overlay(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .strokeBorder(border, lineWidth: (isDragTarget || isToday) ? 2 : 1)
        )
        .opacity(inMonth ? 1 : 0.3)
        .contentShape(Rectangle())
        .onTapGesture {
            guard inMonth, dayDisruptions.isEmpty, drag == nil else { return }
            addDate = date
        }
        .accessibilityElement(children: dayDisruptions.isEmpty ? .ignore : .contain)
        .accessibilityLabel(dayDisruptions.isEmpty ? "Add a disruption on \(Self.longDayFmt.string(from: date))" : Self.longDayFmt.string(from: date))
        .accessibilityAddTraits(dayDisruptions.isEmpty && inMonth ? .isButton : [])
        .background(
            GeometryReader { g in
                Color.clear.preference(key: CellFramesKey.self, value: [iso: g.frame(in: .named(gridSpace))])
            }
        )
    }

    private func chipLabel(_ d: ScheduleDisruption) -> some View {
        let hex = ScheduleEngine.disruptionColorHex(for: d.type)
        return Text(d.displayLabel)
            .font(.system(size: 10, weight: .semibold))
            .lineLimit(1)
            .padding(.horizontal, 6)
            .frame(maxWidth: .infinity, minHeight: 20, maxHeight: 20)
            .background(Color(hex: hex), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
            .foregroundStyle(Color.contrastText(on: hex))
    }

    private func chip(_ d: ScheduleDisruption, cellISO: String) -> some View {
        let longPressThenDrag = LongPressGesture(minimumDuration: 0.3)
            .sequenced(before: DragGesture(minimumDistance: 0, coordinateSpace: .named(gridSpace)))
            .onChanged { value in
                switch value {
                case .second(true, let dragValue):
                    if drag == nil || drag?.id != d.id {
                        drag = DragState(id: d.id, anchor: cellISO)
                    }
                    if let dragValue {
                        drag?.location = dragValue.location
                        drag?.over = hitTest(dragValue.location)
                    }
                default:
                    break
                }
            }
            .onEnded { value in
                if case .second(true, let dragValue?) = value, let target = hitTest(dragValue.location) {
                    Task { await moveDisruption(id: d.id, fromCell: cellISO, toCell: target) }
                }
                drag = nil
            }

        return chipLabel(d)
            .opacity(drag?.id == d.id ? 0.4 : 1)
            .contentShape(Rectangle())
            .onTapGesture { editingDisruption = d }
            .gesture(longPressThenDrag)
            .accessibilityLabel("\(d.displayLabel), tap to edit")
            .accessibilityAddTraits(.isButton)
    }

    private func hitTest(_ p: CGPoint) -> String? {
        cellFrames.first { $0.value.contains(p) }?.key
    }

    // MARK: - Footer: legend + hint
    private var footer: some View {
        VStack(alignment: .leading, spacing: 6) {
            CalendarFlowLayout(spacing: 6, rowSpacing: 6) {
                ForEach(ScheduleEngine.disruptionTypes, id: \.value) { t in
                    Text(t.label)
                        .font(.system(size: 11, weight: .medium))
                        .padding(.horizontal, 8)
                        .frame(height: 22)
                        .background(Color(hex: t.color), in: Capsule())
                        .foregroundStyle(Color.contrastText(on: t.color))
                }
            }
            #if os(macOS)
            Text("Click a day to add · Drag to move · Click event to edit")
                .font(.caption).italic().foregroundStyle(.tertiary)
                .frame(maxWidth: .infinity, alignment: .trailing)
            #else
            Text("Tap a day to add · Tap an event to edit")
                .font(.caption).italic().foregroundStyle(.tertiary)
                .frame(maxWidth: .infinity, alignment: .trailing)
            #endif
        }
        .padding(.top, 4)
    }

    // MARK: - Actions
    private func changeMonth(_ delta: Int) {
        withAnimation(.spring(response: 0.3)) {
            month = cal.date(byAdding: .month, value: delta, to: month) ?? month
        }
    }

    /// Shift `date` AND `endDate` by the offset between the cell the chip was
    /// picked up from and the cell it was dropped on (web handleMove + onDrop).
    private func moveDisruption(id: String, fromCell: String, toCell: String) async {
        guard var d = store.disruptions.first(where: { $0.id == id }),
              let from = fromCell.asDate, let to = toCell.asDate,
              let start = d.date.asDate else { return }
        let offset = cal.dateComponents([.day], from: from, to: to).day ?? 0
        guard offset != 0 else { return }
        guard let newStart = cal.date(byAdding: .day, value: offset, to: start) else { return }
        if let end = d.endDate, !end.isEmpty, let oldEnd = end.asDate,
           let newEnd = cal.date(byAdding: .day, value: offset, to: oldEnd) {
            d.endDate = DateFormatter.iso.string(from: newEnd)
        }
        d.date = DateFormatter.iso.string(from: newStart)
        try? await store.saveDisruption(d, isNew: false)
    }

    /// Every day of the visible grid: full weeks from the Sunday on/before the
    /// 1st through the Saturday on/after the last day.
    private func gridDays() -> [Date] {
        guard let first = cal.date(from: cal.dateComponents([.year, .month], from: month)),
              let range = cal.range(of: .day, in: .month, for: first),
              let last = cal.date(byAdding: .day, value: range.count - 1, to: first) else { return [] }
        let leading = cal.component(.weekday, from: first) - 1          // 0 = Sun
        let trailing = 7 - cal.component(.weekday, from: last)           // days after `last` to Saturday
        guard let gridStart = cal.date(byAdding: .day, value: -leading, to: first) else { return [] }
        let count = leading + range.count + trailing
        return (0..<count).compactMap { cal.date(byAdding: .day, value: $0, to: gridStart) }
    }
}
