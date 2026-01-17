import SwiftUI

enum Theme {
    static let accent = Color(red: 0.18, green: 0.35, blue: 0.30)
    static let backgroundTop = Color(red: 0.96, green: 0.97, blue: 0.95)
    static let backgroundBottom = Color(red: 0.90, green: 0.94, blue: 0.92)
    static let cardBackground = Color.white
    static let subtleBorder = Color.black.opacity(0.05)

    static func titleFont() -> Font {
        .system(size: 28, weight: .semibold, design: .rounded)
    }

    static func sectionFont() -> Font {
        .system(size: 13, weight: .semibold, design: .rounded)
    }
}
