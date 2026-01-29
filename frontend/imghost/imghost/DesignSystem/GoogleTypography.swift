import SwiftUI

// MARK: - Typography Scale

enum GoogleTypography {
    // Display - Large promotional text
    case displayLarge
    case displayMedium
    case displaySmall

    // Headline - High-emphasis text
    case headlineLarge
    case headlineMedium
    case headlineSmall

    // Title - Medium-emphasis text
    case titleLarge
    case titleMedium
    case titleSmall

    // Body - Readable text
    case bodyLarge
    case bodyMedium
    case bodySmall

    // Label - Small utility text
    case labelLarge
    case labelMedium
    case labelSmall

    var font: Font {
        switch self {
        case .displayLarge:
            return .system(size: 57, weight: .regular)
        case .displayMedium:
            return .system(size: 45, weight: .regular)
        case .displaySmall:
            return .system(size: 36, weight: .regular)

        case .headlineLarge:
            return .system(size: 32, weight: .semibold)
        case .headlineMedium:
            return .system(size: 28, weight: .semibold)
        case .headlineSmall:
            return .system(size: 24, weight: .semibold)

        case .titleLarge:
            return .system(size: 22, weight: .medium)
        case .titleMedium:
            return .system(size: 16, weight: .medium)
        case .titleSmall:
            return .system(size: 14, weight: .medium)

        case .bodyLarge:
            return .system(size: 16, weight: .regular)
        case .bodyMedium:
            return .system(size: 14, weight: .regular)
        case .bodySmall:
            return .system(size: 12, weight: .regular)

        case .labelLarge:
            return .system(size: 14, weight: .medium)
        case .labelMedium:
            return .system(size: 12, weight: .medium)
        case .labelSmall:
            return .system(size: 11, weight: .medium)
        }
    }

    var lineHeight: CGFloat {
        switch self {
        case .displayLarge: return 64
        case .displayMedium: return 52
        case .displaySmall: return 44

        case .headlineLarge: return 40
        case .headlineMedium: return 36
        case .headlineSmall: return 32

        case .titleLarge: return 28
        case .titleMedium: return 24
        case .titleSmall: return 20

        case .bodyLarge: return 24
        case .bodyMedium: return 20
        case .bodySmall: return 16

        case .labelLarge: return 20
        case .labelMedium: return 16
        case .labelSmall: return 16
        }
    }
}

// MARK: - View Modifiers

struct GoogleTypographyModifier: ViewModifier {
    let typography: GoogleTypography
    let color: Color

    func body(content: Content) -> some View {
        content
            .font(typography.font)
            .foregroundStyle(color)
            .lineSpacing(typography.lineHeight - 16) // Approximate line height adjustment
    }
}

extension View {
    func googleTypography(_ style: GoogleTypography, color: Color = .googleTextPrimary) -> some View {
        modifier(GoogleTypographyModifier(typography: style, color: color))
    }

    // Convenience modifiers for common uses
    func googleDisplay(_ size: GoogleTypography = .displayMedium) -> some View {
        googleTypography(size)
    }

    func googleHeadline(_ size: GoogleTypography = .headlineMedium) -> some View {
        googleTypography(size)
    }

    func googleTitle(_ size: GoogleTypography = .titleMedium) -> some View {
        googleTypography(size)
    }

    func googleBody(_ size: GoogleTypography = .bodyMedium) -> some View {
        googleTypography(size)
    }

    func googleLabel(_ size: GoogleTypography = .labelMedium) -> some View {
        googleTypography(size, color: .googleTextSecondary)
    }
}
