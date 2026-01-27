import SwiftUI

// MARK: - Google Brand Colors

extension Color {
    // Primary Google Colors
    static let googleBlue = Color(hex: "4285F4")
    static let googleRed = Color(hex: "EA4335")
    static let googleYellow = Color(hex: "FBBC05")
    static let googleGreen = Color(hex: "34A853")

    // Surface Colors
    static let googleSurface = Color(.systemBackground)
    static let googleSurfaceSecondary = Color(.secondarySystemBackground)
    static let googleSurfaceTertiary = Color(.tertiarySystemBackground)

    // Text Colors
    static let googleTextPrimary = Color(.label)
    static let googleTextSecondary = Color(.secondaryLabel)
    static let googleTextTertiary = Color(.tertiaryLabel)

    // Semantic Colors
    static let googleError = Color(hex: "EA4335")
    static let googleSuccess = Color(hex: "34A853")
    static let googleWarning = Color(hex: "FBBC05")

    // Outline Colors
    static let googleOutline = Color(.separator)
    static let googleOutlineVariant = Color(.opaqueSeparator)

    // Gradient for app branding
    static let googleGradientStart = Color(hex: "4285F4")
    static let googleGradientEnd = Color(hex: "34A853")

    // Hex initializer
    init(hex: String) {
        let hex = hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        var int: UInt64 = 0
        Scanner(string: hex).scanHexInt64(&int)
        let a, r, g, b: UInt64
        switch hex.count {
        case 3: // RGB (12-bit)
            (a, r, g, b) = (255, (int >> 8) * 17, (int >> 4 & 0xF) * 17, (int & 0xF) * 17)
        case 6: // RGB (24-bit)
            (a, r, g, b) = (255, int >> 16, int >> 8 & 0xFF, int & 0xFF)
        case 8: // ARGB (32-bit)
            (a, r, g, b) = (int >> 24, int >> 16 & 0xFF, int >> 8 & 0xFF, int & 0xFF)
        default:
            (a, r, g, b) = (1, 1, 1, 0)
        }
        self.init(
            .sRGB,
            red: Double(r) / 255,
            green: Double(g) / 255,
            blue: Double(b) / 255,
            opacity: Double(a) / 255
        )
    }
}

// MARK: - Google Gradient

struct GoogleGradient: View {
    var body: some View {
        LinearGradient(
            colors: [.googleBlue, .googleGreen],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }
}

struct GoogleBrandGradient: View {
    var body: some View {
        LinearGradient(
            colors: [.googleBlue, .googleRed, .googleYellow, .googleGreen],
            startPoint: .leading,
            endPoint: .trailing
        )
    }
}
