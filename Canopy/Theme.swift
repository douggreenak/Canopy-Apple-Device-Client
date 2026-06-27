import SwiftUI

// MARK: - Accent color palette (mirrors web src/lib/theme.ts ACCENT_PRESETS)

struct AccentPreset: Identifiable, Hashable {
    let name: String
    let color: String
    var id: String { color }
}

enum AccentPalette {
    static let presets: [AccentPreset] = [
        // Greens
        .init(name: "Forest",   color: "#2E7D32"),
        .init(name: "Canopy",   color: "#388E3C"),
        .init(name: "Moss",     color: "#558B2F"),
        .init(name: "Sage",     color: "#7CB342"),
        .init(name: "Jade",     color: "#00796B"),
        .init(name: "Fern",     color: "#33691E"),
        // Blues & Teals
        .init(name: "Teal",     color: "#00838F"),
        .init(name: "Sky",      color: "#0288D1"),
        .init(name: "Ocean",    color: "#0277BD"),
        .init(name: "Navy",     color: "#283593"),
        .init(name: "Slate",    color: "#455A64"),
        // Purples
        .init(name: "Twilight", color: "#3949AB"),
        .init(name: "Violet",   color: "#6A1B9A"),
        .init(name: "Plum",     color: "#880E4F"),
        // Warm
        .init(name: "Gold",     color: "#F57F17"),
        .init(name: "Sunset",   color: "#E65100"),
        .init(name: "Crimson",  color: "#C62828"),
        .init(name: "Earth",    color: "#6D4C41"),
        .init(name: "Dusk",     color: "#4E342E"),
    ]

    static let defaultAccent = "#388E3C" // Canopy green

    static func name(for hex: String) -> String {
        presets.first { $0.color.caseInsensitiveCompare(hex) == .orderedSame }?.name ?? "Custom"
    }
}
