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

private let weekdayNames = [0: "Sun", 1: "Mon", 2: "Tue", 3: "Wed", 4: "Thu", 5: "Fri", 6: "Sat"]

// MARK: - View Mode

private enum ScheduleViewMode: String, CaseIterable {
    case day = "Day"
    case week = "Week"
}

// MARK: - Main View

struct ScheduleView: View {
    @Environment(CanopyStore.self) private var store
    @State private var selectedDate = Date.now
    @State private var viewMode: ScheduleViewMode = .day

    private var totalHeight: CGFloat { CGFloat(totalHours) * hourHeight }

    var body: some View {
        NavigationStack {
            ZStack { CanopyBackground()
                VStack(spacing: 0) {
                    controlBar
                        .padding(.horizontal, 16)
                        .padding(.top, 8)
                        .padding(.bottom, 4)

                    if viewMode == .day {
                        daySchedule
                    } else {
                        weekSchedule
                    }
                }
            }
            .navigationTitle("Schedule")
            .navigationBarTitleLarge()
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Button {
                        withAnimation(.spring(response: 0.3)) { selectedDate = .now }
                    } label: {
                        Image(systemName: "calendar.circle")
                            .font(.title3)
                    }
                    .disabled(Calendar.current.isDateInToday(selectedDate))
                }
            }
            .refreshable { await store.loadAll() }
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

