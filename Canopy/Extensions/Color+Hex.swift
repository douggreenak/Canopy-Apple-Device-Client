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

    /// WCAG-AA text colour on top of `bgHex`: white when it clears 4.5:1, else near-black (web contrastTextFor).
    static func contrastText(on bgHex: String) -> Color {
        Color.contrastRatio(bgHex, "#ffffff") >= 4.5 ? .white : Color.black.opacity(0.87)
    }

    static func contrastRatio(_ a: String, _ b: String) -> Double {
        func lum(_ hex: String) -> Double {
            let h = hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
            var int: UInt64 = 0
            Scanner(string: h).scanHexInt64(&int)
            let r, g, b: Double
            if h.count == 3 {
                r = Double((int >> 8) * 17); g = Double((int >> 4 & 0xF) * 17); b = Double((int & 0xF) * 17)
            } else {
                r = Double(int >> 16 & 0xFF); g = Double(int >> 8 & 0xFF); b = Double(int & 0xFF)
            }
            func lin(_ c: Double) -> Double { let cs = c / 255; return cs <= 0.03928 ? cs / 12.92 : pow((cs + 0.055) / 1.055, 2.4) }
            return 0.2126 * lin(r) + 0.7152 * lin(g) + 0.0722 * lin(b)
        }
        let la = lum(a), lb = lum(b)
        let (hi, lo) = la > lb ? (la, lb) : (lb, la)
        return (hi + 0.05) / (lo + 0.05)
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
    /// Relative label for a yyyy-MM-dd date string. Delegates to
    /// GradesUtil.relativeDueLabel (Today/Tomorrow/Yesterday/"In N days"/
    /// "N days ago"/MMM d/MMM d, yyyy) so every call site across the app shares
    /// one implementation matching web's exact relativeDueLabel rules, instead
    /// of the previous simplified Today/Tomorrow-only version.
    var dueDateLabel: String {
        GradesUtil.relativeDueLabel(self)
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
            // Expand hit area to 44×44 without affecting the visual circle size
            .frame(width: 44, height: 44)
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

    /// Completely hides the iOS navigation bar and reclaims its ~44 pt of height.
    /// No-op on macOS — `.navigationBar` placement is unavailable there.
    func iosHideNavigationBar() -> some View {
        #if os(iOS)
        self.toolbar(.hidden, for: .navigationBar)
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
            .overlay(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .strokeBorder(Color.secondary.opacity(0.12), lineWidth: 0.5)
            )
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
        case "Other":    return .pink
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


// MARK: - Solid class chip (web: class-colour bg + contrast text)
struct ClassChip: View {
    let name: String
    let hex: String
    var compact = false
    var body: some View {
        Text(name)
            .font(compact ? .caption2.weight(.semibold) : .caption.weight(.semibold))
            .lineLimit(1)
            .padding(.horizontal, compact ? 6 : 8).padding(.vertical, compact ? 2 : 3)
            .background(Color(hex: hex), in: Capsule())
            .foregroundStyle(Color.contrastText(on: hex))
    }
}

// MARK: - Outlined chip
struct OutlinedChip: View {
    let text: String
    var systemImage: String? = nil
    var color: Color = .secondary
    var body: some View {
        HStack(spacing: 3) {
            if let systemImage { Image(systemName: systemImage).font(.system(size: 9, weight: .semibold)) }
            Text(text)
        }
        .font(.caption2.weight(.medium))
        .lineLimit(1)
        .padding(.horizontal, 7).padding(.vertical, 2)
        .overlay(Capsule().strokeBorder(color.opacity(0.6), lineWidth: 1))
        .foregroundStyle(color)
    }
}

// MARK: - Filled tinted chip
struct TintedChip: View {
    let text: String
    var systemImage: String? = nil
    var color: Color = .accentColor
    var body: some View {
        HStack(spacing: 3) {
            if let systemImage { Image(systemName: systemImage).font(.system(size: 9, weight: .semibold)) }
            Text(text)
        }
        .font(.caption2.weight(.semibold))
        .lineLimit(1)
        .padding(.horizontal, 7).padding(.vertical, 2)
        .background(color.opacity(0.16), in: Capsule())
        .foregroundStyle(color)
    }
}

// MARK: - Transient bottom toast (web Snackbar)
struct ToastMessage: Equatable, Identifiable {
    enum Kind { case info, success, error }
    let id = UUID()
    let text: String
    var kind: Kind = .info
    var actionLabel: String? = nil
    var action: (() -> Void)? = nil
    static func == (a: ToastMessage, b: ToastMessage) -> Bool { a.id == b.id }
}

struct ToastModifier: ViewModifier {
    @Binding var toast: ToastMessage?
    var duration: Double = 5
    func body(content: Content) -> some View {
        content.overlay(alignment: .bottom) {
            if let t = toast {
                HStack(spacing: 10) {
                    Image(systemName: t.kind == .error ? "exclamationmark.triangle.fill" : t.kind == .success ? "checkmark.circle.fill" : "info.circle.fill")
                        .foregroundStyle(t.kind == .error ? Color.red : t.kind == .success ? Color.green : Color.accentColor)
                    Text(t.text).font(.subheadline).lineLimit(3)
                    if let label = t.actionLabel {
                        Spacer(minLength: 4)
                        Button(label) { t.action?(); toast = nil }.font(.subheadline.bold())
                    }
                }
                .padding(.horizontal, 14).padding(.vertical, 11)
                .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                .shadow(color: .black.opacity(0.15), radius: 10, y: 4)
                .padding(.horizontal, 16).padding(.bottom, 8)
                .transition(.move(edge: .bottom).combined(with: .opacity))
                .task(id: t.id) {
                    try? await Task.sleep(nanoseconds: UInt64(duration * 1_000_000_000))
                    if toast?.id == t.id { withAnimation { toast = nil } }
                }
            }
        }
        .animation(.spring(response: 0.35, dampingFraction: 0.8), value: toast)
    }
}

extension View {
    func toast(_ toast: Binding<ToastMessage?>, duration: Double = 5) -> some View {
        modifier(ToastModifier(toast: toast, duration: duration))
    }
}

// MARK: - Inline autosave status (web InlineSaveIndicator)
enum AutosaveStatus { case idle, saving, saved, error }

struct InlineSaveIndicator: View {
    let status: AutosaveStatus
    var body: some View {
        Group {
            switch status {
            case .idle: EmptyView()
            case .saving: HStack(spacing: 4) { ProgressView().controlSize(.mini); Text("Saving…") }
            case .saved: Label("Saved", systemImage: "checkmark.circle.fill").foregroundStyle(.green)
            case .error: Label("Couldn't save — check your connection", systemImage: "exclamationmark.circle.fill").foregroundStyle(.red)
            }
        }
        .font(.caption)
        .foregroundStyle(.secondary)
        .animation(.easeInOut(duration: 0.2), value: status == .idle)
    }
}
