import SwiftUI

// MARK: - Hex color initializer
extension Color {
    init(hex: String) {
        let hex = hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        var int: UInt64 = 0
        Scanner(string: hex).scanHexInt64(&int)
        let a, r, g, b: UInt64
        switch hex.count {
        case 3:  (a, r, g, b) = (255, (int >> 8) * 17, (int >> 4 & 0xF) * 17, (int & 0xF) * 17)
        case 6:  (a, r, g, b) = (255, int >> 16, int >> 8 & 0xFF, int & 0xFF)
        case 8:  (a, r, g, b) = (int >> 24, int >> 16 & 0xFF, int >> 8 & 0xFF, int & 0xFF)
        default: (a, r, g, b) = (255, 0, 0, 0)
        }
        self.init(.sRGB, red: Double(r)/255, green: Double(g)/255, blue: Double(b)/255, opacity: Double(a)/255)
    }

    static let canopyGreen = Color(hex: "#388E3C")
    static let canopyGreenDark = Color(hex: "#1B5E20")
}

// MARK: - Priority color
extension String {
    var priorityColor: Color {
        switch self {
        case "high":   return .red
        case "medium": return .orange
        default:       return Color(uiColor: .tertiaryLabel)
        }
    }

    var priorityOrder: Int {
        switch self { case "high": return 0; case "medium": return 1; default: return 2 }
    }
}

// MARK: - Shared glass card modifier
struct GlassCard: ViewModifier {
    var cornerRadius: CGFloat = 20

    func body(content: Content) -> some View {
        content
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .strokeBorder(.white.opacity(0.18), lineWidth: 0.5)
            )
            .shadow(color: .black.opacity(0.07), radius: 10, y: 3)
    }
}

extension View {
    func glassCard(cornerRadius: CGFloat = 20) -> some View {
        modifier(GlassCard(cornerRadius: cornerRadius))
    }
}

// MARK: - Screen tinted background
struct CanopyBackground: View {
    var body: some View {
        ZStack {
            Color(uiColor: .systemGroupedBackground).ignoresSafeArea()
            LinearGradient(
                colors: [Color.canopyGreen.opacity(0.07), .clear],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            .ignoresSafeArea()
        }
    }
}

// MARK: - Class color dot
struct ClassColorDot: View {
    let hex: String
    var size: CGFloat = 10
    var body: some View {
        Circle().fill(Color(hex: hex)).frame(width: size, height: size)
    }
}

// MARK: - Priority indicator dot
struct PriorityDot: View {
    let priority: String
    var body: some View {
        Circle().fill(priority.priorityColor).frame(width: 8, height: 8)
    }
}

// MARK: - Due date label
extension String {
    var dueDateLabel: String {
        guard let date = self.asDate else { return self }
        if Calendar.current.isDateInToday(date) { return "Today" }
        if Calendar.current.isDateInTomorrow(date) { return "Tomorrow" }
        let f = DateFormatter()
        f.dateFormat = "MMM d"
        return f.string(from: date)
    }

    var isDueToday: Bool {
        guard let d = asDate else { return false }
        return Calendar.current.isDateInToday(d)
    }

    var isOverdue: Bool {
        guard let d = asDate else { return false }
        return d < Calendar.current.startOfDay(for: .now)
    }
}
