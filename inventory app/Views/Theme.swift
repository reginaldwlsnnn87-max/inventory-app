import SwiftUI

enum Theme {
    static let accent = Color(red: 0.18, green: 0.35, blue: 0.30)
    static let backgroundTop = Color(red: 0.94, green: 0.96, blue: 0.93)
    static let backgroundBottom = Color(red: 0.86, green: 0.91, blue: 0.89)
    static let cardBackground = Color(red: 0.99, green: 0.99, blue: 0.98)
    static let subtleBorder = Color.black.opacity(0.05)
    static let textPrimary = Color(red: 0.10, green: 0.16, blue: 0.14)
    static let textSecondary = Color(red: 0.28, green: 0.34, blue: 0.32)
    static let textTertiary = Color(red: 0.45, green: 0.50, blue: 0.47)

    static func titleFont() -> Font {
        .system(size: 28, weight: .semibold, design: .rounded)
    }

    static func sectionFont() -> Font {
        .system(size: 13, weight: .semibold, design: .rounded)
    }
}
