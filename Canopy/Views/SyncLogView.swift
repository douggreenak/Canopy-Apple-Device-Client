import SwiftUI

// MARK: - Sync Log View

struct SyncLogView: View {
    @Environment(CanopyStore.self) private var store
    @State private var query = ""
    @State private var changeFilter = "all"

    private let filters = ["all", "added", "removed", "score_changed", "grade_changed", "flag_changed"]
    private let filterLabels = [
        "all": "All", "added": "Added", "removed": "Removed",
        "score_changed": "Scores", "grade_changed": "Grades", "flag_changed": "Flags"
    ]

    private var classById: [String: String] {
        Dictionary(uniqueKeysWithValues: store.classes.map { ($0.id, $0.name) })
    }

    private var filtered: [SyncLogEntry] {
        let q = query.lowercased().trimmingCharacters(in: .whitespaces)
        return store.syncLog.filter { e in
            if changeFilter != "all" && e.changeType != changeFilter { return false }
            if !q.isEmpty && !e.label.lowercased().contains(q) && !e.detail.lowercased().contains(q) { return false }
            return true
        }
    }

    private var grouped: [(syncId: String, occurredAt: String, items: [SyncLogEntry])] {
        var bySync: [String: [SyncLogEntry]] = [:]
        for e in filtered {
            bySync[e.syncId, default: []].append(e)
        }
        return bySync.map { (syncId: $0.key, occurredAt: $0.value[0].occurredAt, items: $0.value) }
            .sorted { $0.occurredAt > $1.occurredAt }
    }

    var body: some View {
        ZStack { CanopyBackground()
            if store.syncLog.isEmpty {
                emptyState
            } else {
                VStack(spacing: 0) {
                    filterBar.padding(.horizontal, 16).padding(.vertical, 10)
                    Divider()
                    if grouped.isEmpty {
                        noResultsState
                    } else {
                        List {
                            ForEach(grouped, id: \.syncId) { group in
                                syncSection(group)
                            }
                        }
                        .insetGroupedListStyle()
                        .scrollContentBackground(.hidden)
                    }
                }
            }
        }
        .navigationTitle("Sync Log")
        .navigationBarTitleInline()
        .refreshable { await store.loadAll() }
    }

    // MARK: - Filter bar
    private var filterBar: some View {
        VStack(spacing: 8) {
            #if !os(macOS)
            TextField("Search assignments…", text: $query)
                .textFieldStyle(.roundedBorder)
            #else
            TextField("Search assignments…", text: $query)
            #endif

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 6) {
                    ForEach(filters, id: \.self) { f in
                        Button {
                            withAnimation(.spring(response: 0.2)) { changeFilter = f }
                        } label: {
                            Text(filterLabels[f] ?? f)
                                .font(.caption.bold())
                                .padding(.horizontal, 12).padding(.vertical, 6)
                                .background(
                                    changeFilter == f ? Color.accentColor.opacity(0.15) : Color.secondary.opacity(0.1),
                                    in: Capsule()
                                )
                                .foregroundStyle(changeFilter == f ? Color.accentColor : Color.secondary)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
    }

    // MARK: - Sync group section
    @ViewBuilder
    private func syncSection(_ group: (syncId: String, occurredAt: String, items: [SyncLogEntry])) -> some View {
        Section {
            ForEach(group.items) { entry in
                entryRow(entry)
            }
        } header: {
            HStack {
                Text(formatTimestamp(group.occurredAt))
                    .font(.footnote.bold())
                Spacer()
                Text("\(group.items.count) change\(group.items.count == 1 ? "" : "s")")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    // MARK: - Entry row
    private func entryRow(_ entry: SyncLogEntry) -> some View {
        HStack(alignment: .top, spacing: 12) {
            // Icon
            Image(systemName: iconName(entry.changeType))
                .font(.caption)
                .foregroundStyle(entryColor(entry.changeType))
                .frame(width: 20)
                .padding(.top, 2)

            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    Text(changeLabel(entry.changeType))
                        .font(.caption2.bold())
                        .padding(.horizontal, 7).padding(.vertical, 2)
                        .background(entryColor(entry.changeType).opacity(0.12), in: Capsule())
                        .foregroundStyle(entryColor(entry.changeType))
                    Text(entry.entityType)
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }

                Text(entry.label)
                    .font(.subheadline)
                    .lineLimit(2)

                if let cid = entry.classId, let cname = classById[cid] {
                    Text(cname)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                if !entry.detail.isEmpty {
                    Text(entry.detail)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            Spacer(minLength: 0)

            Text(shortTime(entry.occurredAt))
                .font(.caption2)
                .foregroundStyle(.tertiary)
        }
        .padding(.vertical, 4)
    }

    // MARK: - Empty state
    private var emptyState: some View {
        ContentUnavailableView(
            "No Sync History",
            systemImage: "clock.arrow.circlepath",
            description: Text("Every PowerSchool sync records changes here. Run a sync from the web app to get started.")
        )
    }

    private var noResultsState: some View {
        ContentUnavailableView(
            "No Results",
            systemImage: "magnifyingglass",
            description: Text("Try a different search or filter.")
        )
    }

    // MARK: - Helpers
    private func entryColor(_ type: String) -> Color {
        switch type {
        case "added": return .green
        case "removed": return .red
        case "grade_changed", "score_changed": return .accentColor
        case "flag_changed": return .orange
        default: return .secondary
        }
    }

    private func iconName(_ type: String) -> String {
        switch type {
        case "added": return "plus.circle.fill"
        case "removed": return "minus.circle.fill"
        case "score_changed": return "pencil.circle.fill"
        case "grade_changed": return "chart.line.uptrend.xyaxis.circle.fill"
        case "flag_changed": return "flag.circle.fill"
        default: return "circle.fill"
        }
    }

    private func changeLabel(_ type: String) -> String {
        switch type {
        case "added": return "Added"
        case "removed": return "Removed"
        case "score_changed": return "Score"
        case "grade_changed": return "Grade"
        case "flag_changed": return "Flag"
        default: return type
        }
    }

    private func formatTimestamp(_ iso: String) -> String {
        guard let date = CanopyStore.isoFull.date(from: iso) else { return iso }
        let f = DateFormatter()
        f.dateFormat = "MMM d, yyyy · h:mm a"
        return f.string(from: date)
    }

    private func shortTime(_ iso: String) -> String {
        guard let date = CanopyStore.isoFull.date(from: iso) else { return "" }
        let f = DateFormatter()
        f.dateFormat = "h:mm a"
        return f.string(from: date)
    }
}
