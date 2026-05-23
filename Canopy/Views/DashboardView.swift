import SwiftUI

struct DashboardView: View {
    @Environment(CanopyStore.self) private var store
    @Environment(AuthStore.self) private var authStore
    private let today = Date.now

    var body: some View {
        NavigationStack {
            ZStack {
                CanopyBackground()
                ScrollView {
                    LazyVStack(spacing: 16) {
                        dateHeader
                        summaryCards
                        if !store.askTasks.isEmpty { askBanner }
                        if let disruption = todayDisruption { disruptionBanner(disruption) }
                        todaysClassesSection
                        homeworkSection
                        examsSection
                        tasksSection
                    }
                    .padding(.horizontal, 16)
                    .padding(.bottom, 32)
                }
            }
            .navigationTitle("")
            .navigationBarTitleInline()
            .iosHideNavigationBar()
            .refreshable { await store.loadAll() }
        }
    }

    // MARK: - Today's disruption
    private var todayDisruption: ScheduleDisruption? {
        let ds = DateFormatter.iso.string(from: today)
        return store.disruptions.first { $0.date == ds }
    }

    // MARK: - Date Header
    private var dateHeader: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(today, format: .dateTime.weekday(.wide))
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
                .textCase(.uppercase)
                .tracking(0.5)
            Text(today, format: .dateTime.month(.wide).day())
                .font(.largeTitle.bold())
                .fontDesign(.rounded)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.top, 8)
    }

    // MARK: - Summary Cards
    private var summaryCards: some View {
        let classCount = store.todaysClasses(for: today).count
        let hwCount = store.upcomingHomework(limit: 100).count
        let examCount = store.upcomingExams(limit: 100).count
        let (done, total) = completedTodayCounts()

        return HStack(spacing: 10) {
            SummaryCard(value: "\(classCount)", label: "Today", icon: "calendar", color: .accentColor)
            SummaryCard(value: "\(hwCount)", label: "Homework", icon: "book.closed", color: .red)
            SummaryCard(value: "\(examCount)", label: "Exams", icon: "pencil", color: .orange)
            SummaryCard(value: "\(done)", suffix: "/\(total)", label: "Done Today", icon: "checkmark.circle", color: .green)
        }
    }

    private func completedTodayCounts() -> (Int, Int) {
        let todayStr = DateFormatter.iso.string(from: today)
        let todayHW = store.homework.filter { $0.dueDate == todayStr && $0.source != "powerschool" }
        let todayTasks = store.tasks.filter { $0.dueDate == todayStr }
        let done = todayHW.filter(\.completed).count + todayTasks.filter(\.completed).count
        let total = todayHW.count + todayTasks.count
        return (done, total)
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

    // MARK: - Disruption Banner
    private func disruptionBanner(_ d: ScheduleDisruption) -> some View {
        HStack(spacing: 12) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.title2)
                .foregroundStyle(.yellow)
            VStack(alignment: .leading, spacing: 2) {
                Text(d.label)
                    .font(.subheadline.bold())
                Text("Schedule has been modified for today.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
        }
        .padding(14)
        .background(.yellow.opacity(0.10), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous)
            .strokeBorder(.yellow.opacity(0.3), lineWidth: 0.5))
    }

    // MARK: - Today's Classes
    private var todaysClassesSection: some View {
        let todayCls = store.todaysClasses(for: today)
        return VStack(alignment: .leading, spacing: 10) {
            SectionHeader(title: "Today's Classes", icon: "clock.fill")
            if todayCls.isEmpty {
                emptyState("No classes today", icon: "cup.and.saucer.fill")
            } else {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 10) {
                        ForEach(todayCls) { cls in
                            ClassPill(schoolClass: cls)
                        }
                    }
                    .padding(.horizontal, 2)
                    .padding(.vertical, 4)
                }
            }
        }
    }

    // MARK: - Homework
    private var homeworkSection: some View {
        let items = store.upcomingHomework(limit: 5)
        return VStack(alignment: .leading, spacing: 10) {
            SectionHeader(title: "Upcoming Homework", icon: "book.closed.fill")
            if items.isEmpty {
                emptyState("All caught up!", icon: "checkmark.circle.fill")
            } else {
                VStack(spacing: 8) {
                    ForEach(items) { hw in
                        HomeworkRow(hw: hw, store: store)
                    }
                }
            }
        }
    }

    // MARK: - Exams
    private var examsSection: some View {
        let items = store.upcomingExams(limit: 3)
        return VStack(alignment: .leading, spacing: 10) {
            SectionHeader(title: "Upcoming Exams", icon: "pencil.and.list.clipboard")
            if items.isEmpty {
                emptyState("No exams coming up", icon: "star.fill")
            } else {
                VStack(spacing: 8) {
                    ForEach(items) { exam in
                        ExamRow(exam: exam, store: store, isPast: false)
                            .padding(14)
                            .glassCard(cornerRadius: 14)
                    }
                }
            }
        }
    }

    // MARK: - Tasks
    private var tasksSection: some View {
        let items = store.pendingTasks(limit: 5)
        return VStack(alignment: .leading, spacing: 10) {
            SectionHeader(title: "Pending Tasks", icon: "checkmark.circle.fill")
            if items.isEmpty {
                emptyState("Nothing pending", icon: "sparkles")
            } else {
                VStack(spacing: 8) {
                    ForEach(items) { task in
                        TaskRow(task: task, store: store)
                    }
                }
            }
        }
    }

    private func emptyState(_ message: String, icon: String) -> some View {
        HStack(spacing: 10) {
            Image(systemName: icon).foregroundStyle(Color.accentColor.opacity(0.7))
            Text(message).font(.subheadline).foregroundStyle(.secondary)
        }
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

    var body: some View {
        VStack(spacing: 4) {
            Image(systemName: icon)
                .font(.body)
                .foregroundStyle(color)
            HStack(alignment: .lastTextBaseline, spacing: 0) {
                Text(value)
                    .font(.title2.bold())
                    .fontDesign(.rounded)
                    .foregroundStyle(.primary)
                if !suffix.isEmpty {
                    Text(suffix)
                        .font(.caption.weight(.medium))
                        .fontDesign(.rounded)
                        .foregroundStyle(.secondary)
                }
            }
            Text(label)
                .font(.caption2.weight(.medium))
                .foregroundStyle(.secondary)
                .lineLimit(1)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 14)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
    }
}

