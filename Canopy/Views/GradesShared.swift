import SwiftUI

// Shared building blocks for the Grades tab: list, class detail, simulators,
// transcript and sync log. Pure presentation helpers — all grade math lives in
// GradeEngine.swift / GradesUtil.swift.

// MARK: - Section label (also used by HomeworkView / TasksView)

struct SectionLabel: View {
    let text: String
    var body: some View {
        Text(text.uppercased())
            .font(.caption.bold())
            .foregroundStyle(.secondary)
            .tracking(1)
    }
}

// MARK: - Card press style

struct CardPressStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.97 : 1.0)
            .animation(.spring(response: 0.2, dampingFraction: 0.7), value: configuration.isPressed)
    }
}

// MARK: - Display helpers

enum GradesDisplay {
    /// "87.3%"
    static func pct1(_ v: Double) -> String { String(format: "%.1f%%", v) }

    /// JS-style number: 40 → "40", 12.5 → "12.5".
    static func num(_ v: Double) -> String { v == v.rounded() ? String(Int(v)) : String(v) }

    /// Class colour: by percent, else approximated from the letter (web rule
    /// 0.3), grey when neither exists.
    static func classColor(_ cls: SchoolClass) -> Color {
        GradesUtil.gradeColor(cls.gradePercent ?? GradesUtil.approxPercent(forLetter: cls.grade))
    }

    /// Stable display order for a weight table: heaviest first, then name.
    static func orderedWeightKeys(_ weights: [String: Double]) -> [String] {
        weights.keys.sorted { a, b in
            let wa = weights[a] ?? 0, wb = weights[b] ?? 0
            return wa != wb ? wa > wb : a.localizedCaseInsensitiveCompare(b) == .orderedAscending
        }
    }

    /// "Tests 40% · Homework 20%"
    static func weightsText(_ weights: [String: Double], separator: String) -> String {
        orderedWeightKeys(weights).map { "\($0) \(num(weights[$0] ?? 0))%" }.joined(separator: separator)
    }

    /// Web grade velocity: most recent snapshot vs the first one ≥ 5 days old;
    /// nil when under the 0.3-point threshold.
    static func velocity(from history: [GradeHistoryEntry]) -> Double? {
        let sorted = history.sorted { $0.capturedAt > $1.capturedAt }
        guard let recent = sorted.first, let recentPct = recent.gradePercent else { return nil }
        let cutoff = Date.now.addingTimeInterval(-5 * 86400)
        guard let older = sorted.first(where: { e in
            guard e.id != recent.id, let d = CanopyStore.parseISO(e.capturedAt) else { return false }
            return d <= cutoff
        }), let olderPct = older.gradePercent else { return nil }
        let delta = recentPct - olderPct
        return abs(delta) < 0.3 ? nil : delta
    }

    /// "+1.2%" / "-0.4%"
    static func signed1(_ v: Double) -> String { (v > 0 ? "+" : "") + String(format: "%.1f%%", v) }
    static func signed2(_ v: Double) -> String { (v >= 0 ? "+" : "") + String(format: "%.2f%%", v) }

    /// "MMM d, yyyy" for an ISO timestamp (falls back to yyyy-MM-dd input).
    static func shortDate(_ iso: String) -> String {
        let d = CanopyStore.parseISO(iso) ?? iso.asDate
        guard let d else { return iso }
        return DateFormatter.monthDayYear.string(from: d)
    }
}

extension ToastMessage {
    /// Toast severity from a terminal sync status (web Snackbar severity).
    static func forSync(_ status: PowerSchoolStatus, text: String) -> ToastMessage {
        ToastMessage(text: text, kind: status.status == "success" ? .success : status.status == "error" ? .error : .info)
    }
}

// MARK: - Stat tile (web StatTile)

struct GradeStatTile: View {
    let label: String
    let value: String
    var sub: String? = nil
    let systemImage: String
    let color: Color
    /// Colour of the big number; defaults to `color`.
    var valueColor: Color? = nil
    var emphasize = false

    private var shape: RoundedRectangle { RoundedRectangle(cornerRadius: 14, style: .continuous) }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                Image(systemName: systemImage)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(color)
                    .frame(width: 26, height: 26)
                    .background(color.opacity(0.12), in: RoundedRectangle(cornerRadius: 7, style: .continuous))
                Text(label.uppercased())
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .tracking(0.5)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }
            Text(value)
                .font(.title2.weight(.semibold))
                .fontDesign(.rounded)
                .monospacedDigit()
                .foregroundStyle(valueColor ?? color)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
            if let sub {
                Text(sub).font(.caption2).foregroundStyle(.secondary).lineLimit(1)
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background {
            ZStack {
                shape.fill(.regularMaterial)
                if emphasize { shape.fill(color.opacity(0.06)) }
            }
        }
        .overlay(shape.strokeBorder(emphasize ? color.opacity(0.5) : Color.secondary.opacity(0.12), lineWidth: 1))
    }
}

// MARK: - Thin progress bar

struct GradeProgressBar: View {
    /// 0…1
    let value: Double
    let color: Color
    var height: CGFloat = 8

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Capsule().fill(color.opacity(0.15))
                Capsule().fill(color).frame(width: geo.size.width * min(1, max(0, value)))
            }
        }
        .frame(height: height)
    }
}

// MARK: - Small grey category pill (web assignment-row category box)

struct GradeCategoryPill: View {
    let text: String
    var body: some View {
        Text(text)
            .font(.system(size: 10))
            .lineLimit(1)
            .padding(.horizontal, 6).padding(.vertical, 2)
            .background(Color.secondary.opacity(0.12), in: Capsule())
            .foregroundStyle(.secondary)
    }
}

// MARK: - Info box (web Alert severity="info" variant="outlined")

struct GradeInfoBox<Content: View>: View {
    @ViewBuilder var content: Content
    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: "info.circle").foregroundStyle(Color.accentColor).padding(.top, 1)
            content.frame(maxWidth: .infinity, alignment: .leading)
        }
        .font(.subheadline)
        .padding(12)
        .background(Color.accentColor.opacity(0.05), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(Color.accentColor.opacity(0.35), lineWidth: 1))
    }
}

// MARK: - Wrapping chip row

struct GradesFlowLayout: Layout {
    var spacing: CGFloat = 6

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let maxWidth = proposal.width ?? .greatestFiniteMagnitude
        var x: CGFloat = 0, y: CGFloat = 0, rowHeight: CGFloat = 0, widest: CGFloat = 0
        for s in subviews {
            let size = s.sizeThatFits(.unspecified)
            if x > 0, x + size.width > maxWidth {
                x = 0; y += rowHeight + spacing; rowHeight = 0
            }
            x += size.width + spacing
            rowHeight = max(rowHeight, size.height)
            widest = max(widest, x - spacing)
        }
        return CGSize(width: proposal.width ?? widest, height: y + rowHeight)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var x = bounds.minX, y = bounds.minY, rowHeight: CGFloat = 0
        for s in subviews {
            let size = s.sizeThatFits(.unspecified)
            if x > bounds.minX, x + size.width > bounds.maxX {
                x = bounds.minX; y += rowHeight + spacing; rowHeight = 0
            }
            s.place(at: CGPoint(x: x, y: y), proposal: ProposedViewSize(size))
            x += size.width + spacing
            rowHeight = max(rowHeight, size.height)
        }
    }
}
