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
///
/// Use it only via `.background { AppBackground() }`. It must never take part in layout:
/// it fills the whole screen (including under the keyboard), and as a layout child it
/// would make content wider than the screen and push the input bar behind the keyboard.
struct AppBackground: View {
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        let strength = colorScheme == .dark ? 0.35 : 0.22
        Color(.systemBackground)
            .overlay {
                // Gradient glows sized relative to the screen, so nothing overflows it.
                GeometryReader { proxy in
                    let size = proxy.size
                    Circle()
                        .fill(Color.brandCyan.opacity(strength))
                        .frame(width: size.width * 1.1, height: size.width * 1.1)
                        .blur(radius: 120)
                        .position(x: size.width * 0.15, y: size.height * 0.12)
                    Circle()
                        .fill(Color.brandPurple.opacity(strength))
                        .frame(width: size.width * 1.2, height: size.width * 1.2)
                        .blur(radius: 130)
                        .position(x: size.width * 0.85, y: size.height * 0.88)
                }
            }
            .clipped()
            .ignoresSafeArea()
    }
}