// MARK: - Sub-views

struct SectionHeader: View {
    let title: String; let icon: String
    var body: some View {
        Label(title, systemImage: icon)
            .font(.headline)
            .foregroundStyle(.primary)
    }
}

struct ClassPill: View {
    let schoolClass: SchoolClass

    private var isNow: Bool {
        let now = Date.now
        let cal = Calendar.current
        let h = cal.component(.hour, from: now)
        let m = cal.component(.minute, from: now)
        let currentMinutes = h * 60 + m
        let startParts = schoolClass.startTime.split(separator: ":").compactMap { Int($0) }
        let endParts = schoolClass.endTime.split(separator: ":").compactMap { Int($0) }
        guard startParts.count == 2, endParts.count == 2 else { return false }
        let startMinutes = startParts[0] * 60 + startParts[1]
        let endMinutes = endParts[0] * 60 + endParts[1]
        return currentMinutes >= startMinutes && currentMinutes < endMinutes
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(schoolClass.name)
                .font(.subheadline.bold())
                .lineLimit(1)
            Text("\(schoolClass.startTime) – \(schoolClass.endTime)")
                .font(.caption2)
                .foregroundStyle(.secondary)
            if !schoolClass.room.isEmpty {
                Text("Room \(schoolClass.room)")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .frame(minWidth: 90, alignment: .leading)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(alignment: .leading) {
            RoundedRectangle(cornerRadius: 3).fill(Color(hex: schoolClass.color))
                .frame(width: 4)
                .padding(.vertical, 8)
                .offset(x: 4)
        }
        .overlay(
            Group {
                if isNow {
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .strokeBorder(Color.accentColor.opacity(0.5), lineWidth: 1.5)
                }
            }
        )
        .shadow(color: isNow ? Color.accentColor.opacity(0.15) : .clear, radius: 6)
    }
}

struct HomeworkRow: View {
    let hw: Homework
    let store: CanopyStore

    var body: some View {
        HStack(spacing: 12) {
            PriorityDot(priority: hw.priority)
            VStack(alignment: .leading, spacing: 3) {
                Text(hw.title).font(.subheadline.bold()).lineLimit(1)
                if let cls = store.schoolClass(hw.classId) {
                    HStack(spacing: 4) {
                        ClassColorDot(hex: cls.color, size: 7)
                        Text(cls.name).font(.caption).foregroundStyle(.secondary)
                    }
                }
            }
            Spacer()
            Text(hw.dueDate.dueDateLabel)
                .font(.caption.bold())
                .foregroundStyle(hw.dueDate.isOverdue ? .red : (hw.dueDate.isDueToday ? .orange : .secondary))
                .padding(.horizontal, 8).padding(.vertical, 3)
                .background(
                    (hw.dueDate.isOverdue ? Color.red : hw.dueDate.isDueToday ? Color.orange : Color.secondary).opacity(0.12),
                    in: Capsule()
                )
        }
        .padding(14)
        .glassCard(cornerRadius: 14)
    }
}

struct TaskRow: View {
    let task: SchoolTask; let store: CanopyStore
    var body: some View {
        HStack(spacing: 12) {
            PriorityDot(priority: task.priority)
            VStack(alignment: .leading, spacing: 3) {
                Text(task.title).font(.subheadline.bold()).lineLimit(1)
                Text(task.category).font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            if !task.dueDate.isEmpty {
                Text(task.dueDate.dueDateLabel)
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
        .padding(14)
        .glassCard(cornerRadius: 14)
    }
}
