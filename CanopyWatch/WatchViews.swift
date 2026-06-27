import SwiftUI

// MARK: - Login

struct WatchLoginView: View {
    @Environment(WatchStore.self) private var store
    @State private var username = ""
    @State private var password = ""

    var body: some View {
        ScrollView {
            VStack(spacing: 10) {
                Image(systemName: "tree.fill")
                    .font(.largeTitle).foregroundStyle(.green)
                Text("Canopy").font(.headline)
                TextField("Username", text: $username)
                    .textContentType(.username)
                SecureField("Password", text: $password)
                if let e = store.errorMessage {
                    Text(e).font(.caption2).foregroundStyle(.red)
                }
                Button {
                    Task { await store.login(username: username, password: password) }
                } label: {
                    if store.isLoading { ProgressView() } else { Text("Sign In").frame(maxWidth: .infinity) }
                }
                .buttonStyle(.borderedProminent)
                .disabled(store.isLoading || username.isEmpty || password.isEmpty)
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
                    Button(role: .destructive) { store.logout() } label: { Text("Sign Out") }
                }
            }
            .navigationTitle("Grades")
            .refreshable { await store.loadAll() }
        }
    }
}
