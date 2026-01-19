import SwiftUI

enum Theme {
    static let accent = Color(red: 0.07, green: 0.42, blue: 0.40)
    static let backgroundTop = Color(red: 0.93, green: 0.93, blue: 0.92)
    static let backgroundBottom = Color(red: 0.81, green: 0.88, blue: 0.90)
    static let cardBackground = Color(red: 0.97, green: 0.97, blue: 0.96)
    static let subtleBorder = Color.black.opacity(0.08)
    static let textPrimary = Color(red: 0.05, green: 0.09, blue: 0.12)
    static let textSecondary = Color(red: 0.20, green: 0.26, blue: 0.30)
    static let textTertiary = Color(red: 0.34, green: 0.39, blue: 0.43)
    static let glow = Color(red: 0.08, green: 0.50, blue: 0.48).opacity(0.18)

    static func titleFont() -> Font {
        font(30, weight: .semibold)
    }

    static func sectionFont() -> Font {
        font(12, weight: .semibold)
    }

    static func font(_ size: CGFloat, weight: Font.Weight = .regular) -> Font {
        .custom("Avenir Next", size: size).weight(weight)
    }
}
