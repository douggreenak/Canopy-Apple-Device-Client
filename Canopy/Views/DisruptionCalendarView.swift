import SwiftUI

/// Month-grid view of schedule disruptions — the visual "which days are
/// affected" companion to ManageDisruptionsView's flat Upcoming/Past list.
/// Port of web src/components/DisruptionCalendar.tsx, touch-first from the
/// start: tap an empty day to add, tap a chip to edit. No separate
/// mouse-hover/HTML5-drag code path to conditionally hide, unlike web (which
/// forks click+drag for mouse vs. tap-only for touch) — long-press-and-drag
/// below is the one interaction, usable with either input method.
struct DisruptionCalendarView: View {
    @Environment(CanopyStore.self) private var store
    @State private var monthAnchor = Date.now
    @State private var addDate: Date?
    @State private var editingDisruption: ScheduleDisruption?
    @State private var draggingId: String?
    @State private var dragOverDate: Date?

    private let cal = Calendar.current
    private let weekdaySymbols = ["S", "M", "T", "W", "T", "F", "S"]

    var body: some View {
        VStack(spacing: 12) {
            monthHeader
            weekdayRow
            monthGrid
            legend
        }
        .padding(.horizontal, 12)
        .padding(.top, 8)
        .padding(.bottom, 16)
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
    }

    // MARK: - Month header
    private var monthHeader: some View {
        HStack {
            Button { changeMonth(-1) } label: {
                Image(systemName: "chevron.left").font(.body.weight(.semibold))
                    .frame(width: 36, height: 36).background(.regularMaterial, in: Circle())
            }.buttonStyle(.plain)
            Spacer()
            Text(monthAnchor, format: .dateTime.month(.wide).year())
                .font(.headline)
            Spacer()
            Button { monthAnchor = .now } label: {
                Text("Today").font(.caption.bold())
            }
            .buttonStyle(.plain)
            .padding(.horizontal, 10).padding(.vertical, 6)
            .background(.regularMaterial, in: Capsule())
            .padding(.trailing, 4)
            Button { changeMonth(1) } label: {
                Image(systemName: "chevron.right").font(.body.weight(.semibold))
                    .frame(width: 36, height: 36).background(.regularMaterial, in: Circle())
            }.buttonStyle(.plain)
        }
    }

    private var weekdayRow: some View {
        HStack(spacing: 0) {
            ForEach(Array(weekdaySymbols.enumerated()), id: \.offset) { _, s in
                Text(s).font(.caption.bold()).foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity)
            }
        }
    }

    // MARK: - Grid
    private var monthGrid: some View {
        let days = monthDays()
        return LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 4), count: 7), spacing: 4) {
            ForEach(Array(days.enumerated()), id: \.offset) { _, day in
                if let day {
                    dayCell(day)
                } else {
                    Color.clear.frame(height: 66)
                }
            }
        }
    }

    private func dayCell(_ date: Date) -> some View {
        let isToday = cal.isDateInToday(date)
        let dayDisruptions = store.disruptions.filter { disruptionCovers($0, date) }
        let isDragTarget = dragOverDate.map { cal.isDate($0, inSameDayAs: date) } ?? false

        return VStack(spacing: 3) {
            Text("\(cal.component(.day, from: date))")
                .font(.system(size: 13, weight: isToday ? .bold : .regular))
                .foregroundStyle(isToday ? .white : .primary)
                .frame(width: 22, height: 22)
                .background(isToday ? Color.accentColor : Color.clear, in: Circle())

            VStack(spacing: 1) {
                ForEach(dayDisruptions.prefix(2)) { d in
                    let hex = ScheduleEngine.disruptionColorHex(for: d.type)
                    Button { editingDisruption = d } label: {
                        Text(d.label.isEmpty ? ScheduleEngine.disruptionLabel(for: d.type) : d.label)
                            .font(.system(size: 8, weight: .bold))
                            .lineLimit(1)
                            .padding(.horizontal, 3).padding(.vertical, 1)
                            .frame(maxWidth: .infinity)
                            .background(Color(hex: hex).opacity(0.28), in: RoundedRectangle(cornerRadius: 3))
                            .foregroundStyle(Color(hex: hex))
                    }
                    .buttonStyle(.plain)
                    .opacity(draggingId == d.id ? 0.4 : 1)
                    // Long-press then drag to move a disruption to another day —
                    // one interaction that works the same with touch or a trackpad,
                    // unlike web's separate HTML5 drag-and-drop-for-mouse-only path.
                    .onLongPressGesture(minimumDuration: 0.35) {
                        draggingId = d.id
                    }
                }
                if dayDisruptions.count > 2 {
                    Text("+\(dayDisruptions.count - 2)").font(.system(size: 7)).foregroundStyle(.secondary)
                }
            }
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, minHeight: 66, alignment: .top)
        .padding(.top, 3)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(isDragTarget ? Color.accentColor.opacity(0.18) : Color.secondary.opacity(0.06))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .strokeBorder(isDragTarget ? Color.accentColor : .clear, lineWidth: 1.5)
        )
        .contentShape(Rectangle())
        .onTapGesture {
            guard draggingId == nil else { return }
            addDate = date
        }
        .gesture(
            draggingId == nil ? nil :
            DragGesture(minimumDistance: 0, coordinateSpace: .global)
                .onChanged { _ in dragOverDate = date }
                .onEnded { _ in
                    if let id = draggingId, let target = dragOverDate {
                        Task { await moveDisruption(id: id, to: target) }
                    }
                    draggingId = nil
                    dragOverDate = nil
                }
        )
    }

    private var legend: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 10) {
                ForEach(ScheduleEngine.disruptionTypes, id: \.value) { t in
                    HStack(spacing: 4) {
                        Circle().fill(Color(hex: t.color)).frame(width: 7, height: 7)
                        Text(t.label).font(.caption2).foregroundStyle(.secondary)
                    }
                }
            }
            .padding(.top, 4)
        }
    }

    // MARK: - Actions
    private func changeMonth(_ delta: Int) {
        withAnimation(.spring(response: 0.3)) {
            monthAnchor = cal.date(byAdding: .month, value: delta, to: monthAnchor) ?? monthAnchor
        }
    }

    private func moveDisruption(id: String, to date: Date) async {
        guard var d = store.disruptions.first(where: { $0.id == id }) else { return }
        let newStart = DateFormatter.iso.string(from: date)
        // Preserve the span length when moving a multi-day disruption.
        if let end = d.endDate, !end.isEmpty, let oldStart = d.date.asDate, let oldEnd = end.asDate {
            let spanDays = cal.dateComponents([.day], from: oldStart, to: oldEnd).day ?? 0
            if let newEnd = cal.date(byAdding: .day, value: spanDays, to: date) {
                d.endDate = DateFormatter.iso.string(from: newEnd)
            }
        }
        d.date = newStart
        try? await store.saveDisruption(d, isNew: false)
    }

    private func disruptionCovers(_ d: ScheduleDisruption, _ date: Date) -> Bool {
        let ds = DateFormatter.iso.string(from: date)
        return ds >= d.date && ds <= (d.endDate ?? d.date)
    }

    private func monthDays() -> [Date?] {
        guard let range = cal.range(of: .day, in: .month, for: monthAnchor),
              let first = cal.date(from: cal.dateComponents([.year, .month], from: monthAnchor)) else { return [] }
        let leading = cal.component(.weekday, from: first) - 1 // 0=Sun
        var cells: [Date?] = Array(repeating: nil, count: leading)
        for d in range {
            if let date = cal.date(byAdding: .day, value: d - 1, to: first) { cells.append(date) }
        }
        return cells
    }
}
