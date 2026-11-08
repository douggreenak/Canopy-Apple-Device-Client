import SwiftUI

// MARK: - Pairing (the iPhone app signs in; the watch just receives it)

struct WatchPairingView: View {
    @Environment(WatchStore.self) private var store

    var body: some View {
        ScrollView {
            VStack(spacing: 10) {
                Image(systemName: "tree.fill")
                    .font(.largeTitle).foregroundStyle(.green)
                Text("Canopy").font(.headline)
                Text("Sign in on your iPhone")
                    .font(.caption.bold())
                    .multilineTextAlignment(.center)
                Text("Open Canopy on your iPhone and sign in. Your watch picks up the login and your classes automatically.")
                    .font(.caption2).foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                if let m = store.linkMessage {
                    Text(m).font(.caption2).foregroundStyle(.orange)
                        .multilineTextAlignment(.center)
                }
                Button {
                    store.linkMessage = nil
                    WatchPhoneLink.shared.requestSync()
                } label: {
                    Label("Sync from iPhone", systemImage: "iphone.and.arrow.forward")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
            }
            .padding(.horizontal, 4)
        }
    }
}

// MARK: - Root tabs

struct WatchRootView: View {
    @Environment(WatchStore.self) private var store

    var body: some View {
        TabView {
            WatchTodayView().tabItem { Text("Today") }
            WatchHomeworkView().tabItem { Text("To-Do") }
            WatchExamsView().tabItem { Text("Exams") }
            WatchGradesView().tabItem { Text("Grades") }
        }
        .tabViewStyle(.verticalPage)
    }
}

// MARK: - Today

struct WatchTodayView: View {
    @Environment(WatchStore.self) private var store

    var body: some View {
        let today = store.todaysClasses()
        NavigationStack {
            List {
                if today.isEmpty {
                    Text("No classes today").foregroundStyle(.secondary)
                } else {
                    ForEach(today) { c in
                        HStack(spacing: 8) {
                            RoundedRectangle(cornerRadius: 2).fill(Color(wHex: c.color)).frame(width: 4, height: 30)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(c.name).font(.caption.bold()).lineLimit(1)
                                Text("\(c.startTime)–\(c.endTime)\(c.room.isEmpty ? "" : " · Rm \(c.room)")")
                                    .font(.caption2).foregroundStyle(.secondary)
                            }
                        }
                    }
                }
            }
            .navigationTitle("Today")
            .refreshable { await store.loadAll() }
        }
    }
}

// MARK: - To-Do (PowerSchool assignments coming up + personal to-dos)

struct WatchHomeworkView: View {
    @Environment(WatchStore.self) private var store

    var body: some View {
        let assignments = store.upcomingAssignments()
        let todos = store.todoItems()
        NavigationStack {
            List {
                if assignments.isEmpty && todos.isEmpty {
                    Text("All caught up!").foregroundStyle(.secondary)
                    if let e = store.errorMessage {
                        Text(e).font(.caption2).foregroundStyle(.orange)
                    }
                }
                if !assignments.isEmpty {
                    Section("Assignments") {
                        ForEach(assignments) { hw in
                            NavigationLink(value: WatchRoute.assignment(hw.id)) {
                                HStack(spacing: 8) {
                                    RoundedRectangle(cornerRadius: 2)
                                        .fill(Color(wHex: store.classColor(hw.classId)))
                                        .frame(width: 4, height: 30)
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(hw.title).font(.caption).lineLimit(2)
                                        Text(assignmentSubtitle(hw))
                                            .font(.caption2).foregroundStyle(.secondary).lineLimit(1)
                                    }
                                }
                            }
                        }
                    }
                }
                if !todos.isEmpty {
                    Section("To-Do") {
                        ForEach(todos) { item in
                            WatchTodoRow(item: item, subtitle: todoSubtitle(item))
                        }
                    }
                }
            }
            .animation(.spring(duration: 0.4), value: todos.map(\.id))
            .navigationTitle("To-Do")
            .navigationDestination(for: WatchRoute.self) { route in
                switch route {
                case .todo(let id): WatchTodoDetailView(itemID: id)
                case .assignment(let id): WatchAssignmentDetailView(assignmentID: id)
                }
            }
            .refreshable { await store.loadAll() }
        }
    }

    private func assignmentSubtitle(_ hw: WHomework) -> String {
        let cls = store.className(hw.classId)
        let due = hw.dueDate.wDueLabel
        return cls.isEmpty ? due : "\(cls) · \(due)"
    }

    private func todoSubtitle(_ item: WTodoItem) -> String {
        let cls = item.classId.map { store.className($0) } ?? ""
        let due = item.dueDate.isEmpty ? "No due date" : item.dueDate.wDueLabel
        return cls.isEmpty ? due : "\(cls) · \(due)"
    }
}

