import SwiftUI

/// Searchable, region-grouped picker over every IANA timezone identifier —
/// replaces the previous 8-zone hardcoded Settings picker, matching web's
/// full `Autocomplete` over all zones. Used both from Settings directly and
/// from the Setup Wizard's School Info step.
struct TimezonePickerView: View {
    @Binding var selection: String
    @Environment(\.dismiss) private var dismiss
    @State private var query = ""

    // Etc/GMT+N entries are low-value noise (inverted-sign, rarely what a
    // person means) — drop them, matching what a normal timezone picker shows.
    private static let allZones: [String] = TimeZone.knownTimeZoneIdentifiers
        .filter { !$0.hasPrefix("Etc/") }
        .sorted()

    private var grouped: [(region: String, zones: [String])] {
        let filtered = query.isEmpty ? Self.allZones : Self.allZones.filter { zone in
            zone.localizedCaseInsensitiveContains(query) ||
            zone.replacingOccurrences(of: "_", with: " ").localizedCaseInsensitiveContains(query)
        }
        let byRegion = Dictionary(grouping: filtered) { zone -> String in
            zone.split(separator: "/").first.map(String.init) ?? "Other"
        }
        return byRegion.keys.sorted().map { (region: $0, zones: byRegion[$0]!.sorted()) }
    }

    var body: some View {
        List {
            ForEach(grouped, id: \.region) { group in
                Section(group.region) {
                    ForEach(group.zones, id: \.self) { zone in
                        Button {
                            selection = zone
                            dismiss()
                        } label: {
                            HStack {
                                Text(displayName(zone)).foregroundStyle(.primary)
                                Spacer()
                                Text(offsetLabel(zone))
                                    .font(.caption.monospacedDigit())
                                    .foregroundStyle(.secondary)
                                if zone == selection {
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
        .searchable(text: $query, prompt: "Search cities or regions")
        .navigationTitle("Timezone")
        .navigationBarTitleInline()
    }

    private func displayName(_ zone: String) -> String {
        let parts = zone.split(separator: "/")
        let city = parts.count > 1 ? parts.dropFirst().joined(separator: " / ") : zone
        return city.replacingOccurrences(of: "_", with: " ")
    }

    private func offsetLabel(_ zone: String) -> String {
        guard let tz = TimeZone(identifier: zone) else { return "" }
        let seconds = tz.secondsFromGMT()
        let sign = seconds >= 0 ? "+" : "-"
        let hours = abs(seconds) / 3600
        let minutes = abs(seconds) / 60 % 60
        return minutes == 0 ? "GMT\(sign)\(hours)" : String(format: "GMT%@%d:%02d", sign, hours, minutes)
    }
}
