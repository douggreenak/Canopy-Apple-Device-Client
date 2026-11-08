import SwiftUI

// Port of web src/app/sync-log/page.tsx — every change detected on each
// PowerSchool sync, grouped per sync batch, newest first.

struct SyncLogView: View {
    @Environment(CanopyStore.self) private var store
    @State private var query = ""
    @State private var changeFilter = "all"

    private struct Filter: Identifiable { let key: String; let label: String; var id: String { key } }
    private let filters: [Filter] = [
        .init(key: "all", label: "All"),
        .init(key: "added", label: "Added"),
        .init(key: "removed", label: "Removed"),
        .init(key: "score_changed", label: "Scores"),
        .init(key: "grade_changed", label: "Grades"),
        .init(key: "flag_changed", label: "Flags"),
        .init(key: "none", label: "No changes"),
        .init(key: "error", label: "Failed"),
    ]

    private struct SyncGroup: Identifiable {
        let syncId: String
        let occurredAt: String
        let items: [SyncLogEntry]
        var id: String { syncId }
    }

    private var classById: [String: String] {
        Dictionary(store.classes.map { ($0.id, $0.name) }, uniquingKeysWith: { a, _ in a })
    }

    private var filtered: [SyncLogEntry] {
        let q = query.trimmingCharacters(in: .whitespaces).lowercased()
        return store.syncLog.filter { e in
            if changeFilter != "all" && e.changeType != changeFilter { return false }
            if !q.isEmpty && !e.label.lowercased().contains(q) && !e.detail.lowercased().contains(q) { return false }
            return true
        }
    }

    /// Group by syncId (each sync is a batch), most recent first.
    private var grouped: [SyncGroup] {
        var order: [String] = []
        var bySync: [String: [SyncLogEntry]] = [:]
        for e in filtered {
            if bySync[e.syncId] == nil { order.append(e.syncId) }
            bySync[e.syncId, default: []].append(e)
        }
        return order
            .map { SyncGroup(syncId: $0, occurredAt: bySync[$0]?.first?.occurredAt ?? "", items: bySync[$0] ?? []) }
            .sorted { $0.occurredAt > $1.occurredAt }
    }

    var top: AnyView = AnyView(EmptyView())

