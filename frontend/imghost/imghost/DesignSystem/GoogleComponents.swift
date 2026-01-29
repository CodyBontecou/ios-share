import SwiftUI

// MARK: - Google Text Field

struct GoogleTextField: View {
    let label: String
    @Binding var text: String
    var isSecure: Bool = false
    var keyboardType: UIKeyboardType = .default
    var textContentType: UITextContentType?
    var autocapitalization: TextInputAutocapitalization = .sentences

    @FocusState private var isFocused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: GoogleSpacing.xxxs) {
            // Floating label when focused or has text
            if isFocused || !text.isEmpty {
                Text(label)
                    .googleTypography(.labelSmall, color: isFocused ? .googleBlue : .googleTextSecondary)
                    .animation(.easeInOut(duration: 0.15), value: isFocused)
            }

            Group {
                if isSecure {
                    SecureField(isFocused || !text.isEmpty ? "" : label, text: $text)
                } else {
                    TextField(isFocused || !text.isEmpty ? "" : label, text: $text)
                        .keyboardType(keyboardType)
                        .textContentType(textContentType)
                        .textInputAutocapitalization(autocapitalization)
                }
            }
            .focused($isFocused)
            .autocorrectionDisabled()
            .padding(.horizontal, GoogleSpacing.sm)
            .padding(.vertical, GoogleSpacing.xs)
            .background(
                RoundedRectangle(cornerRadius: GoogleCornerRadius.sm)
                    .stroke(isFocused ? Color.googleBlue : Color.googleOutline, lineWidth: isFocused ? 2 : 1)
            )
        }
    }
}

// MARK: - Google Primary Button

struct GooglePrimaryButton: View {
    let title: String
    let action: () -> Void
    var isLoading: Bool = false
    var isDisabled: Bool = false
    var icon: String? = nil

    var body: some View {
        Button(action: action) {
            HStack(spacing: GoogleSpacing.xxs) {
                if isLoading {
                    ProgressView()
                        .progressViewStyle(CircularProgressViewStyle(tint: .white))
                        .scaleEffect(0.8)
                } else {
                    if let icon = icon {
                        Image(systemName: icon)
                            .font(.system(size: GoogleIconSize.sm))
                    }
                    Text(title)
                        .googleTypography(.labelLarge, color: .white)
                }
            }
            .frame(maxWidth: .infinity)
            .frame(height: 48)
            .background(
                RoundedRectangle(cornerRadius: GoogleCornerRadius.full)
                    .fill(isDisabled ? Color.googleBlue.opacity(0.5) : Color.googleBlue)
            )
        }
        .disabled(isDisabled || isLoading)
    }
}

// MARK: - Google Secondary Button

struct GoogleSecondaryButton: View {
    let title: String
    let action: () -> Void
    var isLoading: Bool = false
    var isDisabled: Bool = false
    var icon: String? = nil

    var body: some View {
        Button(action: action) {
            HStack(spacing: GoogleSpacing.xxs) {
                if isLoading {
                    ProgressView()
                        .progressViewStyle(CircularProgressViewStyle(tint: .googleBlue))
                        .scaleEffect(0.8)
                } else {
                    if let icon = icon {
                        Image(systemName: icon)
                            .font(.system(size: GoogleIconSize.sm))
                    }
                    Text(title)
                        .googleTypography(.labelLarge, color: .googleBlue)
                }
            }
            .frame(maxWidth: .infinity)
            .frame(height: 48)
            .background(
                RoundedRectangle(cornerRadius: GoogleCornerRadius.full)
                    .stroke(Color.googleOutline, lineWidth: 1)
            )
        }
        .disabled(isDisabled || isLoading)
    }
}

// MARK: - Google Text Button

struct GoogleTextButton: View {
    let title: String
    let action: () -> Void
    var color: Color = .googleBlue

    var body: some View {
        Button(action: action) {
            Text(title)
                .googleTypography(.labelLarge, color: color)
        }
    }
}

// MARK: - Avatar View

struct AvatarView: View {
    let email: String
    var size: CGFloat = 40
    var backgroundColor: Color = .googleBlue

    private var initials: String {
        let components = email.components(separatedBy: "@").first ?? email
        let firstChar = components.first.map(String.init) ?? "?"
        return firstChar.uppercased()
    }

    var body: some View {
        ZStack {
            Circle()
                .fill(backgroundColor)
            Text(initials)
                .font(.system(size: size * 0.45, weight: .medium))
                .foregroundStyle(.white)
        }
        .frame(width: size, height: size)
    }
}

// MARK: - Circular Storage View

struct CircularStorageView: View {
    let usedBytes: Int
    let limitBytes: Int
    var size: CGFloat = 120
    var lineWidth: CGFloat = 12

