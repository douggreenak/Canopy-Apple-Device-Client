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

struct ScheduleView: View {
    @Environment(CanopyStore.self) private var store
    @State private var selectedDate = Date.now

    private var totalHeight: CGFloat { CGFloat(totalHours) * hourHeight }

    var body: some View {
        NavigationStack {
            ZStack { CanopyBackground()
                VStack(spacing: 0) {
                    dayPicker.padding(.horizontal, 16).padding(.top, 8).padding(.bottom, 4)
                    ScrollView {
                        timelineBody
                            .padding(.horizontal, 16)
                            .padding(.bottom, 32)
                    }
                }
            }
            .navigationTitle("Schedule")
            .navigationBarTitleDisplayMode(.large)
        }
    }

    // MARK: - Day picker
    private var dayPicker: some View {
        HStack {
            Button { selectedDate = Calendar.current.date(byAdding: .day, value: -1, to: selectedDate)! } label: {
                Image(systemName: "chevron.left").font(.title3.bold())
            }
            Spacer()
            VStack(spacing: 2) {
                Text(selectedDate, format: .dateTime.weekday(.wide))
                    .font(.headline)
                Text(selectedDate, format: .dateTime.month(.abbreviated).day())
                    .font(.subheadline).foregroundStyle(.secondary)
            }
            Spacer()
            Button { selectedDate = Calendar.current.date(byAdding: .day, value: 1, to: selectedDate)! } label: {
                Image(systemName: "chevron.right").font(.title3.bold())
            }
        }
        .padding(12)
        .glassCard(cornerRadius: 14)
        .foregroundStyle(.primary)
    }

    // MARK: - Timeline
    private var timelineBody: some View {
        ZStack(alignment: .topLeading) {
            // Hour grid lines + labels
            hourGrid

            // Class + lunch blocks (offset by label column width)
            let blockAreaOffset: CGFloat = 52
            let blockWidth = UIScreen.main.bounds.width - 32 - blockAreaOffset - 32

            ForEach(store.classes(for: selectedDate)) { cls in
                classBlock(cls, offset: blockAreaOffset, width: blockWidth)
            }

            if let lunch = store.lunchTime(for: selectedDate) {
                lunchBlock(lunch, offset: blockAreaOffset, width: blockWidth)
            }

            // Now indicator
            nowIndicator(offset: blockAreaOffset)
        }
        .frame(height: totalHeight + 32)
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
                    Divider()
                        .frame(maxWidth: .infinity)
                        .opacity(0.3)
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
        .background(Color(hex: cls.color).opacity(0.25), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
        .overlay(alignment: .leading) {
            RoundedRectangle(cornerRadius: 3).fill(Color(hex: cls.color)).frame(width: 4)
        }
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
        .background(Color.canopyGreen.opacity(0.12), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
        .overlay(alignment: .leading) {
            RoundedRectangle(cornerRadius: 3).fill(Color.canopyGreen.opacity(0.6)).frame(width: 3)
        }
        .offset(x: offset, y: top)
    }

    // MARK: - Now indicator
    private func nowIndicator(offset: CGFloat) -> some View {
        let now = Date.now
        guard Calendar.current.isDate(now, inSameDayAs: selectedDate) else { return AnyView(EmptyView()) }
        let cal = Calendar.current
        let h = cal.component(.hour, from: now)
        let m = cal.component(.minute, from: now)
        guard h >= dayStart && h < dayEnd else { return AnyView(EmptyView()) }
        let y = CGFloat((h - dayStart) * 60 + m) * (hourHeight / 60)
        return AnyView(
            HStack(spacing: 0) {
                Circle().fill(.red).frame(width: 8, height: 8)
                Rectangle().fill(.red).frame(height: 1.5)
            }
            .offset(x: offset - 4, y: y)
        )
    }
}