enum WatchRoute: Hashable {
    case todo(String)
    case assignment(String)
}

/// The check circle completes the item (with animation + haptic); tapping the
/// rest of the row opens its details.
struct WatchTodoRow: View {
    @Environment(WatchStore.self) private var store
    let item: WTodoItem
    let subtitle: String

    private var done: Bool { item.completed || store.celebrating.contains(item.id) }

    var body: some View {
        NavigationLink(value: WatchRoute.todo(item.id)) {
            HStack(spacing: 8) {
                Button {
                    Task { await store.complete(item) }
                } label: {
                    WatchCheckMark(done: done)
                }
                .buttonStyle(.plain)
                VStack(alignment: .leading, spacing: 2) {
                    Text(item.title)
                        .font(.caption).lineLimit(2)
                        .strikethrough(done, color: .secondary)
                        .foregroundStyle(done ? Color.secondary : Color.primary)
                    Text(subtitle).font(.caption2).foregroundStyle(.secondary).lineLimit(1)
                }
            }
            .opacity(store.celebrating.contains(item.id) ? 0.7 : 1)
        }
        .listRowBackground(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(store.celebrating.contains(item.id) ? Color.green.opacity(0.28) : Color.white.opacity(0.12))
                .animation(.easeOut(duration: 0.3), value: store.celebrating.contains(item.id))
        )
        .swipeActions(edge: .leading) {
            Button { Task { await store.complete(item) } } label: { Image(systemName: "checkmark") }.tint(.green)
        }
    }
}

/// Circle → filled green check with a bounce and an expanding ring.
struct WatchCheckMark: View {
    let done: Bool
    @State private var ring: CGFloat = 0

    var body: some View {
        ZStack {
            Circle()
                .stroke(Color.green, lineWidth: 2)
                .frame(width: 22, height: 22)
                .scaleEffect(1 + ring * 1.2)
                .opacity(ring == 0 ? 0 : Double(1 - ring))
            Image(systemName: done ? "checkmark.circle.fill" : "circle")
                .font(.title3)
                .foregroundStyle(done ? Color.green : Color.secondary)
                .symbolEffect(.bounce, value: done)
                .scaleEffect(done ? 1.1 : 1)
        }
        .frame(width: 30, height: 30)
        .animation(.spring(response: 0.3, dampingFraction: 0.5), value: done)
        .onChange(of: done) { _, now in
            if now {
                ring = 0
                withAnimation(.easeOut(duration: 0.7)) { ring = 1 }
            } else { ring = 0 }
        }
    }
}

// MARK: - To-do detail

struct WatchTodoDetailView: View {
    @Environment(WatchStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    let itemID: String

    var body: some View {
        if let item = store.todoItem(id: itemID) {
            let done = item.completed || store.celebrating.contains(item.id)
            ScrollView {
                VStack(alignment: .leading, spacing: 8) {
                    Text(item.title).font(.headline)
                    detailRow("book.closed", classLine(item), color: item.classId.map { Color(wHex: store.classColor($0)) })
                    detailRow("calendar", dueLine(item), color: overdue(item) ? .red : nil)
                    detailRow("flag", item.priority.capitalized + " priority", color: priorityColor(item.priority))
                    detailRow("tag", item.category, color: nil)
                    if !item.details.isEmpty {
                        Text(item.details).font(.caption2).foregroundStyle(.secondary)
                            .padding(.top, 2)
                    }
                    Button {
                        Task {
                            await store.complete(item)
                            if !item.completed { dismiss() }
                        }
                    } label: {
                        HStack {
                            WatchCheckMark(done: done)
                            Text(item.completed ? "Mark Not Done" : (done ? "Done!" : "Mark Done"))
                                .font(.caption.bold())
                        }
                        .frame(maxWidth: .infinity)
                    }
                    .tint(done ? .green : .accentColor)
                    .padding(.top, 4)
                }
            }
            .navigationTitle("Details")
        } else {
            Text("Item no longer available").font(.caption).foregroundStyle(.secondary)
        }
    }

    private func classLine(_ item: WTodoItem) -> String {
        let c = item.classId.map { store.className($0) } ?? ""
        return c.isEmpty ? "No class" : c
    }
    private func dueLine(_ item: WTodoItem) -> String {
        item.dueDate.isEmpty ? "No due date" : item.dueDate.wFullDue
    }
    private func overdue(_ item: WTodoItem) -> Bool {
        guard let d = item.dueDate.wAsDate else { return false }
        return d < Calendar.current.startOfDay(for: .now) && !item.completed
    }
    private func priorityColor(_ p: String) -> Color? {
        switch p { case "high": return .red; case "medium": return .orange; default: return nil }
    }
}

// MARK: - Assignment detail (read-only; PowerSchool assignments aren't checked off)

struct WatchAssignmentDetailView: View {
    @Environment(WatchStore.self) private var store
    let assignmentID: String