    private var percentage: Double {
        guard limitBytes > 0 else { return 0 }
        return min(Double(usedBytes) / Double(limitBytes), 1.0)
    }

    private var strokeColor: Color {
        if percentage > 0.9 {
            return .googleRed
        } else if percentage > 0.7 {
            return .googleYellow
        } else {
            return .googleBlue
        }
    }

    private var formattedUsed: String {
        formatBytes(usedBytes)
    }

    private var formattedLimit: String {
        formatBytes(limitBytes)
    }

    private func formatBytes(_ bytes: Int) -> String {
        let formatter = ByteCountFormatter()
        formatter.allowedUnits = [.useGB, .useMB, .useKB]
        formatter.countStyle = .binary
        return formatter.string(fromByteCount: Int64(bytes))
    }

    var body: some View {
        ZStack {
            // Background circle
            Circle()
                .stroke(Color.googleOutline.opacity(0.3), lineWidth: lineWidth)

            // Progress arc
            Circle()
                .trim(from: 0, to: CGFloat(percentage))
                .stroke(strokeColor, style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
                .rotationEffect(.degrees(-90))
                .animation(.easeInOut(duration: 0.5), value: percentage)

            // Center text
            VStack(spacing: GoogleSpacing.xxxs) {
                Text(formattedUsed)
                    .googleTypography(.titleMedium)
                Text("of \(formattedLimit)")
                    .googleTypography(.labelSmall, color: .googleTextSecondary)
            }
        }
        .frame(width: size, height: size)
    }
}

// MARK: - Google Card

struct GoogleCard<Content: View>: View {
    let content: Content
    var backgroundColor: Color = .googleSurfaceSecondary
    var padding: CGFloat = GoogleSpacing.sm

    init(backgroundColor: Color = .googleSurfaceSecondary, padding: CGFloat = GoogleSpacing.sm, @ViewBuilder content: () -> Content) {
        self.content = content()
        self.backgroundColor = backgroundColor
        self.padding = padding
    }

    var body: some View {
        content
            .padding(padding)
            .background(
                RoundedRectangle(cornerRadius: GoogleCornerRadius.md)
                    .fill(backgroundColor)
            )
    }
}

// MARK: - Selection Checkmark

struct SelectionCheckmark: View {
    let isSelected: Bool
    var size: CGFloat = 24

    var body: some View {
        ZStack {
            Circle()
                .fill(isSelected ? Color.googleBlue : Color.white.opacity(0.7))
                .frame(width: size, height: size)

            if isSelected {
                Image(systemName: "checkmark")
                    .font(.system(size: size * 0.5, weight: .bold))
                    .foregroundStyle(.white)
            } else {
                Circle()
                    .stroke(Color.white, lineWidth: 2)
                    .frame(width: size, height: size)
            }
        }
        .shadow(color: .black.opacity(0.3), radius: 2, x: 0, y: 1)
    }
}

// MARK: - Settings Row

struct SettingsRow: View {
    let icon: String
    let title: String
    var subtitle: String? = nil
    var iconColor: Color = .googleTextSecondary
    var showChevron: Bool = true
    var action: (() -> Void)? = nil

    var body: some View {
        Button(action: { action?() }) {
            HStack(spacing: GoogleSpacing.sm) {
                Image(systemName: icon)
                    .font(.system(size: GoogleIconSize.md))
                    .foregroundStyle(iconColor)
                    .frame(width: 28)

                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .googleTypography(.bodyLarge, color: .googleTextPrimary)

                    if let subtitle = subtitle {
                        Text(subtitle)
                            .googleTypography(.bodySmall, color: .googleTextSecondary)
                    }
                }

                Spacer()

                if showChevron {
                    Image(systemName: "chevron.right")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(Color.googleTextTertiary)
                }
            }
            .padding(.vertical, GoogleSpacing.xs)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Divider with Label

struct GoogleDivider: View {
    var label: String? = nil

    var body: some View {
        HStack(spacing: GoogleSpacing.sm) {
            Rectangle()
                .fill(Color.googleOutline)
                .frame(height: 1)

            if let label = label {
                Text(label)
                    .googleTypography(.labelMedium, color: .googleTextSecondary)

                Rectangle()
                    .fill(Color.googleOutline)
                    .frame(height: 1)
            }
        }
    }
}

// MARK: - App Logo

struct AppLogo: View {
    var size: CGFloat = 80

    var body: some View {
        ZStack {
            // Background with gradient
            RoundedRectangle(cornerRadius: size * 0.22)
                .fill(
                    LinearGradient(
                        colors: [.googleBlue, .googleGreen],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .frame(width: size, height: size)

            // Photo icon
            Image(systemName: "photo.on.rectangle.angled")
                .font(.system(size: size * 0.45, weight: .medium))
                .foregroundStyle(.white)
        }
    }
}
