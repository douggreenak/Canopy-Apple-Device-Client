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

    // Cross-platform system colors
    static var systemBackground: Color {
        #if os(macOS)
        Color(NSColor.windowBackgroundColor)
        #else
        Color(UIColor.systemBackground)
        #endif
    }
    static var systemGroupedBackground: Color {
        #if os(macOS)
        Color(NSColor.windowBackgroundColor)
        #else
        Color(UIColor.systemGroupedBackground)
        #endif
    }
    static var systemFill: Color {
        #if os(macOS)
        Color(NSColor.controlColor)
        #else
        Color(UIColor.systemFill)
        #endif
    }
    static var tertiaryLabel: Color {
        #if os(macOS)
        Color(NSColor.tertiaryLabelColor)
        #else
        Color(UIColor.tertiaryLabel)
        #endif
    }
}

// MARK: - Priority color
extension String {
    var priorityColor: Color {
        switch self {
        case "high":   return .red
        case "medium": return .orange
        default:       return Color.tertiaryLabel
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
                    .strokeBorder(.secondary.opacity(0.15), lineWidth: 0.5)
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
            Color.systemGroupedBackground.ignoresSafeArea()
            LinearGradient(
                colors: [Color.accentColor.opacity(0.07), .clear],
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
        Circle()
            .fill(priority.priorityColor)
            .frame(width: 8, height: 8)
            .accessibilityLabel("\(priority.capitalized) priority")
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

// MARK: - Animated circular checkbox
struct AnimatedCheckButton: View {
    let checked: Bool
    let action: () -> Void
    @State private var bounce: CGFloat = 1.0

    var body: some View {
        Button {
            // Spring bounce on tap
            withAnimation(.spring(response: 0.13, dampingFraction: 0.35)) { bounce = 1.28 }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.08) {
                withAnimation(.spring(response: 0.3, dampingFraction: 0.6)) { bounce = 1.0 }
            }
            action()
        } label: {
            ZStack {
                Circle()
                    .fill(checked ? Color.accentColor : Color.clear)
                Circle()
                    .strokeBorder(
                        checked ? Color.accentColor : Color.secondary.opacity(0.3),
                        lineWidth: 1.5
                    )
                Image(systemName: "checkmark")
                    .font(.caption2.weight(.bold))
                    .foregroundStyle(.white)
                    .opacity(checked ? 1 : 0)
                    .scaleEffect(checked ? 1 : 0.4)
            }
            .frame(width: 26, height: 26)
            .scaleEffect(bounce)
            .animation(.spring(response: 0.3, dampingFraction: 0.65), value: checked)
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Cross-platform modifiers
extension View {
    func navigationBarTitleLarge() -> some View {
        self.toolbarTitleDisplayMode(.automatic)
    }

    func navigationBarTitleInline() -> some View {
        self.toolbarTitleDisplayMode(.inline)
    }

    func insetGroupedListStyle() -> some View {
        #if os(macOS)
        self.listStyle(.inset)
        #else
        self.listStyle(.insetGrouped)
        #endif
    }

    func textAutocapNever() -> some View {
        #if os(macOS)
        self
        #else
        self.textInputAutocapitalization(.never)
        #endif
    }

    /// Uses .wheel on iOS (natural time/value drum roll), .menu on macOS (no wheel available)
    func wheelPickerStyle() -> some View {
        #if os(macOS)
        self.pickerStyle(.menu)
        #else
        self.pickerStyle(.wheel)
        #endif
    }
}

// MARK: - Premium UI Components

struct CanopyIconView: View {
    var size: CGFloat = 92
    var body: some View {
        ZStack {
            Circle()
                .fill(.regularMaterial)
                .overlay(
                    Circle().strokeBorder(
                        LinearGradient(
                            colors: [Color.accentColor.opacity(0.5), Color.accentColor.opacity(0.15)],
                            startPoint: .topLeading, endPoint: .bottomTrailing
                        ),
                        lineWidth: 1
                    )
                )
                .frame(width: size, height: size)
                .shadow(color: Color.accentColor.opacity(0.25), radius: size * 0.3, y: size * 0.08)

            Image(systemName: "tree.fill")
                .font(.system(size: size * 0.45, weight: .medium))
                .foregroundStyle(Color.accentColor)
        }
    }
}

struct FormEditCard<Content: View>: View {
    let content: Content
    init(@ViewBuilder content: () -> Content) { self.content = content() }
    
    var body: some View {
        content
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous)
                .strokeBorder(.separator.opacity(0.5), lineWidth: 0.5))
    }
}

struct CategoryBadge: View {
    let category: String
    var body: some View {
        Text(category)
            .font(.caption2.bold())
            .padding(.horizontal, 7).padding(.vertical, 2)
            .background(categoryColor.opacity(0.18), in: Capsule())
            .foregroundStyle(categoryColor)
    }
    private var categoryColor: Color {
        switch category {
        case "Ask":      return .orange
        case "Study":    return .blue
        case "Project":  return .purple
        case "Homework": return .accentColor
        case "Reading":  return .teal
        case "Practice": return .indigo
        default:         return .secondary
        }
    }
}

struct PriorityPill: View {
    let value: String
    let label: String
    let color: Color
    @Binding var selection: String

    var body: some View {
        Button {
            withAnimation(.spring(response: 0.25, dampingFraction: 0.7)) { selection = value }
        } label: {
            HStack(spacing: 5) {
                Circle().fill(color).frame(width: 7, height: 7)
                Text(label)
                    .font(.subheadline.weight(selection == value ? .semibold : .regular))
            }
            .padding(.horizontal, 12).padding(.vertical, 8)
            .frame(maxWidth: .infinity)
            .background(
                selection == value ? color.opacity(0.13) : Color.clear,
                in: RoundedRectangle(cornerRadius: 9, style: .continuous)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 9, style: .continuous)
                    .strokeBorder(
                        selection == value ? color.opacity(0.45) : Color.secondary.opacity(0.25),
                        lineWidth: 1
                    )
            )
        }
        .buttonStyle(.plain)
        .foregroundStyle(selection == value ? color : .secondary)
    }
}