            // Day navigation
            HStack {
                Button {
                    withAnimation(.spring(response: 0.3)) {
                        let step: Calendar.Component = viewMode == .week ? .weekOfYear : .day
                        selectedDate = Calendar.current.date(byAdding: step, value: -1, to: selectedDate)!
                    }
                } label: {
                    Image(systemName: "chevron.left")
                        .font(.body.weight(.semibold))
                        .frame(width: 44, height: 44)
                        .background(.regularMaterial, in: Circle())
                }
                .buttonStyle(.plain)

                Spacer()

                VStack(spacing: 2) {
                    if viewMode == .day {
                        Text(selectedDate, format: .dateTime.weekday(.wide))
                            .font(.headline)
                        Text(selectedDate, format: .dateTime.month(.abbreviated).day())
                            .font(.subheadline).foregroundStyle(.secondary)
                    } else {
                        let weekStart = startOfWeek(for: selectedDate)
                        let weekEnd = Calendar.current.date(byAdding: .day, value: 4, to: weekStart)!
                        Text("Week of \(weekStart.formatted(.dateTime.month(.abbreviated).day()))")
                            .font(.headline)
                        Text("\(weekEnd.formatted(.dateTime.month(.abbreviated).day())), \(weekStart.formatted(.dateTime.year()))")
                            .font(.subheadline).foregroundStyle(.secondary)
                    }
                }

                Spacer()

                Button {
                    withAnimation(.spring(response: 0.3)) {
                        let step: Calendar.Component = viewMode == .week ? .weekOfYear : .day
                        selectedDate = Calendar.current.date(byAdding: step, value: 1, to: selectedDate)!
                    }
                } label: {
                    Image(systemName: "chevron.right")
                        .font(.body.weight(.semibold))
                        .frame(width: 44, height: 44)
                        .background(.regularMaterial, in: Circle())
                }
                .buttonStyle(.plain)
            }
            .foregroundStyle(.primary)
        }
    }

    // MARK: - Day Schedule
    private var daySchedule: some View {
        ScrollView {
            GeometryReader { geo in
                timelineBody(for: selectedDate, containerWidth: geo.size.width)
            }
            .frame(height: totalHeight + 32)
            .padding(.horizontal, 16)
            .padding(.bottom, 32)
        }
    }

    // MARK: - Week Schedule
    private var weekSchedule: some View {
        let weekStart = startOfWeek(for: selectedDate)
        let days = (0..<5).compactMap { Calendar.current.date(byAdding: .day, value: $0, to: weekStart) }

        return ScrollView {
            HStack(alignment: .top, spacing: 0) {
                // Hour labels — fixed width
                VStack(alignment: .trailing, spacing: 0) {
                    Spacer().frame(height: 32)
                    ZStack(alignment: .topLeading) {
                        ForEach(dayStart...dayEnd, id: \.self) { hour in
                            Text(hourLabel(hour))
                                .font(.caption2.monospacedDigit())
                                .foregroundStyle(.secondary)
                                .offset(y: CGFloat(hour - dayStart) * hourHeight - 7)
                        }
                    }
                    .frame(height: totalHeight + 32)
                }
                .frame(width: 36)

                // Day columns — each takes an equal share of remaining width
                HStack(spacing: 1) {
                    ForEach(days, id: \.self) { date in
                        VStack(spacing: 0) {
                            let isToday = Calendar.current.isDateInToday(date)
                            VStack(spacing: 2) {
                                Text(date.formatted(.dateTime.weekday(.abbreviated)))
                                    .font(.caption2.weight(.medium))
                                    .foregroundStyle(isToday ? Color.accentColor : .secondary)
                                Text(date.formatted(.dateTime.day()))
                                    .font(.callout.weight(isToday ? .bold : .regular))
                                    .foregroundStyle(isToday ? Color.accentColor : .primary)
                            }
                            .frame(height: 32)

                            GeometryReader { col in
                                weekColumnBody(for: date, width: col.size.width)
                            }
                            .frame(height: totalHeight + 32)
                        }
                        .frame(maxWidth: .infinity)
                    }
                }
            }
            .padding(.horizontal, 8)
            .padding(.bottom, 32)
        }
    }

    private func weekColumnBody(for date: Date, width: CGFloat) -> some View {
        ZStack(alignment: .topLeading) {
            // Hour lines
            ForEach(dayStart...dayEnd, id: \.self) { hour in
                Divider()
                    .opacity(0.3)
                    .offset(y: CGFloat(hour - dayStart) * hourHeight)
            }

            ForEach(store.classes(for: date)) { cls in
                compactClassBlock(cls, width: width)
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
        ZStack(alignment: .topLeading) {
            hourGrid

            let blockAreaOffset: CGFloat = 52
            let blockWidth = containerWidth - blockAreaOffset

            ForEach(store.classes(for: date)) { cls in
                classBlock(cls, offset: blockAreaOffset, width: blockWidth)
            }

            if let lunch = store.lunchTime(for: date) {
                lunchBlock(lunch, offset: blockAreaOffset, width: blockWidth)
            }

            nowIndicator(for: date, offset: blockAreaOffset)
        }
        .frame(width: containerWidth, height: totalHeight + 32)
    }

    // MARK: - Hour grid
    private var hourGrid: some View {
        ZStack(alignment: .topLeading) {
            ForEach(dayStart...dayEnd, id: \.self) { hour in
                let y = CGFloat(hour - dayStart) * hourHeight
                HStack(spacing: 0) {
                    Text(hourLabel(hour))
                        .font(.caption2.monospacedDigit())
                        .foregroundStyle(.secondary)
                        .frame(width: 44, alignment: .trailing)
                        .offset(y: -7)
                    // Explicit horizontal line — Divider() in HStack renders vertically
                    Rectangle()
                        .fill(Color.secondary.opacity(0.3))
                        .frame(maxWidth: .infinity, maxHeight: 0.5)
                }
                .offset(y: y)
            }
        }
        .frame(height: totalHeight + 32)
    }

    private func hourLabel(_ h: Int) -> String {
        h == 0 ? "12a" : h < 12 ? "\(h)a" : h == 12 ? "12p" : "\(h-12)p"
    }

    // MARK: - Class block
    private func classBlock(_ cls: SchoolClass, offset: CGFloat, width: CGFloat) -> some View {
        let top = minutesFrom7am(cls.startTime) * (hourHeight / 60)
        let height = max(24, minutesFrom7am(cls.endTime) * (hourHeight / 60) - top)

        return VStack(alignment: .leading, spacing: 2) {
            Text(cls.name).font(.caption.bold()).lineLimit(1)
            if height > 36 {
                Text("\(cls.startTime) – \(cls.endTime)")
                    .font(.caption2).foregroundStyle(.secondary)
            }
            if height > 52, !cls.room.isEmpty {
                Text("Rm \(cls.room)").font(.caption2).foregroundStyle(.secondary)
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 5)
        .frame(width: width, height: height, alignment: .topLeading)
        .background(Color(hex: cls.color).opacity(0.22), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
        .overlay(alignment: .leading) {
            RoundedRectangle(cornerRadius: 3).fill(Color(hex: cls.color)).frame(width: 4)
        }
        .overlay(RoundedRectangle(cornerRadius: 8, style: .continuous)
            .strokeBorder(Color(hex: cls.color).opacity(0.3), lineWidth: 0.5))
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
        .offset(x: offset, y: top)
    }

    // MARK: - Now indicator
    @ViewBuilder
    private func nowIndicator(for date: Date, offset: CGFloat) -> some View {
        let now = Date.now
        let cal = Calendar.current
        let h = cal.component(.hour, from: now)
        let m = cal.component(.minute, from: now)
        if Calendar.current.isDate(now, inSameDayAs: date) && h >= dayStart && h < dayEnd {
            let y = CGFloat((h - dayStart) * 60 + m) * (hourHeight / 60)
            HStack(spacing: 0) {
                Circle().fill(.red).frame(width: 8, height: 8)
                Rectangle().fill(.red).frame(height: 1.5)
            }
            .shadow(color: .red.opacity(0.5), radius: 4)
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
