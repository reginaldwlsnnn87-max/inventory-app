import SwiftUI

enum RemoteTheme {
    static let backgroundTop = Color(red: 0.04, green: 0.05, blue: 0.08)
    static let backgroundMid = Color(red: 0.06, green: 0.08, blue: 0.13)
    static let backgroundBottom = Color(red: 0.015, green: 0.025, blue: 0.045)

    static let card = Color(red: 0.13, green: 0.15, blue: 0.22).opacity(0.90)
    static let cardStrong = Color(red: 0.16, green: 0.18, blue: 0.26).opacity(0.95)
    static let key = Color(red: 0.20, green: 0.23, blue: 0.31)

    static let glassTop = Color.white.opacity(0.11)
    static let glassBottom = Color.white.opacity(0.03)
    static let keyTop = Color.white.opacity(0.16)
    static let keyBottom = Color.white.opacity(0.06)

    static let accent = Color(red: 0.79, green: 0.16, blue: 0.31)
    static let accentTop = Color(red: 0.88, green: 0.25, blue: 0.40)
    static let accentBottom = Color(red: 0.67, green: 0.11, blue: 0.27)
    static let accentSoft = Color(red: 0.98, green: 0.67, blue: 0.74)
    static let accentGlow = Color(red: 0.95, green: 0.32, blue: 0.49)

    static let stroke = Color.white.opacity(0.17)
    static let textPrimary = Color.white
    static let textSecondary = Color.white.opacity(0.80)
}

extension TVConnectionState {
    var statusColor: Color {
        switch self {
        case .connected:
            return Color(red: 0.46, green: 0.89, blue: 0.70)
        case .scanning, .pairing, .reconnecting:
            return Color(red: 0.96, green: 0.73, blue: 0.39)
        case .failed:
            return Color(red: 0.95, green: 0.42, blue: 0.48)
        case .idle, .discovered:
            return Color.white.opacity(0.42)
        }
    }
}
