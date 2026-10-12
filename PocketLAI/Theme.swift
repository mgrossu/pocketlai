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

/// Soft brand-colored backdrop, so Liquid Glass surfaces have something to refract.
struct AppBackground: View {
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        let strength = colorScheme == .dark ? 0.35 : 0.22
        ZStack {
            Color(.systemBackground)
            Circle()
                .fill(Color.brandCyan.opacity(strength))
                .frame(width: 420, height: 420)
                .blur(radius: 120)
                .offset(x: -140, y: -300)
            Circle()
                .fill(Color.brandPurple.opacity(strength))
                .frame(width: 460, height: 460)
                .blur(radius: 130)
                .offset(x: 160, y: 320)
        }
        .ignoresSafeArea()
    }
}
