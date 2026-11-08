import SwiftUI

private let dayNames = [0: "Sun", 1: "Mon", 2: "Tue", 3: "Wed", 4: "Thu", 5: "Fri", 6: "Sat"]

/// Opens from tapping a card on the Classes page — a read-only "what's going
/// on with this class" view (when it next meets, and every homework/task
/// linked to it). Port of web ClassRosterDialog.tsx. Looks the class up live
/// by id so it reflects edits immediately and dismisses if the class is gone.
struct ClassRosterSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(CanopyStore.self) private var store
    let classId: String
    let onEdit: (SchoolClass) -> Void

    private static let nextMeeting: DateFormatter = {
        let f = DateFormatter(); f.dateFormat = "EEE, MMM d"; return f
    }()

    private struct RosterItem: Identifiable {
        let id: String
        let title: String
        let dueDate: String
        let completed: Bool
        let kind: String // "Homework" | "Task"
    }

    private var cls: SchoolClass? { store.schoolClass(classId) }
    private var isGone: Bool { cls == nil }

    /// All homework (INCLUDING PowerSchool) + tasks linked to this class, by due date.
    private var items: [RosterItem] {
        let hw = store.homework.filter { $0.classId == classId }.map {
            RosterItem(id: "hw-\($0.id)", title: $0.title, dueDate: $0.dueDate, completed: $0.completed, kind: "Homework")
        }
        let tk = store.tasks.filter { $0.classId == classId }.map {
            RosterItem(id: "task-\($0.id)", title: $0.title, dueDate: $0.dueDate, completed: $0.completed, kind: "Task")
        }
        return (hw + tk).sorted { $0.dueDate < $1.dueDate }
    }

    var body: some View {
        NavigationStack {
            ZStack {
                CanopyBackground()
                if let cls {
                    ScrollView {
                        VStack(alignment: .leading, spacing: 16) {
                            header(cls)
                            Divider()
                            itemsSection
                        }
                        .padding(16).padding(.bottom, 32)
                    }
                }
            }
            .navigationTitle(cls?.name ?? "Class")
            .navigationBarTitleInline()
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Close") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button {
                        guard let cls else { return }
                        dismiss()
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) { onEdit(cls) }
                    } label: {
                        Label("Edit", systemImage: "pencil")
                    }
                    .fontWeight(.semibold)
                }
            }
        }
        .onAppear { if isGone { dismiss() } }
        .onChange(of: isGone) { _, gone in if gone { dismiss() } }
    }

    // MARK: Header (web: dot + name, teacher, room, period/time, next meeting, chips)

    private func header(_ cls: SchoolClass) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                ClassColorDot(hex: cls.color, size: 10)
                Text(cls.name)
                    .font(.title3.weight(.semibold)).fontDesign(.rounded)
            }

            VStack(alignment: .leading, spacing: 5) {
                Label(cls.displayTeacher ?? "—", systemImage: "person")
                Label("Room \(cls.room.nonEmpty ?? "—")", systemImage: "mappin.and.ellipse")
                Label("Period \(cls.period) • \(cls.startTime)–\(cls.endTime)", systemImage: "clock")
                Label(nextMeetingText(cls), systemImage: "calendar")
            }
            .font(.subheadline)
            .foregroundStyle(.secondary)

            PlannerFlowLayout(spacing: 5) {
                ForEach(cls.days.sorted(), id: \.self) { d in
                    OutlinedChip(text: dayNames[d] ?? "?")
                }
                if !cls.semester.isEmpty {
                    ClassChip(name: cls.semester, hex: cls.color)
                }
            }
            .padding(.top, 2)
        }
    }

    private func nextMeetingText(_ cls: SchoolClass) -> String {
        let next = ScheduleEngine.nextMeetingDate(days: cls.days)
        if let d = next.asDate { return "Meets next on \(Self.nextMeeting.string(from: d))" }
        return "No meeting days set"
    }

    // MARK: Items (web: Open items (N) / Done (N) first 5)

    @ViewBuilder
    private var itemsSection: some View {
        let open = items.filter { !$0.completed }
        let done = items.filter { $0.completed }

        VStack(alignment: .leading, spacing: 6) {
            Text("Open items (\(open.count))")
                .font(.subheadline.weight(.semibold))
            if open.isEmpty {
                Text("Nothing outstanding for this class.")
                    .font(.subheadline).foregroundStyle(.secondary)
            } else {
                VStack(alignment: .leading, spacing: 0) {
                    ForEach(open) { item in
                        itemRow(item, done: false)
                        if item.id != open.last?.id { Divider() }
                    }
                }
            }
        }

        if !done.isEmpty {
            VStack(alignment: .leading, spacing: 6) {
                Text("Done (\(done.count))")
                    .font(.subheadline.weight(.semibold))
                VStack(alignment: .leading, spacing: 0) {
                    let shown = Array(done.prefix(5))
                    ForEach(shown) { item in
                        itemRow(item, done: true)
                        if item.id != shown.last?.id { Divider() }
                    }
                }
            }
        }
    }

    private func itemRow(_ item: RosterItem, done: Bool) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(item.title)
                .font(.subheadline)
                .strikethrough(done)
                .foregroundStyle(done ? .secondary : .primary)
            Text("\(item.kind) • \(GradesUtil.relativeDueLabel(item.dueDate.nonEmpty))")
                .font(.caption).foregroundStyle(.secondary)
        }
        .padding(.vertical, 7)
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}
