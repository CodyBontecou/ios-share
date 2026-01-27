import SwiftUI

// MARK: - Spacing System (4pt base unit)

enum GoogleSpacing {
    /// 4pt
    static let xxxs: CGFloat = 4
    /// 8pt
    static let xxs: CGFloat = 8
    /// 12pt
    static let xs: CGFloat = 12
    /// 16pt
    static let sm: CGFloat = 16
    /// 20pt
    static let md: CGFloat = 20
    /// 24pt
    static let lg: CGFloat = 24
    /// 32pt
    static let xl: CGFloat = 32
    /// 40pt
    static let xxl: CGFloat = 40
    /// 48pt
    static let xxxl: CGFloat = 48
    /// 64pt
    static let huge: CGFloat = 64
}

// MARK: - Corner Radii

enum GoogleCornerRadius {
    /// 4pt - Small elements like chips
    static let xs: CGFloat = 4
    /// 8pt - Buttons, small cards
    static let sm: CGFloat = 8
    /// 12pt - Cards, dialogs
    static let md: CGFloat = 12
    /// 16pt - Large cards
    static let lg: CGFloat = 16
    /// 24pt - Bottom sheets
    static let xl: CGFloat = 24
    /// 28pt - FAB
    static let xxl: CGFloat = 28
    /// Full circle
    static let full: CGFloat = 9999
}

// MARK: - Icon Sizes

enum GoogleIconSize {
    /// 16pt
    static let xs: CGFloat = 16
    /// 20pt
    static let sm: CGFloat = 20
    /// 24pt - Standard
    static let md: CGFloat = 24
    /// 32pt
    static let lg: CGFloat = 32
    /// 40pt
    static let xl: CGFloat = 40
    /// 48pt
    static let xxl: CGFloat = 48
}

// MARK: - View Extensions

extension View {
    func googlePadding(_ edge: Edge.Set = .all, _ size: CGFloat = GoogleSpacing.sm) -> some View {
        padding(edge, size)
    }

    func googleCornerRadius(_ radius: CGFloat = GoogleCornerRadius.md) -> some View {
        clipShape(RoundedRectangle(cornerRadius: radius))
    }
}

// MARK: - Grid Spacing

enum GoogleGridSpacing {
    /// Gap between grid items
    static let itemSpacing: CGFloat = 2
    /// Standard section header padding
    static let sectionHeaderPadding: CGFloat = 16
    /// Grid content insets
    static let gridInsets: CGFloat = 0
}
