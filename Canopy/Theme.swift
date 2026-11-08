import SwiftUI

// MARK: - Accent color presets (mirrors web src/lib/theme.ts ACCENT_PRESETS)
//
// Each preset carries a light-mode and a dark-mode calibration. The stored
// `accentColor` setting is the preset NAME (web convention); a legacy raw
// hex value falls back to the default, exactly as the web does.

struct AccentPreset: Identifiable, Hashable {
    let name: String
    let primary: String      // light-mode hex
    let primaryDark: String  // dark-mode hex
    var id: String { name }

    func hex(for scheme: ColorScheme) -> String { scheme == .dark ? primaryDark : primary }
    func color(for scheme: ColorScheme) -> Color { Color(hex: hex(for: scheme)) }
}

enum AccentPalette {
    static let presets: [AccentPreset] = [
        .init(name: "Canopy",  primary: "#2E7D32", primaryDark: "#6FAE72"),
        .init(name: "Alaska",  primary: "#01426A", primaryDark: "#3AA3E0"),
        .init(name: "Glacier", primary: "#00695C", primaryDark: "#5CA79C"),
        .init(name: "Aurora",  primary: "#3949AB", primaryDark: "#8C97D4"),
        .init(name: "Sunset",  primary: "#BF360C", primaryDark: "#E08064"),
        .init(name: "Harbor",  primary: "#26418F", primaryDark: "#8C9AC9"),
        .init(name: "Berry",   primary: "#8E1550", primaryDark: "#CC88AC"),
        .init(name: "Slate",   primary: "#37474F", primaryDark: "#93A0A6"),
    ]

    static let defaultAccent = "Canopy"

    /// Case-insensitive name lookup; unknown/hex → default (web resolveAccentPreset).
    static func resolve(_ nameOrLegacy: String?) -> AccentPreset {
        presets.first { $0.name.caseInsensitiveCompare(nameOrLegacy ?? "") == .orderedSame } ?? presets[0]
    }

    static func name(for value: String?) -> String { resolve(value).name }
}

// MARK: - Semantic palette (web theme.ts error/warning/success/info)
enum CanopyPalette {
    static func error(_ s: ColorScheme) -> Color   { Color(hex: s == .dark ? "#f28b82" : "#d93025") }
    static func warning(_ s: ColorScheme) -> Color { Color(hex: s == .dark ? "#fdd663" : "#f9ab00") }
    static func success(_ s: ColorScheme) -> Color { Color(hex: s == .dark ? "#81c995" : "#2E7D32") }
    static func info(_ s: ColorScheme) -> Color    { Color(hex: s == .dark ? "#4fc3f7" : "#0277BD") }
}
