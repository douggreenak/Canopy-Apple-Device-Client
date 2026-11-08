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

// MARK: - Homework

struct WatchHomeworkView: View {
    @Environment(WatchStore.self) private var store

    var body: some View {
        let items = store.upcomingHomework()
        NavigationStack {
            List {
                if items.isEmpty {
                    Text("All caught up!").foregroundStyle(.secondary)
                } else {
                    ForEach(items) { hw in
                        Button {
                            Task { await store.toggle(hw) }
                        } label: {
                            HStack(spacing: 8) {
                                Image(systemName: hw.completed ? "checkmark.circle.fill" : "circle")
                                    .foregroundStyle(hw.completed ? .green : .secondary)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(hw.title).font(.caption).lineLimit(2)
                                    Text(hw.dueDate.wDueLabel).font(.caption2).foregroundStyle(.secondary)
                                }
                            }
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
            .navigationTitle("To-Do")
            .refreshable { await store.loadAll() }
        }
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