    var body: some View {
        ZStack { CanopyBackground()
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 14) {
                    top
                    header
                    filterBar
                    if grouped.isEmpty {
                        if store.syncLog.isEmpty {
                            emptyState
                        } else {
                            noResultsState
                        }
                    } else {
                        ForEach(grouped) { group in
                            syncCard(group)
                        }
                    }
                }
                .padding(16)
                .padding(.bottom, 32)
            }
        }
        .navigationTitle("Sync Log")
        .navigationBarTitleInline()
        .refreshable { await store.loadAll() }
    }

    // MARK: Header

    private var header: some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack(spacing: 6) {
                Image(systemName: "clock.arrow.circlepath").foregroundStyle(Color.accentColor)
                Text("Sync Log")
            }
            .font(.title3.bold())
            .fontDesign(.rounded)
            Text("Every change detected on each PowerSchool sync.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    // MARK: Filter bar

    private var filterBar: some View {
        VStack(spacing: 8) {
            HStack {
                Image(systemName: "magnifyingglass").foregroundStyle(.secondary).font(.caption)
                TextField("Search assignments or classes…", text: $query)
                    .textFieldStyle(.plain)
                    .font(.subheadline)
                    .textAutocapNever()
                if !query.isEmpty {
                    Button { query = "" } label: {
                        Image(systemName: "xmark.circle.fill").foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(8)
            .background(Color.secondary.opacity(0.1), in: RoundedRectangle(cornerRadius: 10, style: .continuous))

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 6) {
                    ForEach(filters) { f in
                        let on = changeFilter == f.key
                        Button {
                            withAnimation(.spring(response: 0.2)) { changeFilter = f.key }
                        } label: {
                            Text(f.label)
                                .font(.caption.weight(on ? .semibold : .regular))
                                .padding(.horizontal, 12).padding(.vertical, 6)
                                .background(on ? Color.accentColor.opacity(0.15) : Color.clear, in: Capsule())
                                .overlay(Capsule().strokeBorder(on ? Color.accentColor.opacity(0.6) : Color.secondary.opacity(0.3), lineWidth: 1))
                                .foregroundStyle(on ? Color.accentColor : Color.primary)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.vertical, 2)
            }
        }
    }

    // MARK: Sync group card

    private func groupChip(_ group: SyncGroup) -> String {
        if group.items.count == 1, group.items[0].changeType == "error" { return "Sync failed" }
        if group.items.count == 1, group.items[0].changeType == "none" { return "No changes" }
        return "\(group.items.count) change\(group.items.count == 1 ? "" : "s")"
    }

    private func syncCard(_ group: SyncGroup) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 8) {
                Text(formatTimestamp(group.occurredAt))
                    .font(.footnote.weight(.semibold))
                Text("(\(GradesUtil.timeAgo(group.occurredAt)))")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                Spacer()
                Text(groupChip(group))
                    .font(.caption2.weight(.medium))
                    .padding(.horizontal, 8).padding(.vertical, 3)
                    .background(Color.secondary.opacity(0.12), in: Capsule())
            }
            .padding(.horizontal, 14).padding(.vertical, 12)

            Divider()

            ForEach(Array(group.items.enumerated()), id: \.element.id) { idx, entry in
                entryRow(entry)
                if idx < group.items.count - 1 { Divider() }
            }
        }
        .glassEffect(.regular, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
    }

    // MARK: Entry row

    private func entryRow(_ entry: SyncLogEntry) -> some View {
        let color = entryColor(entry.changeType)
        return HStack(alignment: .top, spacing: 12) {
            Image(systemName: iconName(entry.changeType))
                .font(.subheadline)
                .foregroundStyle(color)
                .frame(width: 20)
                .padding(.top, 1)

            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    TintedChip(text: changeLabel(entry.changeType), color: color)
                    OutlinedChip(text: entityLabel(entry.entityType))
                }
                Text(entry.label)
                    .font(.subheadline.weight(.medium))
                    .lineLimit(1)
                if let cid = entry.classId, let name = classById[cid] {
                    Text(name).font(.caption).foregroundStyle(.secondary)
                }
                if !entry.detail.isEmpty {
                    Text(entry.detail).font(.caption).foregroundStyle(.secondary)
                }
            }

            Spacer(minLength: 0)

            Text(shortTime(entry.occurredAt))
                .font(.caption2)
                .foregroundStyle(.tertiary)
                .padding(.top, 1)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .overlay(alignment: .leading) {
            Rectangle().fill(color.opacity(0.5)).frame(width: 3)
        }
    }

    // MARK: Empty states

    private var emptyState: some View {
        VStack(spacing: 12) {
            Image(systemName: "clock.arrow.circlepath")
                .font(.system(size: 56))
                .foregroundStyle(.tertiary)
            Text("No sync history yet").font(.title3.weight(.semibold))
            Text("Every PowerSchool sync will record changes here — grade updates, new assignments, flag changes. Run a sync from the Grades page to get started.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .padding(.vertical, 40)
        .padding(.horizontal, 24)
        .frame(maxWidth: .infinity)
        .glassEffect(.regular, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
    }

    private var noResultsState: some View {
        VStack(spacing: 12) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 44))
                .foregroundStyle(.tertiary)
            Text("No matching changes").font(.headline)
            Text("Try a different search or filter.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .padding(.vertical, 32)
        .frame(maxWidth: .infinity)
        .glassEffect(.regular, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
    }

    // MARK: Helpers (web changeIcon / changeColor / changeLabel)

    private func entryColor(_ type: String) -> Color {
        switch type {
        case "added": return .green
        case "removed", "error": return .red
        case "score_changed", "grade_changed": return .accentColor
        case "flag_changed": return .orange
        case "none": return Color.secondary.opacity(0.6)
        default: return .secondary
        }
    }

    private func iconName(_ type: String) -> String {
        switch type {
        case "added": return "plus.circle"
        case "removed": return "minus.circle"
        case "score_changed": return "pencil.and.list.clipboard"
        case "grade_changed": return "chart.line.uptrend.xyaxis"
        case "flag_changed": return "flag"
        case "error": return "exclamationmark.circle"
        case "none": return "checkmark.circle"
        default: return "circle"
        }
    }

    private func changeLabel(_ type: String) -> String {
        switch type {
        case "added": return "Added"
        case "removed": return "Removed"
        case "score_changed": return "Score"
        case "grade_changed": return "Grade"
        case "flag_changed": return "Flag"
        case "error": return "Failed"
        case "none": return "No changes"
        default: return type
        }
    }

    private func entityLabel(_ type: String) -> String {
        switch type {
        case "homework": return "Assignment"
        case "class": return "Class"
        default: return "Sync"
        }
    }

    private func formatTimestamp(_ iso: String) -> String {
        guard let date = CanopyStore.parseISO(iso) else { return iso }
        let f = DateFormatter()
        f.dateFormat = "MMM d, yyyy · h:mm a"
        return f.string(from: date)
    }

    private func shortTime(_ iso: String) -> String {
        guard let date = CanopyStore.parseISO(iso) else { return "" }
        let f = DateFormatter()
        f.dateFormat = "h:mm a"
        return f.string(from: date)
    }
}
