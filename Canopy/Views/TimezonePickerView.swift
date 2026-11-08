import SwiftUI

/// Searchable, region-grouped picker over every IANA timezone identifier —
/// port of web `TimezonePicker`: zones are sorted by their current UTC offset
/// (regions ordered by their earliest zone), each row shows the "GMT-9"-style
/// offset, and search matches the city, the identifier, and the offset text
/// ("GMT-9" or "UTC-9"). Used from Settings and the Setup Wizard.
struct TimezonePickerView: View {
    @Binding var selection: String
    @Environment(\.dismiss) private var dismiss
    @State private var query = ""

    private struct Zone: Identifiable, Hashable {
        let id: String
        let label: String
        let region: String
        let offsetSeconds: Int
        let offset: String
    }

    // Etc/GMT+N entries are low-value noise (inverted-sign, rarely what a
    // person means) — drop them, matching what a normal timezone picker shows.
    private static let allZones: [Zone] = {
        let now = Date()
        return TimeZone.knownTimeZoneIdentifiers
            .filter { !$0.hasPrefix("Etc/") }
            .compactMap { id -> Zone? in
                guard let tz = TimeZone(identifier: id) else { return nil }
                let parts = id.split(separator: "/")
                let city = (parts.count > 1 ? parts.dropFirst().joined(separator: " / ") : id)
                    .replacingOccurrences(of: "_", with: " ")
                let secs = tz.secondsFromGMT(for: now)
                return Zone(id: id, label: city, region: parts.first.map(String.init) ?? "Other",
                            offsetSeconds: secs, offset: Self.offsetLabel(secs))
            }
            .sorted { a, b in
                if a.offsetSeconds != b.offsetSeconds { return a.offsetSeconds < b.offsetSeconds }
                return a.label.localizedCaseInsensitiveCompare(b.label) == .orderedAscending
            }
    }()

    private static func offsetLabel(_ seconds: Int) -> String {
        if seconds == 0 { return "GMT" }
        let sign = seconds >= 0 ? "+" : "-"
        let hours = abs(seconds) / 3600
        let minutes = abs(seconds) / 60 % 60
        return minutes == 0 ? "GMT\(sign)\(hours)" : String(format: "GMT%@%d:%02d", sign, hours, minutes)
    }

    private var filtered: [Zone] {
        let q = query.trimmingCharacters(in: .whitespaces)
        guard !q.isEmpty else { return Self.allZones }
        // "UTC-9" and "GMT-9" mean the same thing to a person searching.
        let normalized = q.replacingOccurrences(of: "UTC", with: "GMT", options: .caseInsensitive)
        return Self.allZones.filter { z in
            z.label.localizedCaseInsensitiveContains(q)
            || z.id.localizedCaseInsensitiveContains(q)
            || z.id.replacingOccurrences(of: "_", with: " ").localizedCaseInsensitiveContains(q)
            || z.offset.localizedCaseInsensitiveContains(normalized)
        }
    }

    /// Regions in order of first appearance in the offset-sorted list (web
    /// Autocomplete groupBy semantics), zones inside keep the offset order.
    private var grouped: [(region: String, zones: [Zone])] {
        var order: [String] = []
        var byRegion: [String: [Zone]] = [:]
        for z in filtered {
            if byRegion[z.region] == nil { order.append(z.region) }
            byRegion[z.region, default: []].append(z)
        }
        return order.map { (region: $0, zones: byRegion[$0] ?? []) }
    }

    var body: some View {
        List {
            if filtered.isEmpty {
                ContentUnavailableView.search(text: query)
            }
            ForEach(grouped, id: \.region) { group in
                Section(group.region) {
                    ForEach(group.zones) { zone in
                        Button {
                            selection = zone.id
                            dismiss()
                        } label: {
                            HStack {
                                Text(zone.label).foregroundStyle(.primary)
                                Spacer()
                                Text(zone.offset)
                                    .font(.caption.monospacedDigit())
                                    .foregroundStyle(.secondary)
                                if zone.id == selection {
                                    Image(systemName: "checkmark")
                                        .font(.caption.bold())
                                        .foregroundStyle(Color.accentColor)
                                }
                            }
                        }
                    }
                }
            }
        }
        .insetGroupedListStyle()
        .searchable(text: $query, prompt: "Search cities, regions, or UTC-9")
        .navigationTitle("Timezone")
        .navigationBarTitleInline()
    }

    /// Display helper shared by the rows that show the current selection.
    static func displayLabel(_ zone: String) -> String {
        if let z = allZones.first(where: { $0.id == zone }) { return "\(z.label) (\(z.offset))" }
        return zone.replacingOccurrences(of: "_", with: " ")
    }
}
