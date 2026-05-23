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
            .shadow(color: .black.opacity(0.06), radius: 10, y: 3)
    }
}

extension View {
    func glassCard(cornerRadius: CGFloat = 20) -> some View {
        modifier(GlassCard(cornerRadius: cornerRadius))
    }
}

// MARK: - Translucent app background (blurs wallpaper / desktop behind window)
struct CanopyBackground: View {
    @AppStorage("backgroundOpacity") private var backgroundOpacity: Double = 0.75
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        ZStack {
            Rectangle()
                .fill(.ultraThinMaterial)
                .ignoresSafeArea()
            // Slider-driven opacity overlay — full range from translucent to near-solid.
            // Dark mode: black overlay; Light mode: white overlay.
            Rectangle()
                .fill(colorScheme == .dark
                      ? Color.black.opacity(backgroundOpacity * 0.88)
                      : Color.white.opacity(backgroundOpacity * 0.92))
                .ignoresSafeArea()
            // Subtle accent tint on top
            LinearGradient(
                colors: [Color.accentColor.opacity(0.04), .clear],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            .ignoresSafeArea()
        }
    }
}

// MARK: - Window transparency
// Apply .makeWindowTransparent() at the root so materials can blur
// the system wallpaper (iOS) or desktop content (macOS) behind the window.
extension View {
    func makeWindowTransparent() -> some View {
        modifier(WindowTransparencyModifier())
    }
}

private struct WindowTransparencyModifier: ViewModifier {
    func body(content: Content) -> some View {
        content
            #if os(macOS)
            .background(MacWindowTransparencyAccessor())
            #else
            .onAppear(perform: applyIOSWindowTransparency)
            #endif
    }

    #if !os(macOS)
    private func applyIOSWindowTransparency() {
        UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .flatMap { $0.windows }
            .forEach {
                $0.backgroundColor = .clear
                $0.isOpaque = false
            }
    }
    #endif
}

#if os(macOS)
/// Zero-size NSView whose sole job is to reach up to NSWindow and clear its background.
private struct MacWindowTransparencyAccessor: NSViewRepresentable {
    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        DispatchQueue.main.async {
            guard let window = view.window else { return }
            window.isOpaque = false
            window.backgroundColor = .clear
            window.hasShadow = true
            window.titlebarAppearsTransparent = true
            window.styleMask.insert(.fullSizeContentView)
        }
        return view
    }
    func updateNSView(_ view: NSView, context: Context) {
        guard let window = view.window else { return }
        window.isOpaque = false
        window.backgroundColor = .clear
        window.titlebarAppearsTransparent = true
    }
}
#endif

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

    /// Hides the navigation bar background on iOS so tab-view filter bars aren't doubled-up.
    /// No-op on macOS (navigationBar placement is unavailable there).
    func iosHideNavBarBackground() -> some View {
        #if os(iOS)
        self.toolbarBackground(.hidden, for: .navigationBar)
        #else
        self
        #endif
    }

    /// Completely hides the iOS navigation bar and reclaims its ~44 pt of height.
    /// No-op on macOS — `.navigationBar` placement is unavailable there.
    func iosHideNavigationBar() -> some View {
        #if os(iOS)
        self.toolbar(.hidden, for: .navigationBar)
        #else
        self
        #endif
    }

    /// Applies ultraThinMaterial to the macOS window toolbar so it matches the app background.
    /// No-op on iOS (tab bar handled separately via UITabBarAppearance).
    func canopyWindowToolbar() -> some View {
        #if os(macOS)
        self
            .toolbarBackground(.ultraThinMaterial, for: .windowToolbar)
            .toolbarBackground(.visible, for: .windowToolbar)
        #else
        self
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
        .foregroundStyle(selection == value ? color : .secondary)
        .contentShape(Rectangle())
        .onTapGesture {
            withAnimation(.spring(response: 0.25, dampingFraction: 0.7)) { selection = value }
        }
    }
}
