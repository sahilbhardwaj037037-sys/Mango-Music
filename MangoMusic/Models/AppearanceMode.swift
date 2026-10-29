import SwiftUI

enum AppearanceMode: String, CaseIterable, Identifiable {
    case system, light, dark
    static let storageKey = "appearanceMode"
    var id: Self { self }
    var label: String {
        switch self {
        case .system: "System"
        case .light: "Light"
        case .dark: "Dark"
        }
    }
    var colorScheme: ColorScheme? {
        switch self {
        case .system: nil
        case .light: .light
        case .dark: .dark
        }
    }
}

/// Keep native semantic surfaces/text and the original dark accents. Darker light
/// variants give small highlighted titles and status icons sufficient contrast.
enum ThemePalette {
    static func accent(for scheme: ColorScheme) -> Color {
        scheme == .dark ? .pink : Color(red: 0.68, green: 0.06, blue: 0.28)
    }
    static func success(for scheme: ColorScheme) -> Color {
        scheme == .dark ? .green : Color(red: 0.10, green: 0.40, blue: 0.18)
    }
    static func selectionFill(for scheme: ColorScheme) -> Color {
        accent(for: scheme).opacity(0.12)
    }
}
