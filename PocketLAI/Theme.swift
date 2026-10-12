import SwiftUI

/// Colors taken from the app icon's gradient.
extension Color {
    static let brandCyan = Color(red: 0.247, green: 0.784, blue: 0.961)
    static let brandPurple = Color(red: 0.478, green: 0.333, blue: 0.941)
}

enum Appearance: String, CaseIterable, Identifiable {
    case system, light, dark

    var id: String { rawValue }

    var title: String {
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