    var body: some View {
        if let hw = store.homework.first(where: { $0.id == assignmentID }) {
            ScrollView {
                VStack(alignment: .leading, spacing: 8) {
                    Text(hw.title).font(.headline)
                    detailRow("book.closed", store.className(hw.classId).isEmpty ? "No class" : store.className(hw.classId),
                              color: Color(wHex: store.classColor(hw.classId)))
                    detailRow("calendar", hw.dueDate.isEmpty ? "No due date" : hw.dueDate.wFullDue, color: nil)
                    if let c = hw.category, !c.isEmpty { detailRow("tag", c, color: nil) }
                    if let f = hw.flags, !f.isEmpty { detailRow("exclamationmark.triangle", f, color: .orange) }
                    if !hw.description.isEmpty {
                        Text(hw.description).font(.caption2).foregroundStyle(.secondary).padding(.top, 2)
                    }
                    Text("From PowerSchool")
                        .font(.caption2).foregroundStyle(.tertiary).padding(.top, 4)
                }
            }
            .navigationTitle("Assignment")
        } else {
            Text("Assignment no longer available").font(.caption).foregroundStyle(.secondary)
        }
    }
}

private func detailRow(_ icon: String, _ text: String, color: Color?) -> some View {
    HStack(alignment: .firstTextBaseline, spacing: 6) {
        Image(systemName: icon).font(.caption2).foregroundStyle(color ?? .secondary).frame(width: 14)
        Text(text).font(.caption).foregroundStyle(color ?? .primary)
    }
}

// MARK: - Exams

struct WatchExamsView: View {
    @Environment(WatchStore.self) private var store

    var body: some View {
        let items = store.upcomingExams()
        NavigationStack {
            List {
                if items.isEmpty {
                    Text("No upcoming exams").foregroundStyle(.secondary)
                } else {
                    ForEach(items) { ex in
                        VStack(alignment: .leading, spacing: 2) {
                            Text(ex.title).font(.caption.bold()).lineLimit(2)
                            Text(store.className(ex.classId)).font(.caption2).foregroundStyle(.secondary)
                            Text(ex.date.wDueLabel + (ex.startTime.isEmpty ? "" : " · \(ex.startTime)"))
                                .font(.caption2).foregroundStyle(.orange)
                        }
                    }
                }
            }
            .navigationTitle("Exams")
            .refreshable { await store.loadAll() }
        }
    }
}

// MARK: - Grades

struct WatchGradesView: View {
    @Environment(WatchStore.self) private var store

    var body: some View {
        let graded = store.gradedClasses
        NavigationStack {
            List {
                if graded.isEmpty {
                    Text("No grades yet").foregroundStyle(.secondary)
                } else {
                    ForEach(graded) { c in
                        let g = c.grade ?? c.gradePercent.map { wLetterGrade(from: $0) } ?? "—"
                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(c.name).font(.caption).lineLimit(1)
                                if let p = c.gradePercent {
                                    Text(String(format: "%.1f%%", p)).font(.caption2).foregroundStyle(.secondary)
                                }
                            }
                            Spacer()
                            Text(g).font(.title3.bold()).foregroundStyle(wGradeColor(g))
                        }
                    }
                }
                Section {
                    Button {
                        WatchPhoneLink.shared.requestSync()
                    } label: {
                        Label("Sync from iPhone", systemImage: "iphone.and.arrow.forward")
                    }
                    if let t = store.lastPhoneSync {
                        Text("Last iPhone sync \(t.formatted(.relative(presentation: .named)))")
                            .font(.caption2).foregroundStyle(.secondary)
                    }
                }
            }
            .navigationTitle("Grades")
            .refreshable { await store.loadAll() }
        }
    }
}
