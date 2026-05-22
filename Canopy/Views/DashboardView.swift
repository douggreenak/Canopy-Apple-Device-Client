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
                        if !store.askTasks.isEmpty { askBanner }
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
            .toolbar {
                ToolbarItem(placement: .principal) {
                    HStack(spacing: 6) {
                        Image(systemName: "leaf.fill").foregroundStyle(Color.accentColor)
                        Text("Canopy").font(.headline)
                    }
                }
            }
            .refreshable { await store.loadAll() }
        }
    }

    // MARK: - Date Header
    private var dateHeader: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(today, format: .dateTime.weekday(.wide))
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(.secondary)
                .textCase(.uppercase)
            Text(today, format: .dateTime.month(.wide).day())
                .font(.system(size: 32, weight: .bold, design: .rounded))
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.top, 8)
    }

    // MARK: - Ask Banner
    private var askBanner: some View {
        HStack(spacing: 12) {
            Image(systemName: "questionmark.circle.fill")
                .font(.title2)
                .foregroundStyle(.orange)
            VStack(alignment: .leading, spacing: 2) {
                Text("Questions to Ask")
                    .font(.subheadline.bold())
                Text(store.askTasks.map(\.title).joined(separator: ", "))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }
            Spacer()
        }
        .padding(14)
        .background(.orange.opacity(0.15), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous)
            .strokeBorder(.orange.opacity(0.3), lineWidth: 0.5))
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
                        ExamRow(exam: exam, store: store)
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
        .frame(minWidth: 110, alignment: .leading)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(alignment: .leading) {
            RoundedRectangle(cornerRadius: 3).fill(Color(hex: schoolClass.color))
                .frame(width: 4)
                .padding(.vertical, 8)
                .offset(x: 4)
        }
        .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous)
            .strokeBorder(.white.opacity(0.15), lineWidth: 0.5))
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
                Text(store.className(for: hw.classId))
                    .font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            Text(hw.dueDate.dueDateLabel)
                .font(.caption.bold())
                .foregroundStyle(hw.dueDate.isOverdue ? .red : (hw.dueDate.isDueToday ? .orange : .secondary))
                .padding(.horizontal, 8).padding(.vertical, 3)
                .background((hw.dueDate.isOverdue ? Color.red : (hw.dueDate.isDueToday ? Color.orange : Color.systemFill)).opacity(0.15),
                             in: Capsule())
        }
        .padding(14)
        .glassCard(cornerRadius: 14)
    }
}

struct ExamRow: View {
    let exam: Exam; let store: CanopyStore
    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "pencil.and.list.clipboard")
                .font(.title3)
                .foregroundStyle(Color.accentColor)
                .frame(width: 32)
            VStack(alignment: .leading, spacing: 3) {
                Text(exam.title).font(.subheadline.bold()).lineLimit(1)
                Text(store.className(for: exam.classId)).font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 2) {
                Text(exam.date.dueDateLabel).font(.caption.bold())
                if !exam.startTime.isEmpty {
                    Text(exam.startTime).font(.caption2).foregroundStyle(.secondary)
                }
            }
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
